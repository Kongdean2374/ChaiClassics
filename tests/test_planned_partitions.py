"""Partition only missing real cases; source metadata is replayed independently.

Synthetic unit evidence exercises verifier rules, not native Simulator success.
"""
import contextlib
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import verify_scoped_ci as scoped
import verify_candidate as candidate
import ui_test_scope as scopes
import test_scoped_ci as existing


class PlannedPartitionTests(unittest.TestCase):
    def setUp(self):
        self.tree = existing.tree()
        self.target = scoped.fingerprints(self.tree)
        self.names = sorted(self.target)
        self.actual = existing.passed(self.names[:8])
        self.source = existing.record(self.tree, self.actual)

    def test_four_changed_parts_are_disjoint_complete_and_exclude_actual_passes(self):
        missing = scoped.planned_tests(self.target, [self.source])
        parts = [scoped.planned_partition(part, self.target, [self.source]) for part in scopes.PART_SCOPES]
        flattened = [name for part in parts for name in part]
        self.assertEqual(sorted(flattened), missing)
        self.assertEqual(len(flattened), len(set(flattened)))
        self.assertFalse(set(flattened) & set(self.actual))
        for part, selected in zip(scopes.PART_SCOPES, parts):
            actual = existing.passed(selected)
            proof = scoped.make_evidence('b' * 40, 20, part, existing.summary(actual), actual, self.tree, [self.source])
            self.assertEqual(set(proof['executed_current_tests']), set(selected))
            self.assertFalse(proof['complete'])

    def test_later_actual_failure_returns_to_a_part_and_complete_union_requires_real_sentinel(self):
        failed = existing.record(self.tree, {self.names[0]: 'failed'}, run=11)
        records = [self.source, failed]
        self.assertIn(self.names[0], scoped.planned_tests(self.target, records))
        parts = [scoped.planned_partition(part, self.target, records) for part in scopes.PART_SCOPES]
        for run, selected in enumerate(parts, start=12):
            records.append(existing.record(self.tree, existing.passed(selected), run=run))
        selected = scoped.planned_tests(self.target, records)
        self.assertEqual(selected, [scoped.FAST_SENTINEL])
        actual = existing.passed(selected)
        proof = scoped.make_evidence('b' * 40, 20, 'affected', existing.summary(actual), actual, self.tree, records)
        self.assertTrue(proof['complete'])
        with self.assertRaises(candidate.CandidateError):
            scoped.make_evidence('b' * 40, 20, 'affected', existing.summary({}), {}, self.tree, records)

    def test_empty_or_ipad_only_parts_still_execute_a_real_phone_case(self):
        home, ipad = scoped.FAST_SENTINEL, 'ChaiClassicsVisualSmokeTests/testIPadSudokuScreenshot'
        target = {home: 'h', ipad: 'p'}
        source = {'run_id': 1, 'sha': 'a' * 40, 'fingerprints': target, 'actual': {home: 'passed'}}
        for part in scopes.PART_SCOPES:
            selected = scoped.planned_partition(part, target, [source])
            self.assertIn(home, selected)
            self.assertEqual(len(selected), len(set(selected)))

    def test_partition_capture_rejects_omissions_extras_failed_or_unexpected_skips(self):
        selected = scoped.planned_partition('part_a', self.target, [self.source])
        valid = existing.passed(selected)
        for mode in ['omit', 'extra', 'fail', 'skip']:
            actual = dict(valid)
            name = next(name for name in actual if name.split('/')[-1] not in candidate.IPAD_TESTS)
            if mode == 'omit': del actual[name]
            if mode == 'extra': actual['Unknown/testInvented'] = 'passed'
            if mode == 'fail': actual[name] = 'failed'
            if mode == 'skip': actual[name] = 'skipped'
            with self.subTest(mode=mode), self.assertRaises(candidate.CandidateError):
                scoped.make_evidence('b' * 40, 20, 'part_a', existing.summary(actual), actual, self.tree, [self.source])

    def test_cli_with_prior_sources_uses_bound_plan_and_empty_sources_keep_original_full_parts(self):
        with mock.patch.dict(os.environ, {'CHAI_CI_SOURCE_RUNS': '10'}), \
             mock.patch.object(scopes, 'affected_selectors', return_value=['ChaiClassicsUITests/Example/testActual']) as planner, \
             contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(scopes.main(['part_a']), 0)
            planner.assert_called_once_with('part_a')
            self.assertEqual(output.getvalue().splitlines(), ['-only-testing:ChaiClassicsUITests/Example/testActual'])
        with mock.patch.dict(os.environ, {'CHAI_CI_SOURCE_RUNS': ''}), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(scopes.main(['part_a']), 0)
            self.assertEqual(len(output.getvalue().splitlines()), 18)

    def test_partition_plan_cannot_be_reused_for_another_part_or_sha(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root / 'build').mkdir(); (root / 'UITests').mkdir()
            (root / 'UITests/Example.swift').write_text('func testActual() {}')
            path = root / 'build/ui-scope-plan.json'
            path.write_text(json.dumps({'source_commit': 'a' * 40, 'scope': 'part_a', 'tests': ['Example/testActual']}))
            with mock.patch.object(scopes, '__file__', str(root / 'scripts/ui_test_scope.py')), \
                 mock.patch.object(scopes.subprocess, 'check_output', return_value='a' * 40):
                self.assertEqual(scopes.affected_selectors('part_a'), ['ChaiClassicsUITests/Example/testActual'])
                with self.assertRaises(ValueError): scopes.affected_selectors('part_b')
                with self.assertRaises(ValueError): scopes.affected_selectors('affected')
            with mock.patch.object(scopes, '__file__', str(root / 'scripts/ui_test_scope.py')), \
                 mock.patch.object(scopes.subprocess, 'check_output', return_value='b' * 40):
                with self.assertRaises(ValueError): scopes.affected_selectors('part_a')

    def test_only_exact_additive_partition_support_preserves_the_previous_execution_source(self):
        for path, pair in scoped.APPROVED_DEPENDENCY_PARTITIONS.items():
            data = (ROOT / path).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), pair[1])
            normalized = scoped.dependency_partition_baseline(path, '100644', data)
            self.assertEqual(hashlib.sha256(normalized).hexdigest(), pair[0])
            self.assertEqual(scoped.shared_content_digest(path, '100644', data), scoped.shared_content_digest(path, '100644', normalized))
            for changed in [data + b'\n# additional command\n', data.replace(b'part_', b'full_')]:
                raw = hashlib.sha256(changed).hexdigest()
                forged = {**scoped.APPROVED_DEPENDENCY_PARTITIONS, path: (pair[0], raw, pair[2])}
                with mock.patch.object(scoped, 'APPROVED_DEPENDENCY_PARTITIONS', forged):
                    self.assertEqual(scoped.dependency_partition_baseline(path, '100644', changed), changed)
            self.assertEqual(scoped.dependency_partition_baseline(path, '100755', data), data)
            self.assertEqual(scoped.dependency_partition_baseline('unknown', '100644', data), data)


