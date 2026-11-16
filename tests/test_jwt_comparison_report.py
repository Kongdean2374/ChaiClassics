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

class ComparisonReportTests(unittest.TestCase):
    def report(self, apps=401, certs=401):
        jwt={name:True for name in reports.JWT_CHECKS}
        def result(resource, status):
            return dict(resource=resource, status=status, category='OK' if status==200 else 'AUTHENTICATION' if status==401 else 'FORBIDDEN' if status==403 else 'SERVER', apple_code=None if status==200 else 'NOT_AUTHORIZED')
        results=[result('apps',apps), result('certificates',certs)]
        return dict(schema=2,jwt=jwt,results=results,conclusion=reports.comparison_conclusion(jwt,results))

    def test_pair_classifications(self):
        for apps,certs,expected in [(401,401,'JWT_AUTHENTICATION_REJECTED'),(200,401,'CERTIFICATES_AUTHENTICATION_REJECTED'),(200,403,'CERTIFICATES_ACCESS_DENIED'),(200,503,'CERTIFICATES_API_FAILED'),(401,200,'APPS_AUTHENTICATION_REJECTED'),(200,200,'AUTHENTICATED_BOTH'),(401,503,'INCONCLUSIVE')]:
            report=self.report(apps,certs)
            self.assertEqual(report['conclusion'],expected)
            self.assertEqual(reports.report_failed(report), expected!='AUTHENTICATED_BOTH')
            text='\n'.join(reports.format_report(report))
            self.assertIn('resource=apps',text); self.assertIn('resource=certificates',text)
            self.assertIn('JWT local checks (values withheld):',text)

    def test_report_validation_never_echoes_identifiers(self):
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/'report.json'
            valid=self.report();path.write_text(json.dumps(valid))
            self.assertEqual(reports.load_report(path),valid)
            cases=[]
            r=self.report();r['jwt']['kid']='DO_NOT_PRINT_KEY_ID';cases.append(r)
            r=self.report();r['token']='DO_NOT_PRINT_TOKEN';cases.append(r)
            r=self.report();r['results'][0]['apple_code']='DO_NOT_PRINT_ERROR_CODE';cases.append(r)
            r=self.report();r['conclusion']='AUTHENTICATED_BOTH';cases.append(r)
            r=self.report();r['results'].reverse();cases.append(r)
            for case in cases:
                path.write_text(json.dumps(case))
                self.assertIsNone(reports.load_report(path))

    def test_wrapper_prints_both_results_even_after_apps_401(self):
        def fake_run(*args,**kwargs):
            kwargs['stdout'].write(b'DO_NOT_PRINT_P8 DO_NOT_PRINT_JWT DO_NOT_PRINT_IDENTIFIERS')
            pathlib.Path(kwargs['env']['CHAI_APPLE_DIAGNOSTIC_PATH']).write_text(json.dumps(self.report()))
            return subprocess.CompletedProcess(args[0],1)
        output=io.StringIO()
        with patch.object(runner,'preflight',return_value=0),patch.object(runner.subprocess,'run',side_effect=fake_run),contextlib.redirect_stdout(output):
            self.assertEqual(runner.main(['diagnose_signing']),1)
        text=output.getvalue()
        self.assertIn('resource=apps method=GET HTTP=401',text)
        self.assertIn('resource=certificates method=GET HTTP=401',text)
        self.assertIn('JWT_AUTHENTICATION_REJECTED',text)
        self.assertNotIn('DO_NOT_PRINT',text)

    def test_invalid_local_claims_are_not_a_permission_diagnosis(self):
        report=self.report();report['jwt']['iss']=False
        report['conclusion']=reports.comparison_conclusion(report['jwt'],report['results'])
        self.assertEqual(report['conclusion'],'JWT_LOCAL_INVALID')
        self.assertIn('iss=FAIL','\n'.join(reports.format_report(report)))

if __name__=='__main__': unittest.main()
