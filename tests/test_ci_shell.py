"""Run the real /bin/bash CI entry point with local fake Apple commands, never a Simulator.

macOS executes these tests with its Bash 3.2, where empty arrays plus nounset fail.
Linux also checks exact argv, selector validation and failure propagation end to end.
"""
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('chai_shell_test_scopes', ROOT / 'scripts/ui_test_scope.py')
SCOPES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SCOPES)
SHA = 'a' * 40

MOCK_TOOL = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with Path(os.environ['CHAI_SHELL_CALLS']).open('a') as stream:
    stream.write(json.dumps({'tool': name, 'args': args}) + '\\n')
if name == 'git':
    if args != ['rev-parse', 'HEAD']: raise SystemExit(98)
    print('a' * 40)
elif name == 'xcrun':
    if args == ['simctl', 'list', 'devices', 'available', '--json']:
        devices = [] if os.environ.get('CHAI_MOCK_NO_SIMULATORS') else [
            {'name': 'iPhone 17 Pro', 'udid': 'SIM-PRO'},
            {'name': 'iPhone 17 Pro Max', 'udid': 'SIM-PRO-MAX'}]
        print(json.dumps({'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-0': devices}}))
    elif args == ['xcresulttool', 'get', 'test-results', 'summary', '--path', 'build/UITests.xcresult']:
        if os.environ.get('CHAI_MOCK_SUMMARY_EXIT'): raise SystemExit(int(os.environ['CHAI_MOCK_SUMMARY_EXIT']))
        print(json.dumps({'fixture': 'shell-only; no XCTest executed'}))
    else: raise SystemExit(97)
elif name == 'xcodebuild':
    if '' in args: raise SystemExit(96)
    Path(args[args.index('-resultBundlePath') + 1]).mkdir(parents=True, exist_ok=True)
    print('Shell fixture only: no Simulator or XCTest executed.')
    raise SystemExit(int(os.environ.get('CHAI_MOCK_XCODE_EXIT', '0')))
