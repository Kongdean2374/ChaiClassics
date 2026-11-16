import contextlib
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'scripts'))
import apple_api_report as reports
import run_signing_lane as runner

class AppleReportTests(unittest.TestCase):
    def report(self, resource='profiles', status=403, category='FORBIDDEN'):
        return {'schema': 1, 'checks': [{'resource': 'certificates', 'status': 200}], 'failure': {'resource': resource, 'status': status, 'category': category, 'apple_code': None}}

    def test_status_and_resource_appear_without_responses_or_credentials(self):
        for status,category in [(401,'AUTHENTICATION'),(403,'FORBIDDEN'),(404,'NOT_FOUND'),(429,'RATE_LIMIT'),(500,'SERVER'),(503,'SERVER'),(200,'PROTOCOL'),(None,'UNKNOWN')]:
            report = self.report(status=status, category=category)
            output = '\n'.join(reports.format_report(report))
            self.assertIn('resource=profiles', output)
            self.assertIn('HTTP=' + (str(status) if status else 'unknown'), output)
            self.assertIn('category=' + category, output)

    def test_untrusted_fields_are_rejected_not_echoed(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory)/'report.json'
            base = self.report()
            cases = [dict(base, headers={'Authorization': 'DO_NOT_PRINT'}), self.report(resource='DO_NOT_PRINT'), self.report(status='DO_NOT_PRINT'), self.report(category='DO_NOT_PRINT')]
            code = self.report(); code['failure']['apple_code'] = 'DO_NOT_PRINT'; cases.append(code)
            for case in cases:
                path.write_text(json.dumps(case))
                self.assertIsNone(reports.load_report(path))
            path.write_text('DO_NOT_PRINT_INVALID_JSON')
            self.assertIsNone(reports.load_report(path))
            path.write_text(json.dumps(base))
            self.assertEqual(reports.load_report(path), base)

    def test_wrapper_uses_structured_status_instead_of_error_keyword(self):
        def fake_run(*args, **kwargs):
            kwargs['stdout'].write(b'forbidden DO_NOT_PRINT_JWT request headers DO_NOT_PRINT')
            pathlib.Path(kwargs['env']['CHAI_APPLE_DIAGNOSTIC_PATH']).write_text(json.dumps(self.report(status=503, category='SERVER')))
            return subprocess.CompletedProcess(args[0], 1)
        output = io.StringIO()
        with patch.object(runner, 'preflight', return_value=0), patch.object(runner.subprocess, 'run', side_effect=fake_run), contextlib.redirect_stdout(output):
            self.assertEqual(runner.main(['diagnose_signing']), 1)
        self.assertIn('APPLE_5XX', output.getvalue())
        self.assertIn('resource=profiles', output.getvalue())
        self.assertNotIn('DO_NOT_PRINT', output.getvalue())
        self.assertNotIn('APPLE_ACCESS', output.getvalue())

    def test_legacy_unexpected_response_and_forbidden_are_unclassified(self):
        self.assertEqual(runner.diagnostic(b'Spaceship::UnexpectedResponse: arbitrary error', 'initialize_signing'), 'APPLE_UNCLASSIFIED')
        self.assertEqual(runner.diagnostic(b'forbidden raw private response', 'initialize_signing'), 'APPLE_UNCLASSIFIED')

    def test_missing_report_does_not_claim_a_successful_apple_diagnostic(self):
        output = io.StringIO()
        result = subprocess.CompletedProcess([], 0)
        with patch.object(runner, 'preflight', return_value=0), patch.object(runner.subprocess, 'run', return_value=result), contextlib.redirect_stdout(output):
            self.assertEqual(runner.main(['diagnose_signing']), 1)
        self.assertIn('Missing or invalid safe report', output.getvalue())
        self.assertNotIn('Completed:', output.getvalue())

    def test_diagnostic_lane_requires_no_match_credentials(self):
        observed = []
        def preflight(flags): observed.extend(flags); return 1
        with patch.object(runner, 'preflight', side_effect=preflight):
            self.assertEqual(runner.main(['diagnose_signing']), 1)
        self.assertIn('--team', observed)
        self.assertNotIn('--signing', observed)
        self.assertNotIn('--check-repo', observed)
        self.assertNotIn('--initialize', observed)

if __name__ == '__main__': unittest.main()
