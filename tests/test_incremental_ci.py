"""An incremental proof must retain the failed full run and identify every reused case."""
import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import verify_candidate as candidate
import verify_incremental_ci as incremental


TEST_METHODS = {
    'ChaiClassicsUITests': [
        'testSudokuNavigationAndRestoration', 'testHomeHasExactlyThreeColumns',
        'testMinesFirstRevealAndRestoration', 'testSlidingCanStartAndRestore',
        'testSlidingSwipesInAllFourDirectionsAndRestoresExactlyOneMove',
        'testMinesSizeCountDifficultyEstimateAndRandomStart',
        'testLegacyFlagModeStillRevealsOnSingleTap',
        'testMinesBoardCenteredAndLargeBoardZoomKeepsHitCoordinates',
        'testThemeLanguagePreferencesAndLegacySummariesPersist',
        'testEnglishIsAppliedToAllGamesAndAccessibility',
        'testBundledLegalAndSupportInBothLanguages',
    ],
    'ChaiClassicsVisualSmokeTests': [
        'testFreshWinCelebratesOnceAndRestoredWinDoesNotReplay',
        'testReducedMotionSuppressesCelebrationButStillCompletesGame',
        'testLowPowerSuppressesCelebrationButStillCompletesGame', 'testScreenshotGallery',
        'testIPadHomeScreenshot', 'testIPadSudokuScreenshot',
        'testIPadMinesweeperScreenshot', 'testIPadSlidingPuzzleScreenshot',
    ],
    'ChaiClassicsV020UITests': [
        'testCompleteCatalogAndThirteenComingSoonPagesInEnglish',
        'testCompleteCatalogAndThirteenComingSoonPagesInTraditionalChinese',
        'testAllEightPlayableCardsOpenRealMenus',
        'testTicTacToeLocalRoundRestoresWinsAndReplays',
        'testConnectFourLocalRoundRestoresWinsAndReplays',
        'testTicTacToeAIRepliesAtEveryDifficultyWithEitherFirstPlayer',
        'testConnectFourAIRepliesAtEveryDifficultyWithEitherFirstPlayer',
        'testTwentyFourRestoresExactCardsCompletesAndStartsNextPuzzle',
        'testMemoryRestoresMatchesHidesUnturnedCardsCompletesAndReplays',
        'testMazeRestoresPositionResumesCompletesAndGeneratesNextMaze',
        'testNewPuzzleModesStartRealBoards',
        'testCorruptNewSaveRecoveryPreservesAllThreeLegacySaves',
        'testFutureSchemaRemainsProtectedAcrossRelaunch',
        'testCatalogLayoutAt320PointViewport', 'testCatalogLayoutAt375PointViewport',
        'testCatalogLayoutAt390PointViewport', 'testCatalogLayoutAt430PointViewport',
        'testAccessibilityTypeAdaptsCatalogAndSupportsReducedMotion',
    ],
}
SELECTED = {
    'ChaiClassicsUITests/testSlidingCanStartAndRestore',
    'ChaiClassicsUITests/testSlidingSwipesInAllFourDirectionsAndRestoresExactlyOneMove',
    'ChaiClassicsVisualSmokeTests/testFreshWinCelebratesOnceAndRestoredWinDoesNotReplay',
}
FAILED = SELECTED - {'ChaiClassicsUITests/testSlidingSwipesInAllFourDirectionsAndRestoresExactlyOneMove'}
SCROLL_HELPER = '''    private func scrollFullyIntoView(_ element: XCUIElement, app: XCUIApplication) {
        let viewport = app.scrollViews.firstMatch
        if viewport.exists { _ = viewport.frame }
        XCTAssertTrue(element.isHittable)
        if !element.exists { XCTFail("Still missing { control }") }
    }
'''
FIXED_SCROLL_HELPER = '''    private func scrollFullyIntoView(_ element: XCUIElement, app: XCUIApplication) {
        // Read actual window geometry; there is no stale ScrollView query.
        _ = app.frame
        XCTAssertTrue(element.isHittable)
        if !element.exists { XCTFail("Still missing { control }") }
    }
'''


