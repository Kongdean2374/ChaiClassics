import copy
import base64
import io
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import subprocess
import unittest
from unittest import mock
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import verify_candidate as candidate
import verify_incremental_ci as incremental
from test_incremental_ci import source_tree


class IncrementalCandidateIntegrationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.tree = source_tree()
        for path, (_mode, content) in self.tree.items():
            file = self.root / path; file.parent.mkdir(parents=True, exist_ok=True); file.write_bytes(content)
        self.repo = 'Kongdean2374/ChaiClassics'; self.sha = 'b' * 40; self.tag = 'v0.2.0-rc.2'
        self.runs = {'ci': 71, 'visual': 72, 'ipad': 73}
        self.baseline_actual = {name: 'failed' if name in incremental.HISTORICAL_FAILURES else
                                'skipped' if name.split('/')[-1] in candidate.IPAD_TESTS else 'passed'
                                for name in candidate.expected_tests('ci', self.root)}
        self.baseline_summary = {'totalTestCount': 37, 'passedTests': 31, 'failedTests': 2, 'skippedTests': 4, 'result': 'Failed'}
        self.target_actual = dict.fromkeys(incremental.SELECTED_TESTS, 'passed')
        self.target_summary = {'totalTestCount': 3, 'passedTests': 3, 'failedTests': 0, 'skippedTests': 0, 'result': 'Passed'}
        self.source = incremental.validate_source_trees(self.tree, self.tree)
        self.responses = {
            f'repos/{self.repo}/git/ref/heads/main': {'object': {'sha': self.sha}},
            f'repos/{self.repo}/git/ref/tags/{self.tag}': {'ref': 'refs/tags/' + self.tag, 'object': {'sha': self.sha, 'type': 'commit'}},
        }
        self.add_run(incremental.BASELINE_RUN, 'ci', incremental.BASELINE_SHA, baseline=True)
        for kind, run_id in self.runs.items():
            self.add_run(run_id, kind, self.sha if kind == 'ci' else incremental.BASELINE_SHA)
        with mock.patch.object(incremental, 'source_proof', return_value=self.source):
            self.evidence = incremental.build_evidence(self.repo, self.sha, self.runs['ci'], self.target_summary,
                                                       self.target_actual, read=self.read, root=self.root, results_reader=self.results)
        self.install_artifact('ci', self.evidence)
        for kind in ('visual', 'ipad'):
            tests = candidate.expected_tests(kind, self.root)
            actual = {name: 'skipped' if kind == 'visual' and name.split('/')[-1] in candidate.IPAD_TESTS else 'passed' for name in tests}
            summary = {'totalTestCount': len(tests), 'passedTests': len(tests) - (4 if kind == 'visual' else 0),
                       'failedTests': 0, 'skippedTests': 4 if kind == 'visual' else 0, 'result': 'Passed'}
            report = {'status': 'success', 'collection_status': 'complete', 'build_status': 'success', 'test_status': 'success',
                      'export_status': 'success', 'errors': [], 'device': {'source_commit': incremental.BASELINE_SHA},
                      'test_execution': {'status': 'verified'},
                      'screenshots': [{'sha256': str(i) * 64, 'width': 2064, 'height': 2752} for i in range(4)]}
            evidence = candidate.make_evidence(kind, summary, incremental.BASELINE_SHA, executed_tests=actual,
                                               report=report, games_summary={'totalTestCount': 5, 'passedTests': 5, 'failedTests': 0, 'skippedTests': 0, 'result': 'Passed'},
                                               executed_game_tests=dict.fromkeys(candidate.ipad_game_tests(self.root), 'passed'), root=self.root)
            self.install_artifact(kind, evidence)

    def add_run(self, run_id, kind, sha, baseline=False):
        prefix = f'repos/{self.repo}/actions/runs/{run_id}'
        self.responses[prefix] = {'id': run_id, 'repository': {'full_name': self.repo}, 'head_sha': sha, 'head_branch': 'develop/0.2.0',
                                  'event': 'workflow_dispatch', 'status': 'completed', 'conclusion': 'failure' if baseline else 'success',
                                  'path': '.github/workflows/' + candidate.WORKFLOWS[kind],
                                  'actor': {'login': 'developer', 'id': 7}, 'triggering_actor': {'login': 'developer', 'id': 7}}
        steps = [{'name': 'Run selected iOS UI tests', 'conclusion': 'success'},
                 {'name': 'Validate incremental candidate XCTest evidence', 'conclusion': 'success'}]
        if kind == 'ci' and not baseline:
            steps.extend({'name': name, 'conclusion': 'skipped'} for name in (
                'Verify puzzles, save compatibility and generated project', 'Run Swift game and save tests',
                'Build iOS Simulator app', 'Run all iOS UI tests'))
        if baseline:
            steps = [{'name': name, 'conclusion': 'failure' if name == 'Run all iOS UI tests' else 'success'} for name in (
                'Verify puzzles, save compatibility and generated project', 'Run Swift game and save tests',
                'Build iOS Simulator app', 'Run all iOS UI tests')]
        entries = [{'name': name, 'conclusion': 'failure' if baseline and name == 'test' else 'success', 'steps': steps if name == 'test' else []}
                   for name in candidate.JOBS[kind]]
        self.responses[prefix + '/jobs?per_page=100&filter=latest'] = {'total_count': len(entries), 'jobs': entries}

    def install_artifact(self, kind, evidence):
        run = self.runs[kind]; artifact_id = run * 10; name = 'candidate-' + kind + '-evidence'
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as archive:
            archive.writestr(name + '.json', json.dumps(evidence))
        blob = buffer.getvalue()
        self.responses[f'repos/{self.repo}/actions/runs/{run}/artifacts?per_page=100'] = {
            'total_count': 1, 'artifacts': [{'id': artifact_id, 'name': name, 'expired': False, 'size_in_bytes': len(blob)}]}
        self.responses[f'repos/{self.repo}/actions/artifacts/{artifact_id}/zip'] = blob

    def read(self, path, **_kwargs):
        self.assertIn(path, self.responses)
        return copy.deepcopy(self.responses[path])

    def results(self, _repo, run, _read):
        if run == incremental.BASELINE_RUN: return copy.deepcopy(self.baseline_summary), copy.deepcopy(self.baseline_actual)
        self.assertEqual(run, self.runs['ci'])
        return copy.deepcopy(self.target_summary), copy.deepcopy(self.target_actual)

    def verify(self):
        with mock.patch.object(incremental, 'source_proof', return_value=self.source), mock.patch.object(incremental, 'load_results', side_effect=self.results):
            return candidate.verify(self.repo, self.sha, '0.2.0', self.tag, self.runs, read=self.read, root=self.root)

    def test_actual_union_accepts_unchanged_application_old_visual_and_ipad_without_fake_full_rerun(self):
        proof = self.verify()
        self.assertEqual(proof['schema'], 2)
        self.assertTrue(proof['release_eligible'])
        ci = proof['workflows']['ci']
        self.assertEqual(ci['summary']['totalTestCount'], 3)
        self.assertEqual(ci['baseline_summary']['failedTests'], 2)
        self.assertEqual(len(ci['coverage']), 37)
        self.assertEqual(proof['workflows']['ipad']['source_commit'], incremental.BASELINE_SHA)
        for name in incremental.SELECTED_TESTS: self.assertEqual(ci['coverage'][name]['source_run'], self.runs['ci'])

    def test_v022_current_run_keeps_the_original_historical_baseline_proof(self):
        self.responses[f'repos/{self.repo}/actions/runs/{self.runs["ci"]}']['head_branch'] = 'develop/0.2.2'
        with mock.patch.object(incremental, 'source_proof', return_value=self.source):
            rebuilt = incremental.validate_incremental_evidence(self.evidence, self.repo, self.sha, self.runs['ci'],
                read=self.read, root=self.root, results_reader=self.results)
        self.assertEqual(rebuilt, self.evidence)
        self.assertEqual(rebuilt['baseline_branch'], 'develop/0.2.0')

    def test_forged_coverage_digest_target_execution_and_source_are_rebuilt_and_rejected(self):
        for edit in (
            lambda e: e.update(app_source_digest='0' * 64),
            lambda e: e.update(source_commit='c' * 40),
            lambda e: e['coverage'][incremental.SELECTED_TESTS[0]].update(source_run=incremental.BASELINE_RUN),
            lambda e: e['baseline_executed_tests'].update({incremental.SELECTED_TESTS[0]: 'passed'}),
            lambda e: e['executed_current_tests'].pop(incremental.SELECTED_TESTS[0]),
        ):
            altered = copy.deepcopy(self.evidence); edit(altered); self.install_artifact('ci', altered)
            with self.assertRaises(candidate.CandidateError): self.verify()

    def test_baseline_cannot_hide_core_release_build_actor_or_wrong_sha_failures(self):
        prefix = f'repos/{self.repo}/actions/runs/{incremental.BASELINE_RUN}'
        for key, value in [('head_sha', 'c' * 40), ('event', 'push'), ('actor', {}), ('conclusion', 'success')]:
            old = copy.deepcopy(self.responses[prefix]); self.responses[prefix][key] = value
            with self.assertRaises(candidate.CandidateError): self.verify()
            self.responses[prefix] = old
        jobs_path = prefix + '/jobs?per_page=100&filter=latest'
        old = copy.deepcopy(self.responses[jobs_path])
        for job in self.responses[jobs_path]['jobs']:
            if job['name'] == 'release-tooling': job['conclusion'] = 'failure'
        with self.assertRaises(candidate.CandidateError): self.verify()
        self.responses[jobs_path] = old
        test = next(job for job in self.responses[jobs_path]['jobs'] if job['name'] == 'test')
        test['steps'][0]['conclusion'] = 'skipped'
        with self.assertRaises(candidate.CandidateError): self.verify()

    def test_current_target_skip_failure_or_missing_capture_is_rejected(self):
        path = f'repos/{self.repo}/actions/runs/{self.runs["ci"]}/jobs?per_page=100&filter=latest'
        test = next(job for job in self.responses[path]['jobs'] if job['name'] == 'test')
        for state in ('skipped', 'failure'):
            test['steps'][0]['conclusion'] = state
            with self.assertRaises(candidate.CandidateError): self.verify()
        test['steps'][0]['conclusion'] = 'success'; test['steps'].pop()
        with self.assertRaises(candidate.CandidateError): self.verify()

    def test_unrelated_old_sha_visual_or_current_app_change_is_rejected(self):
        path = f'repos/{self.repo}/actions/runs/{self.runs["visual"]}'
        self.responses[path]['head_sha'] = 'c' * 40
        with self.assertRaises(candidate.CandidateError): self.verify()
        self.responses[path]['head_sha'] = incremental.BASELINE_SHA
        with mock.patch.object(incremental, 'source_proof', side_effect=candidate.CandidateError('App changed')), mock.patch.object(incremental, 'load_results', side_effect=self.results):
            with self.assertRaises(candidate.CandidateError):
                candidate.verify(self.repo, self.sha, '0.2.0', self.tag, self.runs, read=self.read, root=self.root)

    def test_actual_zip_requires_original_summary_and_log_and_rejects_missing_or_forged_current_summary(self):
        def blob(summary, include_log=True):
            buffer = io.BytesIO()
            with zipfile.ZipFile(buffer, 'w') as archive:
                archive.writestr('build/UITests-summary.json', json.dumps(summary))
                if include_log:
                    archive.writestr('build/UITests.log', '\n'.join("Test Case '-[ChaiClassicsUITests." + key.replace('/', ' ') + "]' passed (1.0 seconds)." for key in self.target_actual))
            buffer.seek(0); return buffer
        summary, actual = incremental.read_zip_results(blob(self.target_summary))
        self.assertEqual(actual, self.target_actual)
        with self.assertRaises(candidate.CandidateError): incremental.read_zip_results(blob(self.target_summary, False))
        summary, actual = incremental.read_zip_results(blob(self.baseline_summary))
        with self.assertRaises(candidate.CandidateError): incremental.summary_matches(summary, actual)

    def test_cli_incremental_rejection_uses_one_exception_identity_without_traceback(self):
        wrong = copy.deepcopy(self.evidence); wrong['verification'] = 'forged'
        self.install_artifact('ci', wrong)
        fixture = self.root / 'responses.json'
        fixture.write_text(json.dumps({key: {'binary': base64.b64encode(value).decode()} if isinstance(value, bytes) else value
                                       for key, value in self.responses.items()}))
        bin_dir = self.root / 'bin'; bin_dir.mkdir()
        fake = bin_dir / 'gh'
        fake.write_text('#!/usr/bin/env python3\nimport os,json,sys,base64\nx=json.load(open(os.environ["CHAI_TEST_GH_RESPONSES"]))[sys.argv[-1]]\nsys.stdout.buffer.write(base64.b64decode(x["binary"]) if isinstance(x,dict) and "binary" in x else json.dumps(x).encode())\n')
        fake.chmod(0o755)
        env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'], CHAI_TEST_GH_RESPONSES=str(fixture))
        process = subprocess.run([sys.executable, str(Path(candidate.__file__)), 'verify', '--repo', self.repo, '--sha', self.sha,
                                  '--version', '0.2.0', '--tag', self.tag, '--ci-run', '71', '--visual-run', '72', '--ipad-run', '73',
                                  '--output', str(self.root / 'proof.json')], env=env, capture_output=True, text=True)
        self.assertEqual(process.returncode, 1)
        self.assertIn('Invalid incremental evidence schema', process.stderr)
        self.assertNotIn('Traceback', process.stderr)

    def test_small_artifact_cache_requires_live_github_digest(self):
        artifact_id = self.runs['ci'] * 10
        path = f'repos/{self.repo}/actions/runs/{self.runs["ci"]}/artifacts?per_page=100'
        artifacts = self.read(path); artifacts['_repo'] = self.repo
        blob = self.read(f'repos/{self.repo}/actions/artifacts/{artifact_id}/zip')
        cache = self.root / 'artifact-cache'; cache.mkdir(); (cache / (str(artifact_id) + '.zip')).write_bytes(blob)
        artifacts['artifacts'][0]['digest'] = 'sha256:' + hashlib.sha256(blob).hexdigest()
        with mock.patch.dict(os.environ, {'CHAI_VERIFICATION_CACHE': str(cache)}):
            self.assertEqual(candidate.artifact_evidence(artifacts, 'ci', self.read), self.evidence)
            artifacts['artifacts'][0]['digest'] = 'sha256:' + '0' * 64
            with self.assertRaises(candidate.CandidateError): candidate.artifact_evidence(artifacts, 'ci', self.read)


if __name__ == '__main__': unittest.main()
