#!/usr/bin/env python3
"""Never forward raw fastlane/Git/OpenSSL output from credential-bearing jobs.
Only fixed diagnostic codes go to the public Actions log. Private log is deleted.
"""
import argparse, os, pathlib, subprocess, tempfile
from check_release_secrets import main as preflight
from apple_api_report import load_report, format_report

DIAGNOSTICS = {
    'BUNDLE_ID': 'Register the exact Bundle ID cc.chaihome.chaiclassics in the Apple Developer team first. No alternative ID is selected automatically.',
    'CERT_QUOTA': 'Apple Distribution certificate quota is exhausted. Initialization stopped without revoking certificates; review existing team signing ownership before any separate action.',
    'APPLE_ACCESS': 'Legacy generic Apple error with no preserved HTTP status. It does not establish a 403 or insufficient privileges; use the read-only diagnostic.',
    'APPLE_DIAGNOSTIC': 'Apple read-only diagnostic failed, but no valid structured report was available. No permission conclusion can be made.',
    'APPLE_UNCLASSIFIED': 'Unclassified Apple/SDK error without preserved HTTP/resource evidence. Check a manual read-only diagnostic; do not assume a role problem.',
    'APPLE_TEAM': 'Apple Developer Team ID does not match the selected API key/profile/certificate team. No certificates were revoked.',
    'APPLE_KEY': 'ASC_API_KEY_P8 is not a valid App Store Connect EC P-256 private key.',
    'MATCH_ASSETS': 'Readonly signing assets are missing, expired or unusable. Run the separate manual Initialize Signing workflow; readonly never creates or replaces them.',
    'MATCH_DECRYPT': 'MATCH_PASSWORD cannot decrypt the private match repository. Keep the original encryption password; do not reset or run destructive operations.',
    'MATCH_GIT': 'match could not clone/push the private signing repository. Check SIGNING_REPO_PAT Contents read/write, repository selection, SSO and branch rules.',
    'SIGNING_FAILED': 'match/signing failed. Possible certificate quota, profile permissions, expired assets or Apple service error. Raw output was suppressed to protect keys; do not revoke unrelated certificates.',
    'UPLOAD_FAILED': 'Signed build/upload did not complete. Check App Record, version/build number, Apple API role and Apple service status. Raw output suppressed.',
}

def diagnostic(raw, lane):
    text = raw.decode('utf-8', errors='replace')
    for code in DIAGNOSTICS:
        if '[CHAI_SIGNING:' + code + ']' in text:
            return code
    low = text.lower()
    if any(s in low for s in ('maximum number of certificates', 'certificate quota', 'maximum number of distribution')):
        return 'CERT_QUOTA'
    if any(s in low for s in ('no code signing identity found', 'no matching provisioning profiles', 'not found in the repository', 'your certificate') ) and ('readonly' in low or 'not valid' in low):
        return 'MATCH_ASSETS'
    if any(s in low for s in ('invalid password', 'bad decrypt', 'could not decrypt')):
        return 'MATCH_DECRYPT'
    if any(s in low for s in ('authentication failed', 'repository not found', 'could not read from remote', 'unable to access', 'permission to ', 'failed to push', '403 from github')):
        return 'MATCH_GIT'
    if any(s in low for s in ('access forbidden', 'not authorized', 'not authorised', 'unauthorized', 'forbidden', 'invalid token', 'authentication credentials are missing')):
        return 'APPLE_UNCLASSIFIED'
    if 'spaceship::unexpectedresponse' in low:
        return 'APPLE_UNCLASSIFIED'
    return 'SIGNING_FAILED' if lane == 'initialize_signing' else 'UPLOAD_FAILED'

def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('lane', choices=['initialize_signing', 'beta', 'prepare_store', 'diagnose_signing'])
    args = parser.parse_args(argv)
    flags = ['--trusted-dispatch']
    if args.lane in ('initialize_signing', 'beta'): flags += ['--signing', '--check-repo']
    if args.lane == 'diagnose_signing': flags += ['--team']
    if args.lane == 'initialize_signing': flags += ['--initialize']
    if preflight(flags): return 1
    root = pathlib.Path(__file__).resolve().parents[1]
    # A subprocess failure/backtrace can contain any transformed secret, not only the
    # exact string masked by GitHub. Capture EVERYTHING and print a fixed message.
    with tempfile.TemporaryDirectory(prefix='chai-apple-diagnostic-') as private_dir, tempfile.TemporaryFile(mode='w+b') as private_log:
        report_path = pathlib.Path(private_dir) / 'report.json'
        report_path.touch(mode=0o600)
        env = dict(os.environ, FASTLANE_OPT_OUT_USAGE='1', FASTLANE_SKIP_UPDATE_CHECK='1', FASTLANE_HIDE_CHANGELOG='1', CI='true',
                   CHAI_APPLE_DIAGNOSTIC_PATH=str(report_path))
        result = subprocess.run(['bundle', 'exec', 'fastlane', 'ios', args.lane], cwd=root, env=env,
                                stdout=private_log, stderr=subprocess.STDOUT)
        report = load_report(report_path)
        if report:
            for line in format_report(report): print(line)
        if result.returncode == 0 and args.lane in ('initialize_signing', 'diagnose_signing') and not report:
            print('Release failed [APPLE_DIAGNOSTIC]: Missing or invalid safe report; no permission conclusion can be made.')
            return 1
        if result.returncode or (report and report['failure']):
            if not report or not report['failure']:
                private_log.seek(0)
                code = diagnostic(private_log.read(), args.lane)
                print('Release failed [' + code + ']: ' + DIAGNOSTICS[code])
            return result.returncode or 1
    print('Completed: ' + args.lane + '. Credential-bearing output was not published.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
