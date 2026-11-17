"""Collector-only fixtures: synthetic PNGs live in temporary tests, never App Store output."""
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import collect_ipad_screenshots as collector


def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(payload, zlib.crc32(kind)) & 0xffffffff)


def synthetic_png(width=2064, height=2752, color=(10, 20, 30), *, scanline_filter=0, truncated=False):
    """Valid compressed blank test fixture only; deliberately unrelated to app rendering."""
    compressor = zlib.compressobj()
    row = bytes([scanline_filter]) + bytes(color) * width
    pieces = [compressor.compress(row) for _ in range(height - int(truncated))]
    pieces.append(compressor.flush())
    header = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    return collector.PNG_SIGNATURE + chunk(b'IHDR', header) + chunk(b'IDAT', b''.join(pieces)) + chunk(b'IEND', b'')


class IPadScreenshotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Four distinct compressed fixtures prevent accidentally treating identical
        # page captures as evidence of navigation. None is a shipping screenshot.
        cls.images = [synthetic_png(color=(10 + index, 20, 30)) for index in range(4)]

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.attachments = self.root / 'attachments'
        self.output = self.root / 'collected'
        self.attachments.mkdir()
        self.device_path = self.root / 'device.json'
        self.device = {
            'schema_version': 1, 'status': 'ready',
            'device_name': 'iPad Pro 13-inch (M4)',
            'device_udid': '9495FFE4-4C27-490B-8E1B-5462EE31206C',
            'device_type_identifier': 'com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB',
            'runtime_identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-26-3',
            'runtime_version': '26.3', 'runtime_build': '23D100',
            'deployment_target': '17.0', 'created': False, 'host_arch': 'x86_64',
            'xcode_version': 'Xcode 26.3 / Build 17C100', 'source_commit': 'a' * 40,
            'diagnostics': {'available_ipads': [], 'installed_ios_runtimes': [], 'installed_13_device_types': []},
            'errors': [],
        }
        self.summary = {'totalTestCount': 4, 'passedTests': 4, 'failedTests': 0, 'skippedTests': 0, 'result': 'Passed'}
        self.items = []
        self.manifest = []
        for index, prefix in enumerate(collector.SCREENSHOTS):
            filename = f'original-{index}.png'
            (self.attachments / filename).write_bytes(self.images[index])
            item = {
                'deviceId': self.device['device_udid'], 'deviceName': self.device['device_name'],
                'exportedFileName': filename,
                'suggestedHumanReadableName': prefix + '_0_07B47CBF-C153-4763-B507-6712AF5CF3BD.png',
            }
            self.items.append(item)
            self.manifest.append({'testIdentifier': collector.EXPECTED_TESTS[prefix] + '()', 'attachments': [item]})

    def collect(self, **statuses):
        self.device_path.write_text(json.dumps(self.device))
        (self.attachments / 'manifest.json').write_text(json.dumps(self.manifest))
        self.output.mkdir(exist_ok=True)
        if self.summary is None:
            (self.output / 'test-summary.json').unlink(missing_ok=True)
        else:
            (self.output / 'test-summary.json').write_text(json.dumps(self.summary))
        result = collector.collect_screenshots(self.attachments, self.device_path, self.output,
                                               **({'test_status': 'success', 'build_status': 'success', 'export_status': 'success'} | statuses))
        self.assertEqual(json.loads((self.output / 'report.json').read_text()), result)
        self.assertIn('Files being present does not mean', (self.output / 'README.txt').read_text())
        self.assertIn('# ChaiClassics iPad screenshots', (self.output / 'REPORT.md').read_text())
        if self.summary is not None:
            self.assertEqual(json.loads((self.output / 'test-summary.json').read_text()), self.summary)
        return result

    def codes(self, report):
        return {error['code'] for error in report['errors']}

    def test_original_bytes_names_hashes_dimensions_and_provenance(self):
        result = self.collect()
        self.assertEqual(result['status'], 'success')
        self.assertEqual(result['collection_status'], 'complete')
        self.assertEqual(result['device'], self.device)
        self.assertEqual(result['test_execution']['status'], 'verified')
        self.assertEqual(len(result['screenshots']), 4)
        for index, image in enumerate(result['screenshots']):
            self.assertEqual(image['filename'], collector.SCREENSHOTS[index] + '.png')
            self.assertEqual((image['width'], image['height']), (2064, 2752))
            self.assertEqual((self.output / image['filename']).read_bytes(), self.images[index])
            self.assertEqual(image['sha256'], hashlib.sha256(self.images[index]).hexdigest())
            self.assertEqual(image['source']['test_identifier'], collector.EXPECTED_TESTS[collector.SCREENSHOTS[index]] + '()')
            self.assertEqual(image['source']['device_id'], self.device['device_udid'])

    def test_other_allowed_native_size_and_exact_plain_attachment_names(self):
        image = synthetic_png(2048, 2732)
        self.assertEqual(collector.validate_png(image), {'width': 2048, 'height': 2732})
        for item, prefix in zip(self.items, collector.SCREENSHOTS):
            item['suggestedHumanReadableName'] = prefix + '.png'
        self.assertEqual(self.collect()['status'], 'success')

    def test_wrong_size_and_rotation_fail_without_discarding_other_pages(self):
        for width, height, code in [(1024, 1366, 'PNG_DIMENSIONS'), (2752, 2064, 'PNG_ORIENTATION')]:
            with self.subTest(size=(width, height)):
                (self.attachments / 'original-0.png').write_bytes(synthetic_png(width, height))
                result = self.collect()
                self.assertEqual(result['status'], 'failure')
                self.assertIn(code, self.codes(result))
                self.assertEqual(len(result['screenshots']), 3)
                self.assertFalse((self.output / '01_iPad_Home.png').exists())

    def test_png_crc_truncation_bad_filter_and_fake_header_are_rejected(self):
        changed = bytearray(self.images[0]); changed[29] ^= 1
        cases = [bytes(changed), self.images[0][:-1],
                 collector.PNG_SIGNATURE + b'fake', synthetic_png(scanline_filter=5),
                 synthetic_png(truncated=True)]
        for image in cases:
            with self.subTest(length=len(image)):
                with self.assertRaises(collector.ValidationError) as caught:
                    collector.validate_png(image)
                self.assertEqual(caught.exception.code, 'PNG_INVALID')

    def test_missing_page_and_misleading_prefix_are_not_silently_accepted(self):
        self.items[0]['suggestedHumanReadableName'] = '01_iPad_Home_fake.png'
        result = self.collect()
        self.assertIn('SCREENSHOT_MISSING', self.codes(result))
        self.assertEqual(len(result['screenshots']), 3)

    def test_manifest_path_traversal_absolute_path_and_symlink_are_rejected(self):
        original = self.items[0]
        for filename in ['../outside.png', '/tmp/outside.png', '..\\outside.png']:
            with self.subTest(filename=filename):
                original['exportedFileName'] = filename
                result = self.collect()
                self.assertIn('MANIFEST_PATH', self.codes(result))
                self.assertEqual(len(result['screenshots']), 3)
        outside = self.root / 'outside.png'; outside.write_bytes(self.images[0])
        (self.attachments / 'linked.png').symlink_to(outside)
        original['exportedFileName'] = 'linked.png'
        self.assertIn('MANIFEST_PATH', self.codes(self.collect()))

    def test_ambiguous_matching_attachments_do_not_choose_first(self):
        self.manifest[0]['attachments'].append(copy.deepcopy(self.manifest[0]['attachments'][0]))
        result = self.collect()
        self.assertIn('SCREENSHOT_DUPLICATE', self.codes(result))
        self.assertEqual(len(result['screenshots']), 3)
        self.assertFalse((self.output / '01_iPad_Home.png').exists())

    def test_shared_export_source_and_identical_content_are_detected(self):
        second = self.items[1]
        second['exportedFileName'] = 'original-0.png'
        result = self.collect()
        self.assertIn('SCREENSHOT_SOURCE_REUSED', self.codes(result))
        self.assertEqual(len(result['screenshots']), 2)
        second['exportedFileName'] = 'original-1.png'
        (self.attachments / 'original-1.png').write_bytes(self.images[0])
        result = self.collect()
        self.assertIn('SCREENSHOT_CONTENT_DUPLICATE', self.codes(result))
        self.assertEqual(len(result['screenshots']), 3)

    def test_iphone_12_9_and_unready_selection_cannot_be_published_as_13_inch(self):
        for kind, status, code in [
            ('com.apple.CoreSimulator.SimDeviceType.iPhone-16', 'ready', 'DEVICE_FAMILY'),
            ('com.apple.CoreSimulator.SimDeviceType.iPad-Pro-12-9-inch-6th-generation', 'ready', 'DEVICE_FAMILY'),
            (self.device['device_type_identifier'], 'error', 'DEVICE_NOT_READY'),
        ]:
            with self.subTest(kind=kind, status=status):
                self.device['device_type_identifier'] = kind; self.device['status'] = status
                result = self.collect()
                self.assertIn(code, self.codes(result))
                self.assertFalse(result['screenshots'])

    def test_created_simulator_name_is_allowed_but_attachment_must_match(self):
        self.device['device_name'] = 'ChaiClassics iPad Screenshots'
        for item in self.items:
            item['deviceName'] = self.device['device_name']
        self.assertEqual(self.collect()['status'], 'success')
        self.items[0]['deviceName'] = 'iPhone 16'
        self.items[1]['deviceId'] = 'different-device'
        result = self.collect()
        self.assertIn('ATTACHMENT_DEVICE', self.codes(result))
        self.assertEqual(len(result['screenshots']), 2)

    def test_every_nonpassing_build_test_export_status_fails_but_keeps_originals(self):
        for phase in ('test', 'build', 'export'):
            for status in ('failure', 'cancelled', 'skipped', 'unknown'):
                with self.subTest(phase=phase, status=status):
                    result = self.collect(**{phase + '_status': status})
                    self.assertEqual(result['status'], 'failure')
                    self.assertEqual(result['collection_status'], 'complete')
                    self.assertEqual(len(result['screenshots']), 4)
                    self.assertEqual(result[phase + '_status'], status)
                    self.assertIn(phase.upper() + '_STATUS', self.codes(result))

    def test_bad_manifest_still_writes_report_and_removes_stale_canonical_images(self):
        self.assertEqual(self.collect()['status'], 'success')
        self.manifest = {'unexpected': 'shape'}
        result = self.collect()
        self.assertIn('MANIFEST_INVALID', self.codes(result))
        self.assertFalse(list(self.output.glob('*.png')))

    def test_actual_summary_with_skipped_failed_zero_or_missing_cases_cannot_pass(self):
        cases = [
            ({'totalTestCount': 4, 'passedTests': 0, 'failedTests': 0, 'skippedTests': 4, 'result': 'Passed'}, 'TEST_CASES_SKIPPED'),
            ({'totalTestCount': 4, 'passedTests': 3, 'failedTests': 1, 'skippedTests': 0, 'result': 'Failed'}, 'TEST_CASES_FAILED'),
            ({'totalTestCount': 0, 'passedTests': 0, 'failedTests': 0, 'skippedTests': 0, 'result': 'Passed'}, 'TEST_CASE_COUNT'),
            ({'unexpected': 'new schema'}, 'TEST_SUMMARY_SCHEMA'),
            (None, 'TEST_SUMMARY_MISSING'),
        ]
        for summary, code in cases:
            with self.subTest(summary=summary):
                self.summary = summary
                result = self.collect()
                self.assertEqual(result['status'], 'failure')
                self.assertEqual(len(result['screenshots']), 4)
                self.assertIn(code, self.codes(result))
                self.assertNotEqual(result['test_execution']['status'], 'verified')

    def test_matching_image_name_from_different_test_cannot_impersonate_capture(self):
        self.manifest[0]['testIdentifier'] = 'ChaiClassicsVisualSmokeTests/testDifferentMethod()'
        self.manifest[1]['testIdentifier'] = collector.EXPECTED_TESTS['01_iPad_Home'] + '()'
        result = self.collect()
        self.assertIn('MANIFEST_PROVENANCE', self.codes(result))
        self.assertEqual(len(result['screenshots']), 2)

    def test_test_identifiers_without_parentheses_are_supported_exactly(self):
        for test in self.manifest:
            test['testIdentifier'] = test['testIdentifier'].removesuffix('()')
        self.assertEqual(self.collect()['status'], 'success')

    def test_cli_exit_status_requires_all_three_success_results(self):
        self.collect()
        arguments = ['--attachments', str(self.attachments), '--device', str(self.device_path), '--output', str(self.output)]
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(collector.main(arguments), 1)
            self.assertEqual(collector.main(arguments + ['--test-status', 'success', '--build-status', 'success', '--export-status', 'success']), 0)


if __name__ == '__main__':
    unittest.main()