class PlannedPartitionReplayTests(unittest.TestCase):
    def setUp(self):
        self.fixture = existing.ProvenanceTests()
        self.fixture.setUp()
        f = self.fixture
        self.raw = {10: (f.prior['summary'], f.prior['actual'])}
        self.runs = []
        template = f'repos/{f.repo}/actions/runs/20'
        target = scoped.fingerprints(f.target)
        for run, part in enumerate(scopes.PART_SCOPES, start=11):
            prefix = f'repos/{f.repo}/actions/runs/{run}'
            for suffix in ('', '/jobs?per_page=100&filter=latest', '/artifacts?per_page=100'):
                f.responses[prefix + suffix] = copy.deepcopy(f.responses[template + suffix])
            f.responses[prefix]['id'] = run
            selected = scoped.planned_partition(part, target, [f.prior])
            actual = existing.passed(selected)
            self.raw[run] = (existing.summary(actual), actual, {
                'scope': part, 'source_commit': f.sha, 'source_runs': [10], 'partition': 'affected-v1'})
            self.runs.append(run)

    def gather(self):
        f = self.fixture
        return scoped.gather_sources(f.repo, self.runs, f.sha, 20, read=f.read,
            results_reader=lambda repo, run, read: self.raw[run],
            tree_reader=lambda sha: f.target if sha == f.sha else f.base, ancestor=lambda sha: True)

    def test_replay_reloads_original_preexecution_sources_and_reconstructs_each_requested_part(self):
        records = self.gather()
        self.assertEqual([record['run_id'] for record in records], [10, 11, 12, 13, 14])
        f = self.fixture
        actual = existing.passed([scoped.FAST_SENTINEL])
        proof = scoped.make_evidence(f.sha, 20, 'affected', existing.summary(actual), actual, f.target, records)
        self.assertTrue(proof['complete'])

    def test_replay_rejects_wrong_legacy_mode_future_sources_and_omitted_current_cases(self):
        baseline = copy.deepcopy(self.raw)
        for mode in ['legacy', 'future', 'missing', 'unknown']:
            self.raw = copy.deepcopy(baseline)
            summary, actual, selection = self.raw[11]
            if mode == 'legacy': selection.pop('partition')
            if mode == 'future': selection['source_runs'] = [14]
            if mode == 'unknown': selection['partition'] = 'unreviewed'
            if mode == 'missing':
                actual.pop(next(iter(actual)))
                self.raw[11] = (existing.summary(actual), actual, selection)
            with self.subTest(mode=mode), self.assertRaises(candidate.CandidateError): self.gather()


if __name__ == '__main__':
    unittest.main()
