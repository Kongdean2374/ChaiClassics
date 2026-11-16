"""Parse private tool logs into fixed codes only. Never return matched text."""
import json
import pathlib
import re
import stat

STAGES = ['BUILD_SETTINGS_CHECKED','BUILD_APP_RETURNED','ARCHIVE_FORMAT_VALID','ARCHIVE_APP_VALID','ARCHIVE_SIGNATURE_VALID','ARCHIVE_CERTIFICATE_MATCH','ARCHIVE_PROFILE_MATCH','SIGNED_ARCHIVE_VERIFIED']
PHASES = {'BUILD_SETTINGS','BUILD_APP','VERIFY_ARCHIVE','COMPLETE','UNKNOWN'}
FAILURES = {'ARCHIVE_SANDBOX_INVALID','GLOBAL_SIGNING_OVERRIDE','BUILD_APP_FAILED','ARCHIVE_VALIDATION_FAILED'}
VERIFY_CODES = {'ARCHIVE_CONTENT_INVALID','ARCHIVE_APP_INVALID','SIGNING_REJECTED','ARCHIVE_CERT_EXTRACT','ARCHIVE_CERT_MISMATCH','ARCHIVE_PROFILE_MISMATCH'}
RULES = [
    ('COMPILE','SWIFT_COMPILE_ERROR',r'\.swift:\d+(?::\d+)?:\s*error:|Swift(?:Compile|EmitModule).*failed'),
    ('COMPILE','CLANG_COMPILE_ERROR',r'\.(?:m|mm|c|cpp|h):\d+(?::\d+)?:\s*(?:fatal )?error:'),
    ('COMPILE','MODULE_MISSING',r'error:\s*(?:no such module|cannot find module|module .* not found)'),
    ('COMPILE','LINKER_FAILED',r'linker command failed|ld: (?:error:|symbol\(s\) not found|framework not found|library not found)'),
    ('SIGNING','CODESIGN_FAILED',r'Command CodeSign failed|codesign.*(?:failed|errSecInternalComponent)|code object is not signed at all'),
    ('SIGNING','SIGNING_CONFLICT',r'has conflicting provisioning settings|automatically signed.*manually specified'),
    ('SIGNING','SIGNING_IDENTITY_UNAVAILABLE',r'No signing certificate|No code signing identity found'),
    ('PROFILE','PROFILE_NOT_APPLICABLE',r'does not support provisioning profiles'),
    ('PROFILE','PROFILE_NOT_FOUND',r'No profiles for|requires a provisioning profile|provisioning profile .* (?:not found|could not be found)'),
    ('PROFILE','PROFILE_CERT_MISMATCH',r'provisioning profile .* (?:does not|doesn.t) include signing certificate'),
    ('PROFILE','PROFILE_TEAM_MISMATCH',r'provisioning profile .* (?:team|app identifier).* (?:does not|doesn.t) match'),
    ('PROFILE','PROFILE_EXPIRED',r'provisioning profile .* (?:has expired|expired on)'),
    ('KEYCHAIN','KEYCHAIN_ACCESS_DENIED',r'errSecInteractionNotAllowed|User interaction is not allowed|keychain .* (?:is locked|could not be unlocked)'),
    ('KEYCHAIN','KEYCHAIN_NOT_FOUND',r'(?:specified )?keychain could not be found'),
    ('SWIFT_PACKAGE','PACKAGE_RESOLUTION_FAILED',r'Could not resolve package dependencies|failed to resolve package|package resolution failed|failed downloading.*package'),
    ('SWIFT_PACKAGE','PACKAGE_RESOURCE_ERROR',r'error:.*(?:resource .* not found|invalid resource|multiple resources named)'),
    ('SWIFT_PACKAGE','PACKAGE_PROFILE_OVERRIDE',r'does not support provisioning profiles.*(?:target [\'"]ChaiCore|project [\'"]ChaiCore)|ChaiCore.*does not support provisioning profiles'),
    ('BUILD_SETTINGS','BUILD_SETTINGS_TIMEOUT',r'xcodebuild -showBuildSettings timed out|xcodebuild.*showBuildSettings.*timed out'),
    ('BUILD_SETTINGS','SCHEME_UNAVAILABLE',r'xcodebuild: error:.*(?:does not contain a scheme|scheme .* not .*configured|scheme .*not found)'),
    ('BUILD_SETTINGS','DESTINATION_UNAVAILABLE',r'Unable to find a destination|Ineligible destinations for'),
    ('BUILD_SETTINGS','SDK_UNAVAILABLE',r'(?:SDK|sdk).* (?:cannot be located|not installed|could not be found)'),
    ('BUILD_SETTINGS','BUILD_OPTION_INVALID',r'xcodebuild: error:.*(?:invalid option|unknown build action|unrecognized option)'),
    ('BUILD_SETTINGS','SIGNING_TEAM_REQUIRED',r'Signing for .* requires a development team'),
    ('ARCHIVE_FORMAT','ARCHIVE_EMPTY',r'archive is empty|archive .* (?:does not contain|is not a valid archive)|no .*archive.*found'),
]
RULES = [(category,code,re.compile(pattern,re.I)) for category,code,pattern in RULES]
CODE_CATEGORIES = {code:category for category,code,_ in RULES}
CODE_CATEGORIES.update({
    'ARCHIVE_SANDBOX_INVALID':'BUILD_SETTINGS','GLOBAL_SIGNING_OVERRIDE':'BUILD_SETTINGS',
    'GYM_SETUP_FAILED':'BUILD_TOOL','XCODEBUILD_ARCHIVE_FAILED':'BUILD_TOOL','GYM_POST_ARCHIVE_FAILED':'BUILD_TOOL',
    'BUILD_APP_FAILED_UNCLASSIFIED':'BUILD_TOOL','ARCHIVE_VALIDATION_FAILED':'ARCHIVE_FORMAT',
    'ARCHIVE_REPORT_INVALID':'DIAGNOSTIC','ARCHIVE_INTERRUPTED':'DIAGNOSTIC','LOG_SCAN_LIMIT':'DIAGNOSTIC',
    'ARCHIVE_CONTENT_INVALID':'ARCHIVE_FORMAT','ARCHIVE_APP_INVALID':'ARCHIVE_FORMAT',
    'SIGNING_REJECTED':'SIGNING','ARCHIVE_CERT_EXTRACT':'SIGNING','ARCHIVE_CERT_MISMATCH':'SIGNING',
    'ARCHIVE_PROFILE_MISMATCH':'PROFILE',
})

