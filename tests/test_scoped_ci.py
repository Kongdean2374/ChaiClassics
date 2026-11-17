"""Real A/B passes survive a C-only fix; missing/failed/changed execution never turns green."""
import copy
import json
import io
import plistlib
import zipfile
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
    path = 'UITests/ChaiClassicsVisualSmokeTests.swift'
    mode, data = value[path]
    extra = ''.join('    func ' + name + '() { XCTAssertTrue(true) }\n' for name in scopes.SESSION_VISUAL_TESTS)
    value[path] = (mode, data[:-2] + extra.encode() + b'}\n')
    value['App/GameSessionComponents.swift'] = ('100644', b'struct GameSessionComponents {}\n')
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

    def test_c_game_view_only_change_preserves_actual_a_and_b_dependencies(self):
        updated = self.edited('App/MazeView.swift')
        self.assertEqual(self.fp[A], updated[A])
        self.assertEqual(self.fp[B], updated[B])
        self.assertNotEqual(self.fp[C], updated[C])

    def test_shared_preferences_clock_resources_bootstrap_and_generator_invalidate_all(self):
        for path in ['Core/AppPreferences.swift', 'Core/MemoryMatch.swift', 'Core/Maze.swift', 'Core/Random.swift', 'App/AnimationFrameClock.swift', 'App/DesignSystem.swift', 'App/NewGameComponents.swift', 'App/UITestBootstrap.swift',
                     'App/Resources/en.lproj/Localizable.strings', 'App/Resources/game-maze.imageset/image.png',
                     'scripts/create_project.py', 'Package.swift', 'ChaiClassics.xcodeproj/project.pbxproj',
                     'scripts/ci.sh', 'scripts/ui_test_scope.py', '.github/workflows/ci.yml', 'App/UnexpectedRuntime.swift',
                     *scoped.SHARED_SESSION_FILES]:
            with self.subTest(path=path):
                updated = self.edited(path)
                self.assertTrue(all(self.fp[test] != updated[test] for test in self.fp))

    def test_session_runtime_cannot_remove_a_required_new_journey(self):
        target = copy.deepcopy(self.base)
        path = 'UITests/ChaiClassicsVisualSmokeTests.swift'
        mode, data = target[path]
        method = scopes.SESSION_LIFECYCLE_TESTS['memory']
        target[path] = (mode, data.replace(('    func ' + method + '() { XCTAssertTrue(true) }\n').encode(), b''))
        with self.assertRaises(candidate.CandidateError): scoped.fingerprints(target)

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


