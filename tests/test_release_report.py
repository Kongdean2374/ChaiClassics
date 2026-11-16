import contextlib
import io
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'scripts'))
import release_report as reports
import signing_asset_report as assets
import run_signing_lane as runner

class ReleaseReportTests(unittest.TestCase):
    def report(self, phase=None):
        index=reports.PHASES.index(phase) if phase else len(reports.PHASES)
        return dict(schema=1,fastlane='2.228.0',completed=reports.PHASES[:index],phase=phase,
                    status='failed' if phase else 'complete',reason='UNKNOWN' if phase else None,http_status=None)

    def load(self, value):
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/'report.json';path.write_text(json.dumps(value))
            return reports.load_release_report(path)

    def test_real_ruby_and_python_allowlists_agree(self):
        source=(pathlib.Path(__file__).resolve().parents[1]/'fastlane/lib/release_pipeline.rb').read_text()
        self.assertEqual(re.search(r'PHASES = %w\[([^]]+)\]',source)[1].split(),reports.PHASES)
        self.assertEqual(set(re.search(r'REASONS = %w\[([^]]+)\]',source)[1].split()),reports.REASONS)

    def test_valid_complete_and_every_failure_phase(self):
        self.assertTrue(reports.release_complete(self.load(self.report())))
        for phase in reports.PHASES:
            report=self.load(self.report(phase))
            self.assertEqual(reports.failure_phase(report),phase)
            self.assertIn('['+phase+']','\n'.join(reports.format_release_report(report)))

    def test_secret_fields_dynamic_values_and_wrong_types_rejected(self):
        for key,value in [('secret','DO_NOT_PRINT'),('phase','DO_NOT_PRINT'),('reason','DO_NOT_PRINT'),
                          ('http_status','401 DO_NOT_PRINT'),('http_status',True),('fastlane','DO_NOT_PRINT'),
                          ('completed',['DO_NOT_PRINT']),('status','DO_NOT_PRINT')]:
            report=self.report('ARCHIVE');report[key]=value
            self.assertIsNone(self.load(report))

    def test_incomplete_and_out_of_order_cannot_be_success(self):
        report=self.report();report['completed']=report['completed'][:-1]
        self.assertIsNone(self.load(report))
        report=self.report('ARCHIVE');report['completed'].reverse()
        self.assertIsNone(self.load(report))

    def test_interrupted_process_keeps_last_phase(self):
        report=self.report('EXPORT_IPA');report.update(status='running',reason=None)
        loaded=self.load(report)
        self.assertIn('PROCESS_INTERRUPTED','\n'.join(reports.format_release_report(loaded)))
        self.assertEqual(reports.failure_phase(loaded),'EXPORT_IPA')

    def fake_child(self, report, success=False, include_assets=True):
        def run(*args,**kwargs):
            kwargs['stdout'].write(b'DO_NOT_PRINT_KEY_TOKEN_CERT_PATH\n[CHAI_SIGNING:UPLOAD_FAILED]')
            pathlib.Path(kwargs['env']['CHAI_RELEASE_REPORT_PATH']).write_text(json.dumps(report))
            if include_assets:
                data=dict(schema=1,readonly=True,stages=assets.STAGES,profile_source='match_env',path_hint='present',failure=None)
                pathlib.Path(kwargs['env']['CHAI_SIGNING_ASSET_REPORT_PATH']).write_text(json.dumps(data))
            return subprocess.CompletedProcess(args[0],0 if success else 1)
        return run

    def test_structured_phase_takes_precedence_over_legacy_raw_output(self):
        for phase in reports.PHASES:
            report=self.report(phase);report.update(reason='RATE_LIMITED',http_status=429)
            output=io.StringIO()
            with patch.object(runner,'preflight',return_value=0),patch.object(runner.subprocess,'run',side_effect=self.fake_child(report)),contextlib.redirect_stdout(output):
                self.assertEqual(runner.main(['beta']),1)
            text=output.getvalue()
            self.assertIn('['+phase+']',text);self.assertIn('http=429',text)
            self.assertNotIn('DO_NOT_PRINT',text);self.assertNotIn('[UPLOAD_FAILED]',text)

    def test_beta_success_requires_both_complete_reports(self):
        for complete,include_assets in [(True,True),(False,True),(True,False)]:
            report=self.report(None if complete else 'EXPORT_IPA')
            with patch.object(runner,'preflight',return_value=0),patch.object(runner.subprocess,'run',side_effect=self.fake_child(report,True,include_assets)),contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(runner.main(['beta']),0 if complete and include_assets else 1)

    def test_http_codes_are_bounded_integers_only(self):
        for status in [401,403,404,429,500,503]:
            report=self.report('UPLOAD_AUTH');report.update(http_status=status)
            self.assertEqual(self.load(report)['http_status'],status)
        for status in [-1,999,401.5,{'token':'DO_NOT_PRINT'}]:
            report=self.report('UPLOAD_AUTH');report.update(http_status=status)
            self.assertIsNone(self.load(report))

if __name__=='__main__':unittest.main()
