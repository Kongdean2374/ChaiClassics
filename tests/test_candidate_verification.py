import copy
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import verify_candidate as candidate
import verify_scoped_ci as scoped


class CandidateVerificationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / 'UITests').mkdir()
        ipad = '\n'.join('func ' + test + '() {}' for test in sorted(candidate.IPAD_TESTS))
        (self.root / 'UITests/ChaiClassicsVisualSmokeTests.swift').write_text(ipad + '\nfunc testLight() {}\nfunc testDark() {}')
        (self.root / 'UITests/ChaiClassicsUITests.swift').write_text('func testPlayRestoreWinRestart() {}')
        (self.root / 'UITests/ChaiClassicsV020UITests.swift').write_text('\n'.join('func ' + test + '() {}' for test in sorted(candidate.IPAD_GAME_TESTS)))
        self.sha = 'a' * 40
        self.repo = 'Kongdean2374/ChaiClassics'
        self.runs = {'ci': 11, 'visual': 12, 'ipad': 13}
        self.tag = 'v0.2.0-rc.1'
        self.responses = {
            f'repos/{self.repo}/git/ref/heads/main': {'object': {'sha': self.sha}},
            f'repos/{self.repo}/git/ref/tags/{self.tag}': {'ref': 'refs/tags/' + self.tag, 'object': {'sha': self.sha, 'type': 'commit'}},
        }
        self.evidence = {}
        for kind in candidate.WORKFLOWS:
            tests = candidate.expected_tests(kind, self.root)
            skipped = 0 if kind == 'ipad' else 4
            summary = {'result': 'Passed', 'totalTestCount': len(tests), 'passedTests': len(tests) - skipped, 'failedTests': 0, 'skippedTests': skipped}
            report = {
                'status': 'success', 'collection_status': 'complete', 'build_status': 'success',
                'test_status': 'success', 'export_status': 'success', 'errors': [],
                'device': {'source_commit': self.sha, 'device_name': 'iPad Pro 13-inch (M4)'},
                'test_execution': {'status': 'verified'},
                'screenshots': [{'sha256': str(i) * 64, 'width': 2064, 'height': 2752} for i in range(4)],
            }
            games_summary = {'result': 'Passed', 'totalTestCount': 5, 'passedTests': 5, 'failedTests': 0, 'skippedTests': 0}
            actual = {name: ('skipped' if kind != 'ipad' and name.split('/')[-1] in candidate.IPAD_TESTS else 'passed') for name in tests}
            game_actual = {name: 'passed' for name in candidate.ipad_game_tests(self.root)}
            self.evidence[kind] = candidate.make_evidence(kind, summary, self.sha, report=report, games_summary=games_summary,
                                                         test_log=self.log(actual), games_log=self.log(game_actual), root=self.root)
            run_id = self.runs[kind]
            prefix = f'repos/{self.repo}/actions/runs/{run_id}'
            self.responses[prefix] = {
                'repository': {'full_name': self.repo}, 'head_sha': self.sha, 'head_branch': 'main',
                'event': 'workflow_dispatch', 'status': 'completed', 'conclusion': 'success',
                'path': '.github/workflows/' + candidate.WORKFLOWS[kind],
                'actor': {'login': 'developer', 'id': 7}, 'triggering_actor': {'login': 'developer', 'id': 7},
            }
            entries = [{'name': job, 'conclusion': 'success', 'steps': [{'name': 'Run all iOS UI tests', 'conclusion': 'success'}]} for job in candidate.JOBS[kind]]
            self.responses[prefix + '/jobs?per_page=100&filter=latest'] = {'total_count': len(entries), 'jobs': entries}
            self.responses[prefix + '/artifacts?per_page=100'] = {'total_count': 1, 'artifacts': [
                {'id': run_id * 10, 'name': 'candidate-' + kind + '-evidence', 'expired': False, 'size_in_bytes': 900},
            ]}
            self.responses[f'repos/{self.repo}/actions/artifacts/{run_id * 10}/zip'] = self.archive(kind)

    def archive(self, kind, *, filename=None, evidence=None):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, 'w') as zipped:
            zipped.writestr(filename or 'candidate-' + kind + '-evidence.json', json.dumps(evidence or self.evidence[kind]))
        return stream.getvalue()

    def log(self, actual):
        return '\n'.join("Test Case '-[ChaiClassicsUITests." + name.replace('/', ' ') + "]' " + state + ' (1.234 seconds).' for name, state in actual.items())

    def read(self, path, **_kwargs):
        self.assertIn(path, self.responses, 'Every verification API request must be an expected read.')
        return copy.deepcopy(self.responses[path])

    def verify(self, **kwargs):
        return candidate.verify(self.repo, self.sha, '0.2.0', self.tag, self.runs, read=self.read, root=self.root, **kwargs)

    def prepare_scoped_evidence(self, scope='affected'):
        source = {str(path.relative_to(self.root)): ('100644', path.read_bytes()) for path in self.root.rglob('*.swift')}
        tests = scoped.planned_tests(scoped.fingerprints(source), []) if scope == 'affected' else scoped.scopes.resolve(scope, scoped.fingerprints(source))
        actual = {test: 'skipped' if test.split('/')[-1] in candidate.IPAD_TESTS else 'passed' for test in tests}
        counts = {'totalTestCount': len(actual), 'passedTests': sum(value == 'passed' for value in actual.values()),
                  'failedTests': 0, 'skippedTests': sum(value == 'skipped' for value in actual.values()), 'result': 'Passed'}
        evidence = scoped.make_evidence(self.sha, self.runs['ci'], scope, counts, actual, source, [])
        prefix = f'repos/{self.repo}/actions/runs/{self.runs["ci"]}'
        self.responses[prefix]['id'] = self.runs['ci']
        entries = self.responses[prefix + '/jobs?per_page=100&filter=latest']['jobs']
        test = next(job for job in entries if job['name'] == 'test')
        test['steps'] = [{'name': name, 'conclusion': 'success'} for name in [
            'Verify puzzles, save compatibility and generated project', 'Run Swift game and save tests',
            'Build iOS Simulator app', 'Run selected iOS UI tests', 'Validate incremental candidate XCTest evidence']]
        self.responses[f'repos/{self.repo}/actions/artifacts/{self.runs["ci"] * 10}/zip'] = self.archive('ci', evidence=evidence)
        return source, counts, actual

    def test_schema_three_candidate_rebuilds_real_scope_and_keeps_visual_ipad_exact_sha(self):
        source, counts, actual = self.prepare_scoped_evidence()
        with mock.patch.object(scoped.historical, 'git_tree', return_value=source), mock.patch.object(scoped.historical, 'load_results', return_value=(counts, actual)):
            proof = self.verify()
            self.assertEqual(proof['schema'], 3)
            self.assertEqual(proof['verification'], 'dependency-scoped')
            self.assertTrue(proof['release_eligible'])
            self.assertEqual(proof['workflows']['ci']['source_runs'], [self.runs['ci']])
            self.responses[f'repos/{self.repo}/actions/runs/{self.runs["visual"]}']['head_sha'] = 'b' * 40
            with self.assertRaises(candidate.CandidateError): self.verify()

    def test_schema_three_partial_actual_pass_cannot_authorize_candidate(self):
        source, counts, actual = self.prepare_scoped_evidence('legacy')
        self.assertEqual(len(actual), 1)
        with mock.patch.object(scoped.historical, 'git_tree', return_value=source), mock.patch.object(scoped.historical, 'load_results', return_value=(counts, actual)):
            with self.assertRaisesRegex(candidate.CandidateError, 'partial'): self.verify()

    def test_exact_candidate_requires_all_three_runs_and_full_test_counts(self):
        proof = self.verify()
        self.assertEqual(proof['status'], 'verified')
        self.assertTrue(proof['release_eligible'])
        self.assertEqual(proof['evidence_branch'], 'main')
        self.assertEqual(proof['apple_upload'], 'not_performed')
        self.assertEqual(proof['apple_processing'], 'not_checked')
        self.assertEqual(set(proof['workflows']), {'ci', 'visual', 'ipad'})
        self.assertEqual(proof['workflows']['ci']['summary']['totalTestCount'], 12)
        self.assertEqual(proof['workflows']['ipad']['summary']['passedTests'], 4)
        self.assertEqual(proof['workflows']['ipad']['games_summary']['passedTests'], 5)

    def test_v021_development_proof_retains_exact_sha_and_never_authorizes_release(self):
        version = '0.2.1'; tag = 'v0.2.1-rc.1'; branch = 'develop/0.2.1'
        self.responses[f'repos/{self.repo}/git/ref/heads/{branch}'] = {'object': {'sha': self.sha}}
        self.responses[f'repos/{self.repo}/git/ref/tags/{tag}'] = {'ref': 'refs/tags/' + tag, 'object': {'sha': self.sha, 'type': 'commit'}}
        for run_id in self.runs.values():
            self.responses[f'repos/{self.repo}/actions/runs/{run_id}']['head_branch'] = branch
        proof = candidate.verify(self.repo, self.sha, version, tag, self.runs, read=self.read, root=self.root, branch=branch)
        self.assertFalse(proof['release_eligible'])
        self.assertEqual(proof['version'], version)
        self.assertEqual(proof['evidence_branch'], branch)
        self.responses[f'repos/{self.repo}/actions/runs/{self.runs["visual"]}']['head_sha'] = 'b' * 40
        with self.assertRaises(candidate.CandidateError):
            candidate.verify(self.repo, self.sha, version, tag, self.runs, read=self.read, root=self.root, branch=branch)

    def test_development_proof_never_authorizes_release(self):
        self.responses[f'repos/{self.repo}/git/ref/heads/develop/0.2.0'] = {'object': {'sha': self.sha}}
        for run_id in self.runs.values():
            self.responses[f'repos/{self.repo}/actions/runs/{run_id}']['head_branch'] = 'develop/0.2.0'
        proof = self.verify(branch='develop/0.2.0')
        self.assertFalse(proof['release_eligible'])
        self.assertEqual(proof['evidence_branch'], 'develop/0.2.0')

    def test_release_reuses_complete_development_evidence_only_after_identical_main_sha(self):
        for run_id in self.runs.values():
            self.responses[f'repos/{self.repo}/actions/runs/{run_id}']['head_branch'] = 'develop/0.2.0'
        proof = self.verify()
        self.assertTrue(proof['release_eligible'])
        self.assertEqual(proof['branch'], 'main')
        self.assertEqual(proof['evidence_branch'], 'develop/0.2.0')
        self.responses[f'repos/{self.repo}/git/ref/heads/main']['object']['sha'] = 'b' * 40
        with self.assertRaises(candidate.CandidateError):
            self.verify()

    def test_mixed_or_untrusted_evidence_branches_never_authorize_release(self):
        path = f'repos/{self.repo}/actions/runs/12'
        for wrong_branch in ['develop/0.2.0', 'feature/untrusted']:
            with self.subTest(branch=wrong_branch):
                self.responses[path]['head_branch'] = wrong_branch
                with self.assertRaises(candidate.CandidateError):
                    self.verify()
        for run_id in self.runs.values():
            self.responses[f'repos/{self.repo}/actions/runs/{run_id}']['head_branch'] = 'feature/untrusted'
        with self.assertRaises(candidate.CandidateError):
            self.verify()

    def test_fast_forward_reuse_still_rejects_a_different_run_sha(self):
        for run_id in self.runs.values():
            self.responses[f'repos/{self.repo}/actions/runs/{run_id}']['head_branch'] = 'develop/0.2.0'
        self.responses[f'repos/{self.repo}/actions/runs/13']['head_sha'] = 'b' * 40
        with self.assertRaises(candidate.CandidateError):
            self.verify()

    def test_main_movement_wrong_tag_or_annotated_tag_cannot_change_sha(self):
        path = f'repos/{self.repo}/git/ref/heads/main'
        self.responses[path]['object']['sha'] = 'b' * 40
        with self.assertRaises(candidate.CandidateError):
            self.verify()
        self.responses[path]['object']['sha'] = self.sha
        tag_path = f'repos/{self.repo}/git/ref/tags/{self.tag}'
        self.responses[tag_path]['object'] = {'sha': 'c' * 40, 'type': 'tag'}
        self.responses[f'repos/{self.repo}/git/tags/' + 'c' * 40] = {'object': {'sha': self.sha, 'type': 'commit'}}
        self.assertTrue(self.verify()['release_eligible'])
        self.responses[f'repos/{self.repo}/git/tags/' + 'c' * 40]['object']['sha'] = 'd' * 40
        with self.assertRaises(candidate.CandidateError):
            self.verify()

    def test_failed_skipped_wrong_repo_event_branch_sha_or_workflow_are_rejected(self):
        path = f'repos/{self.repo}/actions/runs/11'
        original = copy.deepcopy(self.responses[path])
        mutations = [
            {'conclusion': 'failure'}, {'conclusion': 'cancelled'}, {'conclusion': 'skipped'},
            {'status': 'in_progress'}, {'head_sha': 'b' * 40}, {'head_branch': 'other'},
            {'event': 'push'}, {'path': '.github/workflows/other.yml'}, {'repository': {'full_name': 'other/repo'}},
            {'actor': {}}, {'triggering_actor': {'login': 'bad\nlogin', 'id': 8}},
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                self.responses[path] = original | mutation
                with self.assertRaises(candidate.CandidateError):
                    self.verify()

    def test_full_ui_step_cannot_be_skipped_and_all_jobs_must_pass(self):
        path = f'repos/{self.repo}/actions/runs/11/jobs?per_page=100&filter=latest'
        jobs = self.responses[path]['jobs']
        test_job = next(job for job in jobs if job['name'] == 'test')
        test_job['steps'][0]['conclusion'] = 'skipped'
        with self.assertRaises(candidate.CandidateError):
            self.verify()
        test_job['steps'][0]['conclusion'] = 'success'
        jobs[0]['conclusion'] = 'failure'
        with self.assertRaises(candidate.CandidateError):
            self.verify()
        jobs[0]['conclusion'] = 'success'
        self.responses[path]['total_count'] += 1
        with self.assertRaises(candidate.CandidateError):
            self.verify()

    def test_counts_detect_subset_missing_cases_failures_and_unexpected_skips(self):
        for changes in [
            {'totalTestCount': 6}, {'passedTests': 0}, {'failedTests': 1}, {'skippedTests': 5},
            {'skippedTests': 0, 'passedTests': 7}, {'result': 'Failed'}, {'passedTests': True},
        ]:
            with self.subTest(changes=changes):
                with self.assertRaises(candidate.CandidateError):
                    candidate.validate_summary(self.evidence['ci']['summary'] | changes, 12, 4)
        altered = copy.deepcopy(self.evidence['ci'])
        altered['expected_tests'].pop()
        with self.assertRaises(candidate.CandidateError):
            candidate.validate_evidence('ci', altered, self.sha, self.root)

    def test_real_completion_log_rejects_subset_duplicate_failure_wrong_skip_and_wrong_case(self):
        actual = self.evidence['ci']['executed_tests']
        self.assertEqual(candidate.parse_test_log(self.log(actual)), actual)
        with self.assertRaises(candidate.CandidateError):
            candidate.parse_test_log(self.log(actual) + '\n' + self.log(actual))
        with self.assertRaises(candidate.CandidateError):
            candidate.parse_test_log('Build succeeded. No real test completion records.')
        mutations = [
            lambda values: values.pop(next(iter(values))),
            lambda values: values.update({'OtherClass/testDifferent': 'passed'}),
            lambda values: values.update({'ChaiClassicsUITests/testPlayRestoreWinRestart': 'skipped'}),
            lambda values: values.update({'ChaiClassicsUITests/testPlayRestoreWinRestart': 'failed'}),
            lambda values: values.update({'ChaiClassicsVisualSmokeTests/testIPadHomeScreenshot': 'passed'}),
        ]
        for edit in mutations:
            changed = copy.deepcopy(self.evidence['ci']); edit(changed['executed_tests'])
            with self.assertRaises(candidate.CandidateError):
                candidate.validate_evidence('ci', changed, self.sha, self.root)
        changed = copy.deepcopy(self.evidence['ipad'])
        changed['executed_game_tests'][next(iter(changed['executed_game_tests']))] = 'skipped'
        with self.assertRaises(candidate.CandidateError):
            candidate.validate_evidence('ipad', changed, self.sha, self.root)

    def test_ipad_games_summary_and_five_actual_journeys_cannot_be_omitted(self):
        for field in ['games_summary', 'executed_game_tests', 'expected_game_tests']:
            changed = copy.deepcopy(self.evidence['ipad']); changed.pop(field)
            with self.assertRaises(candidate.CandidateError):
                candidate.validate_evidence('ipad', changed, self.sha, self.root)

    def test_original_ipad_capture_integrity_and_execution_are_required(self):
        report = self.evidence['ipad']['ipad_report']
        for key, bad in [('status', 'failure'), ('collection_status', 'partial'), ('build_status', 'skipped'), ('test_status', 'failure'), ('export_status', 'unknown'), ('errors', [{'code': 'FAILURE'}])]:
            with self.subTest(key=key):
                with self.assertRaises(candidate.CandidateError):
                    candidate.validate_ipad(report | {key: bad}, self.sha)
        for edit in [
            lambda r: r['device'].update(source_commit='b' * 40),
            lambda r: r['test_execution'].update(status='unverified'),
            lambda r: r['screenshots'].pop(),
            lambda r: r['screenshots'][0].update(width=1024),
            lambda r: r['screenshots'][0].update(sha256='1' * 64),
        ]:
            altered = copy.deepcopy(report); edit(altered)
            with self.assertRaises(candidate.CandidateError):
                candidate.validate_ipad(altered, self.sha)

    def test_expired_duplicate_oversized_or_wrong_zip_evidence_is_rejected(self):
        path = f'repos/{self.repo}/actions/runs/11/artifacts?per_page=100'
        artifact = self.responses[path]['artifacts'][0]
        original = copy.deepcopy(artifact)
        for changes in [{'expired': True}, {'size_in_bytes': 0}, {'size_in_bytes': candidate.MAX_EVIDENCE_BYTES + 1}]:
            self.responses[path]['artifacts'][0] = original | changes
            with self.assertRaises(candidate.CandidateError):
                self.verify()
        self.responses[path]['artifacts'] = [original, original]
        self.responses[path]['total_count'] = 2
        with self.assertRaises(candidate.CandidateError):
            self.verify()
        self.responses[path]['artifacts'] = [original]
        self.responses[path]['total_count'] = 1
        zip_path = f'repos/{self.repo}/actions/artifacts/110/zip'
        for filename in ['../candidate-ci-evidence.json', 'other.json']:
            self.responses[zip_path] = self.archive('ci', filename=filename)
            with self.assertRaises(candidate.CandidateError):
                self.verify()
        self.responses[zip_path] = b'not a zip file'
        with self.assertRaises(candidate.CandidateError):
            self.verify()

    def test_invalid_candidate_arguments_do_not_make_network_requests(self):
        def never(*_args, **_kwargs):
            self.fail('Invalid input must fail before GitHub reads.')
        for repo, sha, tag, runs, branch in [
            ('bad repo', self.sha, self.tag, self.runs, 'main'),
            (self.repo, 'short', self.tag, self.runs, 'main'),
            (self.repo, self.sha, 'v0.2.0', self.runs, 'main'),
            (self.repo, self.sha, self.tag, {'ci': 1, 'visual': 1, 'ipad': 1}, 'main'),
            (self.repo, self.sha, self.tag, self.runs, 'untrusted'),
        ]:
            with self.assertRaises(candidate.CandidateError):
                candidate.verify(repo, sha, '0.2.0', tag, runs, read=never, root=self.root, branch=branch)


if __name__ == '__main__':
    unittest.main()
