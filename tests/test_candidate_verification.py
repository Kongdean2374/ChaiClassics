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
        tests = scoped.planned_tests(scoped.fingerprints(source), []) if scope == 'affected' else scoped.scopes.resolve(
            scope, scoped.fingerprints(source), include_sessions=bool(scoped.scopes.required_session_tests_for_paths(source)))
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

    def test_scoped_visual_keeps_original_successful_source_and_explicit_dependency_proof(self):
        source, counts, actual = self.prepare_scoped_evidence()
        older = 'b' * 40
        self.responses[f'repos/{self.repo}/actions/runs/{self.runs["visual"]}']['head_sha'] = older
        self.evidence['visual']['source_commit'] = older
        self.responses[f'repos/{self.repo}/actions/artifacts/{self.runs["visual"] * 10}/zip'] = self.archive('visual')
        dependency = {'verification': 'dependency-scoped-visual', 'source_commit': older,
                      'target_commit': self.sha, 'case_fingerprints': {'audited-case': 'c' * 64}}
        with mock.patch.object(scoped.historical, 'git_tree', return_value=source), \
                mock.patch.object(scoped.historical, 'load_results', return_value=(counts, actual)), \
                mock.patch.object(candidate, 'verify_tooling_only_equivalence', side_effect=candidate.CandidateError('Runtime changed.')), \
                mock.patch.object(candidate, 'verify_visual_case_equivalence', return_value=dependency) as validate:
            proof = self.verify()
            self.responses[f'repos/{self.repo}/actions/runs/{self.runs["visual"]}']['conclusion'] = 'failure'
            with self.assertRaises(candidate.CandidateError): self.verify()
        validate.assert_called_with(older, self.sha, self.root)
        visual = proof['workflows']['visual']
        self.assertEqual(visual['source_commit'], older)
        self.assertEqual(visual['case_dependency_equivalence'], dependency)
        self.assertNotIn('tooling_only_equivalence', visual)
        self.assertEqual(proof['source_commit'], self.sha)

    def test_visual_dependency_fallback_never_skips_ipad_runtime_equivalence(self):
        source, counts, actual = self.prepare_scoped_evidence()
        self.responses[f'repos/{self.repo}/actions/runs/{self.runs["ipad"]}']['head_sha'] = 'b' * 40
        with mock.patch.object(scoped.historical, 'git_tree', return_value=source), \
                mock.patch.object(scoped.historical, 'load_results', return_value=(counts, actual)), \
                mock.patch.object(candidate, 'verify_tooling_only_equivalence', side_effect=candidate.CandidateError('Runtime changed.')), \
                mock.patch.object(candidate, 'verify_visual_case_equivalence') as visual:
            with self.assertRaises(candidate.CandidateError): self.verify()
        visual.assert_not_called()

    def test_schema_three_partial_actual_pass_cannot_authorize_candidate(self):
        source, counts, actual = self.prepare_scoped_evidence('legacy')
        self.assertEqual(len(actual), 1)
        with mock.patch.object(scoped.historical, 'git_tree', return_value=source), mock.patch.object(scoped.historical, 'load_results', return_value=(counts, actual)):
            with self.assertRaisesRegex(candidate.CandidateError, 'partial'): self.verify()

    def test_scoped_gate_retains_original_screenshot_sha_only_for_proven_tooling_equivalence(self):
        source, counts, actual = self.prepare_scoped_evidence()
        for path in ['App/Info.plist', 'Core/SaveStore.swift', 'Package.swift',
                     'ChaiClassics.xcodeproj/project.pbxproj', 'scripts/ci.sh', 'fastlane/Fastfile']:
            source[path] = ('100644', ('protected:' + path).encode())
        source['scripts/verify_candidate.py'] = ('100644', b'new evidence reader')
        older = copy.deepcopy(source)
        older['scripts/verify_candidate.py'] = ('100644', b'old evidence reader')
        prior_sha = 'b' * 40
        evidence = scoped.make_evidence(self.sha, self.runs['ci'], 'full', counts, actual, source, [])
        self.responses[f'repos/{self.repo}/actions/artifacts/{self.runs["ci"] * 10}/zip'] = self.archive('ci', evidence=evidence)
        for kind in ['visual', 'ipad']:
            self.responses[f'repos/{self.repo}/actions/runs/{self.runs[kind]}']['head_sha'] = prior_sha
            earlier = copy.deepcopy(self.evidence[kind]); earlier['source_commit'] = prior_sha
            if kind == 'ipad': earlier['ipad_report']['device']['source_commit'] = prior_sha
            self.responses[f'repos/{self.repo}/actions/artifacts/{self.runs[kind] * 10}/zip'] = self.archive(kind, evidence=earlier)
        trees = lambda sha, *args: older if sha == prior_sha else source
        original = candidate.verify_tooling_only_equivalence
        equivalent = lambda old, new, root, **kwargs: original(old, new, root, tree_reader=trees, ancestor=lambda: True, **kwargs)
        with mock.patch.object(scoped.historical, 'git_tree', side_effect=trees), \
             mock.patch.object(scoped.historical, 'load_results', return_value=(counts, actual)), \
             mock.patch.object(candidate, 'verify_tooling_only_equivalence', side_effect=equivalent):
            proof = self.verify()
            self.assertEqual(proof['source_commit'], self.sha)
            for kind in ['visual', 'ipad']:
                self.assertEqual(proof['workflows'][kind]['source_commit'], prior_sha)
                self.assertEqual(proof['workflows'][kind]['tooling_only_equivalence']['target_commit'], self.sha)
            older['UITests/ChaiClassicsVisualSmokeTests.swift'] = ('100644', b'changed helper or assertion')
            with self.assertRaises(candidate.CandidateError): self.verify()

    def prepare_unexecuted_case_repair(self):
        legacy = self.root / 'UITests/ChaiClassicsUITests.swift'
        legacy.write_text('func testPlayRestoreWinRestart() { XCTAssertTrue(true, "repaired current case") }')
        source, counts, actual = self.prepare_scoped_evidence()
        for path in ['App/Info.plist', 'Core/SaveStore.swift', 'Package.swift',
                     'ChaiClassics.xcodeproj/project.pbxproj', 'scripts/ci.sh', 'fastlane/Fastfile']:
            source[path] = ('100644', ('protected:' + path).encode())
        source['scripts/verify_candidate.py'] = ('100644', b'new evidence reader')
        older = copy.deepcopy(source)
        older['scripts/verify_candidate.py'] = ('100644', b'old evidence reader')
        older['UITests/ChaiClassicsUITests.swift'] = ('100644', b'func testPlayRestoreWinRestart() {}')
        evidence = scoped.make_evidence(self.sha, self.runs['ci'], 'full', counts, actual, source, [])
        self.responses[f'repos/{self.repo}/actions/artifacts/{self.runs["ci"] * 10}/zip'] = self.archive('ci', evidence=evidence)
        prior_sha = 'b' * 40
        for kind in ['visual', 'ipad']:
            self.responses[f'repos/{self.repo}/actions/runs/{self.runs[kind]}']['head_sha'] = prior_sha
            earlier = copy.deepcopy(self.evidence[kind]); earlier['source_commit'] = prior_sha
            if kind == 'ipad': earlier['ipad_report']['device']['source_commit'] = prior_sha
            self.responses[f'repos/{self.repo}/actions/artifacts/{self.runs[kind] * 10}/zip'] = self.archive(kind, evidence=earlier)
        return source, older, counts, actual, prior_sha

    def test_unexecuted_case_repair_preserves_actual_screenshot_source_and_selected_bodies(self):
        source, older, counts, actual, prior_sha = self.prepare_unexecuted_case_repair()
        trees = lambda sha, *args: older if sha == prior_sha else source
        original = candidate.verify_tooling_only_equivalence
        equivalent = lambda old, new, root, **kwargs: original(old, new, root, tree_reader=trees, ancestor=lambda: True, **kwargs)
        with mock.patch.object(scoped.historical, 'git_tree', side_effect=trees), \
             mock.patch.object(scoped.historical, 'load_results', return_value=(counts, actual)), \
             mock.patch.object(candidate, 'verify_tooling_only_equivalence', side_effect=equivalent):
            proof = self.verify()
            self.assertEqual(proof['source_commit'], self.sha)
            for kind in ['visual', 'ipad']:
                workflow = proof['workflows'][kind]
                self.assertEqual(workflow['source_commit'], prior_sha)
                self.assertEqual(workflow['tooling_only_equivalence']['source_commit'], prior_sha)
                self.assertEqual(workflow['tooling_only_equivalence']['target_commit'], self.sha)
                protected = candidate.expected_tests(kind, self.root)
                if kind == 'ipad': protected += candidate.ipad_game_tests(self.root)
                self.assertEqual(workflow['tooling_only_equivalence']['tested_cases'], sorted(protected))
                self.assertEqual(len(workflow['tooling_only_equivalence']['runtime_scaffold_and_testbody_digest']), 64)
            self.assertEqual(proof['workflows']['ipad']['device']['source_commit'], prior_sha)
            # Screenshot reuse cannot compensate for failing to execute the repaired CI case.
            actual.pop('ChaiClassicsUITests/testPlayRestoreWinRestart')
            counts['totalTestCount'] -= 1; counts['passedTests'] -= 1
            with self.assertRaises(candidate.CandidateError): self.verify()

    def test_selected_visual_or_ipad_body_and_forged_original_sha_cannot_reuse_evidence(self):
        source, older, counts, actual, prior_sha = self.prepare_unexecuted_case_repair()
        trees = lambda sha, *args: older if sha == prior_sha else source
        original = candidate.verify_tooling_only_equivalence
        equivalent = lambda old, new, root, **kwargs: original(old, new, root, tree_reader=trees, ancestor=lambda: True, **kwargs)
        with mock.patch.object(scoped.historical, 'git_tree', side_effect=trees), \
             mock.patch.object(scoped.historical, 'load_results', return_value=(counts, actual)), \
             mock.patch.object(candidate, 'verify_tooling_only_equivalence', side_effect=equivalent):
            for path, method in [('UITests/ChaiClassicsVisualSmokeTests.swift', 'testLight'),
                                 ('UITests/ChaiClassicsV020UITests.swift', 'testTwentyFourRestoresExactCardsCompletesAndStartsNextPuzzle')]:
                mode, data = older[path]
                older[path] = (mode, data.replace(('func ' + method + '() {}').encode(),
                                                 ('func ' + method + '() { XCTAssertTrue(false) }').encode()))
                with self.subTest(executed=method), self.assertRaises(candidate.CandidateError): self.verify()
                older[path] = (mode, data)
            forged = copy.deepcopy(self.evidence['ipad'])
            self.responses[f'repos/{self.repo}/actions/artifacts/{self.runs["ipad"] * 10}/zip'] = self.archive('ipad', evidence=forged)
            with self.assertRaises(candidate.CandidateError): self.verify()

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

    def test_session_runtime_requires_all_nine_real_journeys_and_counts_them_without_new_skips(self):
        before = {kind: len(candidate.expected_tests(kind, self.root)) for kind in ('ci', 'visual')}
        (self.root / 'App').mkdir(exist_ok=True)
        (self.root / 'App/GameSessionComponents.swift').write_text('struct GameSessionComponents {}')
        with self.assertRaises(candidate.CandidateError): candidate.expected_tests('ci', self.root)
        visual = self.root / 'UITests/ChaiClassicsVisualSmokeTests.swift'
        visual.write_text(visual.read_text() + ''.join('\nfunc ' + name + '() {}' for name in candidate.scopes.SESSION_VISUAL_TESTS))
        for kind in ('ci', 'visual'):
            required = candidate.expected_tests(kind, self.root)
            self.assertEqual(len(required), before[kind] + len(candidate.scopes.SESSION_VISUAL_TESTS))
            actual = {name: 'skipped' if name.split('/')[-1] in candidate.IPAD_TESTS else 'passed' for name in required}
            counts = {'result': 'Passed', 'totalTestCount': len(required), 'passedTests': len(required) - 4,
                      'failedTests': 0, 'skippedTests': 4}
            evidence = candidate.make_evidence(kind, counts, self.sha, executed_tests=actual, root=self.root)
            self.assertEqual(evidence['expected_tests'], required)
            for method in candidate.scopes.SESSION_VISUAL_TESTS:
                skipped = dict(actual); skipped['ChaiClassicsVisualSmokeTests/' + method] = 'skipped'
                with self.subTest(kind=kind, skipped=method), self.assertRaises(candidate.CandidateError):
                    candidate.make_evidence(kind, counts, self.sha, executed_tests=skipped, root=self.root)
            old_counts = dict(counts, totalTestCount=before[kind], passedTests=before[kind] - 4)
            with self.assertRaises(candidate.CandidateError):
                candidate.make_evidence(kind, old_counts, self.sha, executed_tests=actual, root=self.root)
        self.assertEqual(len(candidate.expected_tests('ipad', self.root)), len(candidate.IPAD_TESTS))
        method = candidate.scopes.HISTORY_TEST
        visual.write_text(visual.read_text().replace('\nfunc ' + method + '() {}', ''))
        with self.assertRaises(candidate.CandidateError): candidate.expected_tests('visual', self.root)

    def focused_visual_fixture(self):
        (self.root / 'scripts').mkdir(exist_ok=True)
        script = self.root / 'scripts/visual_smoke.sh'
        script.write_text((Path(__file__).resolve().parents[1] / 'scripts/visual_smoke.sh').read_text())
        visual = self.root / 'UITests/ChaiClassicsVisualSmokeTests.swift'
        names = sorted(candidate.IPAD_TESTS) + [name.split('/')[-1] for name in candidate.VISUAL_FOCUS_TESTS]
        visual.write_text('\n'.join('func ' + name + '() {}' for name in names))
        return visual, script

    def test_focused_visual_is_exact_four_only_for_reviewed_marker_and_session_runtime(self):
        visual, script = self.focused_visual_fixture()
        # The historical eight-case contract keeps four real phone passes and four iPad skips.
        self.assertEqual(len(candidate.expected_tests('visual', self.root)), 8)
        actual = {name: 'skipped' if name.split('/')[-1] in candidate.IPAD_TESTS else 'passed'
                  for name in candidate.expected_tests('visual', self.root)}
        old_summary = {'result': 'Passed', 'totalTestCount': 8, 'passedTests': 4, 'failedTests': 0, 'skippedTests': 4}
        candidate.make_evidence('visual', old_summary, self.sha, executed_tests=actual, root=self.root)
        (self.root / 'App').mkdir(exist_ok=True)
        (self.root / 'App/GameSessionComponents.swift').write_text('struct GameSessionComponents {}')
        visual.write_text(visual.read_text() + ''.join('\nfunc ' + name + '() {}' for name in candidate.scopes.SESSION_VISUAL_TESTS))
        selected = candidate.expected_tests('visual', self.root)
        self.assertEqual(selected, sorted(candidate.VISUAL_FOCUS_TESTS))
        summary = {'result': 'Passed', 'totalTestCount': 4, 'passedTests': 4, 'failedTests': 0, 'skippedTests': 0}
        evidence = candidate.make_evidence('visual', summary, self.sha, executed_tests=dict.fromkeys(selected, 'passed'), root=self.root)
        self.assertEqual(evidence['summary']['passedTests'], 4)
        for altered in (summary | {'skippedTests': 4}, old_summary):
            with self.assertRaises(candidate.CandidateError):
                candidate.make_evidence('visual', altered, self.sha, executed_tests=dict.fromkeys(selected, 'passed'), root=self.root)
        original = script.read_text()
        for bad in (original.replace(candidate.VISUAL_FOCUS_MARKER, candidate.VISUAL_FOCUS_MARKER + '\n' + candidate.VISUAL_FOCUS_MARKER),
                    original.replace('/testScreenshotGallery', ''),
                    original + '\n# -only-testing:ChaiClassicsUITests/ChaiClassicsVisualSmokeTests/testHistory\n'):
            script.write_text(bad)
            with self.assertRaises(candidate.CandidateError): candidate.expected_tests('visual', self.root)
        script.write_text(original.replace(candidate.VISUAL_FOCUS_MARKER, '# unreviewed focus'))
        self.assertEqual(len(candidate.expected_tests('visual', self.root)), 17)

    def test_visual_four_passes_never_replace_any_of_the_nine_mandatory_ci_journeys(self):
        visual, _script = self.focused_visual_fixture()
        (self.root / 'App').mkdir(exist_ok=True)
        (self.root / 'App/GameSessionComponents.swift').write_text('struct GameSessionComponents {}')
        visual.write_text(visual.read_text() + ''.join('\nfunc ' + name + '() {}' for name in candidate.scopes.SESSION_VISUAL_TESTS))
        for kind in ('ci', 'visual'):
            tests = candidate.expected_tests(kind, self.root)
            actual = {name: 'skipped' if name.split('/')[-1] in candidate.IPAD_TESTS else 'passed' for name in tests}
            counts = {'result': 'Passed', 'totalTestCount': len(tests), 'passedTests': sum(state == 'passed' for state in actual.values()),
                      'failedTests': 0, 'skippedTests': sum(state == 'skipped' for state in actual.values())}
            self.evidence[kind] = candidate.make_evidence(kind, counts, self.sha, executed_tests=actual, root=self.root)
            artifact = f'repos/{self.repo}/actions/artifacts/{self.runs[kind] * 10}/zip'
            self.responses[artifact] = self.archive(kind)
        self.assertEqual(self.verify()['workflows']['visual']['summary']['passedTests'], 4)
        artifact = f'repos/{self.repo}/actions/artifacts/{self.runs["ci"] * 10}/zip'
        for method in candidate.scopes.SESSION_VISUAL_TESTS:
            missing = copy.deepcopy(self.evidence['ci'])
            del missing['executed_tests']['ChaiClassicsVisualSmokeTests/' + method]
            missing['summary']['totalTestCount'] -= 1; missing['summary']['passedTests'] -= 1
            self.responses[artifact] = self.archive('ci', evidence=missing)
            with self.subTest(missing=method), self.assertRaises(candidate.CandidateError): self.verify()

    def test_beta_three_passes_remain_partial_for_the_full_formal_candidate_gate(self):
        visual, _script = self.focused_visual_fixture()
        (self.root / 'App').mkdir(exist_ok=True)
        (self.root / 'App/GameSessionComponents.swift').write_text('struct GameSessionComponents {}')
        visual.write_text(visual.read_text() + ''.join('\nfunc ' + name + '() {}' for name in candidate.scopes.SESSION_VISUAL_TESTS))
        source, counts, actual = self.prepare_scoped_evidence('beta')
        self.assertEqual(len(actual), 3)
        self.assertEqual(counts['passedTests'], 3)
        self.assertEqual(counts['skippedTests'], 0)
        with mock.patch.object(scoped.historical, 'git_tree', return_value=source), mock.patch.object(scoped.historical, 'load_results', return_value=(counts, actual)):
            with self.assertRaisesRegex(candidate.CandidateError, 'partial'): self.verify()

    def assert_development_version_stays_exact_sha_and_unsigned(self, version):
        tag = f'v{version}-rc.1'; branch = f'develop/{version}'
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

    def test_v021_development_proof_retains_exact_sha_and_never_authorizes_release(self):
        self.assert_development_version_stays_exact_sha_and_unsigned('0.2.1')

    def test_v022_development_proof_retains_exact_sha_and_never_authorizes_release(self):
        self.assert_development_version_stays_exact_sha_and_unsigned('0.2.2')

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
