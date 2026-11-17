#!/usr/bin/env python3
"""Narrow, test-helper-only repair proof. Current execution and inherited coverage stay separate."""
import argparse
from collections import Counter
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import zipfile

import verify_candidate as candidate

BASELINE_RUN = 44014619310
BASELINE_SHA = '31ca27b8c8461080bdae6e98fface36d49f24d1c'
SELECTED_TESTS = (
    'ChaiClassicsUITests/testSlidingCanStartAndRestore',
    'ChaiClassicsUITests/testSlidingSwipesInAllFourDirectionsAndRestoresExactlyOneMove',
    'ChaiClassicsVisualSmokeTests/testFreshWinCelebratesOnceAndRestoredWinDoesNotReplay',
)
HISTORICAL_FAILURES = {SELECTED_TESTS[0], SELECTED_TESTS[2]}
HELPERS = {
    'UITests/ChaiClassicsUITests.swift': {'scrollFullyIntoView'},
    'UITests/ChaiClassicsVisualSmokeTests.swift': {'scrollFullyIntoView', 'openSavedSliding'},
}
QA_FILES = set(HELPERS) | {
    'README.md', 'scripts/ci.sh', 'scripts/ui_test_scope.py',
    'scripts/verify_candidate.py', 'scripts/verify_incremental_ci.py',
    '.github/workflows/ci.yml', '.github/workflows/testflight.yml',
}
TRUSTED_BRANCHES = ('main', 'develop/0.2.0')
require = candidate.require


def qa_path(path):
    return path in QA_FILES or path.startswith(('tests/', 'docs/'))


def swift_mask(source):
    """Mask comments/string literals while preserving offsets for balanced Swift braces."""
    result = list(source)
    i = 0
    while i < len(source):
        start = i
        if source.startswith('//', i):
            end = source.find('\n', i)
            i = len(source) if end < 0 else end
        elif source.startswith('/*', i):
            i += 2; depth = 1
            while i < len(source) and depth:
                if source.startswith('/*', i): depth += 1; i += 2
                elif source.startswith('*/', i): depth -= 1; i += 2
                else: i += 1
            require(depth == 0, 'Unterminated Swift comment.')
        elif source[i] == '"':
            delimiter = '"""' if source.startswith('"""', i) else '"'
            i += len(delimiter)
            while i < len(source):
                if source[i] == '\\': i += 2
                elif source.startswith(delimiter, i): i += len(delimiter); break
                else: i += 1
            else: raise candidate.CandidateError('Unterminated Swift string.')
        else:
            i += 1
            continue
        result[start:i] = ' ' * (i - start)
    return ''.join(result)


def functions(source):
    mask = swift_mask(source)
    found = {}
    for match in re.finditer(r'\bfunc\s+(\w+)\s*\(', mask):
        start = mask.find('{', match.end())
        require(start >= 0, 'Missing Swift function body.')
        depth = 1; end = start + 1
        while end < len(mask) and depth:
            depth += (mask[end] == '{') - (mask[end] == '}'); end += 1
        require(depth == 0 and match[1] not in found, 'Unbalanced or duplicate Swift function.')
        found[match[1]] = (start, end)
    return found


def assertions(source):
    mask = swift_mask(source)
    values = []
    for match in re.finditer(r'\bXCT(?:Assert\w*|Fail|Unwrap|Skip\w*)\s*\(', mask):
        start = mask.index('(', match.start()); end = start + 1; depth = 1
        while end < len(mask) and depth:
            depth += (mask[end] == '(') - (mask[end] == ')'); end += 1
        require(depth == 0, 'Unbalanced assertion.')
        values.append(source[match.start():end])
    return Counter(values)


def test_method_hashes(tree):
    methods = {}
    for path, (_mode, data) in tree.items():
        if path.startswith('UITests/') and path.endswith('.swift'):
            source = data.decode('utf-8')
            for name, (start, end) in functions(source).items():
                if name.startswith('test'):
                    key = Path(path).stem + '/' + name
                    require(key not in methods, 'Duplicate test identity.')
                    methods[key] = hashlib.sha256(source[start:end].encode()).hexdigest()
    return methods


