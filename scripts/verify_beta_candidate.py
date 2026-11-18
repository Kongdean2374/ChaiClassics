#!/usr/bin/env python3
"""Read-only exact-SHA TestFlight Beta gate, explicitly short of full regression.

The automated mode requires three current-run UI journeys. Explicit --manual-qa
delegates Simulator/CI checks to Beta testers without claiming they passed. No
historical UI pass is inherited and this proof never authorizes App Store release.
The formal verify_candidate.py gate remains independent and unchanged.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

import ui_test_scope as scopes
import verify_candidate as candidate
import verify_incremental_ci as historical
import verify_scoped_ci as scoped


require = candidate.require
REPOSITORY = 'Kongdean2374/ChaiClassics'
BETA_TESTS = tuple(sorted('ChaiClassicsVisualSmokeTests/' + method for method in (
    'testSudokuCommonSessionLifecycleAndContinueDeletion',
    'testSlidingCommonSessionLifecycleAndContinueDeletion',
    'testPlayHistorySearchDismissesKeyboardWithoutSwallowingActions',
)))
REQUIRED_STEPS = (
    'Record actual validation scope',
    'Verify puzzles, save compatibility and generated project',
    'Run Swift game and save tests',
    'Build iOS Simulator app',
    'Run selected iOS UI tests',
    'Validate incremental candidate XCTest evidence',
    'Preserve bounded candidate CI evidence',
    'Preserve verification report and simulator results',
)
MANUAL_QA_ITEMS = (
    ('real_devices', 'Install this Beta on real supported iPhone and iPad devices.'),
    ('120hz', 'Check motion and responsiveness on a physical ProMotion display.'),
    ('haptics', 'Check haptic feedback and its per-game/global preferences on hardware.'),
    ('native_files', 'Check native Files export/import, picker cancellation and share destinations.'),
    ('ipad_accessibility', 'Check iPad layout, VoiceOver and other native accessibility interactions.'),
    ('other_game_modes', 'Exercise remaining games, difficulties, modes and long-running save recovery.'),
)
SOURCE_FILES = {
    'App/AppModel.swift', 'App/GameSessionComponents.swift', 'App/Info.plist',
    'Core/GameSessionData.swift', 'Core/SaveStore.swift', 'Package.swift',
    'ChaiClassics.xcodeproj/project.pbxproj', 'scripts/ci.sh',
    'scripts/ui_test_scope.py', '.github/workflows/ci.yml',
}


def validate_source(tree, version):
    require(isinstance(tree, dict) and SOURCE_FILES.issubset(tree), 'Beta source tree is missing runtime, project or CI provenance.')
    require(all(isinstance(item, tuple) and len(item) == 2 and item[0] in ('100644', '100755')
                and isinstance(item[1], bytes) for item in tree.values()), 'Beta source symlinks/submodules are not trusted.')
    tests = sorted(scoped.fingerprints(tree))
    sessions = scopes.required_session_tests_for_paths(tree)
    expected_tests, expected_sessions = (71, 26) if version.startswith('0.3.') else (50, 9)
    require(len(tests) == expected_tests and len(sessions) == expected_sessions and sessions.issubset(tests),
            'Beta policy preserves the version-specific complete UI and session/history inventory.')
    require(set(BETA_TESTS).issubset(tests), 'A mandatory Beta journey is no longer declared.')
    try:
        project = tree['ChaiClassics.xcodeproj/project.pbxproj'][1].decode('utf-8')
        workflow = tree['.github/workflows/ci.yml'][1].decode('utf-8')
        info = plistlib.loads(tree['App/Info.plist'][1])
    except (ValueError, UnicodeError):
        raise candidate.CandidateError('Beta source project/workflow metadata is invalid.') from None
    for key in ('MARKETING_VERSION', 'CHAI_RELEASE_VERSION'):
        values = re.findall(r'\b' + key + r'\s*=\s*"?(\d+\.\d+\.\d+)"?\s*;', project)
        require(values and set(values) == {version}, 'Candidate version differs from the exact source Xcode project.')
    require(isinstance(info, dict) and info.get('CFBundleShortVersionString') == '$(MARKETING_VERSION)',
            'App bundle version must use the verified Xcode marketing version.')
    # Match the actual, reviewed step block in the test job, not an unrelated
    # similarly named step. Its success therefore establishes full_ui=true.
    require(workflow.count('\n  test:\n') == 1 and workflow.count('\n  codesign-extraction:\n') == 1,
            'Beta source CI job structure is not recognized.')
    test_job = workflow.split('\n  test:\n', 1)[1].split('\n  codesign-extraction:\n', 1)[0]
    selected_step = ("      - name: Run selected iOS UI tests\n"
                     "        if: inputs.full_ui == true && env.CHAI_UI_SCOPE != 'full'\n"
                     "        run: bash scripts/ci.sh ui\n")
    require(test_job.count(selected_step) == 1 and workflow.count(selected_step) == 1,
            'Beta UI execution must retain the actual full_ui=true selected-step guard.')
    require("CHAI_UI_SCOPE: ${{ inputs.ui_scope || 'full' }}" in test_job,
            'Beta UI scope must come from the explicit workflow input.')
    return tests, sorted(sessions)


def validate_ci(run, jobs, repo, sha, run_id):
    require(isinstance(run, dict) and run.get('id') == run_id and run.get('head_branch') in candidate.TRUSTED_BRANCHES,
            'Beta CI source is not an exact trusted workflow run.')
    require(isinstance(run.get('head_repository'), dict)
            and run['head_repository'].get('full_name', '').lower() == repo.lower()
            and run.get('pull_requests') == [], 'Fork/PR evidence cannot authorize TestFlight Beta.')
    require(isinstance(jobs, dict) and isinstance(jobs.get('jobs'), list)
            and all(isinstance(job, dict) for job in jobs['jobs']), 'Missing Beta CI job metadata.')
    scoped.validate_source_metadata(run, jobs, repo, run_id)
    candidate.validate_run(run, jobs, 'ci', repo, sha, run['head_branch'], ui_step='Run selected iOS UI tests')
    entries = jobs['jobs']
    require(len(entries) == 3 and {job.get('name') for job in entries} == candidate.JOBS['ci'],
            'Exactly the three required CI jobs must pass.')
    for job in entries:
        require(job.get('run_id') == run_id and job.get('head_sha') == sha and job.get('status') == 'completed',
                'CI job provenance differs from the requested completed source run.')
    test = next(job for job in entries if job['name'] == 'test')
    steps = test.get('steps', [])
    require(isinstance(steps, list) and all(isinstance(step, dict) for step in steps), 'Invalid Beta CI step metadata.')
    names = [step.get('name') for step in steps]
    require(len(names) == len(set(names)), 'Duplicate CI step names cannot establish Beta execution.')
    by_name = {step['name']: step for step in steps}
    require(all(by_name.get(name, {}).get('conclusion') == 'success' for name in REQUIRED_STEPS),
            'Beta CI must actually pass verification, Core, Simulator build, selected UI and evidence preservation.')
    require(all(step.get('conclusion') in ('success', 'skipped') for step in steps),
            'Failed/cancelled steps cannot authorize a Beta.')
    for name in ('Run all iOS UI tests', 'Validate complete candidate XCTest evidence'):
        require(by_name.get(name, {}).get('conclusion') == 'skipped',
                'Beta scope must remain explicit; full-regression steps must be reported separately.')


def original_results(repo, sha, run_id, source_branch, read):
    path = f'repos/{repo}/actions/runs/{run_id}/artifacts?per_page=100'
    metadata = read(path)
    require(isinstance(metadata, dict) and isinstance(metadata.get('artifacts'), list)
            and metadata.get('total_count') == len(metadata['artifacts'])
            and all(isinstance(item, dict) for item in metadata['artifacts']), 'Incomplete Beta result artifact metadata.')
    matches = [item for item in metadata['artifacts'] if item.get('name') == 'test-results']
    require(len(matches) == 1, 'Exactly one original test-results artifact is required.')
    artifact = matches[0]
    require(type(artifact.get('id')) is int and artifact['id'] > 0 and artifact.get('expired') is False,
            'Original Beta result artifact is missing, expired or invalid.')
    origin = artifact.get('workflow_run', {})
    require(isinstance(origin, dict) and origin.get('id') == run_id and origin.get('head_sha') == sha
            and origin.get('head_branch') == source_branch, 'Original Beta artifact has different workflow/SHA provenance.')
    # The existing bounded ZIP reader verifies the original downloaded/cache ZIP
    # against GitHub's SHA-256 digest and reads raw summary/log/selection members.
    def bound_read(request, **kwargs):
        return metadata if request == path else read(request, **kwargs)
    summary, actual, selection = historical.load_results(repo, run_id, bound_read, include_selection=True)
    require(selection == {'scope': 'beta', 'source_commit': sha, 'source_runs': []},
            'Beta requires the exact pre-execution beta scope and no inherited source runs.')
    candidate.validate_execution(actual, BETA_TESTS, phone=True)
    normalized = candidate.validate_summary(summary, len(BETA_TESTS), 0)
    historical.summary_matches(summary, actual)
    return normalized, actual, {
        'artifact_id': artifact['id'], 'name': 'test-results', 'sha256': artifact['digest'][7:],
        'size_in_bytes': artifact['size_in_bytes'], 'source_commit': sha,
    }


def validate_candidate_source(repo, sha, version, tag, *, branch, read, root, tree_reader):
    require(repo == REPOSITORY and branch == 'main', 'TestFlight Beta verification only authorizes this repository main branch.')
    require(isinstance(sha, str) and re.fullmatch(r'[0-9a-f]{40}', sha) is not None
            and isinstance(version, str) and re.fullmatch(r'0\.(?:2|3)\.\d+', version) is not None,
            'A full SHA and explicit numeric 0.2.x or 0.3.x Beta version are required.')
    require(isinstance(tag, str) and re.fullmatch(re.escape('v' + version) + r'-rc\.[1-9]\d*', tag) is not None,
            'An explicit version-matched vVERSION-rc.N tag is required.')
    head = read(f'repos/{repo}/git/ref/heads/main')
    require(isinstance(head, dict) and isinstance(head.get('object'), dict) and head['object'].get('sha') == sha,
            'Main has advanced or differs from the requested Beta SHA.')
    ref = read(f'repos/{repo}/git/ref/tags/{tag}')
    require(isinstance(ref, dict) and ref.get('ref') == 'refs/tags/' + tag
            and isinstance(ref.get('object'), dict), 'Explicit Beta candidate tag is missing.')
    obj = ref.get('object', {})
    for _ in range(3):
        if obj.get('type') != 'tag': break
        require(isinstance(obj.get('sha'), str) and re.fullmatch(r'[0-9a-f]{40}', obj['sha']) is not None,
                'Invalid annotated Beta tag object.')
        annotated = read(f'repos/{repo}/git/tags/' + obj['sha'])
        require(isinstance(annotated, dict) and isinstance(annotated.get('object'), dict), 'Invalid annotated Beta tag target.')
        obj = annotated['object']
    require(obj.get('type') == 'commit' and obj.get('sha') == sha, 'Beta tag does not resolve to the exact main SHA.')
    tree = (tree_reader or (lambda commit: historical.git_tree(commit, root)))(sha)
    return validate_source(tree, version)


def verify(repo, sha, version, tag, ci_run=None, *, branch='main', manual_qa=False,
           read=candidate.github, root=candidate.ROOT, tree_reader=None):
    require(type(manual_qa) is bool, 'Manual Beta policy must be an explicit boolean.')
    if not manual_qa:
        require(type(ci_run) is int and ci_run > 0, 'A positive current Beta CI run ID is required unless --manual-qa is explicit.')
    inventory, sessions = validate_candidate_source(repo, sha, version, tag, branch=branch,
                                                    read=read, root=root, tree_reader=tree_reader)
    if manual_qa:
        return {
            'schema': 1, 'status': 'manual_beta_ready', 'verification': 'exact-sha-manual-beta',
            'version': version, 'source_commit': sha, 'candidate_tag': tag, 'branch': 'main',
            'beta_eligible': True, 'release_target': 'testflight_beta', 'release_eligible': False,
            'app_store_release_eligible': False, 'full_regression_complete': False,
            'declared_ui_tests': inventory, 'declared_ui_test_count': len(inventory),
            'required_session_journeys': sessions, 'ui_tests': 'not_required_manual_qa',
            'ci_validation': 'not_required_manual_qa', 'workflows': {}, 'executed_ui_tests': [],
            'inherited_ui_cases': [],
            'manual_qa_items': [{'area': area, 'status': 'pending', 'detail': detail} for area, detail in MANUAL_QA_ITEMS],
            'apple_build': 'pending_testflight_workflow', 'apple_archive': 'pending_testflight_workflow',
            'apple_upload': 'not_performed', 'apple_processing': 'not_checked',
        }
    prefix = f'repos/{repo}/actions/runs/{ci_run}'
    run, jobs = read(prefix), read(prefix + '/jobs?per_page=100&filter=latest')
    validate_ci(run, jobs, repo, sha, ci_run)
    summary, actual, artifact = original_results(repo, sha, ci_run, run['head_branch'], read)
    return {
        'schema': 1, 'status': 'beta_verified', 'verification': 'exact-sha-beta-smoke',
        'version': version, 'source_commit': sha, 'candidate_tag': tag, 'branch': 'main',
        'beta_eligible': True, 'release_target': 'testflight_beta', 'release_eligible': False,
        'app_store_release_eligible': False, 'full_regression_complete': False,
        'declared_ui_tests': inventory, 'declared_ui_test_count': len(inventory),
        'required_session_journeys': sessions, 'full_ui_input_verified': True,
        'workflows': {'ci': {
            'run_id': ci_run, 'run_url': f'https://github.com/{repo}/actions/runs/{ci_run}',
            'source_commit': sha, 'source_branch': run['head_branch'],
            'actor': run['actor']['login'], 'triggering_actor': run['triggering_actor']['login'],
            'scope': 'beta', 'required_jobs': sorted(candidate.JOBS['ci']), 'summary': summary,
            'executed_tests': dict(sorted(actual.items())), 'original_results': artifact,
        }},
        'inherited_ui_cases': [], 'ui_tests_not_required_for_beta': sorted(set(inventory) - set(BETA_TESTS)),
        'manual_qa_items': [{'area': area, 'status': 'pending', 'detail': detail} for area, detail in MANUAL_QA_ITEMS],
        'apple_upload': 'not_performed', 'apple_processing': 'not_checked',
    }


def validate_caller(repo, sha):
    if os.environ.get('GITHUB_ACTIONS') != 'true': return
    require(os.environ.get('GITHUB_REPOSITORY') == repo and os.environ.get('GITHUB_SHA') == sha
            and os.environ.get('GITHUB_REF') == 'refs/heads/main'
            and os.environ.get('GITHUB_EVENT_NAME') == 'workflow_dispatch', 'Beta gate caller must be an exact main manual dispatch.')
    require(os.environ.get('GITHUB_JOB') == 'preflight'
            and os.environ.get('GITHUB_WORKFLOW_REF') == f'{repo}/.github/workflows/testflight.yml@refs/heads/main',
            'Beta proof is restricted to unsigned TestFlight preflight, never an App Store or signing job.')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', default=REPOSITORY)
    parser.add_argument('--sha', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--ci-run', type=int)
    parser.add_argument('--manual-qa', action='store_true', help='Explicitly delegate CI/Simulator UI validation to Beta testers; never claims a test pass.')
    parser.add_argument('--branch', choices=('main',), default='main')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        validate_caller(args.repo, args.sha)
        proof = verify(args.repo, args.sha, args.version, args.tag, args.ci_run, branch=args.branch, manual_qa=args.manual_qa)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(proof, indent=2) + '\n')
    except (candidate.CandidateError, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        detail = str(error) if isinstance(error, candidate.CandidateError) else 'Required trusted source, CI or original Beta evidence is unavailable or invalid.'
        print('Beta verification failed: ' + detail, file=sys.stderr)
        return 1
    if args.manual_qa:
        print('Manual Beta ready: main/tag/version/source matched. CI and Simulator UI are not required by this explicit policy; testers must validate the Beta. Signed build/archive/upload remain pending.')
    else:
        print('Beta verified: three current-SHA UI journeys and CI passed. Full regression is incomplete; manual QA remains. No Apple operation performed.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
