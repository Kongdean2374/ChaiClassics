#!/usr/bin/env python3
"""Capture unsigned XCTest evidence, then read-only verify an explicit release candidate.

This script never creates tags, dispatches workflows, accesses Apple, or uploads a build.
GitHub reads use the caller's existing gh authentication; no credential is printed.
"""
import argparse
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
IPAD_TESTS = {f'testIPad{page}Screenshot' for page in ('Home', 'Sudoku', 'Minesweeper', 'SlidingPuzzle')}
IPAD_GAME_TESTS = {
    'testTicTacToeLocalRoundRestoresWinsAndReplays',
    'testConnectFourLocalRoundRestoresWinsAndReplays',
    'testTwentyFourRestoresExactCardsCompletesAndStartsNextPuzzle',
    'testMemoryRestoresMatchesHidesUnturnedCardsCompletesAndReplays',
    'testMazeRestoresPositionResumesCompletesAndGeneratesNextMaze',
}
WORKFLOWS = {'ci': 'ci.yml', 'visual': 'visual-smoke.yml', 'ipad': 'ipad-screenshots.yml'}
JOBS = {'ci': {'test', 'codesign-extraction', 'release-tooling'}, 'visual': {'visual-smoke'}, 'ipad': {'ipad-screenshots'}}
MAX_EVIDENCE_BYTES = 2 * 1024 * 1024


class CandidateError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise CandidateError(message)


def expected_tests(kind, root=ROOT):
    sources = sorted((root / 'UITests').glob('*.swift')) if kind == 'ci' else [root / 'UITests/ChaiClassicsVisualSmokeTests.swift']
    tests = [path.stem + '/' + name for path in sources for name in re.findall(r'\bfunc\s+(test\w+)\s*\(', path.read_text())]
    require(tests and len(tests) == len(set(tests)), 'Missing or duplicate declared UI tests.')
    declared_ipad = {name.split('/')[-1] for name in tests} & IPAD_TESTS
    require(declared_ipad == IPAD_TESTS, 'All four original iPad screenshot tests must remain declared.')
    return sorted(name for name in tests if kind != 'ipad' or name.split('/')[-1] in IPAD_TESTS)


def validate_summary(summary, total, skipped):
    require(isinstance(summary, dict), 'Missing xcresult test summary.')
    fields = ('totalTestCount', 'passedTests', 'failedTests', 'skippedTests')
    require(all(type(summary.get(key)) is int for key in fields), 'Invalid xcresult count schema.')
    counts = {key: summary[key] for key in fields}
    require(summary.get('result') == 'Passed' and counts == {
        'totalTestCount': total, 'passedTests': total - skipped, 'failedTests': 0, 'skippedTests': skipped,
    }, 'xcresult must execute every declared case; only the four iPad-only skips are allowed on iPhone.')
    return dict(counts, result='Passed')


def parse_test_log(text):
    require(isinstance(text, str), 'The real XCTest output log is required.')
    pattern = re.compile(r"^\s*Test Case '-\[(?:[A-Za-z_][A-Za-z0-9_]*\.)?([A-Za-z_][A-Za-z0-9_]*) (test[A-Za-z0-9_]+)\]' (passed|skipped|failed)(?:[ .(]|$)", re.MULTILINE)
    executed = {}
    for match in pattern.finditer(text):
        name = match[1] + '/' + match[2]
        require(name not in executed, 'Duplicate XCTest completion; retries cannot replace an original result.')
        executed[name] = match[3]
    require(executed, 'No actual XCTest case completion was found in the test log.')
    return executed


def validate_execution(executed, tests, *, phone):
    require(isinstance(executed, dict) and set(executed) == set(tests), 'Actual XCTest cases differ from the complete required test set.')
    for name in tests:
        expected = 'skipped' if phone and name.split('/')[-1] in IPAD_TESTS else 'passed'
        require(executed[name] == expected, 'XCTest case failed, was unexpectedly skipped, or ran on the wrong device class: ' + name)
    return {name: executed[name] for name in sorted(tests)}