def validate_source_trees(base, current):
    changed = sorted(path for path in set(base) | set(current) if base.get(path) != current.get(path))
    require(all(qa_path(path) for path in changed), 'Runtime/application/signing source changed; complete new integration evidence is required.')
    flight = '.github/workflows/testflight.yml'
    if flight in changed:
        require(flight in base and flight in current, 'Protected TestFlight workflow cannot be added or removed.')
        def normalize_flight(data):
            data = data.replace(b'Required for 0.2.0: successful full_ui CI workflow run ID',
                                b'Required for 0.2.0: verified full or test-helper-only incremental CI run ID')
            preflight, upload = data.split(b'  upload:\n', 1)
            require(preflight.count(b'          fetch-depth: 0\n') <= 1, 'Unexpected preflight checkout changes.')
            return preflight.replace(b'          fetch-depth: 0\n', b'') + b'  upload:\n' + upload
        require(normalize_flight(base[flight][1]) == normalize_flight(current[flight][1]),
                'Only preflight history checkout and the CI evidence input description may change; signing/gates remain frozen.')
    for path in changed:
        if path in current:
            require(current[path][0] in ('100644', '100755'), 'QA changes cannot introduce symlinks or submodules.')
        if path in HELPERS:
            require(path in base and path in current, 'A UI test source cannot be added or deleted.')
            old = base[path][1].decode('utf-8'); new = current[path][1].decode('utf-8')
            old_funcs, new_funcs = functions(old), functions(new)
            old_masked, new_masked = old, new
            for name in sorted(HELPERS[path], key=lambda name: old_funcs.get(name, (0, 0))[0], reverse=True):
                if name not in old_funcs and name not in new_funcs: continue
                require(name in old_funcs and name in new_funcs, 'A permitted helper cannot be removed or renamed.')
                a, b = old_funcs[name]; x, y = new_funcs[name]
                before = assertions(old[a:b]); after = assertions(new[x:y])
                require(all(after[item] >= count for item, count in before.items()), 'Existing helper assertions cannot be removed or weakened.')
                old_masked = old_masked[:a] + '{QA_HELPER}' + old_masked[b:]
                new_masked = new_masked[:x] + '{QA_HELPER}' + new_masked[y:]
            require(old_masked == new_masked, 'Only the approved private helper bodies may change in UI test files.')
    old_methods = test_method_hashes(base); new_methods = test_method_hashes(current)
    require(old_methods == new_methods and old_methods, 'UI test methods/assertions changed or were removed.')
    def digest(tree):
        records = []
        for path, (mode, data) in sorted(tree.items()):
            if not qa_path(path): records.append((path, mode, hashlib.sha256(data).hexdigest()))
        flight = '.github/workflows/testflight.yml'
        if flight in tree:
            data = tree[flight][1]
            require(b'jobs:\n' in data and b'  upload:\n' in data, 'Missing protected TestFlight sections.')
            header = data.split(b'jobs:\n', 1)[0].replace(
                b'Required for 0.2.0: successful full_ui CI workflow run ID',
                b'Required for 0.2.0: verified full or test-helper-only incremental CI run ID')
            records.extend([(flight + '#header', '100644', hashlib.sha256(header).hexdigest()),
                            (flight + '#signed-upload', '100644', hashlib.sha256(data.split(b'  upload:\n', 1)[1]).hexdigest())])
        return hashlib.sha256(json.dumps(records, separators=(',', ':')).encode()).hexdigest()
    old_digest, new_digest = digest(base), digest(current)
    require(old_digest == new_digest, 'Protected runtime/signing bytes changed.')
    return {'app_source_digest': new_digest,
            'test_methods_digest': hashlib.sha256(json.dumps(old_methods, sort_keys=True).encode()).hexdigest(),
            'changed_paths': changed}


def git_tree(sha, root=candidate.ROOT):
    require(re.fullmatch(r'[0-9a-f]{40}', sha) is not None, 'Invalid source commit SHA.')
    try:
        listing = subprocess.check_output(['git', 'ls-tree', '-rz', '--full-tree', sha], cwd=root, stderr=subprocess.DEVNULL)
        entries = []
        for record in listing.split(b'\0'):
            if not record: continue
            header, path = record.split(b'\t', 1); mode, kind, oid = header.decode().split()
            require(kind == 'blob', 'Source tree contains an unsupported submodule.')
            entries.append((path.decode(), mode, oid))
        stream = subprocess.check_output(['git', 'cat-file', '--batch'], input=''.join(oid + '\n' for _, _, oid in entries).encode(), cwd=root, stderr=subprocess.DEVNULL)
        cursor = 0; tree = {}
        for path, mode, oid in entries:
            end = stream.index(b'\n', cursor); header = stream[cursor:end].decode().split()
            require(header[:2] == [oid, 'blob'], 'Git blob content is unavailable.')
            size = int(header[2]); cursor = end + 1
            tree[path] = (mode, stream[cursor:cursor + size]); cursor += size + 1
        return tree
    except (OSError, subprocess.SubprocessError, ValueError, IndexError):
        raise candidate.CandidateError('Source history is unavailable; checkout must use fetch-depth: 0.') from None


