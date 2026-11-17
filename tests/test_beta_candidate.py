"""Beta is three real current-SHA passes, never a claimed full regression."""
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
import warnings
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import verify_beta_candidate as beta
import verify_candidate as candidate


class BetaCandidateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.addCleanup(self.temporary.cleanup)
        self.cache = Path(self.temporary.name)
        self.environment = mock.patch.dict(os.environ, {'CHAI_VERIFICATION_CACHE': str(self.cache)})
        self.environment.start(); self.addCleanup(self.environment.stop)
        self.repo = beta.REPOSITORY; self.sha = 'a' * 40; self.version = '0.2.2'
        self.tag = 'v0.2.2-rc.1'; self.run_id = 123; self.artifact_id = 456
        self.prefix = f'repos/{self.repo}/actions/runs/{self.run_id}'
        self.tree = {path: ('100644', (candidate.ROOT / path).read_bytes()) for path in beta.SOURCE_FILES}
        self.tree.update({str(path.relative_to(candidate.ROOT)): ('100644', path.read_bytes())
                          for path in (candidate.ROOT / 'UITests').glob('*.swift')})
        # This suite preserves the released 0.2.2 Beta contract, independently of the current marketing version.
        project = 'ChaiClassics.xcodeproj/project.pbxproj'
        mode, data = self.tree[project]
        self.tree[project] = (mode, data.replace(b'0.3.0', b'0.2.2'))
        self.actual = dict.fromkeys(beta.BETA_TESTS, 'passed')
        self.summary = {'result': 'Passed', 'totalTestCount': 3, 'passedTests': 3, 'failedTests': 0, 'skippedTests': 0}
        self.selection = {'scope': 'beta', 'source_commit': self.sha, 'source_runs': []}
        steps = [{'name': name, 'conclusion': 'success'} for name in beta.REQUIRED_STEPS]
        steps += [{'name': name, 'conclusion': 'skipped'} for name in (
            'Run all iOS UI tests', 'Validate complete candidate XCTest evidence')]
        self.responses = {
            f'repos/{self.repo}/git/ref/heads/main': {'object': {'sha': self.sha}},
            f'repos/{self.repo}/git/ref/tags/{self.tag}': {'ref': 'refs/tags/' + self.tag, 'object': {'type': 'commit', 'sha': self.sha}},
            self.prefix: {'id': self.run_id, 'repository': {'full_name': self.repo}, 'head_repository': {'full_name': self.repo},
                          'head_sha': self.sha, 'head_branch': 'main', 'event': 'workflow_dispatch', 'pull_requests': [],
                          'path': '.github/workflows/ci.yml', 'status': 'completed', 'conclusion': 'success',
                          'actor': {'login': 'developer', 'id': 7}, 'triggering_actor': {'login': 'developer', 'id': 7}},
            self.prefix + '/jobs?per_page=100&filter=latest': {'total_count': 3, 'jobs': [
                {'name': name, 'run_id': self.run_id, 'head_sha': self.sha, 'status': 'completed',
                 'conclusion': 'success', 'steps': steps if name == 'test' else []}
                for name in sorted(candidate.JOBS['ci'])]},
        }
        self.install_zip()

    @property
    def ci_run(self): return self.responses[self.prefix]

    @property
    def artifact(self): return self.responses[self.prefix + '/artifacts?per_page=100']['artifacts'][0]

    @property
    def jobs(self): return self.responses[self.prefix + '/jobs?per_page=100&filter=latest']['jobs']

    @property
    def steps(self): return next(job for job in self.jobs if job['name'] == 'test')['steps']

    def install_zip(self, *, members=None, malformed=False):
        log = '\n'.join("Test Case '-[ChaiClassicsUITests." + name.replace('/', ' ') + "]' " + status + ' (1.0 seconds).'
                        for name, status in self.actual.items())
        values = members if members is not None else [
            ('build/UITests-summary.json', json.dumps(self.summary)),
            ('build/UITests.log', log), ('ui-selection.json', json.dumps(self.selection))]
        output = io.BytesIO()
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(output, 'w') as zipped:
                for name, value in values: zipped.writestr(name, value)
        data = b'not a zip' if malformed else output.getvalue()
        (self.cache / f'{self.artifact_id}.zip').write_bytes(data)
        self.responses[self.prefix + '/artifacts?per_page=100'] = {'total_count': 1, 'artifacts': [{
            'id': self.artifact_id, 'name': 'test-results', 'expired': False, 'size_in_bytes': len(data),
            'digest': 'sha256:' + hashlib.sha256(data).hexdigest(),
            'workflow_run': {'id': self.run_id, 'head_sha': self.sha, 'head_branch': 'main'},
        }]}

    def read(self, path, **kwargs):
        self.assertIn(path, self.responses, 'Only expected GitHub metadata GETs may be read; no Apple or write operations.')
        self.assertFalse(kwargs.get('binary', False), 'Original ZIP must use the bounded SHA-verified reader.')
        return copy.deepcopy(self.responses[path])

    def verify(self, **kwargs):
        return beta.verify(self.repo, self.sha, self.version, self.tag, self.run_id,
                           read=self.read, tree_reader=lambda sha: self.tree, **kwargs)

    def rejected(self):
        with self.assertRaises(candidate.CandidateError): self.verify()

    def test_exact_current_three_passes_authorize_beta_only_and_keep_full_inventory(self):
        with mock.patch.object(beta.historical.subprocess, 'run', side_effect=AssertionError('Unexpected network/write command')):
            proof = self.verify()
        self.assertEqual(proof['status'], 'beta_verified')
        self.assertTrue(proof['beta_eligible']); self.assertFalse(proof['release_eligible'])
        self.assertFalse(proof['app_store_release_eligible']); self.assertFalse(proof['full_regression_complete'])
        self.assertEqual(proof['release_target'], 'testflight_beta')
        self.assertEqual(proof['declared_ui_test_count'], 50)
        self.assertEqual(len(proof['required_session_journeys']), 9)
        self.assertEqual(len(proof['ui_tests_not_required_for_beta']), 47)
        self.assertEqual(proof['workflows']['ci']['executed_tests'], self.actual)
        self.assertEqual(proof['workflows']['ci']['original_results']['sha256'], self.artifact['digest'][7:])
        self.assertEqual(proof['inherited_ui_cases'], [])
        self.assertEqual({item['area'] for item in proof['manual_qa_items']},
                         {'real_devices', '120hz', 'haptics', 'native_files', 'ipad_accessibility', 'other_game_modes'})
        self.assertEqual(proof['apple_upload'], 'not_performed')

    def test_explicit_manual_qa_requires_no_ci_or_ui_and_never_fabricates_results(self):
        reads = []
        def identity_only(path, **kwargs):
            reads.append(path)
            self.assertNotIn('/actions/', path, 'Manual Beta must not wait for or inspect Simulator/CI evidence.')
            return self.read(path, **kwargs)
        proof = beta.verify(self.repo, self.sha, self.version, self.tag, manual_qa=True,
                            read=identity_only, tree_reader=lambda sha: self.tree)
        self.assertEqual(len(reads), 2)
        self.assertEqual(proof['status'], 'manual_beta_ready')
        self.assertTrue(proof['beta_eligible']); self.assertFalse(proof['full_regression_complete'])
        self.assertFalse(proof['release_eligible']); self.assertFalse(proof['app_store_release_eligible'])
        self.assertEqual(proof['ui_tests'], 'not_required_manual_qa')
        self.assertEqual(proof['workflows'], {}); self.assertEqual(proof['executed_ui_tests'], [])
        self.assertEqual(proof['apple_archive'], 'pending_testflight_workflow')
        self.assertEqual(proof['declared_ui_test_count'], 50)
        self.assertEqual(len(proof['required_session_journeys']), 9)
        self.assertTrue(all(item['status'] == 'pending' for item in proof['manual_qa_items']))

    def test_missing_ci_id_still_rejects_automated_mode_and_manual_retains_identity_guards(self):
        with self.assertRaises(candidate.CandidateError):
            beta.verify(self.repo, self.sha, self.version, self.tag, read=self.read, tree_reader=lambda sha: self.tree)
        self.responses[f'repos/{self.repo}/git/ref/heads/main']['object']['sha'] = 'b' * 40
        with self.assertRaises(candidate.CandidateError):
            beta.verify(self.repo, self.sha, self.version, self.tag, manual_qa=True,
                        read=self.read, tree_reader=lambda sha: self.tree)

    def test_manual_cli_accepts_no_ci_run_and_reports_pending_instead_of_passed_tests(self):
        proof = {'status': 'manual_beta_ready', 'beta_eligible': True, 'full_regression_complete': False}
        console = io.StringIO(); output = self.cache / 'manual-proof.json'
        with mock.patch.dict(os.environ, {}, clear=True), mock.patch.object(beta, 'verify', return_value=proof) as verify, mock.patch('sys.stdout', console):
            result = beta.main(['--sha', self.sha, '--version', self.version, '--tag', self.tag,
                                '--manual-qa', '--output', str(output)])
        self.assertEqual(result, 0)
        self.assertIsNone(verify.call_args.args[4]); self.assertTrue(verify.call_args.kwargs['manual_qa'])
        self.assertEqual(json.loads(output.read_text()), proof)
        self.assertNotIn('UI journeys and CI passed', console.getvalue())

    def test_exact_same_sha_develop_run_remains_original_source_after_main_fast_forward(self):
        self.ci_run['head_branch'] = 'develop/0.2.2'
        self.artifact['workflow_run']['head_branch'] = 'develop/0.2.2'
        self.assertEqual(self.verify()['workflows']['ci']['source_branch'], 'develop/0.2.2')

    def test_annotated_candidate_tag_is_resolved_to_same_commit(self):
        tag_sha = 'b' * 40
        self.responses[f'repos/{self.repo}/git/ref/tags/{self.tag}']['object'] = {'type': 'tag', 'sha': tag_sha}
        self.responses[f'repos/{self.repo}/git/tags/{tag_sha}'] = {'object': {'type': 'commit', 'sha': self.sha}}
        self.assertTrue(self.verify()['beta_eligible'])

    def test_wrong_main_or_tag_sha_rejects_without_inheriting_any_other_run(self):
        for reference in (f'repos/{self.repo}/git/ref/heads/main', f'repos/{self.repo}/git/ref/tags/{self.tag}'):
            original = copy.deepcopy(self.responses[reference])
            self.responses[reference]['object']['sha'] = 'b' * 40
            self.rejected(); self.responses[reference] = original

    def test_wrong_repo_branch_version_or_tag_is_not_beta_authorization(self):
        for arguments in ((self.repo, self.sha, self.version, self.tag, self.run_id, 'develop/0.2.2'),
                          ('attacker/ChaiClassics', self.sha, self.version, self.tag, self.run_id, 'main'),
                          (self.repo, self.sha, self.version, 'v0.2.1-rc.1', self.run_id, 'main')):
            with self.subTest(arguments=arguments), self.assertRaises(candidate.CandidateError):
                beta.verify(*arguments[:5], branch=arguments[5], read=self.read, tree_reader=lambda sha: self.tree)

    def test_failed_cancelled_incomplete_or_wrong_sha_ci_run_rejects(self):
        for field, value in (('conclusion', 'failure'), ('conclusion', 'cancelled'), ('status', 'in_progress'),
                             ('head_sha', 'b' * 40), ('id', self.run_id + 1)):
            original = self.ci_run[field]; self.ci_run[field] = value
            self.rejected(); self.ci_run[field] = original

    def test_pr_fork_untrusted_branch_missing_actor_and_signed_workflows_reject(self):
        for field, value in (('event', 'pull_request'), ('head_branch', 'feature/beta'),
                             ('path', '.github/workflows/testflight.yml'), ('path', '.github/workflows/initialize-signing.yml'),
                             ('head_repository', {'full_name': 'attacker/fork'}), ('pull_requests', [{'number': 1}]),
                             ('triggering_actor', {'login': 'developer', 'id': 0})):
            original = copy.deepcopy(self.ci_run[field]); self.ci_run[field] = value
            self.rejected(); self.ci_run[field] = original

    def test_every_required_ci_job_and_current_phase_must_really_pass(self):
        for job in self.jobs:
            job['conclusion'] = 'skipped'; self.rejected(); job['conclusion'] = 'success'
        for name in beta.REQUIRED_STEPS:
            step = next(item for item in self.steps if item['name'] == name)
            step['conclusion'] = 'skipped'; self.rejected(); step['conclusion'] = 'success'

    def test_duplicate_jobs_wrong_run_or_mismatched_job_sha_reject(self):
        response = self.responses[self.prefix + '/jobs?per_page=100&filter=latest']
        response['jobs'].append(copy.deepcopy(self.jobs[0])); response['total_count'] = 4
        self.rejected(); response['jobs'].pop(); response['total_count'] = 3
        self.jobs[0]['head_sha'] = 'b' * 40; self.rejected()

    def test_no_missing_failed_skipped_or_extra_actual_beta_case_is_accepted(self):
        for modification in ('missing', 'failed', 'skipped', 'extra'):
            original = copy.deepcopy(self.actual)
            if modification == 'missing': self.actual.pop(beta.BETA_TESTS[0])
            elif modification in ('failed', 'skipped'): self.actual[beta.BETA_TESTS[0]] = modification
            else: self.actual['ChaiClassicsUITests/testHomeHasExactlyThreeColumns'] = 'passed'
            self.install_zip(); self.rejected(); self.actual = original

    def test_summary_cannot_forge_three_successes_when_counts_disagree(self):
        for field, value in (('totalTestCount', 4), ('passedTests', 2), ('skippedTests', 1), ('result', 'Failed')):
            original = self.summary[field]; self.summary[field] = value
            self.install_zip(); self.rejected(); self.summary[field] = original

    def test_actual_scope_source_sha_and_inheritance_index_are_required(self):
        for selection in (None, {'scope': 'full', 'source_commit': self.sha, 'source_runs': []},
                          {'scope': 'beta', 'source_commit': 'b' * 40, 'source_runs': []},
                          {'scope': 'beta', 'source_commit': self.sha, 'source_runs': [12]},
                          {'scope': 'beta', 'source_commit': self.sha}):
            self.selection = selection; self.install_zip(); self.rejected()

    def test_github_digest_mismatch_or_missing_digest_rejects_original_zip(self):
        for digest in ('sha256:' + '0' * 64, '', 'sha1:' + '0' * 40):
            self.artifact['digest'] = digest; self.rejected()

    def test_original_artifact_wrong_run_sha_expired_duplicate_and_cache_symlink_reject(self):
        for field, value in (('id', 124), ('head_sha', 'b' * 40), ('head_branch', 'feature/wrong')):
            original = self.artifact['workflow_run'][field]
            self.artifact['workflow_run'][field] = value; self.rejected()
            self.artifact['workflow_run'][field] = original
        self.artifact['expired'] = True; self.rejected(); self.artifact['expired'] = False
        metadata = self.responses[self.prefix + '/artifacts?per_page=100']
        metadata['artifacts'].append(copy.deepcopy(self.artifact)); metadata['total_count'] = 2
        self.rejected(); metadata['artifacts'].pop(); metadata['total_count'] = 1
        path = self.cache / f'{self.artifact_id}.zip'
        original = path.with_suffix('.original'); path.rename(original); path.symlink_to(original)
        self.rejected()

    def test_raw_summary_log_selection_missing_duplicate_or_malformed_zip_reject(self):
        for members in ([('build/UITests-summary.json', json.dumps(self.summary))],
                        [('build/UITests.log', 'no case records')],
                        [('build/UITests.log', 'first'), ('build/UITests.log', 'second')]):
            self.install_zip(members=members); self.rejected()
        self.install_zip(malformed=True); self.rejected()

    def test_source_version_full_ui_guard_and_mandatory_inventory_are_protected(self):
        path = 'ChaiClassics.xcodeproj/project.pbxproj'
        original = self.tree[path]
        self.tree[path] = (original[0], original[1].replace(b'0.2.2', b'0.2.3'))
        self.rejected(); self.tree[path] = original
        path = '.github/workflows/ci.yml'; original = self.tree[path]
        self.tree[path] = (original[0], original[1].replace(b"if: inputs.full_ui == true && env.CHAI_UI_SCOPE != 'full'", b'if: always()'))
        self.rejected(); self.tree[path] = original
        path = 'UITests/ChaiClassicsVisualSmokeTests.swift'; original = self.tree[path]
        self.tree[path] = (original[0], original[1].replace(beta.BETA_TESTS[0].split('/')[1].encode(), b'testRenamedBetaJourney'))
        self.rejected()

    def test_full_candidate_ledger_is_never_used_as_beta_raw_execution_or_full_promotion(self):
        metadata = self.responses[self.prefix + '/artifacts?per_page=100']
        metadata['artifacts'].append({'id': 789, 'name': 'candidate-ci-evidence', 'expired': False,
                                      'size_in_bytes': 100, 'digest': 'sha256:' + 'f' * 64})
        metadata['total_count'] = 2
        proof = self.verify()
        self.assertFalse(proof['full_regression_complete']); self.assertFalse(proof['release_eligible'])
        self.selection['scope'] = 'full'; self.install_zip(); self.rejected()

    def test_caller_must_be_unsigned_testflight_main_preflight_not_upload_or_app_store(self):
        environment = {'GITHUB_ACTIONS': 'true', 'GITHUB_REPOSITORY': self.repo, 'GITHUB_SHA': self.sha,
                       'GITHUB_REF': 'refs/heads/main', 'GITHUB_EVENT_NAME': 'workflow_dispatch', 'GITHUB_JOB': 'preflight',
                       'GITHUB_WORKFLOW_REF': f'{self.repo}/.github/workflows/testflight.yml@refs/heads/main'}
        with mock.patch.dict(os.environ, environment, clear=True): beta.validate_caller(self.repo, self.sha)
        for key, value in (('GITHUB_JOB', 'upload'), ('GITHUB_EVENT_NAME', 'pull_request'),
                           ('GITHUB_REF', 'refs/heads/develop/0.2.2'),
                           ('GITHUB_WORKFLOW_REF', f'{self.repo}/.github/workflows/app-store.yml@refs/heads/main')):
            with mock.patch.dict(os.environ, dict(environment, **{key: value}), clear=True), self.assertRaises(candidate.CandidateError):
                beta.validate_caller(self.repo, self.sha)


if __name__ == '__main__':
    unittest.main()