def validate_ipad(report, sha):
    require(isinstance(report, dict), 'Missing original iPad capture report.')
    require(all(report.get(key) == value for key, value in {
        'status': 'success', 'collection_status': 'complete', 'build_status': 'success',
        'test_status': 'success', 'export_status': 'success',
    }.items()) and report.get('errors') == [], 'iPad build, four tests, export and original PNG collection must all pass.')
    require(isinstance(report.get('device'), dict) and report['device'].get('source_commit') == sha, 'iPad source SHA does not match the candidate.')
    require(isinstance(report.get('test_execution'), dict) and report['test_execution'].get('status') == 'verified', 'iPad xcresult execution is unverified.')
    images = report.get('screenshots')
    require(isinstance(images, list) and len(images) == 4 and all(isinstance(image, dict) for image in images), 'Exactly four original iPad gallery captures are required.')
    hashes = [image.get('sha256', '') for image in images]
    require(all(isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) for value in hashes) and len(set(hashes)) == 4, 'Original iPad image hashes are invalid or duplicated.')
    require(all((image.get('width'), image.get('height')) in {(2064, 2752), (2048, 2732)} for image in images), 'iPad captures must retain their native portrait dimensions.')
    return report


def ipad_game_tests(root=ROOT):
    source = root / 'UITests/ChaiClassicsV020UITests.swift'
    declared = set(re.findall(r'\bfunc\s+(test\w+)\s*\(', source.read_text()))
    require(IPAD_GAME_TESTS.issubset(declared), 'All five new game journeys must remain declared.')
    return sorted('ChaiClassicsV020UITests/' + name for name in IPAD_GAME_TESTS)


def make_evidence(kind, summary, sha, *, report=None, games_summary=None, test_log=None, games_log=None,
                  executed_tests=None, executed_game_tests=None, root=ROOT):
    require(re.fullmatch(r'[0-9a-f]{40}', sha) is not None, 'A full source commit SHA is required.')
    tests = expected_tests(kind, root)
    skipped = 0 if kind == 'ipad' else 4
    result = {'schema': 1, 'kind': kind, 'source_commit': sha, 'expected_tests': tests,
              'summary': validate_summary(summary, len(tests), skipped)}
    actual = parse_test_log(test_log) if test_log is not None else executed_tests
    result['executed_tests'] = validate_execution(actual, tests, phone=kind != 'ipad')
    if kind == 'ipad':
        result['ipad_report'] = validate_ipad(report, sha)
        result['expected_game_tests'] = ipad_game_tests(root)
        result['games_summary'] = validate_summary(games_summary, 5, 0)
        actual_games = parse_test_log(games_log) if games_log is not None else executed_game_tests
        result['executed_game_tests'] = validate_execution(actual_games, result['expected_game_tests'], phone=False)
    return result


def validate_evidence(kind, evidence, sha, root=ROOT):
    require(isinstance(evidence, dict) and type(evidence.get('schema')) is int and evidence['schema'] == 1 and evidence.get('kind') == kind,
            'Missing or unsupported candidate evidence.')
    require(evidence.get('source_commit') == sha, 'Unsigned evidence source SHA differs from the candidate.')
    result = make_evidence(kind, evidence.get('summary'), sha, report=evidence.get('ipad_report'),
                           games_summary=evidence.get('games_summary'), executed_tests=evidence.get('executed_tests'),
                           executed_game_tests=evidence.get('executed_game_tests'), root=root)
    require(evidence == result, 'Unsigned evidence does not match the complete declared test suite.')
    return result


def github(path, *, binary=False):
    try:
        result = subprocess.run(['gh', 'api', '--hostname', 'github.com', '--method', 'GET', path], capture_output=True, timeout=90)
    except (OSError, subprocess.TimeoutExpired):
        raise CandidateError('GitHub read could not complete; no release was authorized.') from None
    require(result.returncode == 0, 'GitHub read failed; check Actions/Contents read access. Response details are suppressed.')
    if binary:
        require(len(result.stdout) <= MAX_EVIDENCE_BYTES, 'Candidate evidence archive exceeds its size limit.')
        return result.stdout
    require(len(result.stdout) <= MAX_EVIDENCE_BYTES, 'GitHub verification metadata exceeds its size limit.')
    try:
        return json.loads(result.stdout)
    except ValueError:
        raise CandidateError('GitHub returned invalid verification metadata.') from None


