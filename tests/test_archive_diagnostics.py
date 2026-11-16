import contextlib
import io
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'scripts'))
import archive_diagnostics as reports
import signing_asset_report as assets
import run_signing_lane as runner

class ArchiveDiagnosticTests(unittest.TestCase):
    def report(self, complete=False, verify=False):
        return dict(schema=1,phase='COMPLETE' if complete else 'VERIFY_ARCHIVE' if verify else 'BUILD_APP',
                    status='complete' if complete else 'failed',completed=reports.STAGES if complete else reports.STAGES[:2 if verify else 1],
                    failure=None if complete else 'ARCHIVE_VALIDATION_FAILED' if verify else 'BUILD_APP_FAILED',
                    verification_code='ARCHIVE_PROFILE_MISMATCH' if verify else None)

    def load(self,data):
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/'report.json';path.write_text(json.dumps(data))
            return reports.load_archive_report(path)

    def test_ruby_python_report_contract_agrees(self):
        source=(pathlib.Path(__file__).resolve().parents[1]/'fastlane/lib/archive_diagnostics.rb').read_text()
        for name,expected in [('STAGES',reports.STAGES),('FAILURES',reports.FAILURES),('VERIFY_CODES',reports.VERIFY_CODES)]:
            actual=re.search(name+r' = %w\[([^]]+)\]',source)[1].split()
            self.assertEqual(actual,expected) if isinstance(expected,list) else self.assertEqual(set(actual),expected)

    def test_complete_requires_all_real_verification_stages(self):
        self.assertTrue(reports.archive_complete(self.load(self.report(True))))
        data=self.report(True);data['completed']=data['completed'][:-1]
        self.assertIsNone(self.load(data))
        self.assertFalse(reports.archive_complete(self.load(self.report(verify=True))))

    def test_untrusted_report_values_never_reach_output(self):
        for key,value in [('phase','DO_NOT_PRINT'),('failure','DO_NOT_PRINT'),('verification_code','DO_NOT_PRINT'),('secret','DO_NOT_PRINT'),('completed',['DO_NOT_PRINT'])]:
            data=self.report();data[key]=value
            self.assertIsNone(self.load(data))

    def diagnose(self,text,report=None):
        with tempfile.TemporaryDirectory() as directory:
            return reports.diagnose(report or self.report(),io.BytesIO(text.encode()),directory)

    def test_each_requested_error_family_has_fixed_codes(self):
        cases=[('secret.swift:42:9: error: DO_NOT_PRINT','COMPILE','SWIFT_COMPILE_ERROR'),
               ('secret.m:3:2: error: DO_NOT_PRINT','COMPILE','CLANG_COMPILE_ERROR'),
               ('Command CodeSign failed with a nonzero exit code DO_NOT_PRINT','SIGNING','CODESIGN_FAILED'),
               ('No signing certificate DO_NOT_PRINT found','SIGNING','SIGNING_IDENTITY_UNAVAILABLE'),
               ('error: target does not support provisioning profiles DO_NOT_PRINT','PROFILE','PROFILE_NOT_APPLICABLE'),
               ('User interaction is not allowed DO_NOT_PRINT','KEYCHAIN','KEYCHAIN_ACCESS_DENIED'),
               ('Could not resolve package dependencies DO_NOT_PRINT','SWIFT_PACKAGE','PACKAGE_RESOLUTION_FAILED'),
               ('xcodebuild -showBuildSettings timed out DO_NOT_PRINT','BUILD_SETTINGS','BUILD_SETTINGS_TIMEOUT'),
               ('Signing for DO_NOT_PRINT requires a development team','BUILD_SETTINGS','SIGNING_TEAM_REQUIRED'),
               ('archive is empty DO_NOT_PRINT','ARCHIVE_FORMAT','ARCHIVE_EMPTY')]
        for raw,category,code in cases:
            diagnosis=self.diagnose(raw)
            self.assertIn(category,diagnosis['categories']);self.assertIn(code,diagnosis['codes'])
            self.assertNotIn('DO_NOT_PRINT','\n'.join(reports.format_diagnosis(diagnosis)))

    def test_command_failure_and_postcheck_failure_are_distinct(self):
        diagnosis=self.diagnose('** ARCHIVE FAILED **')
        self.assertIn('XCODEBUILD_ARCHIVE_FAILED',diagnosis['codes']);self.assertEqual(diagnosis['phase'],'BUILD_APP')
        diagnosis=self.diagnose('** ARCHIVE SUCCEEDED **')
        self.assertIn('GYM_POST_ARCHIVE_FAILED',diagnosis['codes'])
        diagnosis=self.diagnose('** ARCHIVE SUCCEEDED **',self.report(verify=True))
        self.assertEqual(diagnosis['phase'],'VERIFY_ARCHIVE');self.assertIn('ARCHIVE_PROFILE_MISMATCH',diagnosis['codes'])
        self.assertNotIn('XCODEBUILD_ARCHIVE_FAILED',diagnosis['codes'])

    def test_missing_logs_do_not_prove_setup_or_certificate_failure(self):
        diagnosis=self.diagnose('')
        self.assertEqual(diagnosis['command'],'not_observed')
        self.assertEqual(diagnosis['codes'],['BUILD_APP_FAILED_UNCLASSIFIED'])

    def test_raw_gym_log_and_error_info_are_private_parser_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory);(root/'logs').mkdir()
            (root/'logs'/'app.log').write_text('private-path\n** ARCHIVE FAILED **\nChaiCore does not support provisioning profiles DO_NOT_PRINT\n')
            (root/'archive-error.log').write_text('Could not resolve package dependencies DO_NOT_PRINT')
            diagnosis=reports.diagnose(self.report(),io.BytesIO(b'private-token'),root)
            self.assertIn('PACKAGE_PROFILE_OVERRIDE',diagnosis['codes']);self.assertIn('PACKAGE_RESOLUTION_FAILED',diagnosis['codes'])
            public='\n'.join(reports.format_diagnosis(diagnosis))
            self.assertNotIn('DO_NOT_PRINT',public);self.assertNotIn('private-',public)

    def test_parser_does_not_follow_logs_outside_private_root(self):
        with tempfile.TemporaryDirectory() as directory,tempfile.TemporaryDirectory() as outside:
            root=pathlib.Path(directory);(root/'logs').mkdir()
            file=pathlib.Path(outside)/'log';file.write_text('No profiles for DO_NOT_PRINT')
            (root/'logs'/'outside.log').symlink_to(file)
            diagnosis=reports.diagnose(self.report(),io.BytesIO(),root)
            self.assertNotIn('PROFILE_NOT_FOUND',diagnosis['codes'])

    def test_diagnostic_lane_needs_no_asc_key_and_is_fail_closed(self):
        seen=[]
        with patch.object(runner,'preflight',side_effect=lambda flags:seen.extend(flags) or 1):
            self.assertEqual(runner.main(['diagnose_signed_archive']),1)
        self.assertIn('--assets',seen);self.assertNotIn('--signing',seen)
        for complete in [True,False]:
            def fake_run(*args,**kwargs):
                env=kwargs['env'];root=pathlib.Path(env['CHAI_RELEASE_WORKDIR'])
                self.assertEqual(root.stat().st_mode&0o077,0);self.assertEqual(kwargs['umask'],0o077)
                pathlib.Path(env['CHAI_ARCHIVE_REPORT_PATH']).write_text(json.dumps(self.report(complete)))
                data=dict(schema=1,readonly=True,stages=assets.STAGES,profile_source='match_env',path_hint='present',failure=None)
                pathlib.Path(env['CHAI_SIGNING_ASSET_REPORT_PATH']).write_text(json.dumps(data))
                kwargs['stdout'].write(b'DO_NOT_PRINT_PRIVATE_KEY_PATH_TOKEN')
                return subprocess.CompletedProcess(args[0],0)
            output=io.StringIO()
            with patch.object(runner,'preflight',return_value=0),patch.object(runner.subprocess,'run',side_effect=fake_run),contextlib.redirect_stdout(output):
                self.assertEqual(runner.main(['diagnose_signed_archive']),0 if complete else 1)
            self.assertNotIn('DO_NOT_PRINT',output.getvalue())

    def test_failed_asset_setup_is_preserved_before_archive_diagnosis(self):
        def fake_run(*args,**kwargs):
            kwargs['stdout'].write(b'DO_NOT_PRINT [CHAI_SIGNING:ASSET_MATCH_READ]')
            return subprocess.CompletedProcess(args[0],1)
        output=io.StringIO()
        with patch.object(runner,'preflight',return_value=0),patch.object(runner.subprocess,'run',side_effect=fake_run),contextlib.redirect_stdout(output):
            self.assertEqual(runner.main(['diagnose_signed_archive']),1)
        self.assertIn('[ASSET_MATCH_READ]',output.getvalue())
        self.assertNotIn('ARCHIVE_REPORT_INVALID',output.getvalue());self.assertNotIn('DO_NOT_PRINT',output.getvalue())

if __name__=='__main__':unittest.main()
