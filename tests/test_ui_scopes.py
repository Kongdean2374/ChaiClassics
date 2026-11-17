import importlib.util
import pathlib
import subprocess
import unittest
import json
import tempfile
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ui_scopes', ROOT / 'scripts/ui_test_scope.py')
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)

class UIScopeTests(unittest.TestCase):
    def test_full_emits_no_test_filter(self):
        result = subprocess.run(['python3', str(ROOT / 'scripts/ui_test_scope.py'), 'full'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')

    def test_each_selected_method_is_real_and_unique(self):
        for name, methods in scope.SCOPES.items():
            self.assertEqual(len(methods), len(set(methods)), name)
            for selection in methods:
                fields = selection.split('/')
                source = ROOT / 'UITests' / (fields[1] + '.swift')
                self.assertTrue(source.is_file())
                if len(fields) == 3:
                    self.assertIn('func ' + fields[2] + '(', source.read_text())

    def test_four_partitions_are_disjoint_source_sorted_complete_and_exact_cli_filters(self):
        declared = scope.declared_tests(ROOT)
        self.assertEqual(len(declared), 71)
        partitions = []
        for name, index in scope.PART_SCOPES.items():
            selected = scope.resolve(name, reversed(declared), include_sessions=False)
            self.assertEqual(selected, declared[index::4])
            self.assertEqual(len(selected), 18 if index < 3 else 17)
            result = subprocess.run(['python3', str(ROOT / 'scripts/ui_test_scope.py'), name], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), ['-only-testing:ChaiClassicsUITests/' + test for test in selected])
            self.assertFalse(any(set(selected) & set(previous) for previous in partitions))
            partitions.append(selected)
        combined = [test for partition in partitions for test in partition]
        self.assertEqual(sorted(combined), declared)
        self.assertTrue(scope.required_session_tests(ROOT).issubset(combined))
        for invalid in ([], ['Example/testA'] * 2, ['invalid'], [None]):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError): scope.resolve('part_a', invalid)
        with self.assertRaises(ValueError): scope.resolve('part_d', ['Example/testA'])

    def test_partition_source_inventory_rejects_missing_session_case_and_duplicates(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary); (root / 'UITests').mkdir(); (root / 'App').mkdir()
            (root / 'App/GameSessionComponents.swift').write_text('struct GameSessionComponents {}')
            file = root / 'UITests/ChaiClassicsVisualSmokeTests.swift'
            file.write_text('\n'.join('func ' + name + '() {}' for name in scope.SESSION_VISUAL_TESTS[:-1]))
            with self.assertRaises(ValueError): scope.declared_tests(root)
            file.write_text(file.read_text() + '\nfunc ' + scope.SESSION_VISUAL_TESTS[-1] + '() {}')
            self.assertEqual(len(scope.declared_tests(root)), 9)
            file.write_text(file.read_text() + '\nfunc ' + scope.SESSION_VISUAL_TESTS[-1] + '() {}')
            with self.assertRaises(ValueError): scope.declared_tests(root)

    def test_beta_scope_is_exact_three_real_critical_journeys(self):
        expected = ['ChaiClassicsVisualSmokeTests/' + name for name in (
            'testSudokuCommonSessionLifecycleAndContinueDeletion',
            'testSlidingCommonSessionLifecycleAndContinueDeletion',
            'testPlayHistorySearchDismissesKeyboardWithoutSwallowingActions')]
        self.assertEqual(scope.resolve('beta', scope.declared_tests(ROOT)), sorted(expected))
        result = subprocess.run(['python3', str(ROOT / 'scripts/ui_test_scope.py'), 'beta'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['-only-testing:ChaiClassicsUITests/' + name for name in expected])
        with self.assertRaises(ValueError): scope.resolve('beta', expected, include_sessions=False)

    def test_sliding_retries_both_failed_methods_and_direct_gesture_regression(self):
        methods = scope.SCOPES['sliding']
        for required in ['testSlidingCanStartAndRestore', 'testFreshWinCelebratesOnceAndRestoredWinDoesNotReplay', 'testSlidingSwipesInAllFourDirectionsAndRestoresExactlyOneMove']:
            self.assertTrue(any(item.endswith('/' + required) for item in methods))

    def test_v022_every_game_scope_includes_its_real_lifecycle_and_history_is_selected(self):
        self.assertEqual(len(scope.SESSION_LIFECYCLE_TESTS), 8)
        self.assertEqual(len(set(scope.SESSION_VISUAL_TESTS)), 9)
        for game, method in scope.SESSION_LIFECYCLE_TESTS.items():
            selected = scope.SCOPES[game if game in scope.SCOPES else 'legacy']
            self.assertIn(scope.S + method, selected)
        for game in ('sudoku', 'mines', 'sliding'):
            self.assertIn(scope.S + scope.SESSION_LIFECYCLE_TESTS[game], scope.SCOPES['legacy'])
        self.assertIn(scope.S + scope.HISTORY_TEST, scope.SCOPES['catalog'])
        self.assertEqual(scope.required_session_tests_for_paths([]), set())
        required = scope.required_session_tests_for_paths(['App/GameSessionComponents.swift'])
        self.assertEqual(required, {'ChaiClassicsVisualSmokeTests/' + name for name in scope.SESSION_VISUAL_TESTS})

    def test_previous_runtime_keeps_its_original_named_scope_without_inventing_new_execution(self):
        original = ['ChaiClassicsUITests/testOriginalActualCase']
        self.assertEqual(scope.resolve('legacy', original, include_sessions=False), original)
        with self.assertRaises(ValueError): scope.resolve('legacy', original)

    def test_v021_scopes_include_real_new_regressions(self):
        expected = {'memory': 'testMemoryFlipMismatchGatesAndReducedMotionPreserveNativeCards',
                    'maze': 'testMazeJoystickMovesContinuouslyStopsAndRestoresCell',
                    'twentyfour': 'testTwentyFourOrderedInputHistoryAndZeroDivision'}
        for name, method in expected.items():
            self.assertTrue(any(item.endswith('/' + method) for item in scope.SCOPES[name]))
        for name in ('tictactoe', 'connectfour'):
            self.assertTrue(any(item.endswith('/testBoardGameThinkingAndDropGatesRejectExtraInput') for item in scope.SCOPES[name]))

    def test_each_ai_difficulty_keeps_both_first_players_in_its_independent_case(self):
        source = (ROOT / 'UITests/ChaiClassicsV020UITests.swift').read_text()
        for game,title in [('tictactoe','TicTacToe'),('connectfour','ConnectFour')]:
            for level in ('Easy','Normal','Hard'):
                method = 'test'+title+'AI'+level+'RepliesWithEitherFirstPlayer'
                self.assertIn(scope.V+method, scope.SCOPES[game])
                self.assertIn('func '+method+'() { inspectSinglePlayerAI("'+game+'",difficulty:"'+level+'") }',source)
        self.assertIn('for computerFirst in [false, true]',source)
        self.assertIn('assertMovesStay(replyMoves, game: game, app: app)',source)

    def test_affected_plan_requires_current_sha_real_cases_and_nonempty_selection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary); (root / 'scripts').mkdir(); (root / 'build').mkdir(); (root / 'UITests').mkdir()
            (root / 'UITests/Example.swift').write_text('func testActual() {}')
            file = root / 'build/ui-scope-plan.json'
            valid = {'source_commit': 'a' * 40, 'tests': ['Example/testActual']}
            file.write_text(json.dumps(valid))
            with mock.patch.object(scope, '__file__', str(root / 'scripts/ui_test_scope.py')), mock.patch.object(scope.subprocess, 'check_output', return_value='a' * 40):
                self.assertEqual(scope.affected_selectors(), ['ChaiClassicsUITests/Example/testActual'])
                for invalid in [valid | {'source_commit': 'b' * 40}, valid | {'tests': []}, valid | {'tests': ['Example/testMissing']},
                                valid | {'tests': [['invalid']]}, valid | {'tests': valid['tests'] * 2}]:
                    file.write_text(json.dumps(invalid))
                    with self.assertRaises(ValueError): scope.affected_selectors()

    def test_invalid_scope_fails_before_any_simulator_command(self):
        result = subprocess.run(['bash', 'scripts/ci.sh', 'ui'], cwd=ROOT, env={'PATH': '/usr/bin:/bin', 'CHAI_UI_SCOPE': 'invalid'}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 64)
        self.assertNotIn('xcrun', result.stderr)

if __name__ == '__main__':
    unittest.main()