def load_archive_report(path):
    try:
        with open(path,'rb') as stream: raw=stream.read(8193)
        if len(raw)>8192: return None
        value=json.loads(raw)
        if not isinstance(value,dict) or set(value)!={'schema','phase','status','completed','failure','verification_code'}: return None
        if type(value['schema']) is not int or value['schema']!=1: return None
        stages=value['completed']; phase=value['phase']; status=value['status']; failure=value['failure']; verification=value['verification_code']
        if not isinstance(stages,list) or stages!=STAGES[:len(stages)]: return None
        if phase not in PHASES-{'UNKNOWN'}: return None
        if verification is not None and verification not in VERIFY_CODES: return None
        if status=='complete':
            if phase!='COMPLETE' or stages!=STAGES or failure is not None or verification is not None: return None
        elif status in ('failed','running'):
            if phase=='COMPLETE' or len(stages)==len(STAGES): return None
            if phase=='BUILD_SETTINGS' and stages: return None
            if phase=='BUILD_APP' and stages!=STAGES[:1]: return None
            if phase=='VERIFY_ARCHIVE' and len(stages)<2: return None
            if status=='failed' and failure not in FAILURES: return None
            if status=='running' and (failure is not None or verification is not None): return None
            if failure=='ARCHIVE_VALIDATION_FAILED' and (phase!='VERIFY_ARCHIVE' or verification is None): return None
        else: return None
        return value
    except (OSError,ValueError,TypeError,KeyError): return None

def archive_complete(report):
    return report is not None and report['status']=='complete' and report['completed']==STAGES

def diagnose(report, private_log, workdir):
    codes=set(); command='not_observed'; saw_log=False
    def scan(stream):
        nonlocal command,saw_log
        budget=32*1024*1024
        while budget>0:
            raw=stream.readline(min(65536,budget))
            if not raw: break
            saw_log=True;budget-=len(raw)
            line=raw.decode('utf-8',errors='replace')
            if '** ARCHIVE SUCCEEDED **' in line: command='succeeded'
            if '** ARCHIVE FAILED **' in line: command='failed'
            for _,code,pattern in RULES:
                if pattern.search(line): codes.add(code)
        if budget<=0: codes.add('LOG_SCAN_LIMIT')
    private_log.seek(0);scan(private_log)
    root=pathlib.Path(workdir).resolve()
    paths=[root/'archive-error.log']+sorted((root/'logs').glob('**/*.log'))
    for path in paths:
        try:
            if path.is_symlink() or root not in path.resolve().parents or not stat.S_ISREG(path.stat().st_mode): continue
            with path.open('rb') as stream: scan(stream)
        except OSError: continue
    if report is None:
        codes.add('ARCHIVE_REPORT_INVALID');phase='UNKNOWN';status='failed';completed=[]
    else:
        phase=report['phase'];status=report['status'];completed=report['completed']
        failure=report['failure']
        if status=='running': codes.add('ARCHIVE_INTERRUPTED')
        if failure in ('ARCHIVE_SANDBOX_INVALID','GLOBAL_SIGNING_OVERRIDE'): codes.add(failure)
        if failure=='BUILD_APP_FAILED':
            if command=='failed': codes.add('XCODEBUILD_ARCHIVE_FAILED')
            elif command=='succeeded': codes.add('GYM_POST_ARCHIVE_FAILED')
            else: codes.add('BUILD_APP_FAILED_UNCLASSIFIED')
        if failure=='ARCHIVE_VALIDATION_FAILED':
            codes.add('ARCHIVE_VALIDATION_FAILED');codes.add(report['verification_code'])
    # Result values are selected exclusively from constants, never raw log data.
    return dict(phase=phase,status=status,completed=completed,command=command,
                codes=sorted(codes),categories=sorted({CODE_CATEGORIES[code] for code in codes}))

def format_diagnosis(diagnosis):
    lines=['Signed archive stage passed: '+stage for stage in diagnosis['completed']]
    lines.append('Signed archive phase='+diagnosis['phase']+' status='+diagnosis['status']+' command='+diagnosis['command'])
    lines.extend('Signed archive diagnostic: category='+CODE_CATEGORIES[code]+' code='+code for code in diagnosis['codes'])
    return lines
