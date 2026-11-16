#!/usr/bin/env python3
"""Never forward raw fastlane/Git/OpenSSL output from credential-bearing jobs.
Only fixed diagnostic codes go to the public Actions log. Private log is deleted.
"""
import argparse, os, pathlib, subprocess, tempfile
from check_release_secrets import main as preflight
from apple_api_report import load_report, format_report, report_failed
from signing_asset_report import load_asset_report, format_asset_report, asset_complete, MESSAGES as ASSET_MESSAGES
from release_report import load_release_report, format_release_report, release_complete, MESSAGES as RELEASE_MESSAGES
from archive_diagnostics import load_archive_report, archive_complete, diagnose, format_diagnosis

DIAGNOSTICS = {
    'BUNDLE_ID': 'Register the exact Bundle ID cc.chaihome.chaiclassics in the Apple Developer team first. No alternative ID is selected automatically.',
    'CERT_QUOTA': 'Apple Distribution certificate quota is exhausted. Initialization stopped without revoking certificates; review existing team signing ownership before any separate action.',
    'APPLE_ACCESS': 'Legacy generic Apple error with no preserved HTTP status. It does not establish a 403 or insufficient privileges; use the read-only diagnostic.',
    'APPLE_DIAGNOSTIC': 'Apple read-only diagnostic failed, but no valid structured report was available. No permission conclusion can be made.',
    'APPLE_UNCLASSIFIED': 'Unclassified Apple/SDK error without preserved HTTP/resource evidence. Check a manual read-only diagnostic; do not assume a role problem.',
    'APPLE_TEAM': 'Apple Developer Team ID does not match the selected API key/profile/certificate team. No certificates were revoked.',
    'APPLE_KEY': 'ASC_API_KEY_P8 is not a valid App Store Connect EC P-256 private key.',
    'MATCH_ASSETS': 'Legacy undifferentiated local asset failure. Use Verify Signing Assets (read only); do not rerun Initialize Signing or replace existing certificates.',
    'MATCH_DECRYPT': 'MATCH_PASSWORD cannot decrypt the private match repository. Keep the original encryption password; do not reset or run destructive operations.',
    'MATCH_GIT': 'match could not clone/push the private signing repository. Check SIGNING_REPO_PAT Contents read/write, repository selection, SSO and branch rules.',
    'SIGNING_FAILED': 'match/signing failed. Possible certificate quota, profile permissions, expired assets or Apple service error. Raw output was suppressed to protect keys; do not revoke unrelated certificates.',
    'UPLOAD_FAILED': 'Legacy undifferentiated build/upload failure without stage evidence. It does not establish that an upload or archive was attempted. Raw output suppressed.',
}

