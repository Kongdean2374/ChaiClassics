"""Real A/B passes survive a C-only fix; missing/failed/changed execution never turns green."""
import copy
import json
from pathlib import Path
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import verify_candidate as candidate
import verify_scoped_ci as scoped
import ui_test_scope as scopes
from test_incremental_ci import source_tree

A = 'ChaiClassicsV020UITests/testMemoryRestoresMatchesHidesUnturnedCardsCompletesAndReplays'
B = 'ChaiClassicsV020UITests/testTwentyFourRestoresExactCardsCompletesAndStartsNextPuzzle'
C = 'ChaiClassicsV020UITests/testMazeRestoresPositionResumesCompletesAndGeneratesNextMaze'
NEW = ['testBoardGameThinkingAndDropGatesRejectExtraInput', 'testMemoryFlipMismatchGatesAndReducedMotionPreserveNativeCards',
       'testMazeJoystickMovesContinuouslyStopsAndRestoresCell', 'testTwentyFourOrderedInputHistoryAndZeroDivision']


def tree():
    value = source_tree()
    path = 'UITests/ChaiClassicsV020UITests.swift'
    mode, data = value[path]
    extra = ''.join('    func ' + name + '() { XCTAssertTrue(true) }\n' for name in NEW)
    value[path] = (mode, data[:-2] + extra.encode() + b'}\n')
    for game in ('Memory', 'TwentyFour', 'Maze'):
        value['Core/' + ('MemoryMatch' if game == 'Memory' else game) + '.swift'] = ('100644', ('struct ' + game + 'Board {}\n').encode())
        value['App/' + game + 'View.swift'] = ('100644', ('struct ' + game + 'View {}\n').encode())
    return value


def summary(actual):
    counts = {state: sum(value == state for value in actual.values()) for state in ('passed', 'failed', 'skipped')}
    return {'totalTestCount': len(actual), 'passedTests': counts['passed'], 'failedTests': counts['failed'],
            'skippedTests': counts['skipped'], 'result': 'Failed' if counts['failed'] else 'Passed'}


def passed(tests):
    return {test: 'skipped' if test.split('/')[-1] in candidate.IPAD_TESTS else 'passed' for test in tests}


def record(source, actual=None, run=10, sha='a' * 40):
    fingerprints = scoped.fingerprints(source)
    actual = actual or passed(fingerprints)
    return {'run_id': run, 'sha': sha, 'actual': actual, 'summary': summary(actual), 'fingerprints': fingerprints}


class FingerprintTests(unittest.TestCase):
    def setUp(self):
        self.base = tree()
        self.fp = scoped.fingerprints(self.base)

    def edited(self, path):
        result = copy.deepcopy(self.base)
        mode, data = result.get(path, ('100644', b''))
        result[path] = (mode, data + b'\n// changed dependency\n')
        return scoped.fingerprints(result)

    def test_c_game_only_change_preserves_actual_a_and_b_dependencies(self):
        updated = self.edited('Core/Maze.swift')
        self.assertEqual(self.fp[A], updated[A])
        self.assertEqual(self.fp[B], updated[B])
        self.assertNotEqual(self.fp[C], updated[C])

    def test_shared_preferences_clock_resources_bootstrap_and_generator_invalidate_all(self):
        for path in ['Core/AppPreferences.swift', 'Core/Random.swift', 'App/AnimationFrameClock.swift', 'App/DesignSystem.swift', 'App/NewGameComponents.swift', 'App/UITestBootstrap.swift',
                     'App/Resources/en.lproj/Localizable.strings', 'App/Resources/game-maze.imageset/image.png',
                     'scripts/create_project.py', 'Package.swift', 'ChaiClassics.xcodeproj/project.pbxproj',
                     'scripts/verify_scoped_ci.py', 'App/UnexpectedRuntime.swift']:
            with self.subTest(path=path):
                updated = self.edited(path)
                self.assertTrue(all(self.fp[test] != updated[test] for test in self.fp))

    def test_only_c_test_body_change_keeps_a_b_while_helper_change_invalidates_all(self):
        updated = copy.deepcopy(self.base)
        path = 'UITests/ChaiClassicsV020UITests.swift'
        mode, data = updated[path]
        source = data.decode()
        start, end = scoped.historical.functions(source)[C.split('/')[-1]]
        changed = source[:start] + source[start:end].replace('true', 'false') + source[end:]
        updated[path] = (mode, changed.encode())
        fp = scoped.fingerprints(updated)
        self.assertEqual(self.fp[A], fp[A]); self.assertEqual(self.fp[B], fp[B]); self.assertNotEqual(self.fp[C], fp[C])
        updated[path] = (mode, data.replace(b'import XCTest', b'import XCTest\nfunc sharedHelper() { XCTAssertTrue(true) }'))
        fp = scoped.fingerprints(updated)
        self.assertTrue(all(self.fp[test] != fp[test] for test in self.fp))

    def test_unknown_mixed_tests_depend_on_every_game_and_symlinks_are_refused(self):
        fp = self.edited('Core/Maze.swift')
        mixed = 'ChaiClassicsV020UITests/testNewPuzzleModesStartRealBoards'
        self.assertNotEqual(self.fp[mixed], fp[mixed])
        updated = copy.deepcopy(self.base); updated['Core/Maze.swift'] = ('120000', b'/outside')
        with self.assertRaises(candidate.CandidateError): scoped.fingerprints(updated)