def source_proof(sha, root=candidate.ROOT):
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    require(head == sha, 'Verifier checkout differs from the target source commit.')
    dirty = subprocess.check_output(['git', 'diff', '--name-only', 'HEAD'], cwd=root, text=True).splitlines()
    untracked = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard'], cwd=root, text=True).splitlines()
    require(all(qa_path(path) for path in dirty) and all(qa_path(path) or path in ('ui-selection.json', 'sudoku-verification.json') for path in untracked),
            'Uncommitted runtime/application files differ from the verified tree.')
    selection = Path(root) / 'ui-selection.json'
    if selection.exists():
        require(json.loads(selection.read_text()) == {'scope': 'sliding', 'source_commit': sha}, 'Actual selected-scope report differs from the target source.')
    return validate_source_trees(git_tree(BASELINE_SHA, root), git_tree(sha, root))


def summary_matches(summary, actual):
    counts = Counter(actual.values())
    expected = {'totalTestCount': len(actual), 'passedTests': counts['passed'], 'failedTests': counts['failed'], 'skippedTests': counts['skipped']}
    require(isinstance(summary, dict) and all(type(summary.get(k)) is int and summary[k] == v for k, v in expected.items()), 'Actual case log and xcresult summary disagree.')
    require(summary.get('result') == ('Failed' if counts['failed'] else 'Passed'), 'Incorrect xcresult result.')
    return dict(expected, result=summary['result'])


def validate_coverage(baseline_summary, baseline_actual, target_summary, target_actual, expected_tests, baseline_run, target_run):
    require(baseline_run == BASELINE_RUN and type(target_run) is int and target_run > 0 and target_run != baseline_run, 'Unexpected baseline or target workflow run.')
    require(len(expected_tests) == 37 and set(baseline_actual) == set(expected_tests), 'Baseline must contain all 37 actual UI cases.')
    require({name for name, status in baseline_actual.items() if status == 'failed'} == HISTORICAL_FAILURES, 'Only the two historical scroll-helper failures may be inherited.')
    for name, status in baseline_actual.items():
        expected = 'failed' if name in HISTORICAL_FAILURES else 'skipped' if name.split('/')[-1] in candidate.IPAD_TESTS else 'passed'
        require(status == expected, 'Unexpected baseline pass/skip/failure identity.')
    baseline = summary_matches(baseline_summary, baseline_actual)
    require(set(target_actual) == set(SELECTED_TESTS) and all(value == 'passed' for value in target_actual.values()), 'The exact three selected UI cases must all execute and pass.')
    target = summary_matches(target_summary, target_actual)
    coverage = {name: {'status': target_actual[name] if name in target_actual else baseline_actual[name],
                       'source_run': target_run if name in target_actual else baseline_run} for name in sorted(expected_tests)}
    statuses = {name: value['status'] for name, value in coverage.items()}
    candidate.validate_execution(statuses, expected_tests, phone=True)
    return {'baseline_summary': baseline, 'current_summary': target, 'aggregate_statuses': statuses, 'coverage': coverage}


