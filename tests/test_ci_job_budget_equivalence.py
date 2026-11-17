"""A longer whole-job bound cannot supply missing XCTest evidence or change selectors."""
import hashlib
from pathlib import Path
import sys
import unittest
from unittest import mock
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
import verify_scoped_ci as scoped

class CIJobBudgetEquivalenceTests(unittest.TestCase):
    def setUp(self):
        self.path='.github/workflows/ci.yml';self.current=(ROOT/self.path).read_bytes()
        self.before,self.after=scoped.APPROVED_CI_JOB_TIMEOUT
        self.old=self.current.replace(b'    timeout-minutes: 180\n',b'    timeout-minutes: 90\n',1)

    def test_exact_job_timeout_delta_keeps_original_actual_passes(self):
        self.assertEqual(hashlib.sha256(self.current).hexdigest(),self.after)
        self.assertEqual(hashlib.sha256(self.old).hexdigest(),self.before)
        self.assertEqual(self.current.count(b'    timeout-minutes: 180\n'),1)
        self.assertEqual(scoped.shared_content_digest(self.path,'100644',self.current),self.before)
        self.assertEqual(scoped.shared_content_digest(self.path,'100644',self.old),self.before)

    def test_any_other_runtime_selector_mode_path_or_added_command_invalidates(self):
        for data in [self.current+b'\n# unreviewed\n',self.current.replace(b'180\n',b'360\n',1),
                     self.current.replace(b'full_ui:',b'changed_full_ui:',1),
                     self.current.replace(b'bash scripts/ci.sh ui',b'echo bypassed',1)]:
            raw=hashlib.sha256(data).hexdigest()
            self.assertEqual(scoped.shared_content_digest(self.path,'100644',data),raw)
            with mock.patch.object(scoped,'APPROVED_CI_JOB_TIMEOUT',(self.before,raw)):
                self.assertEqual(scoped.shared_content_digest(self.path,'100644',data),raw)
        self.assertEqual(scoped.shared_content_digest(self.path,'100755',self.current),self.after)
        self.assertEqual(scoped.shared_content_digest('.github/workflows/other.yml','100644',self.current),self.after)

    def test_failed_cancelled_and_missing_cases_are_not_covered(self):
        for status in ['failed','cancelled',None]:
            self.assertFalse(scoped.covered('ChaiClassicsUITests/testHomeHasExactlyThreeColumns',{'status':status}))

if __name__=='__main__':unittest.main()