class CoverageTests(unittest.TestCase):
    def setUp(self):
        self.base = tree()
        self.target = copy.deepcopy(self.base)
        self.target['Core/Maze.swift'] = ('100644', b'struct MazeBoard { let repaired = true }\n')
        actual = passed(scoped.fingerprints(self.base)); actual[C] = 'failed'
        self.prior = record(self.base, actual)

    def test_real_a_b_passes_c_failure_then_c_dependency_recheck_completes_coverage(self):
        needed = scoped.planned_tests(scoped.fingerprints(self.target), [self.prior])
        self.assertNotIn(A, needed); self.assertNotIn(B, needed); self.assertIn(C, needed)
        actual = passed(needed)
        proof = scoped.make_evidence('b' * 40, 20, 'affected', summary(actual), actual, self.target, [self.prior])
        self.assertTrue(proof['complete']); self.assertEqual(proof['uncovered_tests'], [])
        self.assertEqual(proof['coverage'][A]['source_run'], 10)
        self.assertEqual(proof['coverage'][B]['source_run'], 10)
        self.assertEqual(proof['coverage'][C]['source_run'], 20)
        self.assertEqual(proof['current_summary']['totalTestCount'], len(needed))
        self.assertLess(len(needed), len(proof['expected_tests']))
        self.assertEqual(self.prior['actual'][C], 'failed', 'Historical failure stays a failure in source evidence')

    def test_selected_partial_capture_is_successful_but_truthfully_not_complete(self):
        actual = passed(scopes.resolve('maze', scoped.fingerprints(self.target)))
        proof = scoped.make_evidence('b' * 40, 20, 'maze', summary(actual), actual, self.target, [])
        self.assertFalse(proof['complete']); self.assertIn(A, proof['uncovered_tests'])
        self.assertEqual(set(proof['executed_current_tests']), set(actual))

    def test_latest_failed_case_requires_reexecution_even_with_older_identical_pass(self):
        older = record(self.base, run=8)
        coverage = scoped.inherited_coverage(scoped.fingerprints(self.base), [self.prior, older])
        self.assertEqual(coverage[C]['status'], 'failed')
        self.assertEqual(coverage[C]['source_run'], 10)
        self.assertIn(C, scoped.planned_tests(scoped.fingerprints(self.base), [older, self.prior]))

    def test_missing_wrong_skipped_failed_case_and_forged_summary_are_rejected(self):
        needed = scoped.planned_tests(scoped.fingerprints(self.target), [self.prior])
        original = passed(needed)
        for variant in ['missing', 'wrong', 'skip', 'fail', 'count']:
            actual = dict(original); counts = summary(actual)
            chosen = next(test for test in actual if test.split('/')[-1] not in candidate.IPAD_TESTS)
            if variant == 'missing': actual.pop(chosen)
            if variant == 'wrong': actual['Unknown/testInvented'] = actual.pop(chosen)
            if variant == 'skip': actual[chosen] = 'skipped'; counts = summary(actual)
            if variant == 'fail': actual[chosen] = 'failed'; counts = summary(actual)
            if variant == 'count': counts['passedTests'] += 1
            with self.subTest(variant=variant), self.assertRaises(candidate.CandidateError):
                scoped.make_evidence('b' * 40, 20, 'affected', counts, actual, self.target, [self.prior])

    def test_deleted_previously_required_case_cannot_shrink_coverage(self):
        target = copy.deepcopy(self.base); path = 'UITests/ChaiClassicsV020UITests.swift'
        mode, data = target[path]; source = data.decode(); start, end = scoped.historical.functions(source)[C.split('/')[-1]]
        declaration = source.rfind('    func ', 0, start)
        target[path] = (mode, (source[:declaration] + source[end:]).encode())
        with self.assertRaises(candidate.CandidateError):
            scoped.planned_tests(scoped.fingerprints(target), [self.prior])

    def test_no_missing_cases_rechecks_one_real_case_instead_of_empty_green(self):
        needed = scoped.planned_tests(scoped.fingerprints(self.base), [record(self.base)])
        self.assertEqual(len(needed), 1)
        self.assertNotIn(needed[0].split('/')[-1], candidate.IPAD_TESTS)


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.repo = 'Kongdean2374/ChaiClassics'; self.sha = 'b' * 40
        self.base = tree(); self.target = copy.deepcopy(self.base)
        self.target['Core/Maze.swift'] = ('100644', b'struct MazeBoard { let repaired = true }\n')
        actual = passed(scoped.fingerprints(self.base)); actual[C] = 'failed'
        self.prior = record(self.base, actual)
        selected = scoped.planned_tests(scoped.fingerprints(self.target), [self.prior])
        self.current_actual = passed(selected)
        self.evidence = scoped.make_evidence(self.sha, 20, 'affected', summary(self.current_actual), self.current_actual, self.target, [self.prior])
        self.responses = {}
        for run_id, sha, failed in [(10, 'a' * 40, True), (20, self.sha, False)]:
            prefix = f'repos/{self.repo}/actions/runs/{run_id}'
            self.responses[prefix] = {'id': run_id, 'repository': {'full_name': self.repo}, 'head_sha': sha, 'head_branch': 'develop/0.2.1',
                'event': 'workflow_dispatch', 'status': 'completed', 'conclusion': 'failure' if failed else 'success',
                'path': '.github/workflows/ci.yml', 'actor': {'id': 1, 'login': 'developer'}, 'triggering_actor': {'id': 1, 'login': 'developer'}}
            steps = [{'name': name, 'conclusion': 'success'} for name in ['Verify puzzles, save compatibility and generated project',
                       'Run Swift game and save tests', 'Build iOS Simulator app', 'Validate incremental candidate XCTest evidence']]
            steps.append({'name': 'Run selected iOS UI tests', 'conclusion': 'failure' if failed else 'success'})
            jobs = [{'name': name, 'conclusion': 'failure' if failed and name == 'test' else 'success', 'steps': steps if name == 'test' else []}
                    for name in candidate.JOBS['ci']]
            self.responses[prefix + '/jobs?per_page=100&filter=latest'] = {'total_count': len(jobs), 'jobs': jobs}
            self.responses[prefix + '/artifacts?per_page=100'] = {'total_count': 0, 'artifacts': []}

    def read(self, path, **_kwargs):
        self.assertIn(path, self.responses)
        return copy.deepcopy(self.responses[path])

    def results(self, _repo, run, _read):
        return (self.prior['summary'], self.prior['actual']) if run == 10 else (summary(self.current_actual), self.current_actual)

    def verify(self, evidence=None, ancestor=None):
        return scoped.validate_evidence(evidence or self.evidence, self.repo, self.sha, 20, read=self.read,
            results_reader=self.results, tree_reader=lambda sha: self.target if sha == self.sha else self.base, ancestor=ancestor or (lambda _: True))

    def test_actual_source_jobs_logs_dependencies_and_provenance_are_rebuilt(self):
        self.assertEqual(self.verify(), self.evidence)
        for change in [lambda e: e['coverage'][A].update(source_run=20), lambda e: e['fingerprints'].update({A: '0' * 64}),
                       lambda e: e.update(complete=False), lambda e: e['executed_current_tests'].pop(C)]:
            forged = copy.deepcopy(self.evidence); change(forged)
            with self.assertRaises(candidate.CandidateError): self.verify(forged)

    def test_failed_build_skipped_core_wrong_workflow_untrusted_branch_and_nonancestor_are_rejected(self):
        prefix = f'repos/{self.repo}/actions/runs/10'
        for field, wrong in [('event', 'push'), ('head_branch', 'feature/untrusted'), ('status', 'in_progress'), ('path', '.github/workflows/other.yml')]:
            saved = copy.deepcopy(self.responses[prefix]); self.responses[prefix][field] = wrong
            with self.subTest(field=field), self.assertRaises(candidate.CandidateError): self.verify()
            self.responses[prefix] = saved
        path = prefix + '/jobs?per_page=100&filter=latest'
        saved = copy.deepcopy(self.responses[path])
        for name, state in [('Run Swift game and save tests', 'skipped'), ('Build iOS Simulator app', 'failure')]:
            self.responses[path] = copy.deepcopy(saved)
            job = next(job for job in self.responses[path]['jobs'] if job['name'] == 'test')
            next(step for step in job['steps'] if step['name'] == name)['conclusion'] = state
            with self.assertRaises(candidate.CandidateError): self.verify()
        self.responses[path] = saved
        with self.assertRaises(candidate.CandidateError): self.verify(ancestor=lambda _: False)

    def test_partial_ledger_cannot_authorize_release_even_when_current_scope_passes(self):
        partial = scoped.make_evidence(self.sha, 20, 'affected', summary(passed(scoped.fingerprints(self.target))), passed(scoped.fingerprints(self.target)), self.target, [])
        # A declared complete ledger is still reconstructed from the actual selected execution.
        partial['coverage'].pop(A)
        partial['complete'] = True
        with self.assertRaises(candidate.CandidateError): self.verify(partial)

    def test_prior_ledger_only_indexes_real_runs_and_cannot_forge_a_pass(self):
        prefix = f'repos/{self.repo}/actions/runs/10/artifacts?per_page=100'
        self.responses[prefix] = {'total_count': 1, 'artifacts': [{'name': 'candidate-ci-evidence'}]}
        forged = {'schema': 3, 'source_runs': [10], 'coverage': {C: {'status': 'passed'}}}
        with mock.patch.object(candidate, 'artifact_evidence', return_value=forged):
            rebuilt = self.verify()
        self.assertEqual(rebuilt['coverage'][C]['source_run'], 20)
        forged['source_runs'] = [20]
        with mock.patch.object(candidate, 'artifact_evidence', return_value=forged), self.assertRaises(candidate.CandidateError): self.verify()

    def test_run_id_inputs_are_bounded_positive_and_nonduplicated(self):
        self.assertEqual(scoped.parse_runs('10, 11'), [10, 11])
        self.assertEqual(scoped.parse_runs(''), [])
        for text in ['0', '-1', '1,1', '1.5', '1; command', ',1', 'True', ','.join(map(str, range(1, 22)))]:
            with self.subTest(text=text), self.assertRaises(candidate.CandidateError): scoped.parse_runs(text)


if __name__ == '__main__':
    unittest.main()
