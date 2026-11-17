"""Validate and byte-copy real XCTest iPad attachments; never render or resize images."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import sys
import zlib


SCREENSHOTS = (
    '01_iPad_Home', '02_iPad_Sudoku', '03_iPad_Minesweeper', '04_iPad_SlidingPuzzle',
)
EXPECTED_TESTS = {
    prefix: 'ChaiClassicsVisualSmokeTests/testIPad' + page + 'Screenshot'
    for prefix, page in zip(SCREENSHOTS, ('Home', 'Sudoku', 'Minesweeper', 'SlidingPuzzle'))
}
STATUSES = ('success', 'failure', 'cancelled', 'skipped', 'unknown')
NATIVE_PORTRAIT_SIZES = {(2064, 2752), (2048, 2732)}
PNG_SIGNATURE = b'\x89PNG\r\n\x1a\n'
MAX_FILE_BYTES = 64 * 1024 * 1024
UUID_PATTERN = r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
DEVICE_FIELDS = (
    'schema_version', 'status', 'device_name', 'device_udid', 'device_type_identifier',
    'runtime_identifier', 'runtime_version', 'runtime_build', 'deployment_target',
    'created', 'host_arch', 'xcode_version', 'source_commit', 'diagnostics', 'errors',
)
UNVERIFIED_UI = [
    'PNG integrity and simulator provenance do not prove the visual content is correct; review all four original images.',
    'This capture does not certify every game gesture, difficulty, puzzle, save recovery, language, theme, or accessibility setting.',
    'No physical-device, signing, App Store submission, or TestFlight upload is performed by this collection.',
]


class ValidationError(ValueError):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def _load_json(path, limit, code):
    try:
        with path.open('rb') as stream:
            raw = stream.read(limit + 1)
        if len(raw) > limit:
            raise ValidationError(code, 'JSON input exceeds the allowed size.')
        return json.loads(raw)
    except (OSError, ValueError) as exc:
        if isinstance(exc, ValidationError):
            raise
        raise ValidationError(code, 'Required JSON input is missing or invalid.') from None


def _device_errors(device):
    errors = []
    def reject(code, message):
        errors.append({'code': code, 'message': message})
    if not isinstance(device, dict):
        reject('DEVICE_METADATA', 'Device metadata must be a JSON object.')
        return errors
    if type(device.get('schema_version')) is not int or device['schema_version'] != 1:
        reject('DEVICE_METADATA', 'Unsupported device metadata schema.')
    if device.get('status') != 'ready':
        reject('DEVICE_NOT_READY', 'Simulator selection did not report ready.')
    kind = device.get('device_type_identifier', '')
    if not isinstance(kind, str) or not re.fullmatch(
            r'com\.apple\.CoreSimulator\.SimDeviceType\.iPad-(?:Pro|Air)-13-inch(?:-[A-Za-z0-9-]+)?', kind):
        reject('DEVICE_FAMILY', 'The selected simulator must be an actual 13-inch iPad; iPhone and 12.9-inch types are rejected.')
    name = device.get('device_name')
    if not isinstance(name, str) or not name.strip() or 'iphone' in name.lower():
        reject('DEVICE_NAME', 'The selected iPad must have a nonempty simulator name.')
    if not isinstance(device.get('device_udid'), str) or not re.fullmatch(UUID_PATTERN, device['device_udid']):
        reject('DEVICE_UDID', 'A valid selected simulator UDID is required.')
    runtime = device.get('runtime_identifier', '')
    if not isinstance(runtime, str) or not re.fullmatch(r'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9]+(?:-[0-9]+)*', runtime):
        reject('DEVICE_RUNTIME', 'A selected iOS simulator runtime is required.')
    for key in ('runtime_version', 'runtime_build', 'deployment_target', 'xcode_version'):
        if not isinstance(device.get(key), str) or not device[key].strip():
            reject('DEVICE_PROVENANCE', 'Runtime, deployment target and Xcode provenance must be present.')
            break
    if device.get('host_arch') not in ('x86_64', 'arm64'):
        reject('DEVICE_ARCH', 'A known simulator host architecture is required.')
    if not isinstance(device.get('source_commit'), str) or not re.fullmatch(r'[0-9a-fA-F]{40}', device['source_commit']):
        reject('SOURCE_COMMIT', 'The full source commit SHA is required.')
    if device.get('errors'):
        reject('DEVICE_SELECTION_ERRORS', 'Simulator selection recorded errors.')
    return errors


def _pass_rows(width, height, bits_per_pixel, interlace):
    passes = [(0, 0, 1, 1)] if not interlace else [
        (0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4),
        (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2),
    ]
    for x, y, dx, dy in passes:
        columns = max(0, (width - x + dx - 1) // dx)
        rows = max(0, (height - y + dy - 1) // dy)
        if columns and rows:
            yield rows, 1 + (columns * bits_per_pixel + 7) // 8


def _test_execution(path):
    """A successful xcodebuild exit with four XCTSkip cases is not a passing run."""
    execution = {'status': 'unverified', 'source': path.name}
    errors = []
    try:
        summary = _load_json(path, 8 * 1024 * 1024, 'TEST_SUMMARY_MISSING')
    except ValidationError as exc:
        return execution, [{'code': exc.code, 'message': 'Actual xcresult test summary is missing or unreadable; test execution remains unverified.'}]
    required = ('totalTestCount', 'passedTests', 'failedTests', 'skippedTests')
    if not isinstance(summary, dict) or any(type(summary.get(key)) is not int or summary[key] < 0 for key in required) or not isinstance(summary.get('result'), str):
        return execution, [{'code': 'TEST_SUMMARY_SCHEMA', 'message': 'Unsupported xcresult test summary schema; no passing execution is inferred.'}]
    execution.update({key: summary[key] for key in (*required, 'result')})
    execution['status'] = 'failed'
    if summary['skippedTests']:
        errors.append({'code': 'TEST_CASES_SKIPPED', 'message': 'The iPad capture suite contains skipped cases; four passing screenshot cases are required.'})
    if summary['failedTests'] or summary['result'] != 'Passed':
        errors.append({'code': 'TEST_CASES_FAILED', 'message': 'The actual xcresult summary does not report a fully passed run.'})
    if summary['totalTestCount'] != 4 or summary['passedTests'] != 4 or sum(summary[key] for key in ('passedTests', 'failedTests', 'skippedTests')) != summary['totalTestCount']:
        errors.append({'code': 'TEST_CASE_COUNT', 'message': 'Exactly four executed and passed iPad screenshot cases must be present in xcresult.'})
    if not errors:
        execution['status'] = 'verified'
    return execution, errors


def validate_png(data):
    """Check PNG framing, every CRC, native size, and complete bounded scanlines."""
    def invalid(message):
        raise ValidationError('PNG_INVALID', message)
    if len(data) > MAX_FILE_BYTES or not data.startswith(PNG_SIGNATURE):
        invalid('Attachment is not a bounded PNG file.')
    position = 8
    chunks = []
    compressed = []
    header = None
    palette = False
    idat_closed = False
    finished = False
    while position < len(data):
        if len(data) - position < 12:
            invalid('PNG contains a truncated chunk.')
        length = struct.unpack_from('>I', data, position)[0]
        kind = data[position + 4:position + 8]
        end = position + length + 12
        if end > len(data) or not re.fullmatch(b'[A-Za-z]{4}', kind):
            invalid('PNG chunk framing is invalid.')
        payload = data[position + 8:position + 8 + length]
        crc = struct.unpack_from('>I', data, position + 8 + length)[0]
        if zlib.crc32(payload, zlib.crc32(kind)) & 0xffffffff != crc:
            invalid('PNG chunk checksum does not match.')
        if not chunks and kind != b'IHDR':
            invalid('PNG must begin with IHDR.')
        if kind == b'IHDR':
            if header is not None or length != 13:
                invalid('PNG must contain exactly one valid IHDR.')
            header = struct.unpack('>IIBBBBB', payload)
            width, height, depth, color, compression, filtering, interlace = header
            if width >= height:
                raise ValidationError('PNG_ORIENTATION', 'Screenshot must be native portrait, without rotation.')
            if (width, height) not in NATIVE_PORTRAIT_SIZES:
                raise ValidationError('PNG_DIMENSIONS', 'Screenshot must be exactly 2064x2752 or 2048x2732 pixels; resizing is not performed.')
            allowed_depths = {0: (1, 2, 4, 8, 16), 2: (8, 16), 3: (1, 2, 4, 8), 4: (8, 16), 6: (8, 16)}
            if color not in allowed_depths or depth not in allowed_depths[color] or compression or filtering or interlace not in (0, 1):
                invalid('PNG IHDR encoding is invalid.')
        elif kind == b'PLTE':
            if palette or compressed or not length or length > 768 or length % 3:
                invalid('PNG palette is invalid or out of order.')
            if header[3] in (0, 4) or (header[3] == 3 and length // 3 > 2 ** header[2]):
                invalid('PNG palette is incompatible with IHDR.')
            palette = True
        elif kind == b'IDAT':
            if idat_closed:
                invalid('PNG IDAT chunks must be consecutive.')
            compressed.append(payload)
        elif kind == b'IEND':
            if length or not compressed or end != len(data):
                invalid('PNG must end after a complete IDAT stream and empty IEND.')
            finished = True
        else:
            if kind[0] < 97:
                invalid('PNG contains an unknown critical chunk.')
            if compressed:
                idat_closed = True
        chunks.append(kind)
        position = end
    if not finished or header is None:
        invalid('PNG is missing its required final chunk.')
    width, height, depth, color, _, _, interlace = header
    if color == 3 and not palette:
        invalid('Indexed PNG requires a palette.')
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color]
    rows = list(_pass_rows(width, height, depth * channels, interlace))
    expected = sum(count * length for count, length in rows)
    try:
        decoder = zlib.decompressobj()
        raw = decoder.decompress(b''.join(compressed), expected + 1)
        if len(raw) != expected or not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
            invalid('PNG pixel data is truncated or has an unexpected length.')
    except zlib.error:
        invalid('PNG pixel data is not a complete zlib stream.')
    offset = 0
    for count, length in rows:
        for _ in range(count):
            if raw[offset] > 4:
                invalid('PNG contains an invalid scanline filter.')
            offset += length
    return {'width': width, 'height': height}


def _screenshot_name(name):
    if not isinstance(name, str):
        return None
    for prefix in SCREENSHOTS:
        if re.fullmatch(re.escape(prefix) + r'(?:_[0-9]+_' + UUID_PATTERN + r')?\.png', name):
            return prefix
    return None


def _source_path(directory, filename):
    if not isinstance(filename, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*\.png', filename):
        raise ValidationError('MANIFEST_PATH', 'PNG exportedFileName must be a plain PNG filename, without path components.')
    path = directory / filename
    if path.is_symlink() or path.resolve().parent != directory.resolve():
        raise ValidationError('MANIFEST_PATH', 'Attachment symlinks and paths outside the export directory are rejected.')
    return path


def _write_reports(output, report):
    (output / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    lines = [
        'ChaiClassics — Original iPad simulator screenshots',
        '',
        'Overall status: ' + report['status'],
        'Image collection: ' + report['collection_status'],
        'Build: ' + report['build_status'],
        'UI test: ' + report['test_status'],
        'Actual xcresult test execution: ' + report['test_execution']['status'],
        'XCTest attachment export: ' + report['export_status'],
        '',
        'These PNGs are unmodified byte copies of XCTest attachments. No rendering, resizing, compositing or AI image generation is performed.',
        'Files being present does not mean the build or tests passed. Any non-success status keeps this report failed.',
        'Synthetic images exist only in temporary automated-test fixtures, never as screenshot deliverables.',
        '',
        'Capture provenance (device.json):',
    ]
    for key in ('source_commit', 'xcode_version', 'device_name', 'device_udid', 'device_type_identifier', 'runtime_identifier', 'runtime_version', 'runtime_build', 'host_arch', 'deployment_target'):
        lines.append(key + ': ' + json.dumps(report['device'].get(key), ensure_ascii=False))
    lines.extend(['', 'Collected original images:'])
    for image in report['screenshots']:
        lines.append(f"{image['filename']}: {image['width']}x{image['height']}; sha256={image['sha256']}; source={image['source']['exported_file_name']}")
    lines.extend(['', 'Errors:'])
    lines.extend(error['code'] + ': ' + error['message'] + (' [' + error['screenshot'] + ']' if 'screenshot' in error else '') for error in report['errors'])
    if not report['errors']:
        lines.append('None recorded. Review the actual images before using them.')
    lines.extend(['', 'Still requires verification:', *UNVERIFIED_UI, ''])
    (output / 'README.txt').write_text('\n'.join(lines), encoding='utf-8')
    execution = report['test_execution']
    markdown = [
        '# ChaiClassics iPad screenshots', '',
        '**Overall:** ' + report['status'] + ' · **Images:** ' + report['collection_status'], '',
        '| Verification | Result |', '| --- | --- |',
        '| Build command | ' + report['build_status'] + ' |',
        '| UI test command | ' + report['test_status'] + ' |',
        '| Actual xcresult case execution | ' + execution['status'] + ' |',
        '| Attachment export | ' + report['export_status'] + ' |', '',
        'Original PNG bytes only. File availability never substitutes for passing tests.', '',
        '## Capture provenance', '',
    ]
    for key in ('source_commit', 'xcode_version', 'device_name', 'device_udid', 'device_type_identifier', 'runtime_identifier', 'runtime_version', 'runtime_build', 'host_arch', 'deployment_target'):
        markdown.append('- ' + key + ': ' + json.dumps(report['device'].get(key), ensure_ascii=False))
    markdown.extend(['', '## Executed tests', '',
                     'xcresult summary: ' + json.dumps(execution, ensure_ascii=False), '',
                     '## Unmodified screenshots', '',
                     '| Image | Native pixels | SHA-256 |', '| --- | --- | --- |'])
    for image in report['screenshots']:
        markdown.append(f"| {image['filename']} | {image['width']} × {image['height']} | {image['sha256']} |")
    markdown.extend(['', 'Original exported filenames and source XCTest cases are recorded in report.json.', '', '## Errors', ''])
    markdown.extend('- ' + error['code'] + ': ' + error['message'] + (' [' + error['screenshot'] + ']' if 'screenshot' in error else '') for error in report['errors'])
    if not report['errors']:
        markdown.append('None recorded. Review all four originals before using them.')
    markdown.extend(['', '## Still requires verification', '', *['- ' + note for note in UNVERIFIED_UI], ''])
    (output / 'REPORT.md').write_text('\n'.join(markdown), encoding='utf-8')


def collect_screenshots(attachments, device_path, output, *, test_status='unknown', build_status='unknown', export_status='unknown', test_summary=None):
    attachments, device_path, output = Path(attachments), Path(device_path), Path(output)
    output.mkdir(parents=True, exist_ok=True)
    report = {
        'schema_version': 1, 'status': 'failure', 'collection_status': 'failed',
        'build_status': build_status, 'test_status': test_status, 'export_status': export_status,
        'device': {}, 'screenshots': [], 'errors': [], 'unverified_ui': UNVERIFIED_UI,
        'test_execution': {'status': 'unverified'},
    }
    def error(code, message, screenshot=None):
        value = {'code': code, 'message': message}
        if screenshot:
            value['screenshot'] = screenshot
        report['errors'].append(value)
    for phase, status in [('BUILD', build_status), ('TEST', test_status), ('EXPORT', export_status)]:
        if status != 'success':
            error(phase + '_STATUS', phase.title() + ' did not report success; image availability is not a passing test result.')
    execution, execution_errors = _test_execution(Path(test_summary) if test_summary else output / 'test-summary.json')
    report['test_execution'] = execution
    report['errors'].extend(execution_errors)
    # Never let a retry publish a previous attempt's canonical screenshots.
    if output.resolve() == attachments.resolve():
        error('OUTPUT_COLLISION', 'The output directory must differ from the attachment export directory.')
        _write_reports(output, report)
        return report
    for prefix in SCREENSHOTS:
        destination = output / (prefix + '.png')
        if destination.exists() or destination.is_symlink():
            try:
                destination.unlink()
            except OSError:
                error('OUTPUT_IO', 'A previous canonical screenshot could not be removed.', prefix)
    device_ready = False
    try:
        device = _load_json(device_path, 512 * 1024, 'DEVICE_METADATA')
        if isinstance(device, dict):
            report['device'] = {key: device[key] for key in DEVICE_FIELDS if key in device}
        problems = _device_errors(device)
        report['errors'].extend(problems)
        device_ready = not problems
    except ValidationError as exc:
        error(exc.code, str(exc))
    entries = []
    try:
        manifest_path = attachments / 'manifest.json'
        if manifest_path.is_symlink():
            raise ValidationError('MANIFEST_PATH', 'Manifest symlinks are rejected.')
        manifest = _load_json(manifest_path, 8 * 1024 * 1024, 'MANIFEST_INVALID')
        if not isinstance(manifest, list):
            raise ValidationError('MANIFEST_INVALID', 'XCTest attachment manifest must be a list of test records.')
        for test in manifest:
            if not isinstance(test, dict) or not isinstance(test.get('attachments'), list):
                raise ValidationError('MANIFEST_INVALID', 'Each manifest test must contain an attachment list.')
            for attachment in test['attachments']:
                if not isinstance(attachment, dict):
                    raise ValidationError('MANIFEST_INVALID', 'Each manifest attachment must be an object.')
                prefix = _screenshot_name(attachment.get('suggestedHumanReadableName'))
                if prefix:
                    entries.append((prefix, attachment, test.get('testIdentifier')))
    except ValidationError as exc:
        error(exc.code, str(exc))
    source_counts = Counter(attachment.get('exportedFileName') for _, attachment, _ in entries if isinstance(attachment.get('exportedFileName'), str))
    copied_hashes = {}
    for prefix in SCREENSHOTS:
        candidates = [(item, identifier) for name, item, identifier in entries if name == prefix]
        if not candidates:
            error('SCREENSHOT_MISSING', 'No exactly named XCTest screenshot was exported.', prefix)
            continue
        if len(candidates) != 1:
            error('SCREENSHOT_DUPLICATE', 'Multiple matching attachments are ambiguous; none was selected.', prefix)
            continue
        attachment, identifier = candidates[0]
        if not device_ready:
            continue
        destination = output / (prefix + '.png')
        try:
            if attachment.get('deviceId') != device['device_udid'] or attachment.get('deviceName') != device['device_name']:
                raise ValidationError('ATTACHMENT_DEVICE', 'Attachment device ID and name must exactly match the selected iPad.')
            if identifier not in (EXPECTED_TESTS[prefix], EXPECTED_TESTS[prefix] + '()'):
                raise ValidationError('MANIFEST_PROVENANCE', 'Screenshot must originate from its exact expected iPad XCTest method.')
            filename = attachment.get('exportedFileName')
            source = _source_path(attachments, filename)
            if source_counts[filename] != 1:
                raise ValidationError('SCREENSHOT_SOURCE_REUSED', 'The same exported file is assigned to more than one screenshot.')
            with source.open('rb') as stream:
                data = stream.read(MAX_FILE_BYTES + 1)
            dimensions = validate_png(data)
            checksum = hashlib.sha256(data).hexdigest()
            if checksum in copied_hashes:
                raise ValidationError('SCREENSHOT_CONTENT_DUPLICATE', 'Another named page contains the exact same PNG bytes; review the capture navigation.')
            shutil.copyfile(source, destination)
            if hashlib.sha256(destination.read_bytes()).hexdigest() != checksum:
                destination.unlink(missing_ok=True)
                raise ValidationError('COPY_INTEGRITY', 'Copied bytes do not match the original XCTest attachment.')
            copied_hashes[checksum] = prefix
            report['screenshots'].append({
                'filename': destination.name, **dimensions, 'sha256': checksum,
                'source': {
                    'exported_file_name': filename,
                    'suggested_human_readable_name': attachment['suggestedHumanReadableName'],
                    'test_identifier': identifier,
                    'device_id': attachment['deviceId'], 'device_name': attachment['deviceName'],
                },
            })
        except ValidationError as exc:
            error(exc.code, str(exc), prefix)
        except OSError:
            error('SCREENSHOT_IO', 'Original screenshot could not be read or byte-copied.', prefix)
            try:
                destination.unlink(missing_ok=True)
            except OSError:
                error('OUTPUT_IO', 'Incomplete screenshot output could not be removed.', prefix)
    count = len(report['screenshots'])
    report['collection_status'] = 'complete' if count == len(SCREENSHOTS) else 'partial' if count else 'failed'
    if count == len(SCREENSHOTS) and not report['errors']:
        report['status'] = 'success'
    _write_reports(output, report)
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--attachments', required=True, type=Path)
    parser.add_argument('--device', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--test-summary', type=Path, help='xcresulttool test-results summary JSON; defaults to OUTPUT/test-summary.json')
    for status in ('test', 'build', 'export'):
        parser.add_argument('--' + status + '-status', choices=STATUSES, default='unknown')
    args = parser.parse_args(argv)
    try:
        report = collect_screenshots(args.attachments, args.device, args.output,
                                     test_status=args.test_status, build_status=args.build_status, export_status=args.export_status,
                                     test_summary=args.test_summary)
    except OSError:
        print('iPad screenshot collection failed [OUTPUT_IO]: report files could not be written.', file=sys.stderr)
        return 1
    print('iPad screenshot collection: ' + report['collection_status'] + '; overall=' + report['status'])
    for item in report['errors']:
        print('[' + item['code'] + ']' + (' ' + item['screenshot'] if 'screenshot' in item else '') + ': ' + item['message'])
    return 0 if report['status'] == 'success' else 1


if __name__ == '__main__':
    raise SystemExit(main())