def source_tree():
    tree = {}
    for name, methods in TEST_METHODS.items():
        helpers = SCROLL_HELPER if name != 'ChaiClassicsV020UITests' else ''
        if name == 'ChaiClassicsVisualSmokeTests':
            helpers += '''    private func openSavedSliding(_ app: XCUIApplication) {
        let resume = app.buttons["sliding.continue"]
        resume.tap()
    }
'''
        bodies = ''.join('    func ' + method + '''() {
        let text = "A literal { brace } does not delimit a method."
        if true { XCTAssertTrue(true, text) }
    }
''' for method in methods)
        text = 'import XCTest\nfinal class ' + name + ': XCTestCase {\n' + helpers + bodies + '}\n'
        tree['UITests/' + name + '.swift'] = ('100644', text.encode())
    for path in (
        'App/AppModel.swift', 'App/UITestBootstrap.swift', 'Core/Maze.swift',
        'App/Resources/en.lproj/Localizable.strings', 'Core/Resources/sudoku-v1.json',
        'ChaiClassics.xcodeproj/project.pbxproj', 'Package.swift', 'Gemfile', 'Gemfile.lock',
        'fastlane/Fastfile', 'scripts/create_project.py', 'scripts/run_signing_lane.py',
        '.github/workflows/initialize-signing.yml', '.github/workflows/appstore.yml',
    ):
        tree[path] = ('100644', ('protected bytes: ' + path + '\n').encode())
    tree['.github/workflows/testflight.yml'] = ('100644', b'name: TestFlight\non:\n  workflow_dispatch:\njobs:\n  preflight:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: actions/checkout@fixture\n        with:\n          persist-credentials: false\n  upload:\n    environment: testflight\n    runs-on: macos-15-intel\n')
    tree['scripts/ci.sh'] = ('100755', b'#!/bin/bash\nset -euo pipefail\n')
    tree['.github/workflows/ci.yml'] = ('100644', b'name: CI\n')
    tree['docs/v020-release.md'] = ('100644', b'Existing release documentation.\n')
    return tree


