"""Strictly decode an allowlisted IPC report; never echo arbitrary JSON fields."""
import json
RESOURCES = {'apps', 'certificates', 'profiles', 'bundleIds', 'authentication'}
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

JWT_CHECKS = {'structure', 'alg', 'kid', 'iss', 'aud', 'iat', 'exp', 'signature'}
COMPARISONS = {
    'JWT_LOCAL_INVALID': 'Local JWT consistency/signature checks failed. Field values remain hidden; do not infer Apple permissions.',
    'JWT_AUTHENTICATION_REJECTED': 'Both APIs rejected the same JWT with 401. Investigate shared key/issuer validity, token lifetime and clock; a matching p8 filename alone cannot prove Apple accepts the key.',
    'CERTIFICATES_AUTHENTICATION_REJECTED': 'Apps accepted the same JWT, but certificates returned 401. This is not a global rejection of this JWT; investigate the certificates endpoint/account policy separately. A 401 is not proof of a 403 role denial.',
    'CERTIFICATES_ACCESS_DENIED': 'Apps accepted the same JWT; certificates returned 403. Check certificate-specific team/access policy and any allowlisted agreement error.',
    'CERTIFICATES_API_FAILED': 'Apps accepted the same JWT; the certificates probe failed for another reason. Use its HTTP/category; do not assume a role problem.',
    'APPS_AUTHENTICATION_REJECTED': 'Certificates accepted the same JWT, but apps returned 401. This is an apps-specific failure, not a global JWT rejection.',
    'APPS_ACCESS_DENIED': 'Certificates accepted the same JWT; apps returned 403. Check apps-specific access.',
    'APPS_API_FAILED': 'Certificates accepted the same JWT; the apps probe failed for another reason.',
    'AUTHENTICATED_BOTH': 'Both APIs accepted the same JWT. This proves read authentication only, not permission to create certificates/profiles.',
    'INCONCLUSIVE': 'The pair does not isolate a shared JWT rejection versus one resource. Use the separate HTTP results; network, rate-limit and service failures are not permission evidence.',
}

def comparison_conclusion(jwt, results):
    if not all(jwt.values()): return 'JWT_LOCAL_INVALID'
    apps, certs = results
    if apps['status'] == 401 and certs['status'] == 401: return 'JWT_AUTHENTICATION_REJECTED'
    apps_ok = apps['status'] == 200 and apps['category'] == 'OK'
    certs_ok = certs['status'] == 200 and certs['category'] == 'OK'
    if apps_ok and certs_ok: return 'AUTHENTICATED_BOTH'
    if apps_ok:
        if certs['status'] == 401: return 'CERTIFICATES_AUTHENTICATION_REJECTED'
        if certs['status'] == 403: return 'CERTIFICATES_ACCESS_DENIED'
        return 'CERTIFICATES_API_FAILED'
    if certs_ok:
        if apps['status'] == 401: return 'APPS_AUTHENTICATION_REJECTED'
        if apps['status'] == 403: return 'APPS_ACCESS_DENIED'
        return 'APPS_API_FAILED'
    return 'INCONCLUSIVE'

def valid_result(result, resource):
    if not isinstance(result, dict) or set(result) != {'resource', 'status', 'category', 'apple_code'}: return False
    if result['resource'] != resource or result['category'] not in {*CATEGORIES, 'OK'}: return False
    if result['status'] is not None and (type(result['status']) is not int or not 100 <= result['status'] <= 599): return False
    if result['apple_code'] is not None and result['apple_code'] not in APPLE_CODES: return False
    if result['category'] == 'OK' and (result['status'] != 200 or result['apple_code'] is not None): return False
    return True

def validate_comparison(report):
    if set(report) != {'schema', 'jwt', 'results', 'conclusion'}: return None
    jwt = report['jwt']; results = report['results']
    if not isinstance(jwt, dict) or set(jwt) != JWT_CHECKS or any(type(value) is not bool for value in jwt.values()): return None
    if not isinstance(results, list) or len(results) != 2: return None
    if not all(valid_result(result, resource) for result,resource in zip(results, ['apps','certificates'])): return None
    if report['conclusion'] not in COMPARISONS or report['conclusion'] != comparison_conclusion(jwt, results): return None
    return report


def load_report(path):
    try:
        with open(path, 'rb') as stream:
            raw = stream.read(8193)
        if len(raw) > 8192: return None
        report = json.loads(raw)
        if not isinstance(report, dict) or type(report.get('schema')) is not int: return None
        if report['schema'] == 2: return validate_comparison(report)
        if set(report) != {'schema', 'checks', 'failure'} or report['schema'] != 1: return None
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

def report_failed(report):
    return report['conclusion'] != 'AUTHENTICATED_BOTH' if report['schema'] == 2 else report['failure'] is not None

def format_report(report):
    if report['schema'] == 2:
        checks = ' '.join(name + '=' + ('PASS' if report['jwt'][name] else 'FAIL') for name in ['structure','alg','kid','iss','aud','iat','exp','signature'])
        lines = ['JWT local checks (values withheld): ' + checks]
        for result in report['results']:
            status = str(result['status']) if result['status'] is not None else 'unknown'
            code = result['apple_code'] or 'FILTERED_OR_ABSENT'
            lines.append(f"Apple same-JWT probe: resource={result['resource']} method=GET HTTP={status} category={result['category']} apple_code={code}")
        conclusion = report['conclusion']
        lines.append('JWT/API comparison [' + conclusion + ']: ' + COMPARISONS[conclusion])
        return lines
    lines = ['Apple read-only check: resource=' + check['resource'] + ' method=GET HTTP=200' for check in report['checks']]
    failure = report['failure']
    if failure:
        code, advice = CATEGORIES[failure['category']]
        line = f"Apple API failure [{code}]: resource={failure['resource']} method=GET HTTP={failure['status'] if failure['status'] is not None else 'unknown'} category={failure['category']}"
        if failure['apple_code']: line += ' apple_code=' + failure['apple_code']
        lines += [line, advice]
    return lines
