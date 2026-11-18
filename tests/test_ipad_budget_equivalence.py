"""Long native iPad work keeps bounded limits and cannot reuse failed/missing results."""
import hashlib
from pathlib import Path
import sys
import unittest
from unittest import mock
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
import verify_candidate as candidate
import verify_scoped_ci as scoped

class IPadBudgetEquivalenceTests(unittest.TestCase):
    def setUp(self):
        self.path='.github/workflows/ipad-screenshots.yml'
        self.current=(ROOT/'tests/Fixtures/pipeline-audits/ipad-budget-v1.yml').read_bytes()
        self.before,self.after=scoped.APPROVED_IPAD_JOB_BUDGET
        self.old=self.current.replace(b'    timeout-minutes: 330\n',b'    timeout-minutes: 240\n',1)
        self.old=self.old.replace(b'        id: boot\n        timeout-minutes: 15\n',b'        id: boot\n        timeout-minutes: 10\n',1)
        self.old=self.old.replace(b'        id: ui\n        timeout-minutes: 60\n',b'        id: ui\n        timeout-minutes: 25\n',1)

    def test_only_exact_three_budget_changes_project_back_to_original_workflow(self):
        self.assertEqual(hashlib.sha256(self.current).hexdigest(),self.after)
        self.assertEqual(hashlib.sha256(self.old).hexdigest(),self.before)
        self.assertEqual(scoped.shared_content_digest(self.path,'100644',self.current),self.before)
        self.assertEqual(scoped.shared_content_digest(self.path,'100644',self.old),self.before)
        self.assertIn(b'        timeout-minutes: 210',self.current)
        self.assertIn(b'CODE_SIGNING_ALLOWED=NO',(ROOT/'scripts/ipad_screenshots.sh').read_bytes())

    def test_selector_commands_permissions_modes_and_other_budget_changes_fail_closed(self):
        for data in [(ROOT/self.path).read_bytes(),self.current+b'\n# unreviewed\n',self.current.replace(b'timeout-minutes: 330',b'timeout-minutes: 360'),
                     self.current.replace(b'contents: read',b'contents: write'),
                     self.current.replace(b'run: bash scripts/ipad_screenshots.sh games',b'run: echo skipped')]:
            raw=hashlib.sha256(data).hexdigest()
            self.assertEqual(scoped.shared_content_digest(self.path,'100644',data),raw)
            with mock.patch.object(scoped,'APPROVED_IPAD_JOB_BUDGET',(self.before,raw)):
                self.assertEqual(scoped.shared_content_digest(self.path,'100644',data),raw)
        self.assertEqual(scoped.shared_content_digest(self.path,'100755',self.current),self.after)
        self.assertEqual(scoped.shared_content_digest('.github/workflows/other.yml','100644',self.current),self.after)

    def test_phone_plan_never_becomes_skipped_only_after_an_ipad_case_changes(self):
        home=scoped.FAST_SENTINEL
        ipad='ChaiClassicsVisualSmokeTests/testIPadSudokuScreenshot'
        targets={home:'h',ipad:'new'}
        record={'run_id':1,'sha':'a'*40,'actual':{home:'passed',ipad:'skipped'},'fingerprints':{home:'h',ipad:'old'}}
        self.assertEqual(scoped.planned_tests(targets,[record]),sorted([home,ipad]))
        record['fingerprints'][ipad]='new'
        self.assertEqual(scoped.planned_tests(targets,[record]),[home])
        real='ChaiClassicsUITests/testSlidingCanStartAndRestore'
        self.assertEqual(scoped.planned_tests({home:'h',ipad:'new',real:'r'},[record]),[real])
        for status in ['failed','cancelled',None]:self.assertFalse(scoped.covered(home,{'status':status}))

if __name__=='__main__':unittest.main()