class IncrementalSourceTests(unittest.TestCase):
    def setUp(self):
        self.base = source_tree()

    def edit(self, path, change):
        current = copy.deepcopy(self.base)
        mode, data = current[path]
        current[path] = (mode, change(data))
        return current

    def test_identical_trees_and_allowed_helper_changes_keep_application_digest(self):
        same = incremental.validate_source_trees(self.base, self.base)
        current = copy.deepcopy(self.base)
        for path in ('UITests/ChaiClassicsUITests.swift', 'UITests/ChaiClassicsVisualSmokeTests.swift'):
            mode, data = current[path]
            current[path] = (mode, data.replace(SCROLL_HELPER.encode(), FIXED_SCROLL_HELPER.encode()))
        current['scripts/ui_test_scope.py'] = ('100644', b'# Targeted test selectors only.\n')
        current['scripts/verify_incremental_ci.py'] = ('100644', b'# Evidence verifier.\n')
        current['tests/test_incremental_ci.py'] = ('100644', b'# Regression coverage.\n')
        current['docs/v020-release.md'] = ('100644', b'Explicit incremental evidence documentation.\n')
        result = incremental.validate_source_trees(self.base, current)
        self.assertRegex(result['app_source_digest'], r'^[0-9a-f]{64}$')
        self.assertEqual(result['app_source_digest'], same['app_source_digest'])
        self.assertEqual(result['test_methods_digest'], same['test_methods_digest'])
        self.assertEqual(set(result['changed_paths']), {path for path in current if current.get(path) != self.base.get(path)})

    def test_open_saved_sliding_can_add_real_readiness_assertion(self):
        current = self.edit('UITests/ChaiClassicsVisualSmokeTests.swift', lambda data: data.replace(
            b'        resume.tap()', b'        XCTAssertTrue(resume.waitForExistence(timeout: 10))\n        resume.tap()'))
        result = incremental.validate_source_trees(self.base, current)
        self.assertEqual(result['test_methods_digest'], incremental.validate_source_trees(self.base, self.base)['test_methods_digest'])

    def test_application_resource_project_bootstrap_and_signing_changes_are_rejected(self):
        protected = [path for path in self.base if not path.startswith(('UITests/', 'docs/')) and path not in {
            'scripts/ci.sh', '.github/workflows/ci.yml', '.github/workflows/testflight.yml',
        }]
        for path in protected:
            with self.subTest(path=path), self.assertRaises(candidate.CandidateError):
                incremental.validate_source_trees(self.base, self.edit(path, lambda data: data + b'changed\n'))

    def test_application_file_addition_deletion_or_mode_change_are_rejected(self):
        for change in ('addition', 'deletion', 'mode'):
            current = copy.deepcopy(self.base)
            if change == 'addition':
                current['App/UnexpectedRuntime.swift'] = ('100644', b'import Foundation\n')
            elif change == 'deletion':
                current.pop('Core/Maze.swift')
            else:
                current['App/AppModel.swift'] = ('100755', current['App/AppModel.swift'][1])
            with self.subTest(change=change), self.assertRaises(candidate.CandidateError):
                incremental.validate_source_trees(self.base, current)

    def test_test_body_changes_deletions_and_injected_assertion_removal_are_rejected(self):
        path = 'UITests/ChaiClassicsUITests.swift'
        changes = [
            lambda data: data.replace(b'XCTAssertTrue(true, text)', b'XCTAssertTrue(false, text)', 1),
            lambda data: data.replace(b'XCTAssertTrue(true, text)', b'_ = text', 1),
            lambda data: data.replace(b'func testSlidingCanStartAndRestore', b'func removedSlidingCase'),
            lambda data: data.replace(b'A literal { brace }', b'A changed literal { brace }', 1),
        ]
        for index, change in enumerate(changes):
            with self.subTest(change=index), self.assertRaises(candidate.CandidateError):
                incremental.validate_source_trees(self.base, self.edit(path, change))

    def test_unapproved_helpers_or_setup_code_cannot_change(self):
        for path, change in [
            ('UITests/ChaiClassicsUITests.swift', lambda data: data.replace(b'import XCTest', b'import XCTest\n// changed setup')),
            ('UITests/ChaiClassicsV020UITests.swift', lambda data: data.replace(b'import XCTest', b'import XCTest\n// helper change')),
        ]:
            with self.subTest(path=path), self.assertRaises(candidate.CandidateError):
                incremental.validate_source_trees(self.base, self.edit(path, change))

    def test_allowed_helper_cannot_remove_existing_assertions(self):
        path = 'UITests/ChaiClassicsUITests.swift'
        for expression in [b'        XCTAssertTrue(element.isHittable)\n', b'        if !element.exists { XCTFail("Still missing { control }") }\n']:
            current = self.edit(path, lambda data: data.replace(expression, b'', 1))
            with self.subTest(expression=expression), self.assertRaises(candidate.CandidateError):
                incremental.validate_source_trees(self.base, current)

    def test_testflight_preflight_only_changes_cannot_modify_header_or_upload(self):
        path = '.github/workflows/testflight.yml'
        allowed = self.edit(path, lambda data: data.replace(b'          persist-credentials: false\n', b'          persist-credentials: false\n          fetch-depth: 0\n'))
        incremental.validate_source_trees(self.base, allowed)
        for before, after in [
            (b'name: TestFlight', b'name: Unprotected Flight'),
            (b'environment: testflight', b'environment: other'),
            (b'    runs-on: ubuntu-24.04', b'    runs-on: ubuntu-24.04\n    # arbitrary preflight gate change'),
        ]:
            with self.subTest(before=before), self.assertRaises(candidate.CandidateError):
                incremental.validate_source_trees(self.base, self.edit(path, lambda data: data.replace(before, after)))


