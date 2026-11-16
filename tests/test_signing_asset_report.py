import contextlib
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'scripts'))
import signing_asset_report as reports
import run_signing_lane as runner
import check_release_secrets as checks

class AssetReportTests(unittest.TestCase):
    def report(self, failure=None):
        return dict(schema=1,readonly=True,stages=reports.STAGES.copy(),profile_source='installed_scan',path_hint='missing',failure=failure)
    def test_no_api_key_needed_for_asset_preflight(self):
        checks.validate_asset_environment(dict(APPLE_TEAM_ID='T123456789',SIGNING_REPO_PAT='fixture',MATCH_PASSWORD='fixture'))
        with self.assertRaises(checks.ConfigurationError): checks.validate_asset_environment({})
    def test_strict_report_suppresses_paths_and_values(self):
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/'report.json'
            path.write_text(json.dumps(self.report()))
            self.assertTrue(reports.asset_complete(reports.load_asset_report(path)))
            for key,value in [('profile_source','/DO_NOT_PRINT'),('path_hint','DO_NOT_PRINT'),('failure','DO_NOT_PRINT'),('readonly',False),('private_key','DO_NOT_PRINT')]:
                report=self.report();report[key]=value;path.write_text(json.dumps(report))
                self.assertIsNone(reports.load_asset_report(path))
    def test_each_fixed_stage_code_has_safe_message(self):
        for code in reports.MESSAGES:
            report=self.report(code)
            text='\n'.join(reports.format_asset_report(report))
            self.assertIn(code,text); self.assertFalse(reports.asset_complete(report))
    def test_wrapper_uses_new_readonly_lane_without_asc_config(self):
        seen=[]
        with patch.object(runner,'preflight',side_effect=lambda flags:seen.extend(flags) or 1):
            self.assertEqual(runner.main(['verify_signing_assets']),1)
        self.assertIn('--assets',seen);self.assertIn('--check-repo',seen)
        self.assertNotIn('--initialize',seen);self.assertNotIn('--signing',seen)
    def test_private_output_is_not_printed_and_success_requires_all_stages(self):
        for complete in [True,False]:
            def fake_run(*args,**kwargs):
                kwargs['stdout'].write(b'DO_NOT_PRINT_PRIVATE_PATH_PASSWORD_TOKEN_CERT')
                report=self.report()
                if not complete: report['stages']=report['stages'][:-2]
                pathlib.Path(kwargs['env']['CHAI_SIGNING_ASSET_REPORT_PATH']).write_text(json.dumps(report))
                return subprocess.CompletedProcess(args[0],0)
            output=io.StringIO()
            with patch.object(runner,'preflight',return_value=0),patch.object(runner.subprocess,'run',side_effect=fake_run),contextlib.redirect_stdout(output):
                self.assertEqual(runner.main(['verify_signing_assets']),0 if complete else 1)
            self.assertNotIn('DO_NOT_PRINT',output.getvalue())
    def test_failure_is_granular_not_legacy_match_assets(self):
        def fake_run(*args,**kwargs):
            pathlib.Path(kwargs['env']['CHAI_SIGNING_ASSET_REPORT_PATH']).write_text(json.dumps(self.report('ASSET_PRIVATE_KEY_SIGN')))
            return subprocess.CompletedProcess(args[0],1)
        output=io.StringIO()
        with patch.object(runner,'preflight',return_value=0),patch.object(runner.subprocess,'run',side_effect=fake_run),contextlib.redirect_stdout(output):
            self.assertEqual(runner.main(['verify_signing_assets']),1)
        self.assertIn('ASSET_PRIVATE_KEY_SIGN',output.getvalue());self.assertNotIn('[MATCH_ASSETS]',output.getvalue())

if __name__=='__main__':unittest.main()
