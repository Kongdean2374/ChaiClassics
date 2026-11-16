"""Strictly decode an allowlisted IPC report; never echo arbitrary JSON fields."""
import json
RESOURCES = {'certificates', 'profiles', 'bundleIds', 'authentication'}
CATEGORIES = {
    'AUTHENTICATION': ('APPLE_401', 'Authentication rejected. Verify key/issuer pairing, key validity and runner clock; this is not a 403 role diagnosis.'),
    'FORBIDDEN': ('APPLE_403', 'Apple denied this resource. Check the selected team key role and Certificates, Identifiers & Profiles access; Admin naming alone does not prove access.'),
    'AGREEMENTS': ('APPLE_AGREEMENTS', 'Apple explicitly reports required agreements missing or expired. The Account Holder must review Developer agreements.'),
    'NOT_FOUND': ('APPLE_404', 'Endpoint/resource not found or hidden. Verify API route and account visibility; a list-endpoint 404 does not prove the app Bundle ID is missing.'),
    'RATE_LIMIT': ('APPLE_429', 'Apple rate limit. Wait before another manual read-only diagnostic; do not recreate keys or certificates.'),
    'SERVER': ('APPLE_5XX', 'Apple service error. No evidence of a role problem; do not change certificates.'),
    'INVALID_REQUEST': ('APPLE_REQUEST', 'Apple rejected request parameters or resource state. Review API compatibility; do not assume insufficient privileges.'),
    'REDIRECT': ('APPLE_REDIRECT', 'Redirect refused; credentials were not forwarded to another endpoint.'),
    'PROTOCOL': ('APPLE_PROTOCOL', 'Unexpected response format/schema. Check Apple service/API compatibility, not just key permissions.'),
    'NETWORK': ('APPLE_NETWORK', 'Network, DNS, connection or timeout failure; not proof of insufficient privileges.'),
    'TLS': ('APPLE_TLS', 'TLS verification/connection failure; not proof of insufficient privileges.'),
    'CLIENT_COMPATIBILITY': ('APPLE_CLIENT', 'Client/token interface incompatibility. Check the pinned fastlane version and adapter.'),
    'TEAM_MISMATCH': ('APPLE_TEAM', 'Certificate team differs from APPLE_TEAM_ID. Verify team selection; do not revoke certificates.'),
    'BUNDLE_ID_MISSING': ('BUNDLE_ID', 'A successful Bundle ID query found no exact cc.chaihome.chaiclassics registration. Check that team registration; no replacement ID is selected.'),
    'CERTIFICATE_DATA': ('APPLE_CERTIFICATE_DATA', 'Apple returned unusable certificate data; this is not a permission conclusion.'),
    'UNKNOWN': ('APPLE_UNKNOWN', 'Unclassified client/API failure; no permission conclusion can be made.'),
}
APPLE_CODES = {'FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED', 'PARAMETER_ERROR.INVALID', 'PARAMETER_ERROR.UNKNOWN', 'NOT_FOUND', 'NOT_AUTHORIZED', 'RATE_LIMIT_EXCEEDED'}

def load_report(path):
    try:
        with open(path, 'rb') as stream:
            raw = stream.read(8193)
        if len(raw) > 8192: return None
        report = json.loads(raw)
        if not isinstance(report, dict) or set(report) != {'schema', 'checks', 'failure'} or type(report['schema']) is not int or report['schema'] != 1: return None
        checks = report['checks']
        if not isinstance(checks, list) or len(checks) > 3: return None
        for check in checks:
            if not isinstance(check, dict) or set(check) != {'resource', 'status'}: return None
            if check['resource'] not in RESOURCES or type(check['status']) is not int or check['status'] != 200: return None
        expected = ['certificates', 'profiles', 'bundleIds']
        if [check['resource'] for check in checks] != expected[:len(checks)]: return None
        failure = report['failure']
        if failure is None and len(checks) != 3: return None
        if failure is not None:
            if not isinstance(failure, dict) or set(failure) != {'resource', 'status', 'category', 'apple_code'}: return None
            if failure['resource'] not in RESOURCES or failure['category'] not in CATEGORIES: return None
            if failure['status'] is not None and (type(failure['status']) is not int or not 100 <= failure['status'] <= 599): return None
            if failure['apple_code'] is not None and failure['apple_code'] not in APPLE_CODES: return None
        return report
    except (OSError, ValueError, TypeError, KeyError):
        return None

def format_report(report):
    lines = ['Apple read-only check: resource=' + check['resource'] + ' method=GET HTTP=200' for check in report['checks']]
    failure = report['failure']
    if failure:
        code, advice = CATEGORIES[failure['category']]
        line = f"Apple API failure [{code}]: resource={failure['resource']} method=GET HTTP={failure['status'] if failure['status'] is not None else 'unknown'} category={failure['category']}"
        if failure['apple_code']: line += ' apple_code=' + failure['apple_code']
        lines += [line, advice]
    return lines
