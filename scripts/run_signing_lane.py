#!/usr/bin/env python3
"""Never forward raw fastlane/Git/OpenSSL output from credential-bearing jobs.
Only fixed diagnostic codes go to the public Actions log. Private log is deleted.
"""
import argparse, os, pathlib, subprocess, tempfile
from check_release_secrets import main as preflight

DIAGNOSTICS = {
    'BUNDLE_ID': 'Register the exact Bundle ID cc.chaihome.chaiclassics in the Apple Developer team first. No alternative ID is selected automatically.',
    'CERT_QUOTA': 'Apple Distribution certificate quota is exhausted. Initialization stopped without revoking certificates; review existing team signing ownership before any separate action.',
    'APPLE_ACCESS': 'Apple API key is unauthorized for Certificates, Identifiers & Profiles or this App. Check key role, issuer, validity, agreements and resource access.',
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
        return 'APPLE_ACCESS'
    return 'SIGNING_FAILED' if lane == 'initialize_signing' else 'UPLOAD_FAILED'

def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('lane', choices=['initialize_signing', 'beta', 'prepare_store'])
    args = parser.parse_args(argv)
    flags = ['--trusted-dispatch']
    if args.lane != 'prepare_store': flags += ['--signing', '--check-repo']
    if args.lane == 'initialize_signing': flags += ['--initialize']
    if preflight(flags): return 1
    root = pathlib.Path(__file__).resolve().parents[1]
    # A subprocess failure/backtrace can contain any transformed secret, not only the
    # exact string masked by GitHub. Capture EVERYTHING and print a fixed message.
    with tempfile.TemporaryFile(mode='w+b') as private_log:
        env = dict(os.environ, FASTLANE_OPT_OUT_USAGE='1', FASTLANE_SKIP_UPDATE_CHECK='1', FASTLANE_HIDE_CHANGELOG='1', CI='true')
        result = subprocess.run(['bundle', 'exec', 'fastlane', 'ios', args.lane], cwd=root, env=env,
                                stdout=private_log, stderr=subprocess.STDOUT)
        if result.returncode:
            private_log.seek(0)
            code = diagnostic(private_log.read(), args.lane)
            print('Release failed [' + code + ']: ' + DIAGNOSTICS[code])
            return result.returncode
    print('Completed: ' + args.lane + '. Credential-bearing output was not published.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