def validate_run(run, jobs, kind, repo, sha, branch='main'):
    require(isinstance(run, dict) and isinstance(run.get('repository'), dict), 'Missing workflow repository provenance.')
    require(run['repository'].get('full_name', '').lower() == repo.lower(), 'Workflow belongs to a different repository.')
    require(run.get('head_sha') == sha and run.get('head_branch') == branch, 'Candidate workflows must run on the exact requested branch and SHA.')
    require(run.get('event') == 'workflow_dispatch' and run.get('status') == 'completed' and run.get('conclusion') == 'success',
            'Candidate verification must be explicitly dispatched and fully successful.')
    require(run.get('path', '').split('@')[0] == '.github/workflows/' + WORKFLOWS[kind], 'Wrong candidate verification workflow.')
    for field in ('actor', 'triggering_actor'):
        actor = run.get(field, {})
        require(isinstance(actor, dict) and isinstance(actor.get('login'), str) and re.fullmatch(r'[A-Za-z0-9_-]+(?:\[bot\])?', actor['login']) is not None
                and type(actor.get('id')) is int and actor['id'] > 0, 'Missing valid workflow actor provenance.')
    require(isinstance(jobs, dict) and isinstance(jobs.get('jobs'), list) and jobs.get('total_count') == len(jobs['jobs']), 'Incomplete workflow job metadata.')
    entries = jobs['jobs']
    require(JOBS[kind].issubset({job.get('name') for job in entries}) and all(job.get('conclusion') == 'success' for job in entries),
            'Every required verification job must pass without a skipped or failed job.')
    if kind == 'ci':
        test = next(job for job in entries if job.get('name') == 'test')
        require(any(step.get('name') == 'Run all iOS UI tests' and step.get('conclusion') == 'success' for step in test.get('steps', [])),
                'CI did not successfully execute the full_ui test step.')


def artifact_evidence(artifacts, kind, read=github):
    expected = 'candidate-' + kind + '-evidence'
    require(isinstance(artifacts, dict) and isinstance(artifacts.get('artifacts'), list)
            and all(isinstance(entry, dict) for entry in artifacts['artifacts']), 'Invalid candidate artifact metadata.')
    matches = [entry for entry in artifacts['artifacts'] if entry.get('name') == expected]
    require(len(matches) == 1 and matches[0].get('expired') is False, 'Exactly one unexpired ' + expected + ' artifact is required.')
    item = matches[0]
    require(type(item.get('id')) is int and item['id'] > 0, 'Invalid candidate artifact identity.')
    require(type(item.get('size_in_bytes')) is int and 0 < item['size_in_bytes'] <= MAX_EVIDENCE_BYTES, 'Invalid candidate evidence artifact size.')
    archive = read('repos/' + artifacts['_repo'] + '/actions/artifacts/' + str(item['id']) + '/zip', binary=True)
    try:
        with zipfile.ZipFile(io.BytesIO(archive)) as zipped:
            require(zipped.namelist() == [expected + '.json'], 'Unexpected candidate artifact contents.')
            member = zipped.infolist()[0]
            require(member.file_size <= MAX_EVIDENCE_BYTES, 'Candidate evidence JSON exceeds its size limit.')
            return json.loads(zipped.read(member))
    except (ValueError, OSError, KeyError, zipfile.BadZipFile):
        raise CandidateError('Candidate artifact is not valid bounded JSON evidence.') from None


