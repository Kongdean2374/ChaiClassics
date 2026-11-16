"""Only fixed codes/stage names may leave the credential-bearing subprocess."""
import json
STAGES = ['MATCH_READONLY','PROFILE_LOCATED','PROFILE_DECODED','BUNDLE_ID_VALID','TEAM_ID_VALID','PROFILE_DATES_VALID','APPSTORE_PROFILE_VALID','CERTIFICATE_VALID','KEYCHAIN_CERTIFICATE_MATCH','DISTRIBUTION_IDENTITY_MATCH','PRIVATE_KEY_SIGNED','SIGNATURE_VERIFIED','SIGNED_CERTIFICATE_MATCH','XCODE_PROFILE_READY']
MESSAGES = {
 'ASSET_READONLY_REQUIRED': 'Only readonly reuse is permitted. No certificates will be created or replaced.',
 'ASSET_KEYCHAIN_SETUP': 'Temporary keychain setup failed. No existing keychain assets were replaced.',
 'ASSET_MATCH_READ': 'Readonly match download/decryption/import did not complete. Check repository access, MATCH_PASSWORD and existing assets; do not rerun initialization.',
 'ASSET_PROFILE_PATH': 'No installed profile for this app could be located in match hints or modern/legacy directories.',
 'ASSET_PROFILE_READ': 'The selected profile file could not be read; path suppressed.',
 'ASSET_PROFILE_DECODE': 'The selected CMS profile could not be decoded; contents and path suppressed.',
 'ASSET_PROFILE_CONTENT': 'Profile structure/required metadata is invalid.',
 'ASSET_PROFILE_AMBIGUOUS': 'Multiple conflicting installed profiles match this app; refusing to choose arbitrarily.',
 'ASSET_PROFILE_METADATA': 'Installed profiles do not match the UUID metadata returned by match.',
 'ASSET_BUNDLE_ID': 'The selected profile does not contain the exact ChaiClassics Bundle ID; other apps are not selected.',
 'ASSET_TEAM_ID': 'Profile TeamIdentifier/entitlement does not match APPLE_TEAM_ID; values suppressed.',
 'ASSET_PROFILE_EXPIRED': 'The installed profile has expired. Verification stopped without replacing it.',
 'ASSET_PROFILE_TYPE': 'The installed profile is not an iOS App Store distribution profile.',
 'ASSET_CERT_CONTENT': 'Profile DeveloperCertificates data is missing or invalid.',
 'ASSET_CERT_EXPIRED': 'No non-expired certificate is available in the profile. No certificate was renewed.',
 'ASSET_CERT_NOT_YET_VALID': 'The profile certificate is not yet valid. Check validity/clock without recreating assets.',
 'ASSET_CERT_TEAM': 'The profile certificate belongs to another team; values suppressed.',
 'ASSET_CERT_TYPE': 'The profile certificate is not an Apple/iPhone Distribution identity.',
 'ASSET_KEYCHAIN_CERT': 'Temporary keychain certificate enumeration failed; output suppressed.',
 'ASSET_CERT_PROFILE_PAIR': 'The temporary keychain has no certificate whose DER matches the profile DeveloperCertificates.',
 'ASSET_DISTRIBUTION_IDENTITY': 'The profile certificate has no valid codesigning identity/private-key pair in the temporary keychain. Check import, trust and key availability.',
 'ASSET_IDENTITY_AMBIGUOUS': 'More than one matching distribution identity is present; refusing arbitrary selection.',
 'ASSET_PROBE_BUILD': 'The local temporary Mach-O signing probe could not be compiled.',
 'ASSET_PRIVATE_KEY_SIGN': 'Real codesign using the selected identity failed. Check private-key access/ACL, keychain unlock and certificate trust chain; output suppressed.',
 'ASSET_SIGNATURE_VERIFY': 'The temporary Mach-O signature failed strict verification.',
 'ASSET_SIGNED_CERT_PAIR': 'The actual embedded signing certificate does not match the validated profile certificate, or extraction failed.',
 'ASSET_PROFILE_INSTALL': 'Validated profile could not be prepared in Xcode directories, or an occupied filename differs. No existing file was overwritten.',
 'ASSET_INTERNAL': 'Unclassified local verification error. Raw exception/path/certificate data was suppressed.',
}
SOURCES={'match_env','match_metadata','installed_scan','unknown'}
HINTS={'present','stale','missing'}

def load_asset_report(path):
    try:
        with open(path,'rb') as stream: raw=stream.read(8193)
        if len(raw)>8192: return None
        report=json.loads(raw)
        if not isinstance(report,dict) or set(report)!={'schema','readonly','stages','profile_source','path_hint','failure'}: return None
        if type(report['schema']) is not int or report['schema']!=1 or report['readonly'] is not True: return None
        stages=report['stages']
        if not isinstance(stages,list) or not stages or stages!=STAGES[:len(stages)]: return None
        if report['profile_source'] not in SOURCES or report['path_hint'] not in HINTS: return None
        if report['failure'] is not None and report['failure'] not in MESSAGES: return None
        return report
    except (OSError, ValueError, TypeError, KeyError): return None

def format_asset_report(report):
    lines=['Signing asset check passed: '+stage for stage in report['stages']]
    lines.append('Profile discovery: source='+report['profile_source']+' path_hint='+report['path_hint']+' (all paths/identifiers withheld)')
    if report['failure']:
        code=report['failure']; lines.append('Signing asset failure ['+code+']: '+MESSAGES[code])
    return lines

def asset_complete(report):
    return report is not None and report['failure'] is None and report['stages']==STAGES