class IncrementalCoverageTests(unittest.TestCase):
    def setUp(self):
        self.expected = sorted(name + '/' + method for name, methods in TEST_METHODS.items() for method in methods)
        self.assertEqual(len(self.expected), 37)
        self.baseline = {name: ('skipped' if name.split('/')[-1] in candidate.IPAD_TESTS else 'failed' if name in FAILED else 'passed') for name in self.expected}
        self.target = {name: 'passed' for name in SELECTED}
        self.baseline_summary = {'totalTestCount': 37, 'passedTests': 31, 'failedTests': 2, 'skippedTests': 4, 'result': 'Failed'}
        self.target_summary = {'totalTestCount': 3, 'passedTests': 3, 'failedTests': 0, 'skippedTests': 0, 'result': 'Passed'}
        self.baseline_run = incremental.BASELINE_RUN
        self.target_run = 99_999_999_999

    def verify(self, **changes):
        arguments = {
            'baseline_summary': self.baseline_summary, 'baseline_actual': self.baseline,
            'target_summary': self.target_summary, 'target_actual': self.target,
            'expected_tests': self.expected, 'baseline_run': self.baseline_run, 'target_run': self.target_run,
        }
        arguments.update(changes)
        return incremental.validate_coverage(**arguments)

    def test_real_full_baseline_and_three_targeted_passes_produce_explicit_union(self):
        result = self.verify()
        expected = {name: ('skipped' if name.split('/')[-1] in candidate.IPAD_TESTS else 'passed') for name in self.expected}
        self.assertEqual(result['aggregate_statuses'], expected)
        self.assertEqual(set(result['coverage']), set(self.expected))
        for name, status in expected.items():
            self.assertEqual(result['coverage'][name]['status'], status)
            self.assertEqual(result['coverage'][name]['source_run'], self.target_run if name in SELECTED else self.baseline_run)
        self.assertEqual(sum(value == 'passed' for value in self.baseline.values()), 31)
        self.assertEqual(sum(value == 'passed' for value in result['aggregate_statuses'].values()), 33)

    def test_missing_failed_skipped_or_wrong_target_case_is_rejected(self):
        original = sorted(SELECTED)[0]
        variants = []
        missing = dict(self.target); missing.pop(original); variants.append(missing)
        for state in ['failed', 'skipped']:
            values = dict(self.target); values[original] = state; variants.append(values)
        wrong = dict(self.target); wrong.pop(original); wrong['ChaiClassicsUITests/testUnrelatedCase'] = 'passed'; variants.append(wrong)
        for index, actual in enumerate(variants):
            with self.subTest(change=index), self.assertRaises(candidate.CandidateError):
                self.verify(target_actual=actual)

    def test_baseline_only_the_two_known_failures_and_four_ipad_skips_are_accepted(self):
        other = next(name for name, status in self.baseline.items() if status == 'passed' and name not in SELECTED)
        for name, status in [(other, 'failed'), (other, 'skipped'), (next(iter(FAILED)), 'passed')]:
            changed = dict(self.baseline); changed[name] = status
            with self.subTest(name=name, status=status), self.assertRaises(candidate.CandidateError):
                self.verify(baseline_actual=changed)

    def test_baseline_missing_case_or_wrong_case_cannot_hide_behind_same_count(self):
        name = next(iter(self.baseline))
        missing = dict(self.baseline); missing.pop(name)
        wrong = dict(missing); wrong['AnotherClass/testReplacement'] = self.baseline[name]
        for actual in [missing, wrong]:
            with self.assertRaises(candidate.CandidateError):
                self.verify(baseline_actual=actual)

    def test_summary_cannot_forge_current_full_run_or_disagree_with_actual_records(self):
        for summary in [
            self.target_summary | {'totalTestCount': 37, 'passedTests': 33, 'skippedTests': 4},
            self.target_summary | {'passedTests': 2},
            self.target_summary | {'failedTests': 1},
            self.target_summary | {'result': 'Failed'},
            self.target_summary | {'passedTests': True},
        ]:
            with self.subTest(summary=summary), self.assertRaises(candidate.CandidateError):
                self.verify(target_summary=summary)
        with self.assertRaises(candidate.CandidateError):
            self.verify(baseline_summary=self.baseline_summary | {'passedTests': 33, 'failedTests': 0, 'result': 'Passed'})

    def test_unknown_or_same_run_ids_cannot_substitute_baseline_evidence(self):
        for changes in [
            {'baseline_run': 123}, {'target_run': self.baseline_run}, {'target_run': 0}, {'target_run': True},
        ]:
            with self.subTest(changes=changes), self.assertRaises(candidate.CandidateError):
                self.verify(**changes)


if __name__ == '__main__':
    unittest.main()