def validate_baseline_metadata(run, jobs, repo):
    # Historical failure remains a failure. Validate identity independently;
    # never normalize it into a fictional successful full integration run.
    require(run.get('id') == BASELINE_RUN and run.get('head_sha') == BASELINE_SHA and run.get('head_branch') in TRUSTED_BRANCHES,
            'Wrong historical full-integration baseline.')
    require(run.get('status') == 'completed' and run.get('conclusion') == 'failure', 'Baseline historical run state changed.')
    candidate.validate_workflow_identity(run, 'ci', repo, BASELINE_SHA, run['head_branch'])
    entries = jobs.get('jobs', [])
    require(jobs.get('total_count') == len(entries) and {job.get('name') for job in entries} == candidate.JOBS['ci'], 'Missing baseline required jobs.')
    require(all(job.get('conclusion') == ('failure' if job['name'] == 'test' else 'success') for job in entries), 'Only baseline UI test job may have failed.')
    test = next(job for job in entries if job['name'] == 'test')
    required = {'Verify puzzles, save compatibility and generated project': 'success', 'Run Swift game and save tests': 'success',
                'Build iOS Simulator app': 'success', 'Run all iOS UI tests': 'failure'}
    steps = {step.get('name'): step for step in test.get('steps', [])}
    require(all(steps.get(name, {}).get('conclusion') == value for name, value in required.items()), 'Baseline Core/build/full-UI stages are not established.')
    require({name for name, step in steps.items() if step.get('conclusion') == 'failure'} == {'Run all iOS UI tests'}, 'Baseline had a failure outside the full UI step.')


def validate_target_metadata(run, jobs, repo, sha, current_run):
    require(run.get('id') == current_run and run.get('head_branch') in TRUSTED_BRANCHES, 'Wrong targeted CI identity or branch.')
    candidate.validate_run(run, jobs, 'ci', repo, sha, run['head_branch'], ui_step='Run selected iOS UI tests')
    test = next(job for job in jobs['jobs'] if job['name'] == 'test')
    steps = {step.get('name'): step for step in test.get('steps', [])}
    required = {'Verify puzzles, save compatibility and generated project': 'skipped', 'Run Swift game and save tests': 'skipped',
                'Build iOS Simulator app': 'skipped', 'Run all iOS UI tests': 'skipped',
                'Run selected iOS UI tests': 'success', 'Validate incremental candidate XCTest evidence': 'success'}
    require(all(steps.get(name, {}).get('conclusion') == value for name, value in required.items()), 'Target must explicitly report selected execution and baseline reuse, without a fictional current full suite.')
    require(all(step.get('conclusion') in ('success', 'skipped') for step in steps.values()), 'Targeted CI contains a failed or cancelled step.')


def load_results(repo, run_id, read=candidate.github):
    prefix = f'repos/{repo}/actions/runs/{run_id}'
    response = read(prefix + '/artifacts?per_page=100')
    require(response.get('total_count') == len(response.get('artifacts', [])), 'Incomplete raw result artifact list.')
    matches = [a for a in response.get('artifacts', []) if a.get('name') == 'test-results']
    require(len(matches) == 1 and matches[0].get('expired') is False, 'One unexpired original test-results artifact is required.')
    artifact = matches[0]
    require(type(artifact.get('id')) is int and type(artifact.get('size_in_bytes')) is int and 0 < artifact['size_in_bytes'] <= 1024**3,
            'Invalid original result artifact identity or size.')
    digest = artifact.get('digest', '')
    require(isinstance(digest, str) and re.fullmatch(r'sha256:[0-9a-f]{64}', digest) is not None, 'Original artifact has no verifiable GitHub digest.')
    cached = None
    if os.environ.get('CHAI_VERIFICATION_CACHE'):
        directory = Path(os.environ['CHAI_VERIFICATION_CACHE']).resolve(); directory.mkdir(parents=True, exist_ok=True)
        cached = directory / (str(artifact['id']) + '.zip')
        require(not cached.is_symlink(), 'Artifact cache symlinks are refused.')
    with tempfile.TemporaryFile() as archive:
        if cached and cached.is_file():
            with cached.open('rb') as stream:
                while chunk := stream.read(1024**2): archive.write(chunk)
        else:
            result = subprocess.run(['gh', 'api', '--hostname', 'github.com', '--method', 'GET',
                                     f'repos/{repo}/actions/artifacts/{artifact["id"]}/zip'], stdout=archive, stderr=subprocess.PIPE, timeout=180)
            require(result.returncode == 0, 'Original GitHub test-results download failed; no inherited coverage accepted.')
        require(archive.tell() <= 1024**3, 'Original result archive exceeds its limit.')
        archive.seek(0); actual_digest = hashlib.sha256()
        while chunk := archive.read(1024**2): actual_digest.update(chunk)
        require(actual_digest.hexdigest() == digest[7:], 'Original result ZIP differs from GitHub artifact digest.')
        if cached and not cached.exists():
            archive.seek(0)
            with cached.open('xb') as output:
                while chunk := archive.read(1024**2): output.write(chunk)
        archive.seek(0)
        return read_zip_results(archive)