class ReviewedFlowProfileTests(unittest.TestCase):
    def setUp(self):
        self.base = tree()
        root = Path(__file__).resolve().parents[1]
        for path in (root / 'UITests').glob('*.swift'):
            self.base[str(path.relative_to(root))] = ('100644', path.read_bytes())
        for path in scoped.ALL_GAME_FILES:
            file = root / path
            if file.exists(): self.base[path] = ('100644', file.read_bytes())
        self.bodies = {}; self.helpers = {}
        for path, (_mode, data) in self.base.items():
            if path.startswith('UITests/') and path.endswith('.swift'):
                source = data.decode()
                functions = scoped.historical.functions(source)
                scaffold = source
                for name, (start, end) in sorted(functions.items(), key=lambda item: item[1][0], reverse=True):
                    if name.startswith('test'): self.bodies[Path(path).stem + '/' + name] = source[start:end]
                    if name.startswith('test'): scaffold = scaffold[:start] + '{TEST_BODY}' + scaffold[end:]
                self.helpers[Path(path).stem] = scoped.hashlib.sha256(scaffold.encode()).hexdigest()
        self.before = scoped.fingerprints(self.base)

    def dependencies(self, name, body):
        return scoped.dependencies(name, body, helper_fingerprint=self.helpers.get(name.split('/')[0]))

    def changed(self, path):
        result = copy.deepcopy(self.base)
        mode, data = result.get(path, ('100644', b''))
        result[path] = (mode, data + b'\n// actual changed dependency\n')
        return scoped.fingerprints(result)

    def test_profiles_are_bound_to_reviewed_current_test_bodies(self):
        self.assertGreaterEqual(len(scoped.BODY_PROFILES), 24)
        for name, (expected, games) in scoped.BODY_PROFILES.items():
            with self.subTest(test=name):
                self.assertIn(name, self.bodies)
                body = self.bodies[name]
                if scoped.hashlib.sha256(body.encode()).hexdigest() == expected:
                    self.assertEqual(self.dependencies(name, body), set().union(*(scoped.GAME_FILES[game] for game in games)))
                elif name in scoped.SESSION_BODY_PROFILES:
                    expected, games = scoped.SESSION_BODY_PROFILES[name]
                    self.assertEqual(scoped.hashlib.sha256(body.encode()).hexdigest(), expected)
                    self.assertEqual(self.helpers[name.split('/')[0]], scoped.VISUAL_SCAFFOLD_DIGEST)
                    self.assertEqual(self.dependencies(name, body), set().union(*(scoped.GAME_FILES[game] for game in games)))
                else:
                    self.assertEqual(self.dependencies(name, body), scoped.ALL_GAME_FILES,
                                     'An edited body must not inherit its previous reviewed profile')

    def test_current_session_profiles_require_both_actual_body_and_complete_shared_scaffold(self):
        self.assertEqual(len(scoped.SESSION_BODY_PROFILES), len(scopes.SESSION_VISUAL_TESTS) + 8)
        for name, (expected, games) in scoped.SESSION_BODY_PROFILES.items():
            body = self.bodies[name]
            self.assertEqual(scoped.hashlib.sha256(body.encode()).hexdigest(), expected)
            self.assertEqual(self.helpers[name.split('/')[0]], scoped.VISUAL_SCAFFOLD_DIGEST)
            self.assertEqual(self.dependencies(name, body), set().union(*(scoped.GAME_FILES[game] for game in games)))
            self.assertEqual(scoped.dependencies(name, body + '\n// changed', helper_fingerprint=scoped.VISUAL_SCAFFOLD_DIGEST), scoped.ALL_GAME_FILES)
            self.assertEqual(scoped.dependencies(name, body, helper_fingerprint='unreviewed helper'), scoped.ALL_GAME_FILES)

    def test_shared_session_requires_all_lifecycles_but_real_game_view_dependencies_remain_scoped(self):
        shared = self.changed('App/GameSessionComponents.swift')
        maze = self.changed('App/MazeView.swift')
        sliding = self.changed('App/SlidingView.swift')
        for game, method in scopes.SESSION_LIFECYCLE_TESTS.items():
            key = 'ChaiClassicsVisualSmokeTests/' + method
            self.assertNotEqual(self.before[key], shared[key])
            self.assertEqual(self.before[key] == maze[key], game != 'maze')
            # Every journey intentionally visits another saved menu after deletion.
            self.assertNotEqual(self.before[key], sliding[key])

    def test_zoom_board_audits_actual_multiple_consumers_and_keeps_shared_fallback(self):
        self.assertFalse(scoped.zoom_board_is_mines_only(self.base))
        with mock.patch.object(Path, 'read_bytes', side_effect=AssertionError('Use the supplied Git tree, never the checkout')):
            self.assertFalse(scoped.zoom_board_is_mines_only(self.base))
        shared = self.changed(scoped.ZOOM_BOARD_FILE)
        self.assertEqual({name for name in self.before if self.before[name] != shared[name]},set(self.before))
        after = self.changed('App/MinesView.swift')
        invalidated = {name for name in self.before if self.before[name] != after[name]}
        self.assertGreater(len(invalidated),0);self.assertLess(len(invalidated),len(self.before))
        self.assertIn('ChaiClassicsVisualSmokeTests/testMinesweeperCommonSessionLifecycleAndContinueDeletion',invalidated)
        self.assertIn('ChaiClassicsVisualSmokeTests/testSlidingCommonSessionLifecycleAndContinueDeletion',invalidated)
        self.assertNotIn('ChaiClassicsVisualSmokeTests/testMazeCommonSessionLifecycleAndContinueDeletion',invalidated)
        self.assertNotIn('ChaiClassicsV030UITests/testGomokuCompleteSessionRestoresAndConfirmsDeletion',invalidated)
        legacy = {path:entry for path,entry in self.base.items() if path not in {'App/ExpandedPuzzleView.swift','App/ExpandedStrategyView.swift','App/ExpandedSolitaireView.swift'}}
        self.assertTrue(scoped.zoom_board_is_mines_only(legacy),'An actual historical sole-consumer tree retains its scoped behavior')

    def test_zoom_board_unknown_consumer_and_global_or_shared_declarations_restore_shared_fallback(self):
        # Exercise the historical sole-consumer-to-shared transition; the current
        # multi-consumer tree is independently checked above.
        base = {path:entry for path,entry in self.base.items() if path not in {'App/ExpandedPuzzleView.swift','App/ExpandedStrategyView.swift','App/ExpandedSolitaireView.swift'}}
        before = scoped.fingerprints(base)
        mode, original = base[scoped.ZOOM_BOARD_FILE]
        variants = {
            'global': original + b'\nvar globallySharedZoom = 0\n',
            'shared extension': original + b'\nextension Color { static var sharedZoom: Int { 0 } }\n',
            'static state': original.replace(b'    let size:', b'    static var sharedZoom = 0\n    let size:', 1),
            'shared mutation': original.replace(b'        return scroll', b'        UserDefaults.standard.set(true, forKey: "global")\n        return scroll', 1),
            'new import': b'import Foundation\n' + original,
            'unknown nested declaration': original.replace(b'    let size:', b'    struct UnknownHelper {}\n    let size:', 1),
            'unknown attribute': original.replace(b'    let size:', b'    @MainActor let size:', 1),
            'malformed UTF8': original + b'\xff',
        }
        for label, data in variants.items():
            with self.subTest(change=label):
                target = copy.deepcopy(base); target[scoped.ZOOM_BOARD_FILE] = (mode, data)
                self.assertFalse(scoped.zoom_board_is_mines_only(target))
                after = scoped.fingerprints(target)
                self.assertTrue(all(before[name] != after[name] for name in before))
        for consumer in ('App/SudokuView.swift', 'App/UnexpectedView.swift'):
            target = copy.deepcopy(base)
            mode, data = target.get(consumer, ('100644', b''))
            target[consumer] = (mode, data + b'\ntypealias AnotherZoomConsumer = ZoomBoard\n')
            self.assertFalse(scoped.zoom_board_is_mines_only(target))
            after = scoped.fingerprints(target)
            self.assertTrue(all(before[name] != after[name] for name in before))
        target = copy.deepcopy(base)
        target[scoped.ZOOM_BOARD_FILE] = ('100755', original)
        self.assertFalse(scoped.zoom_board_is_mines_only(target))
        after = scoped.fingerprints(target)
        self.assertTrue(all(before[name] != after[name] for name in before))

    def privacy_fixture(self):
        path = scoped.PRIVACY_MANIFEST_FILE
        approved = (Path(__file__).resolve().parents[1] / path).read_bytes()
        boot_entry = (b'\t\t<dict>\n\t\t\t<key>NSPrivacyAccessedAPIType</key>\n'
                      b'\t\t\t<string>NSPrivacyAccessedAPICategorySystemBootTime</string>\n'
                      b'\t\t\t<key>NSPrivacyAccessedAPITypeReasons</key>\n\t\t\t<array>\n'
                      b'\t\t\t\t<string>35F9.1</string>\n\t\t\t</array>\n\t\t</dict>\n')
        self.assertEqual(approved.count(boot_entry), 1)
        legacy = approved.replace(boot_entry, b'')
        self.assertEqual(scoped.hashlib.sha256(legacy).hexdigest(), scoped.PRIVACY_GAMEPLAY_DIGEST)
        self.assertEqual(set(scoped.APPROVED_PRIVACY_MANIFESTS), {
            scoped.hashlib.sha256(legacy).hexdigest(), scoped.hashlib.sha256(approved).hexdigest()})
        target = copy.deepcopy(self.base); target[path] = ('100644', legacy)
        return target, legacy, approved

    def test_only_two_exact_validated_privacy_declarations_have_equal_shared_gameplay_hashes(self):
        before, legacy, approved = self.privacy_fixture()
        path = scoped.PRIVACY_MANIFEST_FILE
        self.assertNotIn(path, scoped.PURE_EVIDENCE_SCRIPTS)
        self.assertNotIn(path, scoped.ALL_GAME_FILES)
        target = copy.deepcopy(before); target[path] = ('100644', approved)
        self.assertEqual(scoped.fingerprints(before), scoped.fingerprints(target))
        self.assertEqual(scoped.shared_content_digest(path, '100644', approved), scoped.PRIVACY_GAMEPLAY_DIGEST)
        self.assertEqual(scoped.shared_content_digest('App/Resources/Other.xcprivacy', '100644', approved),
                         scoped.hashlib.sha256(approved).hexdigest())
        # Shared runtime edits still invalidate every case with the approved metadata.
        for shared in ('App/GameSessionComponents.swift', 'App/PlayHistoryView.swift'):
            mode, data = target.get(shared, ('100644', b''))
            changed = copy.deepcopy(target); changed[shared] = (mode, data + b'\n// actual runtime change\n')
            self.assertTrue(all(scoped.fingerprints(target)[name] != scoped.fingerprints(changed)[name]
                                for name in scoped.fingerprints(target)))

    def test_unapproved_privacy_values_xml_duplicates_modes_and_reencoding_invalidate_all_cases(self):
        base, _legacy, approved = self.privacy_fixture()
        path = scoped.PRIVACY_MANIFEST_FILE; before = scoped.fingerprints(base)
        parsed = plistlib.loads(approved)
        variants = {
            'tracking': approved.replace(b'<false/>', b'<true/>'),
            'unknown reason': approved.replace(b'35F9.1', b'35F9.2'),
            'user defaults reason': approved.replace(b'CA92.1', b'CA92.2'),
            'unknown category': approved.replace(b'SystemBootTime', b'FileTimestamp'),
            'extra root key': approved.replace(b'<key>NSPrivacyTracking</key>', b'<key>Extra</key><false/><key>NSPrivacyTracking</key>'),
            'duplicate root key': approved.replace(b'<key>NSPrivacyTracking</key>', b'<key>NSPrivacyTracking</key><false/><key>NSPrivacyTracking</key>'),
            'duplicate API key': approved.replace(b'<key>NSPrivacyAccessedAPITypeReasons</key>', b'<key>NSPrivacyAccessedAPITypeReasons</key><array/><key>NSPrivacyAccessedAPITypeReasons</key>', 1),
            'malformed': approved[:100],
            'valid but unreviewed XML': plistlib.dumps(parsed),
            'collected data': plistlib.dumps(dict(parsed, NSPrivacyCollectedDataTypes=[{'NSPrivacyCollectedDataType': 'Other'}])),
        }
        for label, data in variants.items():
            with self.subTest(change=label):
                self.assertNotIn(scoped.hashlib.sha256(data).hexdigest(), scoped.APPROVED_PRIVACY_MANIFESTS)
                self.assertEqual(scoped.shared_content_digest(path, '100644', data), scoped.hashlib.sha256(data).hexdigest())
                target = copy.deepcopy(base); target[path] = ('100644', data)
                after = scoped.fingerprints(target)
                self.assertTrue(all(before[name] != after[name] for name in before))
        target = copy.deepcopy(base); target[path] = ('100755', approved)
        self.assertEqual(scoped.shared_content_digest(path, '100755', approved), scoped.hashlib.sha256(approved).hexdigest())
        self.assertTrue(all(before[name] != scoped.fingerprints(target)[name] for name in before))
        target[path] = ('120000', approved)
        with self.assertRaises(candidate.CandidateError): scoped.fingerprints(target)
        # The static value check is independent of the byte allowlist.
        for invalid in (variants['tracking'], variants['unknown reason'], variants['malformed']):
            raw = scoped.hashlib.sha256(invalid).hexdigest()
            with mock.patch.dict(scoped.APPROVED_PRIVACY_MANIFESTS, {raw: True}):
                self.assertEqual(scoped.shared_content_digest(path, '100644', invalid), raw)

    def test_memory_play_change_preserves_unopened_flows_and_invalidates_six_real_dependents(self):
        after = self.changed('App/MemoryView.swift')
        changed = {test for test in self.before if self.before[test] != after[test]}
        unknown_memory_dependents = {name for name, (expected, _games) in scoped.BODY_PROFILES.items()
                                     if scoped.hashlib.sha256(self.bodies[name].encode()).hexdigest() != expected
                                     and 'App/MemoryView.swift' in self.dependencies(name, self.bodies[name])}
        reviewed_memory_dependents = {
            'ChaiClassicsV020UITests/testAllEightPlayableCardsOpenRealMenus',
            'ChaiClassicsV020UITests/testMemoryFlipMismatchGatesAndReducedMotionPreserveNativeCards',
            'ChaiClassicsV020UITests/testMemoryRestoresMatchesHidesUnturnedCardsCompletesAndReplays',
            'ChaiClassicsV020UITests/testNewPuzzleModesStartRealBoards',
            'ChaiClassicsV020UITests/testCorruptNewSaveRecoveryPreservesAllThreeLegacySaves',
            'ChaiClassicsV020UITests/testFutureSchemaRemainsProtectedAcrossRelaunch',
            'ChaiClassicsVisualSmokeTests/' + scopes.SESSION_LIFECYCLE_TESTS['memory'],
        }
        self.assertEqual(changed, unknown_memory_dependents | reviewed_memory_dependents)
        self.assertEqual(len(self.before) - len(changed), len(self.before) - len(unknown_memory_dependents | reviewed_memory_dependents))
        coverage = scoped.inherited_coverage(after, [record(self.base)])
        self.assertEqual(set(coverage), set(self.before) - changed)
        for retained in (B, 'ChaiClassicsV020UITests/testTicTacToeLocalRoundRestoresWinsAndReplays'):
            self.assertIn(retained, coverage)
            self.assertEqual(self.before[retained], after[retained])

    def test_core_changes_invalidate_every_flow_because_startup_restores_all_games(self):
        for path in ['Core/MemoryMatch.swift', 'Core/Maze.swift', 'Core/TicTacToe.swift', 'Core/TwentyFour.swift']:
            with self.subTest(path=path):
                after = self.changed(path)
                self.assertTrue(all(self.before[test] != after[test] for test in self.before))
                self.assertNotEqual(self.before['ChaiClassicsUITests/testHomeHasExactlyThreeColumns'], after['ChaiClassicsUITests/testHomeHasExactlyThreeColumns'])
                self.assertNotEqual(self.before['ChaiClassicsV020UITests/testTicTacToeLocalRoundRestoresWinsAndReplays'], after['ChaiClassicsV020UITests/testTicTacToeLocalRoundRestoresWinsAndReplays'])

    def test_pad_and_visual_flows_keep_their_actual_game_dependencies(self):
        sudoku_changed = self.changed('App/SudokuView.swift')
        for name in ('testIPadSudokuScreenshot', 'testScreenshotGallery'):
            key = 'ChaiClassicsVisualSmokeTests/' + name
            self.assertNotEqual(self.before[key], sudoku_changed[key])
        for name in ('testIPadHomeScreenshot', 'testIPadMinesweeperScreenshot', 'testIPadSlidingPuzzleScreenshot',
                     'testFreshWinCelebratesOnceAndRestoredWinDoesNotReplay', 'testReducedMotionSuppressesCelebrationButStillCompletesGame',
                     'testLowPowerSuppressesCelebrationButStillCompletesGame'):
            key = 'ChaiClassicsVisualSmokeTests/' + name
            self.assertEqual(self.before[key], sudoku_changed[key])
        sliding_changed = self.changed('App/SlidingView.swift')
        key = 'ChaiClassicsVisualSmokeTests/testFreshWinCelebratesOnceAndRestoredWinDoesNotReplay'
        self.assertNotEqual(self.before[key], sliding_changed[key])

    def test_edited_profile_body_and_unknown_identity_fall_back_to_all_games(self):
        key = 'ChaiClassicsUITests/testHomeHasExactlyThreeColumns'
        original = self.bodies[key]
        edited = original.replace('let app = launch("base")', 'let app = launch("base"); app.buttons["game.memory"].tap(); app.buttons["memory.start"].tap()')
        self.assertNotEqual(edited, original)
        self.assertEqual(scoped.dependencies(key, original), set())
        self.assertEqual(scoped.dependencies(key, edited), scoped.ALL_GAME_FILES)
        self.assertEqual(scoped.dependencies('Unknown/testHomeHasExactlyThreeColumns', original), scoped.ALL_GAME_FILES)
        target = copy.deepcopy(self.base)
        path = 'UITests/ChaiClassicsUITests.swift'; mode, data = target[path]
        target[path] = (mode, data.replace(original.encode(), edited.encode()))
        changed_body = scoped.fingerprints(target)
        target['App/MemoryView.swift'] = ('100644', target['App/MemoryView.swift'][1] + b'// Memory fix')
        self.assertNotEqual(changed_body[key], scoped.fingerprints(target)[key])

    def test_shared_clock_preferences_assets_helpers_and_runtime_tooling_still_invalidate_every_case(self):
        for path in ['App/AnimationFrameClock.swift', 'Core/AppPreferences.swift', 'App/DesignSystem.swift',
                     'App/Resources/Assets.xcassets/Memory.imageset/art.png', 'App/Resources/en.lproj/Localizable.strings',
                     'scripts/create_project.py', 'scripts/ui_test_scope.py', 'scripts/ci.sh', '.github/workflows/ci.yml']:
            with self.subTest(path=path):
                after = self.changed(path)
                self.assertTrue(all(self.before[test] != after[test] for test in self.before))
        target = copy.deepcopy(self.base)
        path = 'UITests/ChaiClassicsUITests.swift'; mode, data = target[path]
        target[path] = (mode, data.replace(b'import XCTest', b'import XCTest\nfunc changedSharedHelper() {}'))
        after = scoped.fingerprints(target)
        self.assertTrue(all(self.before[test] != after[test] for test in self.before))

    def test_only_two_pure_evidence_scripts_are_excluded(self):
        self.assertEqual(scoped.PURE_EVIDENCE_SCRIPTS, {'scripts/verify_scoped_ci.py', 'scripts/verify_candidate.py'})
        for path in scoped.PURE_EVIDENCE_SCRIPTS:
            with self.subTest(path=path): self.assertEqual(self.before, self.changed(path))


