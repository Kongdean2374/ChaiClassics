import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/select_ipad_simulator.py'
SPEC = importlib.util.spec_from_file_location('select_ipad_simulator', SCRIPT)
selector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(selector)
PRO4 = selector.TYPE_PREFIX + 'iPad-Pro-13-inch-M4'
PRO5 = selector.TYPE_PREFIX + 'iPad-Pro-13-inch-M5'
OLD = selector.TYPE_PREFIX + 'iPad-Pro-12-9-inch-6th-generation'
PHONE = selector.TYPE_PREFIX + 'iPhone-16'
AIR = selector.TYPE_PREFIX + 'iPad-Air-13-inch-M3'
UDID4 = '11111111-1111-4111-8111-111111111111'
UDID5 = '22222222-2222-4222-8222-222222222222'
CREATED = '33333333-3333-4333-8333-333333333333'
SHA = 'a' * 40


def kind(identifier=PRO4, name='iPad Pro 13-inch (M4)', minimum='17.4', maximum='65535.255.255'):
    return {'identifier': identifier, 'name': name,
            'minRuntimeVersionString': minimum, 'maxRuntimeVersionString': maximum}


def runtime(version='26.2', build='23C54', name=None, available=True):
    return {'identifier': selector.RUNTIME_PREFIX + version.replace('.', '-'),
            'name': name or 'iOS ' + version, 'version': version,
            'buildversion': build, 'isAvailable': available}


def device(identifier=PRO4, name='iPad Pro 13-inch (M4)', udid=UDID4, available=True):
    return {'name': name, 'udid': udid, 'deviceTypeIdentifier': identifier, 'isAvailable': available}


def inventory(runtimes=None, kinds=None, devices=None):
    runtimes = [runtime()] if runtimes is None else runtimes
    return {'devicetypes': [kind()] if kinds is None else kinds, 'runtimes': runtimes,
            'devices': {runtimes[0]['identifier']: [device()]} if devices is None else devices}