def read_zip_results(archive):
    try:
        with zipfile.ZipFile(archive) as zipped:
            names = zipped.namelist()
            def member(name, limit):
                require(names.count(name) == 1 and zipped.getinfo(name).file_size <= limit, 'Missing, duplicate or oversized actual result evidence.')
                return zipped.read(name).decode('utf-8-sig')
            return json.loads(member('build/UITests-summary.json', 2 * 1024**2)), candidate.parse_test_log(member('build/UITests.log', 16 * 1024**2))
    except (OSError, ValueError, KeyError, zipfile.BadZipFile):
        raise candidate.CandidateError('Original test summary/log archive is invalid.') from None


def baseline_data(repo, read=candidate.github, results_reader=None):
    results_reader = results_reader or load_results
    prefix = f'repos/{repo}/actions/runs/{BASELINE_RUN}'
    run, jobs = read(prefix), read(prefix + '/jobs?per_page=100&filter=latest')
    validate_baseline_metadata(run, jobs, repo)
    summary, actual = results_reader(repo, BASELINE_RUN, read)
    return run, summary, actual


def build_evidence(repo, sha, current_run, target_summary, target_actual, *, read=candidate.github, root=candidate.ROOT, results_reader=None):
    run, baseline_summary, baseline_actual = baseline_data(repo, read, results_reader)
    proof = source_proof(sha, root)
    expected = candidate.expected_tests('ci', root)
    coverage = validate_coverage(baseline_summary, baseline_actual, target_summary, target_actual, expected, BASELINE_RUN, current_run)
    return {'schema': 2, 'kind': 'ci', 'verification': 'test-helper-only-incremental', 'source_commit': sha,
            'baseline_run': BASELINE_RUN, 'baseline_commit': BASELINE_SHA, 'baseline_branch': run['head_branch'],
            'current_run': current_run, 'executed_current_tests': dict(sorted(target_actual.items())),
            'baseline_executed_tests': dict(sorted(baseline_actual.items())),
            'expected_tests': expected, **proof, **coverage}


def validate_incremental_evidence(evidence, repo, sha, current_run, *, read=candidate.github, root=candidate.ROOT, results_reader=None):
    results_reader = results_reader or load_results
    require(isinstance(evidence, dict) and type(evidence.get('schema')) is int and evidence['schema'] == 2
            and evidence.get('verification') == 'test-helper-only-incremental', 'Invalid incremental evidence schema.')
    prefix = f'repos/{repo}/actions/runs/{current_run}'
    validate_target_metadata(read(prefix), read(prefix + '/jobs?per_page=100&filter=latest'), repo, sha, current_run)
    target_summary, target_actual = results_reader(repo, current_run, read)
    rebuilt = build_evidence(repo, sha, current_run, target_summary, target_actual, read=read, root=root, results_reader=results_reader)
    require(evidence == rebuilt, 'Incremental artifact is forged or differs from actual baseline/current execution and source trees.')
    return rebuilt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-run', required=True, type=int)
    parser.add_argument('--summary', required=True, type=Path)
    parser.add_argument('--log', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        require(args.baseline_run == BASELINE_RUN, 'Only the reviewed full baseline is authorized.')
        repo = os.environ.get('GITHUB_REPOSITORY', 'Kongdean2374/ChaiClassics')
        require(repo == 'Kongdean2374/ChaiClassics', 'Untrusted repository.')
        sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=candidate.ROOT, text=True).strip()
        current_run = int(os.environ['GITHUB_RUN_ID'])
        capture_run = candidate.github(f'repos/{repo}/actions/runs/{current_run}')
        require(capture_run.get('id') == current_run and capture_run.get('head_branch') in TRUSTED_BRANCHES, 'Capture workflow is not a trusted selected run.')
        candidate.validate_workflow_identity(capture_run, 'ci', repo, sha, capture_run['head_branch'])
        evidence = build_evidence(repo, sha, current_run, json.loads(args.summary.read_text()), candidate.parse_test_log(args.log.read_text()))
        args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(evidence, indent=2) + '\n')
    except (candidate.CandidateError, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print('Incremental verification failed: ' + (str(error) if isinstance(error, candidate.CandidateError) else 'Required actual summary/log/source evidence is unavailable.'), file=sys.stderr)
        return 1
    print('Verified test-helper-only incremental coverage: 3 current passes; unchanged baseline coverage retained with per-case source runs. No new full-run claim.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
