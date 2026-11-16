"""Strict allowlist for build/export/upload progress; never publish raw tool data."""
import json

PHASES = ['UPLOAD_AUTH','BUILD_CONFIG','ARCHIVE','EXPORT_IPA','UPLOAD_TRANSFER']
REASONS = {'TOOL_VERSION','EXPORT_METHOD_UNSUPPORTED','GYM_OPTIONS_REJECTED','IDENTITY_BINDING','KEY_CONFIG','APP_RECORD_MISSING','BUILD_NUMBER_CONFLICT','AUTH_REJECTED','ACCESS_REJECTED','RESOURCE_MISSING','RATE_LIMITED','APPLE_SERVER','INPUT_REJECTED','SIGNING_REJECTED','COMMAND_FAILED','ARCHIVE_CONTENT_INVALID','ARCHIVE_CERT_EXTRACT','ARCHIVE_CERT_MISMATCH','ARCHIVE_PROFILE_MISMATCH','IPA_MISSING','TRANSFER_FAILED','UNKNOWN','PROCESS_INTERRUPTED'}
HTTP_STATUSES = {400,401,403,404,409,422,429,500,501,502,503,504}
MESSAGES = {
    'UPLOAD_AUTH': 'Developer API key setup or ASC App/build lookup did not complete. Inspect the fixed reason/status; this does not automatically establish a permissions problem.',
    'BUILD_CONFIG': 'Pinned fastlane build_app parameter validation failed before archiving. No upload was attempted.',
    'ARCHIVE': 'Release archive or its exact signing-asset pairing check failed. Export/upload was not attempted.',
    'EXPORT_IPA': 'IPA export or output verification failed after archive. Upload was not attempted.',
    'UPLOAD_TRANSFER': 'IPA transfer to App Store Connect did not complete. Check the fixed reason/status and ASC before retrying; Apple may have accepted data before a connection failure.',
}

def load_release_report(path):
    try:
        with open(path,'rb') as stream: raw=stream.read(4097)
        if len(raw)>4096: return None
        report=json.loads(raw)
        if not isinstance(report,dict) or set(report)!={'schema','fastlane','completed','phase','status','reason','http_status'}: return None
        if type(report['schema']) is not int or report['schema']!=1 or report['fastlane']!='2.228.0': return None
        done=report['completed']
        if not isinstance(done,list) or done!=PHASES[:len(done)]: return None
        status=report['status']; phase=report['phase']; reason=report['reason']; http=report['http_status']
        if http is not None and (type(http) is not int or http not in HTTP_STATUSES): return None
        if status=='complete':
            if done!=PHASES or phase is not None or reason is not None or http is not None: return None
        elif status in ('running','failed'):
            if len(done)>=len(PHASES) or phase not in (None,PHASES[len(done)]): return None
            if status=='failed' and (phase is None or reason not in REASONS): return None
            if status=='running' and (reason is not None or http is not None): return None
        else: return None
        return report
    except (OSError,ValueError,TypeError,KeyError): return None

def release_complete(report):
    return report is not None and report['status']=='complete' and report['completed']==PHASES

def failure_phase(report):
    if release_complete(report): return None
    return report['phase'] or PHASES[len(report['completed'])]

def format_release_report(report):
    lines=['Release stage passed: '+phase for phase in report['completed']]
    phase=failure_phase(report)
    if phase:
        reason=report['reason'] or 'PROCESS_INTERRUPTED'
        status=str(report['http_status']) if report['http_status'] is not None else 'unknown'
        lines.append('Release failed ['+phase+']: reason='+reason+' http='+status+'. '+MESSAGES[phase])
    return lines