class SelectionTests(unittest.TestCase):
    def assert_code(self, code, inventory_value, target='17.0', requested='auto'):
        with self.assertRaises(selector.SelectionError) as context:
            selector.select_device(inventory_value, target, requested)
        self.assertEqual(context.exception.code, code)

    def test_real_pro_13_names_normalize_without_accepting_other_types(self):
        for name in ('iPad Pro 13-inch (M4)', 'iPad Pro (13-inch) (M4)', 'iPad Pro 13 吋 (M4)', 'iPad Pro 13‑inch (M4)'):
            with self.subTest(name=name):
                self.assertTrue(selector.is_pro_13_type(kind(name=name)))
        for identifier, name in ((OLD, 'iPad Pro 13-inch (M4)'), (PHONE, 'iPad Pro 13-inch (M4)'),
                                 (AIR, 'iPad Air 13-inch (M3)'), (PRO4, 'iPad Pro 12.9-inch')):
            self.assertFalse(selector.is_pro_13_type(kind(identifier, name)))

    def test_selects_latest_existing_stable_runtime_numerically(self):
        older, newer = runtime('26.2'), runtime('26.10', '23K45')
        value = inventory([older, newer], devices={older['identifier']: [device()], newer['identifier']: [device(udid=UDID5)]})
        result = selector.select_device(value, '17.0')
        self.assertEqual(result['runtime_version'], '26.10')
        self.assertEqual(result['device_udid'], UDID5)
        self.assertFalse(result['requires_creation'])

    def test_existing_device_wins_over_newer_runtime_creation(self):
        older, newer = runtime('18.5', '22F76'), runtime()
        value = inventory([older, newer], devices={older['identifier']: [device()]})
        self.assertEqual(selector.select_device(value, '17.0')['runtime_version'], '18.5')

    def test_newer_model_wins_on_same_existing_runtime(self):
        value = inventory(kinds=[kind(), kind(PRO5, 'iPad Pro 13-inch (M5)')])
        value['devices'][runtime()['identifier']].append(device(PRO5, 'iPad Pro 13-inch (M5)', UDID5))
        self.assertEqual(selector.select_device(value, '17.0')['device_udid'], UDID5)

    def test_beta_rc_seed_and_missing_build_are_never_stable(self):
        for candidate in (runtime('27.0', '24A5276f'), runtime('27.0', '24A50', 'iOS 27.0 Beta'),
                          runtime('27.0', '24A50', 'iOS 27.0 RC'), runtime('27.0', '24A50', 'iOS 27.0 Release Candidate'),
                          runtime('27.0', ''), runtime('27.0 beta', '24A50')):
            with self.subTest(runtime=candidate):
                self.assertFalse(selector.is_stable_runtime(candidate))
                self.assert_code('IPAD13_NO_STABLE_RUNTIME', inventory([candidate], devices={}))

    def test_stable_existing_is_preferred_to_newer_beta(self):
        stable, beta = runtime(), runtime('27.0', '24A5001a')
        value = inventory([stable, beta], devices={stable['identifier']: [device()], beta['identifier']: [device(udid=UDID5)]})
        self.assertEqual(selector.select_device(value, '17.0')['device_udid'], UDID4)

    def test_deployment_floor_and_runtime_availability(self):
        for item in (runtime('16.4', '20E247'), runtime(available=False)):
            self.assert_code('IPAD13_NO_STABLE_RUNTIME', inventory([item]))
        self.assert_code('IPAD13_DEPLOYMENT_UNAVAILABLE', inventory(), target='invalid')

    def test_unavailable_device_requires_creation_rather_than_reuse(self):
        value = inventory(devices={runtime()['identifier']: [device(available=False)]})
        result = selector.select_device(value, '17.0')
        self.assertTrue(result['requires_creation'])
        self.assertIn('iPad Pro 13-inch (M4)', result['device_name'])
        self.assertIsNone(result['device_udid'])

    def test_unavailable_error_overrides_available_boolean(self):
        candidate = runtime()
        candidate['availabilityError'] = 'Runtime not usable'
        self.assert_code('IPAD13_NO_STABLE_RUNTIME', inventory([candidate]))

    def test_exact_request_never_substitutes_another_name(self):
        value = inventory()
        self.assertEqual(selector.select_device(value, '17.0', 'iPad Pro 13-inch (M4)')['device_udid'], UDID4)
        for request in ('iPad Pro 13-inch (M5)', 'iPhone 16', 'iPad Pro 12.9-inch', 'ipad pro 13-inch (m4)'):
            with self.subTest(request=request):
                self.assert_code('IPAD13_REQUEST_NOT_FOUND', value, requested=request)

    def test_renamed_12_9_or_phone_cannot_spoof_thirteen_inches(self):
        value = inventory(kinds=[kind(), kind(OLD, 'iPad Pro 12.9-inch'), kind(PHONE, 'iPhone 16')],
                          devices={runtime()['identifier']: [device(OLD), device(PHONE, udid=UDID5)]})
        result = selector.select_device(value, '17.0')
        self.assertTrue(result['requires_creation'])
        self.assertEqual(result['device_type_identifier'], PRO4)

    def test_missing_model_error_includes_manual_standard_arm_suggestion(self):
        value = inventory(kinds=[kind(OLD, 'iPad Pro 12.9-inch'), kind(PHONE, 'iPhone 16')])
        with self.assertRaises(selector.SelectionError) as context:
            selector.select_device(value, '17.0')
        self.assertEqual(context.exception.code, 'IPAD13_MODEL_NOT_INSTALLED')
        self.assertIn('standard macos-15 ARM', str(context.exception))

    def test_runtime_bounds_apply_to_existing_and_new_devices(self):
        for selected_kind in (kind(minimum='27.0'), kind(maximum='26.1')):
            self.assert_code('IPAD13_NO_COMPATIBLE_DEVICE', inventory(kinds=[selected_kind]))

    def test_packed_bounds_and_explicit_supported_type_list(self):
        packed = {'identifier': PRO4, 'name': 'iPad Pro 13-inch (M4)',
                  'minRuntimeVersion': 17 << 16 | 4 << 8, 'maxRuntimeVersion': 0xffffffff}
        value = inventory(kinds=[packed], devices={})
        self.assertTrue(selector.select_device(value, '17.0')['requires_creation'])
        value['runtimes'][0]['supportedDeviceTypes'] = [{'identifier': PRO5}]
        self.assert_code('IPAD13_NO_COMPATIBLE_DEVICE', value)
        value['runtimes'][0]['supportedDeviceTypes'] = [{'identifier': PRO4}]
        self.assertTrue(selector.select_device(value, '17.0')['requires_creation'])

    def test_creation_requires_affirmative_compatibility_but_existing_can_prove_it(self):
        unbounded = {'identifier': PRO4, 'name': 'iPad Pro 13-inch (M4)'}
        self.assertEqual(selector.select_device(inventory(kinds=[unbounded]), '17.0')['device_udid'], UDID4)
        self.assert_code('IPAD13_NO_COMPATIBLE_DEVICE', inventory(kinds=[unbounded], devices={}))

    def test_creation_prefers_latest_runtime_and_newest_model(self):
        old, new = runtime('18.5', '22F76'), runtime()
        value = inventory([old, new], [kind(), kind(PRO5, 'iPad Pro 13-inch (M5)')], {})
        plan = selector.select_device(value, '17.0')
        self.assertEqual(plan['runtime_version'], '26.2')
        self.assertEqual(plan['device_type_identifier'], PRO5)
        self.assertEqual(plan['device_name'], 'iPad Pro 13-inch (M5) - ChaiClassics')

    def test_exact_model_can_create_only_exact_model(self):
        value = inventory(kinds=[kind(), kind(PRO5, 'iPad Pro 13-inch (M5)')], devices={})
        plan = selector.select_device(value, '17.0', 'iPad Pro 13-inch (M4)')
        self.assertEqual(plan['device_type_identifier'], PRO4)
        self.assertEqual(plan['device_name'], 'iPad Pro 13-inch (M4)')

    def test_diagnostics_include_all_ipads_and_all_ios_runtimes(self):
        value = inventory(kinds=[kind(), kind(OLD, 'iPad Pro 12.9-inch'), kind(PHONE, 'iPhone 16')],
                          devices={runtime()['identifier']: [device(), device(OLD, 'Old iPad'), device(PHONE, 'iPhone 16')]})
        result = selector.inventory_diagnostics(value)
        self.assertEqual(len(result['available_ipads']), 2)
        self.assertEqual(len(result['installed_ipad_types']), 2)
        self.assertTrue(result['available_ipads'][0]['is_13_inch_pro'])
        self.assertFalse(result['available_ipads'][1]['is_13_inch_pro'])

    def test_invalid_inventory_is_fixed_error(self):
        for value in ({}, [], {'devicetypes': [], 'runtimes': [], 'devices': {'runtime': [None]}}):
            self.assert_code('IPAD13_INVENTORY_INVALID', value)


class CliTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'scripts').mkdir()
        (self.root / 'scripts/create_project.py').write_text("base={'IPHONEOS_DEPLOYMENT_TARGET':'17.0'}")
        self.output = self.root / 'build/device.json'
        self.calls = []

    def runner(self, arguments, timeout=60):
        self.calls.append(arguments)
        if arguments[0] == 'git':
            return SHA
        if arguments[0] == 'xcodebuild':
            return 'Xcode 26.3\nBuild version 17C529'
        if arguments[1:3] == ['simctl', 'list']:
            return json.dumps(self.value)
        if arguments[1:3] == ['simctl', 'create']:
            return CREATED
        self.fail('Unexpected external command: ' + str(arguments))

    def invoke(self, value, extra=(), runner=None):
        self.value = value
        console = io.StringIO()
        with redirect_stdout(console), patch.dict(os.environ, {'GITHUB_SHA': SHA}):
            status = selector.main(['--output', str(self.output), *extra], runner or self.runner, self.root)
        self.console_output = console.getvalue()
        return status, json.loads(self.output.read_text())

    def test_success_lists_available_ipads_and_selected_public_provenance(self):
        value = inventory(kinds=[kind(), kind(OLD, 'iPad Pro 12.9-inch')],
                          devices={runtime()['identifier']: [device(), device(OLD, 'iPad Pro 12.9-inch', UDID5)]})
        status, _ = self.invoke(value)
        self.assertEqual(status, 0)
        self.assertIn('Available iPads:\n', self.console_output)
        self.assertIn('"iPad Pro 12.9-inch" | iOS 26.2 | Build 23C54', self.console_output)
        self.assertIn('Selected iPad: "iPad Pro 13-inch (M4)" | iOS 26.2 | Build 23C54', self.console_output)
        self.assertIn('Selected Xcode: Xcode 26.3 | Build version 17C529', self.console_output)
        self.assertNotIn(UDID4, self.console_output)
        self.assertNotIn(str(self.root), self.console_output)

    def test_failure_also_lists_available_ipads_without_claiming_selection(self):
        value = inventory(kinds=[kind(OLD, 'iPad Pro 12.9-inch')],
                          devices={runtime()['identifier']: [device(OLD, 'iPad Pro 12.9-inch')]})
        status, _ = self.invoke(value)
        self.assertEqual(status, 1)
        self.assertIn('Available iPads:\n  "iPad Pro 12.9-inch" | iOS 26.2 | Build 23C54', self.console_output)
        self.assertNotIn('Selected iPad:', self.console_output)

    def test_live_existing_writes_complete_ready_provenance_without_creation(self):
        status, result = self.invoke(inventory())
        self.assertEqual(status, 0)
        self.assertEqual(result['status'], 'ready')
        self.assertEqual(result['schema_version'], 1)
        self.assertEqual(result['source_commit'], SHA)
        self.assertEqual(result['deployment_target'], '17.0')
        self.assertEqual(result['xcode_version'], 'Xcode 26.3\nBuild version 17C529')
        self.assertEqual(result['errors'], [])
        self.assertFalse(result['created'])
        self.assertEqual(self.calls[-1], ['xcrun', 'simctl', 'list', '--json'])

    def test_live_creation_uses_only_local_create_and_validated_type_runtime(self):
        status, result = self.invoke(inventory(devices={}))
        self.assertEqual(status, 0)
        self.assertTrue(result['created'])
        self.assertEqual(result['device_udid'], CREATED)
        self.assertEqual(self.calls[-1], ['xcrun', 'simctl', 'create', 'iPad Pro 13-inch (M4) - ChaiClassics', PRO4, runtime()['identifier']])

    def test_create_failure_timeout_and_bad_uuid_are_fixed_safe_diagnostics(self):
        for failure, expected in ((subprocess.CalledProcessError(1, ['xcrun'], stderr='PRIVATE_RAW_ERROR'), 'IPAD13_CREATE_FAILED'),
                                  (subprocess.TimeoutExpired(['xcrun'], 60), 'IPAD13_CREATE_FAILED'),
                                  ('PRIVATE_INVALID_UUID', 'IPAD13_CREATE_INVALID_UDID')):
            def command(arguments, timeout=60):
                if arguments[1:3] == ['simctl', 'create']:
                    if isinstance(failure, Exception):
                        raise failure
                    return failure
                return self.runner(arguments, timeout)
            with self.subTest(expected=expected):
                status, result = self.invoke(inventory(devices={}), runner=command)
                self.assertEqual(status, 1)
                self.assertEqual(result['diagnostics']['code'], expected)
                self.assertFalse(result['created'])
                self.assertNotIn('PRIVATE', json.dumps(result))

    def test_offline_existing_does_not_call_simctl_or_fabricate_xcode(self):
        fixture = self.root / 'inventory.json'
        fixture.write_text(json.dumps(inventory()))
        def no_xcode(arguments, timeout=60):
            if arguments[0] == 'xcodebuild':
                raise FileNotFoundError()
            return self.runner(arguments, timeout)
        status, result = self.invoke(None, ['--inventory', str(fixture)], no_xcode)
        self.assertEqual(status, 0)
        self.assertIsNone(result['xcode_version'])
        self.assertFalse(any('simctl' in command for command in self.calls))

    def test_offline_never_creates_device(self):
        fixture = self.root / 'inventory.json'
        fixture.write_text(json.dumps(inventory(devices={})))
        status, result = self.invoke(None, ['--inventory', str(fixture)])
        self.assertEqual(status, 1)
        self.assertEqual(result['diagnostics']['code'], 'IPAD13_OFFLINE_CREATION_REQUIRED')
        self.assertFalse(any('simctl' in command for command in self.calls))

    def test_failure_replaces_stale_ready_json_and_keeps_diagnostic_inventory(self):
        self.invoke(inventory())
        value = inventory(kinds=[kind(OLD, 'iPad Pro 12.9-inch')],
                          devices={runtime()['identifier']: [device(OLD, 'iPad Pro 12.9-inch')]})
        status, result = self.invoke(value)
        self.assertEqual(status, 1)
        self.assertEqual(result['status'], 'error')
        self.assertIsNone(result['device_udid'])
        self.assertEqual(result['errors'][0]['code'], 'IPAD13_MODEL_NOT_INSTALLED')
        self.assertEqual(result['available_ipads'][0]['device_name'], 'iPad Pro 12.9-inch')
        self.assertEqual(result['diagnostics']['installed_ios_runtimes'][0]['version'], '26.2')

    def test_inventory_subprocess_error_does_not_publish_raw_stderr(self):
        def command(arguments, timeout=60):
            if 'simctl' in arguments:
                raise subprocess.CalledProcessError(1, arguments, stderr='PRIVATE_RAW_INVENTORY')
            return self.runner(arguments, timeout)
        status, result = self.invoke(None, runner=command)
        self.assertEqual(status, 1)
        self.assertEqual(result['diagnostics']['code'], 'IPAD13_INVENTORY_COMMAND_FAILED')
        self.assertNotIn('PRIVATE', json.dumps(result))
        self.assertNotIn('PRIVATE', self.console_output)
        self.assertFalse(result['diagnostics']['inventory_available'])
        self.assertNotIn('models: none', self.console_output)
        self.assertNotIn('Available iPads: none', self.console_output)

    def test_inventory_timeout_then_success_retries_read_only_with_60_second_bound(self):
        attempts = []
        def command(arguments, timeout=60):
            if arguments[1:3] == ['simctl', 'list']:
                attempts.append((arguments, timeout))
                if len(attempts) == 1:
                    raise subprocess.TimeoutExpired(arguments, timeout, output='PRIVATE_PARTIAL_OUTPUT')
            return self.runner(arguments, timeout)
        status, result = self.invoke(inventory(), runner=command)
        self.assertEqual(status, 0)
        self.assertEqual(result['status'], 'ready')
        self.assertEqual(attempts, [(['xcrun', 'simctl', 'list', '--json'], 60)] * 2)
        self.assertEqual(self.console_output.count('IPAD13_INVENTORY_RETRY:'), 1)
        self.assertIn('Available iPads:', self.console_output)
        self.assertNotIn('PRIVATE', self.console_output + json.dumps(result))

    def test_inventory_timeout_exhaustion_is_distinct_and_does_not_claim_missing_model(self):
        attempts = []
        def command(arguments, timeout=60):
            if arguments[1:3] == ['simctl', 'list']:
                attempts.append(timeout)
                raise subprocess.TimeoutExpired(arguments, timeout, stderr='PRIVATE_TIMEOUT_ERROR')
            return self.runner(arguments, timeout)
        status, result = self.invoke(None, runner=command)
        self.assertEqual(status, 1)
        self.assertEqual(attempts, [60, 60, 60])
        self.assertEqual(result['diagnostics']['code'], 'IPAD13_INVENTORY_TIMEOUT')
        self.assertFalse(result['diagnostics']['inventory_available'])
        self.assertEqual(self.console_output.count('IPAD13_INVENTORY_RETRY:'), 2)
        self.assertIn('models and iOS runtimes are unknown', self.console_output)
        self.assertNotIn('models: none', self.console_output)
        self.assertNotIn('IPAD13_MODEL_NOT_INSTALLED', self.console_output)
        self.assertNotIn('PRIVATE', self.console_output + json.dumps(result))

    def test_inventory_malformed_json_has_distinct_code_without_retries_or_raw_output(self):
        attempts = []
        def command(arguments, timeout=60):
            if arguments[1:3] == ['simctl', 'list']:
                attempts.append(timeout)
                return 'PRIVATE_MALFORMED_JSON'
            return self.runner(arguments, timeout)
        status, result = self.invoke(None, runner=command)
        self.assertEqual(status, 1)
        self.assertEqual(attempts, [60])
        self.assertEqual(result['diagnostics']['code'], 'IPAD13_INVENTORY_JSON_INVALID')
        self.assertFalse(result['diagnostics']['inventory_available'])
        self.assertNotIn('IPAD13_INVENTORY_RETRY:', self.console_output)
        self.assertNotIn('PRIVATE', self.console_output + json.dumps(result))

    def test_deployment_target_reads_project_first_and_generator_fallback(self):
        self.assertEqual(selector.deployment_target(self.root), '17.0')
        project = self.root / 'ChaiClassics.xcodeproj'
        project.mkdir()
        (project / 'project.pbxproj').write_text('IPHONEOS_DEPLOYMENT_TARGET = 18.0; IPHONEOS_DEPLOYMENT_TARGET = 17.0;')
        self.assertEqual(selector.deployment_target(self.root), '18.0')
        (project / 'project.pbxproj').unlink()
        (self.root / 'scripts/create_project.py').unlink()
        with self.assertRaises(selector.SelectionError) as context:
            selector.deployment_target(self.root)
        self.assertEqual(context.exception.code, 'IPAD13_DEPLOYMENT_UNAVAILABLE')

    def test_invalid_xcode_output_is_not_copied_to_report(self):
        def command(arguments, timeout=60):
            return 'PRIVATE_UNEXPECTED_OUTPUT' if arguments[0] == 'xcodebuild' else self.runner(arguments, timeout)
        status, result = self.invoke(inventory(), runner=command)
        self.assertEqual(status, 0)
        self.assertIsNone(result['xcode_version'])
        self.assertNotIn('PRIVATE', json.dumps(result))


if __name__ == '__main__':
    unittest.main()