else: raise SystemExit(99)
'''


class CIShellTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='chai-ci-shell-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / 'scripts').mkdir()
        for name in ('ci.sh', 'ui_test_scope.py'):
            shutil.copyfile(ROOT / 'scripts' / name, self.root / 'scripts' / name)
        shutil.copytree(ROOT / 'UITests', self.root / 'UITests')
        self.bin = self.root / 'bin'; self.bin.mkdir()
        for name in ('xcrun', 'xcodebuild', 'git'):
            file = self.bin / name
            file.write_text(MOCK_TOOL)
            file.chmod(0o755)
        self.calls = self.root / 'calls.jsonl'
        self.declared = sorted(path.stem + '/' + name for path in (self.root / 'UITests').glob('*.swift')
                               for name in re.findall(r'\bfunc\s+(test\w+)\s*\(', path.read_text()))

    def run_ui(self, scope, **settings):
        self.calls.write_text('')
        env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ.get('PATH', '/usr/bin:/bin'),
                   CHAI_UI_SCOPE=scope, CHAI_SHELL_CALLS=str(self.calls), **settings)
        result = subprocess.run(['/bin/bash', 'scripts/ci.sh', 'ui'], cwd=self.root, env=env,
                                capture_output=True, text=True, timeout=30)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        return result, calls

    def invocation(self, calls):
        builds = [call['args'] for call in calls if call['tool'] == 'xcodebuild']
        self.assertEqual(len(builds), 1)
        args = builds[0]
        self.assertNotIn('', args)
        self.assertEqual(args.count('-parallel-testing-enabled'), 1)
        self.assertEqual(args[args.index('-parallel-testing-enabled') + 1], 'NO')
        self.assertEqual(args[-1], 'test')
        self.assertIn('CODE_SIGNING_ALLOWED=NO', args)
        self.assertIn('ONLY_ACTIVE_ARCH=YES', args)
        self.assertEqual(args[args.index('-destination') + 1],
                         'platform=iOS Simulator,arch=' + platform.machine() + ',id=SIM-PRO-MAX')
        return args

    def plan(self, value):
        file = self.root / 'build/ui-scope-plan.json'
        file.parent.mkdir(exist_ok=True)
        file.write_text(json.dumps(value))

    def test_full_scope_preserves_all_tests_without_filters_or_empty_arguments(self):
        result, calls = self.run_ui('full')
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.invocation(calls)
        self.assertFalse(any(arg.startswith(('-only-testing', '-skip-testing')) for arg in args))
        self.assertEqual(args.count('-test-timeouts-enabled'), 1)
        self.assertEqual(args[args.index('-test-timeouts-enabled') + 1], 'YES')
        self.assertEqual(args[args.index('-maximum-test-execution-time-allowance') + 1], '1800')
        self.assertTrue((self.root / 'build/UITests-summary.json').is_file())
        self.assertNotIn('unbound variable', result.stderr)

    def test_each_static_scope_uses_exact_allowlisted_filters(self):
        for scope, selectors in SCOPES.SCOPES.items():
            if scope == 'full': continue
            with self.subTest(scope=scope):
                result, calls = self.run_ui(scope)
                self.assertEqual(result.returncode, 0, result.stderr)
                args = self.invocation(calls)
                self.assertEqual([arg for arg in args if arg.startswith('-only-testing:')],
                                 ['-only-testing:' + method for method in selectors])
                self.assertFalse(any(arg.startswith('-skip-testing') for arg in args))

    def test_each_partition_uses_only_its_source_declared_methods(self):
        for name in SCOPES.PART_SCOPES:
            with self.subTest(scope=name):
                result, calls = self.run_ui(name)
                self.assertEqual(result.returncode, 0, result.stderr)
                args = self.invocation(calls)
                self.assertEqual([arg for arg in args if arg.startswith('-only-testing:')],
                                 ['-only-testing:ChaiClassicsUITests/' + test for test in SCOPES.resolve(name, self.declared)])
                self.assertFalse(any(arg.startswith('-skip-testing') for arg in args))

    def test_affected_scope_checks_current_plan_and_emits_every_declared_case(self):
        self.assertGreaterEqual(len(self.declared), 41)
        self.plan({'source_commit': SHA, 'tests': self.declared})
        result, calls = self.run_ui('affected')
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.invocation(calls)
        self.assertEqual([arg for arg in args if arg.startswith('-only-testing:')],
                         ['-only-testing:ChaiClassicsUITests/' + name for name in self.declared])
        self.assertTrue(any(call['tool'] == 'git' and call['args'] == ['rev-parse', 'HEAD'] for call in calls))

    def test_invalid_affected_plan_stops_before_any_simulator_or_build_command(self):
        for value in [None, {'source_commit': 'b' * 40, 'tests': self.declared},
                      {'source_commit': SHA, 'tests': []}, {'source_commit': SHA, 'tests': ['Unknown/testInvented']},
                      {'source_commit': SHA, 'tests': self.declared[:1] * 2}]:
            with self.subTest(plan=value):
                if value is None:
                    file = self.root / 'build/ui-scope-plan.json'
                    if file.exists(): file.unlink()
                else: self.plan(value)
                result, calls = self.run_ui('affected')
                self.assertEqual(result.returncode, 64, result.stderr)
                self.assertFalse(any(call['tool'] in ('xcrun', 'xcodebuild') for call in calls))

    def test_unknown_scope_stops_before_any_apple_tool(self):
        result, calls = self.run_ui('not-a-scope')
        self.assertEqual(result.returncode, 64)
        self.assertEqual(calls, [])

    def test_xcode_failure_remains_nonzero_and_still_exports_summary(self):
        result, calls = self.run_ui('full', CHAI_MOCK_XCODE_EXIT='7')
        self.assertEqual(result.returncode, 7, result.stderr)
        self.invocation(calls)
        self.assertTrue(any(call['tool'] == 'xcrun' and call['args'][0] == 'xcresulttool' for call in calls))
        self.assertTrue((self.root / 'build/UITests-summary.json').is_file())
        self.assertIn('no Simulator or XCTest executed', (self.root / 'build/UITests.log').read_text())

    def test_summary_export_failure_cannot_turn_green(self):
        result, calls = self.run_ui('full', CHAI_MOCK_SUMMARY_EXIT='9')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.invocation(calls)

    def test_no_available_phone_stops_before_build(self):
        result, calls = self.run_ui('full', CHAI_MOCK_NO_SIMULATORS='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call['tool'] == 'xcodebuild' for call in calls))
        self.assertIn('No available iPhone simulator', result.stderr)


if __name__ == '__main__':
    unittest.main()