DIAGNOSTICS.update(ASSET_MESSAGES)
DIAGNOSTICS.update(RELEASE_MESSAGES)

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
    parser.add_argument('lane', choices=['initialize_signing', 'beta', 'prepare_store', 'diagnose_signing', 'verify_signing_assets', 'diagnose_signed_archive'])
    args = parser.parse_args(argv)
    flags = ['--trusted-dispatch']
    if args.lane in ('initialize_signing', 'beta'): flags += ['--signing', '--check-repo']
    if args.lane == 'diagnose_signing': flags += ['--team']
    if args.lane in ('verify_signing_assets','diagnose_signed_archive'): flags += ['--assets', '--check-repo']
    if args.lane == 'initialize_signing': flags += ['--initialize']
    if preflight(flags): return 1
    root = pathlib.Path(__file__).resolve().parents[1]
    # A subprocess failure/backtrace can contain any transformed secret, not only the
    # exact string masked by GitHub. Capture EVERYTHING and print a fixed message.
    with tempfile.TemporaryDirectory(prefix='chai-apple-diagnostic-') as private_dir, tempfile.TemporaryFile(mode='w+b') as private_log:
        report_path = pathlib.Path(private_dir) / 'report.json'
        report_path.touch(mode=0o600)
        asset_path = pathlib.Path(private_dir) / 'assets.json'
        asset_path.touch(mode=0o600)
        release_path = pathlib.Path(private_dir) / 'release.json'
        release_path.touch(mode=0o600)
        archive_path = pathlib.Path(private_dir) / 'archive.json'
        archive_path.touch(mode=0o600)
        workdir = (pathlib.Path(private_dir) / 'work').resolve()
        workdir.mkdir(mode=0o700)
        (workdir/'tmp').mkdir(mode=0o700)
        env = dict(os.environ, FASTLANE_OPT_OUT_USAGE='1', FASTLANE_SKIP_UPDATE_CHECK='1', FASTLANE_HIDE_CHANGELOG='1', CI='true',
                   CHAI_APPLE_DIAGNOSTIC_PATH=str(report_path), CHAI_SIGNING_ASSET_REPORT_PATH=str(asset_path),
                   CHAI_RELEASE_REPORT_PATH=str(release_path),CHAI_ARCHIVE_REPORT_PATH=str(archive_path),
                   CHAI_RELEASE_WORKDIR=str(workdir),TMPDIR=str(workdir/'tmp')+'/')
        result = subprocess.run(['bundle', 'exec', 'fastlane', 'ios', args.lane], cwd=root, env=env,
                                stdout=private_log, stderr=subprocess.STDOUT, umask=0o077)
        assets = load_asset_report(asset_path)
        if assets:
            for line in format_asset_report(assets): print(line)
        if assets and assets['failure']: return result.returncode or 1
        if args.lane in ('beta','diagnose_signed_archive') and not asset_complete(assets):
            # Preserve fixed pre-archive match/keychain failures even when no
            # asset report could be written. Do not mislabel these as archiving.
            private_log.seek(0)
            raw = private_log.read()
            for code in ASSET_MESSAGES:
                if ('[CHAI_SIGNING:'+code+']').encode() in raw:
                    print('Release failed ['+code+']: '+ASSET_MESSAGES[code])
                    return result.returncode or 1
        archive = load_archive_report(archive_path)
        if archive_path.stat().st_size or args.lane == 'diagnose_signed_archive':
            diagnosis=diagnose(archive,private_log,workdir)
            for line in format_diagnosis(diagnosis): print(line)
        if args.lane == 'diagnose_signed_archive':
            if not asset_complete(assets) or not archive_complete(archive) or result.returncode:
                print('Release failed [ARCHIVE]: Signed archive verification did not complete. No export or upload was attempted.')
                return result.returncode or 1
        release = load_release_report(release_path)
        if args.lane == 'beta':
            if release:
                for line in format_release_report(release): print(line)
                if not release_complete(release): return result.returncode or 1
            if result.returncode == 0 and (not release_complete(release) or not asset_complete(assets) or not archive_complete(archive)):
                print('Release failed [BUILD_CONFIG]: Missing/incomplete safe release or signing report. Success was not assumed.')
                return 1
        if args.lane == 'verify_signing_assets' and result.returncode == 0 and not asset_complete(assets):
            print('Release failed [ASSET_INTERNAL]: Missing/incomplete safe signing asset verification report.')
            return 1
        report = load_report(report_path)
        if report:
            for line in format_report(report): print(line)
        if result.returncode == 0 and args.lane in ('initialize_signing', 'diagnose_signing') and not report:
            print('Release failed [APPLE_DIAGNOSTIC]: Missing or invalid safe report; no permission conclusion can be made.')
            return 1
        if result.returncode or (report and report_failed(report)):
            if not report or not report_failed(report):
                private_log.seek(0)
                code = diagnostic(private_log.read(), args.lane)
                print('Release failed [' + code + ']: ' + DIAGNOSTICS[code])
            return result.returncode or 1
    print('Completed: ' + args.lane + '. Credential-bearing output was not published.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
