#!/usr/bin/env python3
"""Accumulate real per-case UI evidence only while its strict source fingerprint matches.

Partial coverage is a diagnostic success, never release authorization. All GitHub operations
are reads; full Core/build checks and final exact-SHA visual/iPad evidence remain required.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

import ui_test_scope as scopes
import verify_candidate as candidate
import verify_incremental_ci as historical

require = candidate.require
BRANCHES = ('main', 'develop/0.2.0', 'develop/0.2.1')
MAX_RUNS = 20
GAME_FILES = {
    'sudoku': {'Core/Sudoku.swift', 'App/SudokuView.swift'},
    'mines': {'Core/Minesweeper.swift', 'App/MinesView.swift'},
    'sliding': {'Core/SlidingPuzzle.swift', 'Core/SlidingInput.swift', 'App/SlidingView.swift'},
    'tictactoe': {'Core/TicTacToe.swift', 'App/TicTacToeView.swift'},
    'connectfour': {'Core/ConnectFour.swift', 'Core/ConnectFourPresentation.swift', 'App/ConnectFourView.swift'},
    'twentyfour': {'Core/TwentyFour.swift', 'Core/TwentyFourInput.swift', 'Core/Rational.swift', 'App/TwentyFourView.swift'},
    'memory': {'Core/MemoryMatch.swift', 'App/MemoryView.swift'},
    'maze': {'Core/Maze.swift', 'Core/MazeMotion.swift', 'App/MazeView.swift'},
}
ALL_GAME_FILES = set().union(*GAME_FILES.values())


def dependencies(test):
    method = test.split('/')[-1].lower()
    if method.startswith('testboardgamethinking'):
        return GAME_FILES['tictactoe'] | GAME_FILES['connectfour']
    for game in GAME_FILES:
        if method.startswith('test' + game):
            return GAME_FILES[game]
    # Unknown/mixed journeys, catalog, settings, legal and visual checks depend on all games.
    return ALL_GAME_FILES


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def fingerprints(tree):
    """Include literal assertions, shared helpers/resources/prefs/clocks and project/runtime tooling.

    Only known game-local files may be omitted for an unrelated journey. Unknown source
    files are shared by default. Other test bodies are masked; all signatures/setup/helper
    bytes remain shared, so editing C's test body alone does not invalidate unchanged A/B.
    """
    methods, scaffolds, shared = {}, [], []
    for path, (mode, data) in sorted(tree.items()):
        require(mode in ('100644', '100755'), 'Source symlinks/submodules cannot establish scoped evidence.')
        if path.startswith('UITests/') and path.endswith('.swift'):
            source = data.decode('utf-8')
            bodies = historical.functions(source)
            scaffold = source
            for name, (start, end) in sorted(bodies.items(), key=lambda item: item[1][0], reverse=True):
                if name.startswith('test'):
                    identity = Path(path).stem + '/' + name
                    require(identity not in methods, 'Duplicate UI test identity.')
                    methods[identity] = source[start:end]
                    scaffold = scaffold[:start] + '{TEST_BODY}' + scaffold[end:]
            scaffolds.append((path, mode, hashlib.sha256(scaffold.encode()).hexdigest()))
        elif path not in ALL_GAME_FILES and not path.startswith(('docs/', 'tests/')) and path != 'README.md':
            shared.append((path, mode, hashlib.sha256(data).hexdigest()))
    require(methods, 'No declared UI tests available for fingerprints.')
    result = {}
    for test, body in sorted(methods.items()):
        local = [(path, tree[path][0], hashlib.sha256(tree[path][1]).hexdigest())
                 for path in sorted(dependencies(test)) if path in tree]
        result[test] = digest({'version': 1, 'shared': shared, 'helpers': scaffolds, 'local': local, 'test_body': body})
    return result


def parse_runs(value):
    if not value.strip():
        return []
    require(re.fullmatch(r'[0-9]+(?:\s*,\s*[0-9]+)*', value.strip()) is not None, 'Source runs must be positive comma-separated workflow IDs.')
    runs = [int(item) for item in value.split(',')]
    require(len(runs) <= MAX_RUNS and len(set(runs)) == len(runs) and all(run > 0 for run in runs), 'Invalid, duplicate or excessive source runs.')
    return runs


def validate_source_metadata(run, jobs, repo, run_id):
    require(run.get('id') == run_id and run.get('head_branch') in BRANCHES, 'Wrong scoped source run or branch.')
    candidate.validate_workflow_identity(run, 'ci', repo, run.get('head_sha', ''), run['head_branch'])
    require(run.get('status') == 'completed' and run.get('conclusion') in ('success', 'failure'), 'Source run has not completed.')
    entries = jobs.get('jobs', [])
    require(jobs.get('total_count') == len(entries) and {job.get('name') for job in entries} == candidate.JOBS['ci'], 'Incomplete scoped source jobs.')
    require(all(job.get('conclusion') == 'success' for job in entries if job['name'] != 'test'), 'Source tooling/codesign jobs did not pass.')
    test = next(job for job in entries if job['name'] == 'test')
    require(test.get('conclusion') in ('success', 'failure'), 'Source UI job was skipped/cancelled.')
    steps = {step.get('name'): step for step in test.get('steps', [])}
    for name in ('Verify puzzles, save compatibility and generated project', 'Run Swift game and save tests', 'Build iOS Simulator app'):
        require(steps.get(name, {}).get('conclusion') == 'success', 'Every scoped source must actually pass current verification, Core tests and build.')
    ui_steps = {'Run all iOS UI tests', 'Run selected iOS UI tests'}
    require(any(steps.get(name, {}).get('conclusion') in ('success', 'failure') for name in ui_steps), 'Source did not execute a UI step.')
    require(all(step.get('conclusion') in ('success', 'skipped') or
                (name in ui_steps and step.get('conclusion') == 'failure') for name, step in steps.items()), 'Source failed outside UI execution.')


def gather_sources(repo, ids, sha, current_run, *, read=candidate.github, results_reader=None,
                   root=candidate.ROOT, tree_reader=None, ancestor=None):
    results_reader = results_reader or historical.load_results
    tree_reader = tree_reader or (lambda commit: historical.git_tree(commit, root))
    ancestor = ancestor or (lambda commit: subprocess.run(['git', 'merge-base', '--is-ancestor', commit, sha], cwd=root,
                                                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0)
    pending, records = list(ids), {}
    while pending:
        run_id = pending.pop(0)
        require(type(run_id) is int and 0 < run_id < current_run, 'Only earlier workflow run IDs may supply coverage.')
        if run_id in records:
            continue
        require(len(records) < MAX_RUNS - 1, 'Scoped source chain exceeds its bounded run limit.')
        prefix = f'repos/{repo}/actions/runs/{run_id}'
        run = read(prefix)
        validate_source_metadata(run, read(prefix + '/jobs?per_page=100&filter=latest'), repo, run_id)
        commit = run.get('head_sha', '')
        require(re.fullmatch(r'[0-9a-f]{40}', commit) is not None and ancestor(commit), 'Source commit is not an ancestor of the target.')
        summary, actual = results_reader(repo, run_id, read)
        historical.summary_matches(summary, actual)
        source_fingerprints = fingerprints(tree_reader(commit))
        require(set(actual).issubset(source_fingerprints), 'Source log contains an undeclared case.')
        require(all(status in ('passed', 'failed', 'skipped') for status in actual.values()), 'Invalid actual source status.')
        records[run_id] = {'run_id': run_id, 'sha': commit, 'summary': summary, 'actual': actual, 'fingerprints': source_fingerprints}
        # A prior partial ledger is an index only. Every referenced run is independently
        # reloaded from GitHub raw results and source trees; its claimed pass is never trusted.
        artifacts = read(prefix + '/artifacts?per_page=100')
        require(artifacts.get('total_count') == len(artifacts.get('artifacts', [])), 'Incomplete source artifact list.')
        if any(item.get('name') == 'candidate-ci-evidence' for item in artifacts.get('artifacts', [])):
            artifacts['_repo'] = repo
            ledger = candidate.artifact_evidence(artifacts, 'ci', read)
            if ledger.get('schema') == 3:
                inherited = ledger.get('source_runs')
                require(isinstance(inherited, list) and len(inherited) <= MAX_RUNS and
                        all(type(value) is int and 0 < value <= run_id for value in inherited), 'Invalid source ledger index.')
                pending.extend(value for value in inherited if value != run_id and value not in records)
    return [records[key] for key in sorted(records)]


def inherited_coverage(target_fingerprints, records):
    coverage = {}
    for record in sorted(records, key=lambda item: item['run_id']):
        require(set(record['fingerprints']).issubset(target_fingerprints), 'Previously required UI cases were removed; scoped coverage cannot shrink the suite.')
        for test, status in record['actual'].items():
            if record['fingerprints'].get(test) == target_fingerprints.get(test) and test in target_fingerprints:
                # Later failures override earlier passes. A flaky or failed case must rerun.
                coverage[test] = {'status': status, 'source_run': record['run_id'], 'source_commit': record['sha'],
                                  'fingerprint': target_fingerprints[test]}
    return coverage


def covered(test, item):
    expected = 'skipped' if test.split('/')[-1] in candidate.IPAD_TESTS else 'passed'
    return item is not None and item.get('status') == expected


def planned_tests(target_fingerprints, records):
    coverage = inherited_coverage(target_fingerprints, records)
    missing = sorted(test for test in target_fingerprints if not covered(test, coverage.get(test)))
    # Never turn an empty selector into an accidentally unfiltered or fictional green run.
    return missing or [next(test for test in sorted(target_fingerprints) if test.split('/')[-1] not in candidate.IPAD_TESTS)]


def make_evidence(sha, current_run, scope, summary, actual, tree, records):
    target = fingerprints(tree)
    selected = planned_tests(target, records) if scope == 'affected' else scopes.resolve(scope, sorted(target))
    require(set(actual) == set(selected), 'Actual cases differ from the requested scoped selection.')
    normalized = historical.summary_matches(summary, actual)
    require(all(covered(test, {'status': status}) for test, status in actual.items()), 'Current scoped execution failed or unexpectedly skipped.')
    coverage = inherited_coverage(target, records)
    for test, status in actual.items():
        coverage[test] = {'status': status, 'source_run': current_run, 'source_commit': sha, 'fingerprint': target[test]}
    uncovered = sorted(test for test in target if not covered(test, coverage.get(test)))
    return {'schema': 3, 'kind': 'ci', 'verification': 'dependency-scoped', 'source_commit': sha, 'current_run': current_run,
            'scope': scope, 'source_runs': sorted({current_run} | {record['run_id'] for record in records}),
            'expected_tests': sorted(target), 'current_summary': normalized, 'executed_current_tests': dict(sorted(actual.items())),
            'fingerprints': target, 'coverage': dict(sorted(coverage.items())), 'uncovered_tests': uncovered, 'complete': not uncovered}


def validate_evidence(evidence, repo, sha, current_run, *, read=candidate.github, root=candidate.ROOT,
                      results_reader=None, tree_reader=None, ancestor=None):
    results_reader = results_reader or historical.load_results
    require(isinstance(evidence, dict) and evidence.get('schema') == 3 and evidence.get('verification') == 'dependency-scoped', 'Unsupported scoped evidence.')
    prefix = f'repos/{repo}/actions/runs/{current_run}'
    run, jobs = read(prefix), read(prefix + '/jobs?per_page=100&filter=latest')
    validate_source_metadata(run, jobs, repo, current_run)
    candidate.validate_run(run, jobs, 'ci', repo, sha, run['head_branch'], ui_step='Run selected iOS UI tests')
    require(any(step.get('name') == 'Validate incremental candidate XCTest evidence' and step.get('conclusion') == 'success'
                for job in jobs['jobs'] if job['name'] == 'test' for step in job.get('steps', [])), 'Current scoped evidence was not captured successfully.')
    ids = evidence.get('source_runs')
    require(isinstance(ids, list) and current_run in ids and len(ids) <= MAX_RUNS, 'Missing current run or excessive source ledger.')
    records = gather_sources(repo, [value for value in ids if value != current_run], sha, current_run, read=read,
                             root=root, results_reader=results_reader, tree_reader=tree_reader, ancestor=ancestor)
    summary, actual = results_reader(repo, current_run, read)
    tree = (tree_reader or (lambda commit: historical.git_tree(commit, root)))(sha)
    rebuilt = make_evidence(sha, current_run, evidence.get('scope'), summary, actual, tree, records)
    require(evidence == rebuilt, 'Scoped ledger differs from actual raw execution, dependencies or source provenance.')
    require(rebuilt['complete'], 'Scoped coverage is partial; changed, failed or missing cases still require execution.')
    return rebuilt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('plan', 'capture'))
    parser.add_argument('--source-runs', default='')
    parser.add_argument('--scope', choices=tuple(scopes.SCOPES) + ('affected',))
    parser.add_argument('--summary', type=Path)
    parser.add_argument('--log', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        repo = os.environ.get('GITHUB_REPOSITORY', 'Kongdean2374/ChaiClassics')
        require(repo == 'Kongdean2374/ChaiClassics', 'Untrusted scoped repository.')
        sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=candidate.ROOT, text=True).strip()
        require(not subprocess.check_output(['git', 'diff', '--name-only', 'HEAD'], cwd=candidate.ROOT, text=True).strip(), 'Uncommitted tracked source cannot establish evidence.')
        current_run = int(os.environ['GITHUB_RUN_ID'])
        run = candidate.github(f'repos/{repo}/actions/runs/{current_run}')
        require(run.get('id') == current_run and run.get('head_branch') in BRANCHES, 'Untrusted current scope run.')
        candidate.validate_workflow_identity(run, 'ci', repo, sha, run['head_branch'])
        records = gather_sources(repo, parse_runs(args.source_runs), sha, current_run)
        tree = historical.git_tree(sha)
        if args.mode == 'plan':
            result = {'source_commit': sha, 'tests': planned_tests(fingerprints(tree), records)}
        else:
            require(args.scope is not None and args.summary is not None and args.log is not None, 'Capture requires scope and actual summary/log.')
            result = make_evidence(sha, current_run, args.scope, json.loads(args.summary.read_text()), candidate.parse_test_log(args.log.read_text()), tree, records)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    except (candidate.CandidateError, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print('Scoped evidence failed: ' + (str(error) if isinstance(error, candidate.CandidateError) else 'Required source/execution evidence is unavailable.'), file=sys.stderr)
        return 1
    if args.mode == 'capture':
        print(f"Actual current cases: {len(result['executed_current_tests'])}; complete coverage: {result['complete']}; uncovered: {len(result['uncovered_tests'])}. No full-current-run or release claim.")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
