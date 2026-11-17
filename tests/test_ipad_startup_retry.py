"""Synthetic Xcode startup fixtures; these never represent executed App UI results."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('ipad_startup_retry',ROOT/'scripts/ipad_startup_retry.py')
retry = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(retry)
LOG = 'Failed to initialize for UI testing: Error Domain=XCTDaemonErrorDomain Code=18 "Timed out waiting for AX loaded notification"\n** TEST EXECUTE FAILED **\n'
MOCK_TOOL = '''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
name=Path(sys.argv[0]).name; args=sys.argv[1:]
with Path('calls.jsonl').open('a') as stream: stream.write(json.dumps([name,args])+'\\n')
if name=='xcodebuild':
    count=Path('attempts'); n=int(count.read_text())+1 if count.exists() else 1; count.write_text(str(n))
    result=Path(args[args.index('-resultBundlePath')+1]); result.mkdir(parents=True)
    (result/'original-attempt.txt').write_text(str(n))
    mode=os.environ['MOCK_STARTUP_MODE']
    if mode=='always-ax' or mode=='ax-then-pass' and n==1:
        print(os.environ['MOCK_AX_LOG']); raise SystemExit(65)
    if mode=='ui-failure':
        print("Test Case '-[ChaiClassicsUITests.ChaiClassicsVisualSmokeTests testIPadHomeScreenshot]' started.")
        print('XCTAssertTrue failed'); raise SystemExit(65)
    print('Synthetic shell fixture only; no Simulator or real XCTest executed.')
elif name=='xcrun' and args[:4]==['xcresulttool','get','test-results','summary']:
    print(Path('mock-summary.json').read_text())
'''


def summary():
    return {'totalTestCount':1,'passedTests':0,'failedTests':1,'skippedTests':0,'result':'Failed',
            'testFailures':[{'failureText':retry.FAILURE,'targetName':'ChaiClassicsUITests',
                             'testIdentifierString':'ChaiClassicsUITests-Runner (13340) encountered an error'}]}


class IPadStartupRetryTests(unittest.TestCase):
    def test_exact_pre_case_ax_failure_is_the_only_eligible_reason(self):
        self.assertTrue(retry.eligible(LOG,summary()))
        self.assertFalse(retry.eligible(LOG.replace('Code=18','Code=99'),summary()))
        self.assertFalse(retry.eligible(LOG.replace('** TEST EXECUTE FAILED **','** TEST EXECUTE SUCCEEDED **'),summary()))

    def test_any_started_passed_failed_or_skipped_case_prevents_retry(self):
        for status in ('started.','passed (1 seconds).','failed (1 seconds).','skipped (1 seconds).'):
            case = "Test Case '-[ChaiClassicsUITests.ChaiClassicsVisualSmokeTests testIPadHomeScreenshot]' "+status
            self.assertFalse(retry.eligible(LOG+case,summary()))

    def test_assertion_app_accessibility_and_other_runner_failures_are_not_retried(self):
        for text in ('XCTAssertTrue failed','Application has not loaded accessibility',
                     'Failed to launch application','The test runner failed to initialize for UI testing.'):
            value=summary(); value['testFailures'][0]['failureText']=text
            self.assertFalse(retry.eligible(LOG,value))

    def test_incomplete_counts_other_targets_extra_failures_and_invalid_types_fail_closed(self):
        cases=[]
        for key,value in [('totalTestCount',4),('passedTests',1),('failedTests',0),('skippedTests',1),('totalTestCount',True),('result','Passed')]:
            cases.append(summary()|{key:value})
        for key,value in [('targetName','OtherTests'),('testIdentifierString','testIPadHomeScreenshot'),('testIdentifierString',42)]:
            candidate=summary(); candidate['testFailures'][0][key]=value; cases.append(candidate)
        candidate=summary(); candidate['testFailures']*=2; cases.append(candidate)
        cases.extend([{},None,{'testFailures':[]}])
        for candidate in cases: self.assertFalse(retry.eligible(LOG,candidate))

    def test_cli_preserves_files_and_reports_only_fixed_codes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary); log=root/'tests.log'; report=root/'summary.json'
            log.write_text(LOG); report.write_text(json.dumps(summary()))
            command=['python3',str(ROOT/'scripts/ipad_startup_retry.py'),'--log',str(log),'--summary',str(report)]
            result=subprocess.run(command,capture_output=True,text=True)
            self.assertEqual(result.returncode,0); self.assertEqual(result.stdout.strip(),'IPAD_AX_STARTUP_RETRY_ELIGIBLE')
            self.assertEqual(log.read_text(),LOG); self.assertEqual(json.loads(report.read_text()),summary())
            report.write_text('invalid')
            result=subprocess.run(command,capture_output=True,text=True)
            self.assertEqual(result.returncode,1); self.assertEqual(result.stdout.strip(),'IPAD_STARTUP_RETRY_NOT_ALLOWED')

    def shell(self,mode):
        temporary=tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup); root=Path(temporary.name)
        (root/'scripts').mkdir(); (root/'bin').mkdir(); output=root/'build/ipad-screenshots'; output.mkdir(parents=True)
        for name in ('ipad_screenshots.sh','ipad_startup_retry.py'): shutil.copyfile(ROOT/'scripts'/name,root/'scripts'/name)
        (output/'device.json').write_text(json.dumps({'status':'ready','device_udid':'9495FFE4-4C27-490B-8E1B-5462EE31206C'}))
        (root/'mock-summary.json').write_text(json.dumps(summary()))
        for name in ('xcrun','xcodebuild','open'):
            path=root/'bin'/name; path.write_text(MOCK_TOOL); path.chmod(0o755)
        environment=dict(os.environ,PATH=str(root/'bin')+os.pathsep+os.environ['PATH'],MOCK_STARTUP_MODE=mode,MOCK_AX_LOG=LOG)
        result=subprocess.run(['bash','scripts/ipad_screenshots.sh','test'],cwd=root,env=environment,capture_output=True,text=True,timeout=20)
        calls=[json.loads(line) for line in (root/'calls.jsonl').read_text().splitlines()]
        return result,calls,output

    def test_real_shell_retries_once_preserves_original_and_reboots_same_device(self):
        result,calls,output=self.shell('ax-then-pass')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(sum(name=='xcodebuild' for name,args in calls),2)
        self.assertIn(['xcrun',['simctl','shutdown','9495FFE4-4C27-490B-8E1B-5462EE31206C']],calls)
        self.assertEqual((output/'IPadScreenshots-startup-attempt1.xcresult/original-attempt.txt').read_text(),'1')
        self.assertEqual((output/'IPadScreenshots.xcresult/original-attempt.txt').read_text(),'2')
        self.assertEqual((output/'tests-startup-attempt1.log').read_text().strip(),LOG.strip())

    def test_second_startup_failure_still_fails_and_does_not_retry_a_third_time(self):
        result,calls,output=self.shell('always-ax')
        self.assertEqual(result.returncode,65,result.stderr)
        self.assertEqual(sum(name=='xcodebuild' for name,args in calls),2)
        self.assertTrue((output/'IPadScreenshots-startup-attempt1.xcresult').is_dir())

    def test_success_and_any_real_case_failure_are_never_retried_or_rebooted(self):
        for mode,status in [('pass',0),('ui-failure',65)]:
            with self.subTest(mode=mode):
                result,calls,output=self.shell(mode)
                self.assertEqual(result.returncode,status,result.stderr)
                self.assertEqual(sum(name=='xcodebuild' for name,args in calls),1)
                self.assertFalse(any(name=='xcrun' and args[:2]==['simctl','shutdown'] for name,args in calls))
                self.assertFalse((output/'IPadScreenshots-startup-attempt1.xcresult').exists())


if __name__ == '__main__': unittest.main()
