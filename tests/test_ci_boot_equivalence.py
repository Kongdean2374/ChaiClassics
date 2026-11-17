"""An exact Simulator warm-up cannot turn an unexecuted/failed UI case into a pass."""
import hashlib
from pathlib import Path
import sys
import unittest
from unittest import mock
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import verify_scoped_ci as scoped

class CIBootEquivalenceTests(unittest.TestCase):
    def setUp(self):
        self.path='scripts/ci.sh'
        self.current=(Path(__file__).resolve().parents[1]/self.path).read_bytes()
        old_default,new_default=scoped.APPROVED_CI_DEFAULT_ALLOWANCE
        if hashlib.sha256(self.current).hexdigest()==new_default:
            self.current=self.current.replace(b'-default-test-execution-time-allowance 600',b'-default-test-execution-time-allowance 420')
            assert hashlib.sha256(self.current).hexdigest()==old_default
        self.before,self.after,self.block=scoped.APPROVED_CI_BOOTSTRAP
        self.original=self.current.replace(self.block,b'',1)
        self.canonical=scoped.APPROVED_TIMEOUT_CEILINGS[self.path][0]

    def test_exact_same_device_preflight_projects_back_to_unchanged_execution(self):
        self.assertEqual(hashlib.sha256(self.current).hexdigest(),self.after)
        self.assertEqual(hashlib.sha256(self.original).hexdigest(),self.before)
        self.assertEqual(self.current.count(self.block),1)
        self.assertEqual(scoped.shared_content_digest(self.path,'100644',self.current),self.canonical)
        self.assertEqual(scoped.shared_content_digest(self.path,'100644',self.original),self.canonical)

    def test_any_other_boot_test_selector_command_or_result_edit_invalidates(self):
        variants=[self.current+b'\nexit 0\n',
                  self.current.replace(b'simctl bootstatus',b'simctl erase'),
                  self.current.replace(b'"$CHAI_SIM_UDID" -b',b'"another-device" -b'),
                  self.current.replace(b'"${CHAI_UI_ARGS[@]}"',b'-only-testing:Fake/test'),
                  self.current.replace(b'return "$CHAI_UI_EXIT"',b'return 0'),
                  self.current+self.block]
        for data in variants:
            raw=hashlib.sha256(data).hexdigest()
            self.assertNotEqual(raw,self.after)
            self.assertEqual(scoped.shared_content_digest(self.path,'100644',data),raw)
            # Even an accidentally extended allowlist cannot bypass baseline validation.
            with mock.patch.object(scoped,'APPROVED_CI_BOOTSTRAP',(self.before,raw,self.block)):
                self.assertEqual(scoped.shared_content_digest(self.path,'100644',data),raw)

    def test_other_paths_and_changed_modes_do_not_receive_equivalence(self):
        self.assertEqual(scoped.shared_content_digest('scripts/other.sh','100644',self.current),self.after)
        self.assertEqual(scoped.shared_content_digest(self.path,'100755',self.current),self.after)

    def test_pre_case_failure_and_missing_results_are_never_covered(self):
        name='ChaiClassicsUITests/testHomeHasExactlyThreeColumns'
        self.assertFalse(scoped.covered(name,None))
        for status in ('failed','skipped',None):
            self.assertFalse(scoped.covered(name,{'status':status}))

if __name__=='__main__':unittest.main()
