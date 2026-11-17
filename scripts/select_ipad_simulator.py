"""Select a real installed 13-inch iPad Pro; never substitute a phone or 12.9-inch iPad.

The optional inventory file is an offline inspection fixture. Only a live inventory
may create a local simulator; this script never downloads runtimes or boots devices.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import unicodedata
import uuid


ROOT = Path(__file__).resolve().parents[1]
TYPE_PREFIX = 'com.apple.CoreSimulator.SimDeviceType.'
RUNTIME_PREFIX = 'com.apple.CoreSimulator.SimRuntime.iOS-'


class SelectionError(ValueError):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def run_command(arguments, timeout=60):
    return subprocess.run(arguments, check=True, capture_output=True, text=True, timeout=timeout).stdout.strip()


def version_tuple(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d+(?:\.\d+){0,2}', value):
        return None
    return tuple((list(map(int, value.split('.'))) + [0, 0])[:3])


def normalize_name(value):
    value = unicodedata.normalize('NFKC', str(value)).casefold()
    value = re.sub(r'[‐‑‒–—−]', '-', value)
    value = re.sub(r'13\s*(?:吋|英寸)', '13-inch', value)
    value = re.sub(r'13\s*-?\s*inch', '13-inch', value)
    return re.sub(r'\s+', ' ', value).strip()


def is_pro_13_type(kind):
    # The installed type identifier, not a user-editable simulator name, is proof.
    identifier = kind.get('identifier', '')
    name = normalize_name(kind.get('name', ''))
    return (isinstance(identifier, str) and re.fullmatch(
        re.escape(TYPE_PREFIX) + r'iPad-Pro-13-inch(?:-[A-Za-z0-9-]+)?', identifier) is not None
        and re.search(r'\bipad pro\b', name) is not None
        and re.search(r'\b13-inch\b', name) is not None
        and '12.9' not in name)


def is_available(item):
    if item.get('availabilityError'):
        return False
    if 'isAvailable' in item:
        return item['isAvailable'] is True
    return item.get('availability') == '(available)'


def is_stable_runtime(runtime):
    if not str(runtime.get('identifier', '')).startswith(RUNTIME_PREFIX):
        return False
    if version_tuple(runtime.get('version')) is None:
        return False
    labels = ' '.join(str(runtime.get(key, '')) for key in ('name', 'identifier', 'version', 'buildversion'))
    if re.search(r'beta|preview|seed|release\s*candidate|(?:^|[\s._-])rc(?:\d|$|[\s._-])', labels, re.I):
        return False
    # Apple seed builds carry a lowercase suffix. Missing build provenance is not
    # adequate for an App Store screenshot capture either.
    return re.fullmatch(r'\d+[A-Z]\d+', str(runtime.get('buildversion', ''))) is not None


def _bound(kind, prefix):
    value = version_tuple(kind.get(prefix + 'RuntimeVersionString'))
    if value is not None:
        return value
    packed = kind.get(prefix + 'RuntimeVersion')
    if type(packed) is int and packed >= 0:
        return (packed >> 16, (packed >> 8) & 255, packed & 255)
    return None


def compatible(kind, runtime, existing=False):
    version = version_tuple(runtime['version'])
    low, high = _bound(kind, 'min'), _bound(kind, 'max')
    if low is not None and version < low or high is not None and version > high:
        return False
    supported = runtime.get('supportedDeviceTypes')
    if isinstance(supported, list):
        identifiers = {row.get('identifier') if isinstance(row, dict) else row for row in supported}
        return kind['identifier'] in identifiers
    # A live available created device proves compatibility even on older simctl
    # inventories without bounds. Creating a new device requires affirmative data.
    return existing or low is not None


def deployment_target(root=ROOT):
    project = root / 'ChaiClassics.xcodeproj/project.pbxproj'
    generator = root / 'scripts/create_project.py'
    patterns = ((project, r'IPHONEOS_DEPLOYMENT_TARGET\s*=\s*"?(\d+(?:\.\d+){0,2})'),
                (generator, r"['\"]IPHONEOS_DEPLOYMENT_TARGET['\"]\s*:\s*['\"](\d+(?:\.\d+){0,2})"))
    for path, pattern in patterns:
        try:
            versions = re.findall(pattern, path.read_text(encoding='utf-8'))
        except OSError:
            continue
        if versions:
            return max(versions, key=version_tuple)
    raise SelectionError('IPAD13_DEPLOYMENT_UNAVAILABLE', 'Cannot determine the project iOS deployment target.')


def inventory_diagnostics(inventory):
    kinds = {kind['identifier']: kind for kind in inventory.get('devicetypes', [])
             if isinstance(kind, dict) and isinstance(kind.get('identifier'), str)}
    runtimes = {runtime['identifier']: runtime for runtime in inventory.get('runtimes', [])
                if isinstance(runtime, dict) and isinstance(runtime.get('identifier'), str)}
    ipads = []
    for runtime_id, devices in inventory.get('devices', {}).items():
        runtime = runtimes.get(runtime_id, {})
        for device in devices:
            kind = kinds.get(device.get('deviceTypeIdentifier'), {})
            if 'ipad' not in str(kind.get('name', device.get('name', ''))).lower():
                continue
            ipads.append({
                'device_name': device.get('name'), 'device_type_identifier': device.get('deviceTypeIdentifier'),
                'runtime_identifier': runtime_id, 'runtime_version': runtime.get('version'),
                'runtime_build': runtime.get('buildversion'),
                'is_available': is_available(device) and is_available(runtime),
                'is_13_inch_pro': is_pro_13_type(kind),
            })
    return {
        'available_ipads': ipads,
        'installed_ipad_types': [{'name': kind.get('name'), 'identifier': kind['identifier'],
                                  'is_13_inch_pro': is_pro_13_type(kind)}
                                 for kind in kinds.values() if 'ipad' in str(kind.get('name', '')).lower()],
        'installed_ios_runtimes': [{'name': runtime.get('name'), 'identifier': runtime['identifier'],
                                    'version': runtime.get('version'), 'build': runtime.get('buildversion'),
                                    'is_available': is_available(runtime), 'is_stable': is_stable_runtime(runtime)}
                                   for runtime in runtimes.values() if runtime['identifier'].startswith(RUNTIME_PREFIX)],
    }


def validate_inventory(inventory):
    if (not isinstance(inventory, dict) or not isinstance(inventory.get('devices'), dict)
            or not isinstance(inventory.get('runtimes'), list) or not isinstance(inventory.get('devicetypes'), list)
            or any(not isinstance(devices, list) or any(not isinstance(device, dict) for device in devices)
                   for devices in inventory['devices'].values())):
        raise SelectionError('IPAD13_INVENTORY_INVALID', 'Simulator inventory has an unsupported JSON structure.')


def _model_rank(kind):
    match = re.search(r'\bM(\d+)\b', kind.get('name', ''), re.I)
    return int(match.group(1)) if match else 0


def select_device(inventory, target, device_name='auto'):
    """Pure selection plan. A create plan contains no host-side effects."""
    validate_inventory(inventory)
    floor = version_tuple(target)
    if floor is None:
        raise SelectionError('IPAD13_DEPLOYMENT_UNAVAILABLE', 'The project iOS deployment target is invalid.')
    if not isinstance(device_name, str) or not device_name.strip():
        raise SelectionError('IPAD13_REQUEST_INVALID', 'Specify an exact simulator model/name or auto.')
    automatic = device_name.lower() == 'auto'
    kinds = {kind['identifier']: kind for kind in inventory['devicetypes']
             if isinstance(kind, dict) and isinstance(kind.get('identifier'), str)}
    pro_types = [kind for kind in kinds.values() if is_pro_13_type(kind)]
    if not pro_types:
        raise SelectionError('IPAD13_MODEL_NOT_INSTALLED',
                             'No genuine iPad Pro 13-inch device type is installed. Try the standard macos-15 ARM runner manually; no iPhone or 12.9-inch fallback is permitted.')
    runtimes = {runtime['identifier']: runtime for runtime in inventory['runtimes']
                if isinstance(runtime, dict) and isinstance(runtime.get('identifier'), str)
                and is_available(runtime) and is_stable_runtime(runtime)
                and version_tuple(runtime.get('version')) >= floor}
    if not runtimes:
        raise SelectionError('IPAD13_NO_STABLE_RUNTIME', 'No available stable installed iOS runtime meets the project deployment target; beta and RC runtimes are rejected.')
    candidates = []
    for runtime_id, devices in inventory['devices'].items():
        runtime = runtimes.get(runtime_id)
        if runtime is None:
            continue
        for device in devices:
            kind = kinds.get(device.get('deviceTypeIdentifier'), {})
            if (not automatic and device.get('name') != device_name
                    or not is_available(device) or not is_pro_13_type(kind)
                    or not compatible(kind, runtime, existing=True)):
                continue
            try:
                udid = str(uuid.UUID(device.get('udid', '')))
            except (ValueError, AttributeError, TypeError):
                continue
            candidates.append((runtime, kind, device.get('name'), udid))
    if candidates:
        runtime, kind, name, udid = max(candidates, key=lambda row: (
            version_tuple(row[0]['version']), _model_rank(row[1]), row[2], row[3]))
        return _plan(runtime, kind, name, udid, False)
    # A strict explicit name can only create that exact installed 13-inch model.
    requested_types = pro_types if automatic else [kind for kind in pro_types if kind.get('name') == device_name]
    if not requested_types:
        raise SelectionError('IPAD13_REQUEST_NOT_FOUND', 'The exact requested available 13-inch iPad Pro name/model was not found; no other device will be substituted.')
    pairs = [(runtime, kind) for runtime in runtimes.values() for kind in requested_types if compatible(kind, runtime)]
    if not pairs:
        raise SelectionError('IPAD13_NO_COMPATIBLE_DEVICE', 'No installed stable runtime is confirmed compatible with the requested 13-inch iPad Pro type.')
    runtime, kind = max(pairs, key=lambda row: (version_tuple(row[0]['version']), _model_rank(row[1]), row[1]['identifier']))
    name = kind['name'] + ' - ChaiClassics' if automatic else device_name
    return _plan(runtime, kind, name, None, True)


def _plan(runtime, kind, name, udid, create):
    return {'device_name': name, 'device_udid': udid, 'device_type_identifier': kind['identifier'],
            'runtime_identifier': runtime['identifier'], 'runtime_version': runtime['version'],
            'runtime_build': runtime['buildversion'], 'created': False, 'requires_creation': create}


def _metadata(runner, root):
    sha = os.environ.get('GITHUB_SHA', '')
    if not re.fullmatch(r'[0-9a-fA-F]{40}', sha):
        try:
            sha = runner(['git', '-C', str(root), 'rev-parse', 'HEAD'], timeout=20)
        except (OSError, subprocess.SubprocessError):
            sha = None
    if not isinstance(sha, str) or not re.fullmatch(r'[0-9a-fA-F]{40}', sha):
        sha = None
    try:
        xcode = runner(['xcodebuild', '-version'], timeout=20)
    except (OSError, subprocess.SubprocessError):
        xcode = None
    # Only public version/build lines are accepted, never arbitrary command output.
    if not isinstance(xcode, str) or not re.fullmatch(r'Xcode \d+(?:\.\d+){0,2}\nBuild version [A-Za-z0-9]+', xcode.strip()):
        xcode = None
    return {'host_arch': platform.machine(), 'xcode_version': xcode, 'source_commit': sha}


def main(argv=None, runner=run_command, root=ROOT):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--device-name', default='auto')
    parser.add_argument('--inventory', type=Path, help='Offline JSON inventory fixture; never creates a simulator.')
    args = parser.parse_args(argv)
    report = {'schema_version': 1, 'status': 'error', 'device_name': None, 'device_udid': None,
              'device_type_identifier': None, 'runtime_identifier': None, 'runtime_version': None,
              'runtime_build': None, 'deployment_target': None, 'created': False,
              **_metadata(runner, root), 'available_ipads': [], 'errors': [], 'diagnostics': {}}
    try:
        report['deployment_target'] = deployment_target(root)
        try:
            raw = args.inventory.read_text(encoding='utf-8') if args.inventory else runner(['xcrun', 'simctl', 'list', '--json'], timeout=60)
            inventory = json.loads(raw)
        except (OSError, ValueError, subprocess.SubprocessError):
            raise SelectionError('IPAD13_INVENTORY_UNAVAILABLE', 'Cannot read the installed local simulator inventory.') from None
        validate_inventory(inventory)
        diagnostics = inventory_diagnostics(inventory)
        report['available_ipads'] = diagnostics.pop('available_ipads')
        report['diagnostics'].update(diagnostics)
        plan = select_device(inventory, report['deployment_target'], args.device_name)
        needs_creation = plan.pop('requires_creation')
        report.update(plan)
        if needs_creation:
            if args.inventory:
                raise SelectionError('IPAD13_OFFLINE_CREATION_REQUIRED', 'The offline inventory requires simulator creation; no host device was created.')
            try:
                created = runner(['xcrun', 'simctl', 'create', plan['device_name'],
                                  plan['device_type_identifier'], plan['runtime_identifier']], timeout=60)
            except (OSError, subprocess.SubprocessError):
                raise SelectionError('IPAD13_CREATE_FAILED', 'Local 13-inch iPad Pro simulator creation failed; no runtime download or fallback was attempted.') from None
            try:
                report['device_udid'] = str(uuid.UUID(created))
            except (ValueError, TypeError, AttributeError):
                raise SelectionError('IPAD13_CREATE_INVALID_UDID', 'Simulator creation did not return a valid simulator UUID.') from None
            report['created'] = True
        report['status'] = 'ready'
        report['diagnostics'].update(code='IPAD13_READY', message='Selected a genuine 13-inch iPad Pro on an available installed stable iOS runtime.')
    except SelectionError as error:
        entry = {'code': error.code, 'message': str(error)}
        report['errors'].append(entry)
        report['diagnostics'].update(entry)
    try:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.output.with_name(args.output.name + '.tmp')
        temporary.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        temporary.replace(args.output)
    except OSError:
        print('IPAD13_OUTPUT_WRITE_FAILED: Cannot write simulator selection diagnostics.', file=sys.stderr)
        return 1
    print(report['diagnostics']['code'] + ': ' + report['diagnostics']['message'])
    if report['status'] != 'ready':
        models = sorted({str(item.get('name')) for item in report['diagnostics'].get('installed_ipad_types', [])})
        runtimes = [str(item.get('name')) + ' ' + str(item.get('version'))
                    for item in report['diagnostics'].get('installed_ios_runtimes', [])]
        print('Installed iPad models: ' + (', '.join(models) or 'none'))
        print('Installed iOS runtimes: ' + (', '.join(runtimes) or 'none'))
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
