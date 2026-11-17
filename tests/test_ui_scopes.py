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

    def test_sliding_retries_both_failed_methods_and_direct_gesture_regression(self):
        methods = scope.SCOPES['sliding']
        self.assertEqual(len(methods), 3)
        for required in ['testSlidingCanStartAndRestore', 'testFreshWinCelebratesOnceAndRestoredWinDoesNotReplay', 'testSlidingSwipesInAllFourDirectionsAndRestoresExactlyOneMove']:
            self.assertTrue(any(item.endswith('/' + required) for item in methods))

    def test_v021_scopes_include_real_new_regressions(self):
        expected = {'memory': 'testMemoryFlipMismatchGatesAndReducedMotionPreserveNativeCards',
                    'maze': 'testMazeJoystickMovesContinuouslyStopsAndRestoresCell',
                    'twentyfour': 'testTwentyFourOrderedInputHistoryAndZeroDivision'}
        for name, method in expected.items():
            self.assertTrue(any(item.endswith('/' + method) for item in scope.SCOPES[name]))
        for name in ('tictactoe', 'connectfour'):
            self.assertTrue(any(item.endswith('/testBoardGameThinkingAndDropGatesRejectExtraInput') for item in scope.SCOPES[name]))

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