def verify(repo, sha, version, tag, runs, read=github, root=ROOT, branch='main'):
    require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo) is not None, 'Invalid repository name.')
    require(re.fullmatch(r'[0-9a-f]{40}', sha) is not None and re.fullmatch(r'\d+\.\d+\.\d+', version) is not None, 'Full SHA and numeric release version are required.')
    require(re.fullmatch(re.escape('v' + version) + r'-rc\.[1-9]\d*', tag) is not None, 'An explicit vVERSION-rc.N candidate tag is required.')
    require(branch in ('main', 'develop/0.2.0'), 'Only main and the isolated 0.2.0 development branch are trusted.')
    require(len(set(runs.values())) == 3 and all(type(value) is int and value > 0 for value in runs.values()), 'Three distinct positive workflow run IDs are required.')
    head = read('repos/' + repo + '/git/ref/heads/' + branch)
    require(head.get('object', {}).get('sha') == sha, 'Branch has advanced or does not match the tested candidate SHA.')
    ref = read('repos/' + repo + '/git/ref/tags/' + tag)
    require(ref.get('ref') == 'refs/tags/' + tag, 'Explicit candidate tag is missing.')
    obj = ref.get('object', {})
    for _ in range(3):
        if obj.get('type') != 'tag':
            break
        require(re.fullmatch(r'[0-9a-f]{40}', obj.get('sha', '')) is not None, 'Invalid annotated tag object.')
        obj = read('repos/' + repo + '/git/tags/' + obj['sha']).get('object', {})
    require(obj.get('type') == 'commit' and obj.get('sha') == sha, 'Candidate tag does not resolve to the tested SHA.')
    results = {}
    evidence_branch = None
    for kind in WORKFLOWS:
        prefix = 'repos/' + repo + '/actions/runs/' + str(runs[kind])
        run = read(prefix)
        require(isinstance(run, dict) and run.get('head_branch') in ('main', 'develop/0.2.0'),
                'Candidate evidence must come from a trusted main or development branch.')
        if evidence_branch is None:
            evidence_branch = run['head_branch']
        require(run['head_branch'] == evidence_branch, 'All three verification runs must use the same evidence branch.')
        require(branch == 'main' or evidence_branch == branch, 'A development proof must use that development branch.')
        # A fast-forward preserves the exact source tree and SHA. In release
        # mode the current main/tag checks above still bind all pre-merge runs
        # to that identical commit; a new merge SHA always needs fresh evidence.
        validate_run(run, read(prefix + '/jobs?per_page=100&filter=latest'), kind, repo, sha, evidence_branch)
        artifacts = read(prefix + '/artifacts?per_page=100')
        require(artifacts.get('total_count') == len(artifacts.get('artifacts', [])), 'Incomplete candidate artifact list.')
        artifacts['_repo'] = repo
        evidence = validate_evidence(kind, artifact_evidence(artifacts, kind, read), sha, root)
        results[kind] = {'run_id': runs[kind], 'run_url': f'https://github.com/{repo}/actions/runs/{runs[kind]}',
                         'actor': run['actor']['login'], 'triggering_actor': run['triggering_actor']['login'],
                         'summary': evidence['summary'], 'executed_tests': evidence['executed_tests']}
        if kind == 'ipad':
            results[kind]['device'] = evidence['ipad_report']['device']
            results[kind]['games_summary'] = evidence['games_summary']
            results[kind]['executed_game_tests'] = evidence['executed_game_tests']
    return {'schema': 1, 'status': 'verified', 'version': version, 'source_commit': sha,
            'candidate_tag': tag, 'branch': branch, 'evidence_branch': evidence_branch,
            'release_eligible': branch == 'main', 'workflows': results,
            'apple_upload': 'not_performed', 'apple_processing': 'not_checked'}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest='mode', required=True)
    capture = modes.add_parser('capture')
    capture.add_argument('--kind', choices=WORKFLOWS, required=True)
    capture.add_argument('--summary', type=Path, required=True)
    capture.add_argument('--log', type=Path, required=True)
    capture.add_argument('--ipad-report', type=Path)
    capture.add_argument('--games-summary', type=Path)
    capture.add_argument('--games-log', type=Path)
    capture.add_argument('--output', type=Path, required=True)
    gate = modes.add_parser('verify')
    gate.add_argument('--repo', default='Kongdean2374/ChaiClassics')
    gate.add_argument('--sha', required=True)
    gate.add_argument('--version', required=True)
    gate.add_argument('--tag', required=True)
    gate.add_argument('--branch', choices=('main', 'develop/0.2.0'), default='main')
    for kind in WORKFLOWS:
        gate.add_argument('--' + kind + '-run', type=int, required=True)
    gate.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.mode == 'capture':
            sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
            result = make_evidence(args.kind, json.loads(args.summary.read_text()), sha,
                                   report=json.loads(args.ipad_report.read_text()) if args.ipad_report else None,
                                   games_summary=json.loads(args.games_summary.read_text()) if args.games_summary else None,
                                   test_log=args.log.read_text(), games_log=args.games_log.read_text() if args.games_log else None)
        else:
            result = verify(args.repo, args.sha, args.version, args.tag, {kind: getattr(args, kind + '_run') for kind in WORKFLOWS}, branch=args.branch)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    except (CandidateError, OSError, ValueError, subprocess.SubprocessError) as error:
        print('Candidate verification failed: ' + (str(error) if isinstance(error, CandidateError) else 'Required evidence is unavailable or invalid.'), file=sys.stderr)
        return 1
    print('Candidate ' + args.mode + ' passed; no Apple operation or release dispatch was performed.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
