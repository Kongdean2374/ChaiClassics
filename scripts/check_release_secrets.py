#!/usr/bin/env python3
"""Preflight emits names and fixed diagnostics only, never credentials or HTTP bodies."""
import argparse, json, os, re, subprocess, sys, urllib.error, urllib.request

REPO = 'Kongdean2374/ChaiClassics-Signing'
class ConfigurationError(Exception):
    pass

def validate_environment(env, signing=False, team=False):
    names = ['ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_API_KEY_P8']
    if signing or team:
        names += ['APPLE_TEAM_ID']
    if signing:
        names += ['SIGNING_REPO_PAT', 'MATCH_PASSWORD']
    missing = [name for name in names if not env.get(name, '').strip()]
    if missing:
        raise ConfigurationError('Missing configuration: ' + ', '.join(missing) + '. APPLE_TEAM_ID may be a workflow input, Repository Variable or Secret. See docs/RELEASING.md')
    if not re.fullmatch(r'[A-Z0-9]{10}', env['ASC_KEY_ID']):
        raise ConfigurationError('ASC_KEY_ID must be the 10-character Apple API key ID.')
    if not re.fullmatch(r'[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}', env['ASC_ISSUER_ID']):
        raise ConfigurationError('ASC_ISSUER_ID must be the issuer UUID, not the Apple Team ID.')
    pem = env['ASC_API_KEY_P8'].replace('\r\n', '\n').strip()
    if not re.fullmatch(r'-----BEGIN PRIVATE KEY-----\n[A-Za-z0-9+/=\n]+\n-----END PRIVATE KEY-----', pem):
        raise ConfigurationError('ASC_API_KEY_P8 must contain the complete ORIGINAL multiline .p8 PEM, not Base64 and not literal \\n characters.')
    # Parse via stdin; do not place the key in a command argument, file or error log.
    result = subprocess.run(['openssl', 'pkey', '-check', '-noout'], input=pem.encode(), capture_output=True)
    if result.returncode:
        raise ConfigurationError('ASC_API_KEY_P8 could not be parsed as a private key. Its contents are suppressed.')
    if (signing or team) and not re.fullmatch(r'[A-Z0-9]{10}', env['APPLE_TEAM_ID']):
        raise ConfigurationError('APPLE_TEAM_ID must be the 10-character Apple Developer Team ID, not ASC_ISSUER_ID.')

def validate_trusted_dispatch(env):
    if env.get('GITHUB_EVENT_NAME') != 'workflow_dispatch' or env.get('GITHUB_REF') != 'refs/heads/main':
        raise ConfigurationError('Signing is allowed only by manual workflow_dispatch on trusted main.')

def github_request(path, token):
    request = urllib.request.Request('https://api.github.com/' + path,
        headers={'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code in (401, 403, 404):
            raise ConfigurationError('SIGNING_REPO_PAT cannot access the private signing repository/main (HTTP ' + str(error.code) + '). Verify repository selection, Contents permission, token expiry and organization SSO approval.') from None
        raise ConfigurationError('GitHub signing repository preflight failed (HTTP ' + str(error.code) + '); response suppressed.') from None
    except (OSError, ValueError):
        raise ConfigurationError('GitHub signing repository preflight could not complete; network/response details suppressed.') from None

def validate_signing_repo(token, initialize=False, request=github_request):
    repo = request('repos/' + REPO, token)
    if repo.get('full_name', '').lower() != REPO.lower() or repo.get('private') is not True:
        raise ConfigurationError('Signing storage must be the exact PRIVATE repository ' + REPO + '; refusing public or redirected storage.')
    if repo.get('default_branch') != 'main':
        raise ConfigurationError('Signing repository default branch must be main.')
    permissions = repo.get('permissions', {})
    if not permissions.get('pull') or (initialize and not permissions.get('push')):
        raise ConfigurationError('SIGNING_REPO_PAT requires Contents read/write for initialization and Contents read for readonly TestFlight. Actual Git push is checked by match; a PAT with only metadata access is insufficient.')
    branch = request('repos/' + REPO + '/git/ref/heads/main', token)
    if branch.get('ref') != 'refs/heads/main':
        raise ConfigurationError('Private signing repository main must exist; initialize it with a README first.')

def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('--signing', action='store_true')
    parser.add_argument('--team', action='store_true')
    parser.add_argument('--initialize', action='store_true')
    parser.add_argument('--trusted-dispatch', action='store_true')
    parser.add_argument('--check-repo', action='store_true')
    args = parser.parse_args(argv)
    try:
        if args.trusted_dispatch:
            validate_trusted_dispatch(os.environ)
        validate_environment(os.environ, args.signing or args.initialize, args.team)
        if args.check_repo:
            validate_signing_repo(os.environ.get('SIGNING_REPO_PAT', ''), args.initialize)
    except ConfigurationError as error:
        print(str(error), file=sys.stderr)
        return 1
    print('Preflight passed; no credential values printed. Apple portal privileges and actual Git push are verified by match at runtime.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