class CoverageTests(unittest.TestCase):
    def setUp(self):
        self.base = tree()
        self.target = copy.deepcopy(self.base)
        self.target['App/MazeView.swift'] = ('100644', b'struct MazeView { let repaired = true }\n')
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

    def test_four_partitions_remain_partial_and_merge_actual_disjoint_coverage_then_home_sentinel(self):
        target = scoped.fingerprints(self.target)
        sources = []
        for run, name in enumerate(scopes.PART_SCOPES, start=10):
            selected = scopes.resolve(name, target)
            actual = passed(selected)
            proof = scoped.make_evidence('b' * 40, run, name, summary(actual), actual, self.target, [])
            self.assertFalse(proof['complete'])
            self.assertEqual(set(proof['executed_current_tests']), set(selected))
            self.assertEqual(proof['source_runs'], [run])
            sources.append(record(self.target, actual, run=run, sha='b' * 40))
        needed = scoped.planned_tests(target, sources)
        self.assertEqual(needed, [scoped.FAST_SENTINEL])
        actual = passed(needed)
        proof = scoped.make_evidence('b' * 40, 20, 'affected', summary(actual), actual, self.target, sources)
        self.assertTrue(proof['complete'])
        self.assertEqual(proof['uncovered_tests'], [])
        self.assertEqual(set(proof['coverage']), set(target))
        self.assertEqual(proof['source_runs'], [10, 11, 12, 13, 20])
        # A missing or failed required lifecycle can never be supplied by Visual.
        required = 'ChaiClassicsVisualSmokeTests/' + scopes.SESSION_VISUAL_TESTS[0]
        failed_sources = copy.deepcopy(sources)
        for source in failed_sources:
            if required in source['actual']: source['actual'][required] = 'failed'
        self.assertEqual(scoped.planned_tests(target, failed_sources), [required])
        absent_sources = copy.deepcopy(sources)
        for source in absent_sources: source['actual'].pop(required, None)
        self.assertEqual(scoped.planned_tests(target, absent_sources), [required])

    def test_beta_capture_requires_exact_three_actual_passes_and_remains_partial(self):
        target = scoped.fingerprints(self.target)
        selected = scopes.resolve('beta', target)
        self.assertEqual(set(selected), {'ChaiClassicsVisualSmokeTests/' + name for name in (
            'testSudokuCommonSessionLifecycleAndContinueDeletion',
            'testSlidingCommonSessionLifecycleAndContinueDeletion',
            'testPlayHistorySearchDismissesKeyboardWithoutSwallowingActions')})
        actual = passed(selected)
        proof = scoped.make_evidence('b' * 40, 20, 'beta', summary(actual), actual, self.target, [])
        self.assertFalse(proof['complete'])
        self.assertEqual(proof['source_runs'], [20])
        self.assertEqual(proof['current_summary']['totalTestCount'], 3)
        self.assertEqual(proof['current_summary']['passedTests'], 3)
        self.assertEqual(proof['current_summary']['skippedTests'], 0)
        self.assertEqual(set(proof['expected_tests']), set(target))
        self.assertTrue(scopes.required_session_tests_for_paths(self.target).issubset(proof['expected_tests']))
        with self.assertRaises(candidate.CandidateError):
            scoped.make_evidence('b' * 40, 20, 'beta', summary(actual), actual, self.target, [record(self.target)])
        for label in ('missing', 'extra', 'skipped', 'failed'):
            changed = dict(actual); chosen = selected[0]
            if label == 'missing': changed.pop(chosen)
            if label == 'extra': changed[A] = 'passed'
            if label == 'skipped': changed[chosen] = 'skipped'
            if label == 'failed': changed[chosen] = 'failed'
            with self.subTest(change=label), self.assertRaises(candidate.CandidateError):
                scoped.make_evidence('b' * 40, 20, 'beta', summary(changed), changed, self.target, [])

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
        self.assertEqual(needed, [scoped.FAST_SENTINEL])


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.repo = 'Kongdean2374/ChaiClassics'; self.sha = 'b' * 40
        self.base = tree(); self.target = copy.deepcopy(self.base)
        self.target['App/MazeView.swift'] = ('100644', b'struct MazeView { let repaired = true }\n')
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

    def test_v022_trusted_branch_retains_raw_scoped_provenance(self):
        for run in (10, 20):
            self.responses[f'repos/{self.repo}/actions/runs/{run}']['head_branch'] = 'develop/0.2.2'
        self.assertEqual(self.verify(), self.evidence)

    def test_four_same_sha_parts_are_rebuilt_from_each_original_source_partition(self):
        target = scoped.fingerprints(self.target)
        records, raw = [], {}
        template = f'repos/{self.repo}/actions/runs/20'
        for run, part in enumerate(scopes.PART_SCOPES, start=11):
            prefix = f'repos/{self.repo}/actions/runs/{run}'
            for suffix in ('', '/jobs?per_page=100&filter=latest', '/artifacts?per_page=100'):
                self.responses[prefix + suffix] = copy.deepcopy(self.responses[template + suffix])
            self.responses[prefix]['id'] = run
            actual = passed(scopes.resolve(part, target))
            raw[run] = (summary(actual), actual, {'scope': part, 'source_commit': self.sha, 'source_runs': []})
            records.append(record(self.target, actual, run=run, sha=self.sha))
        sentinel = passed([scoped.FAST_SENTINEL])
        raw[20] = (summary(sentinel), sentinel)
        expected = scoped.make_evidence(self.sha, 20, 'affected', summary(sentinel), sentinel, self.target, records)
        read_runs = []
        def original_results(_repo, run, _read):
            read_runs.append(run)
            return raw[run]
        def verify():
            return scoped.validate_evidence(expected, self.repo, self.sha, 20, read=self.read,
                results_reader=original_results, tree_reader=lambda _: self.target, ancestor=lambda sha: sha == self.sha)
        self.assertEqual(verify(), expected)
        self.assertEqual(set(read_runs), {11, 12, 13, 14, 20})
        self.assertTrue(expected['complete'])
        self.assertEqual(expected['executed_current_tests'], sentinel)
        saved = copy.deepcopy(raw[11])
        # A source cannot claim its neighbour's real case as its own partition.
        foreign = next(name for name in target if name not in raw[11][1])
        altered = dict(raw[11][1]); altered[foreign] = passed([foreign])[foreign]
        raw[11] = (summary(altered), altered, saved[2])
        with self.assertRaisesRegex(candidate.CandidateError, 'partition'): verify()
        altered = dict(saved[1]); altered.pop(next(iter(altered)))
        raw[11] = (summary(altered), altered, saved[2])
        with self.assertRaisesRegex(candidate.CandidateError, 'omitted'): verify()
        raw[11] = saved
        # Independently reloaded failure beats any copied successful ledger.
        altered = dict(saved[1]); affected = next(name for name in altered if name.split('/')[-1] not in candidate.IPAD_TESTS)
        altered[affected] = 'failed'
        raw[11] = (summary(altered), altered, saved[2])
        with self.assertRaises(candidate.CandidateError): verify()

    def test_excluding_pure_tool_bytes_cannot_forge_actual_raw_statuses(self):
        for path in scoped.PURE_EVIDENCE_SCRIPTS:
            self.base[path] = ('100644', b'previous evidence tool')
            self.target[path] = ('100644', b'changed tool claiming every test passed')
        self.assertEqual(self.verify(), self.evidence)
        self.prior['actual'][A] = 'failed'
        self.prior['summary'] = summary(self.prior['actual'])
        # Even with equal fingerprints and an artifact claiming an inherited pass,
        # the independently reloaded failure makes that case require execution.
        with self.assertRaises(candidate.CandidateError): self.verify()

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

    def test_failed_scope_preexecution_index_keeps_prior_ab_without_success_artifact(self):
        prefix = f'repos/{self.repo}/actions/runs/'
        for suffix in ('', '/jobs?per_page=100&filter=latest', '/artifacts?per_page=100'):
            self.responses[prefix + '5' + suffix] = copy.deepcopy(self.responses[prefix + '10' + suffix])
        self.responses[prefix + '5']['id'] = 5
        self.responses[prefix + '5']['conclusion'] = 'success'
        for job in self.responses[prefix + '5/jobs?per_page=100&filter=latest']['jobs']:
            job['conclusion'] = 'success'
            for step in job['steps']: step['conclusion'] = 'success'
        prior_ab = record(self.base, run=5)
        failed_c = record(self.base, {C: 'failed'}, run=10)
        expected = scoped.make_evidence(self.sha, 20, 'affected', summary(self.current_actual), self.current_actual, self.target, [prior_ab, failed_c])
        selection = {'scope': 'maze', 'source_commit': 'a' * 40, 'source_runs': [5]}
        def actual_results(_repo, run, _read):
            if run == 5: return prior_ab['summary'], prior_ab['actual']
            if run == 10: return failed_c['summary'], failed_c['actual'], selection
            return summary(self.current_actual), self.current_actual
        with mock.patch.object(self, 'results', side_effect=actual_results):
            rebuilt = self.verify(expected)
            self.assertEqual(rebuilt['source_runs'], [5, 10, 20])
            self.assertEqual(rebuilt['coverage'][A]['source_run'], 5)
            self.assertEqual(rebuilt['coverage'][B]['source_run'], 5)
            selection['source_commit'] = 'c' * 40
            with self.assertRaises(candidate.CandidateError): self.verify(expected)

    def test_optional_raw_source_index_is_read_without_changing_legacy_result_shape(self):
        selection = {'scope': 'maze', 'source_commit': 'a' * 40, 'source_runs': [5]}
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, 'w') as zipped:
            zipped.writestr('build/UITests-summary.json', json.dumps(summary({C: 'failed'})))
            zipped.writestr('build/UITests.log', "Test Case '-[ChaiClassicsUITests." + C.replace('/', ' ') + "]' failed (1.0 seconds).")
            zipped.writestr('ui-selection.json', json.dumps(selection))
        archive.seek(0)
        self.assertEqual(len(scoped.historical.read_zip_results(archive)), 2)
        archive.seek(0)
        self.assertEqual(scoped.historical.read_zip_results(archive, include_selection=True)[2], selection)

    def test_run_id_inputs_are_bounded_positive_and_nonduplicated(self):
        self.assertEqual(scoped.parse_runs('10, 11'), [10, 11])
        self.assertEqual(scoped.parse_runs(''), [])
        for text in ['0', '-1', '1,1', '1.5', '1; command', ',1', 'True', ','.join(map(str, range(1, 22)))]:
            with self.subTest(text=text), self.assertRaises(candidate.CandidateError): scoped.parse_runs(text)


if __name__ == '__main__':
    unittest.main()
