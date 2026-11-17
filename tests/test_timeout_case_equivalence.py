"""Only two complete audited timeout-ceiling pairs may retain actual earlier passes."""
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import verify_scoped_ci as scoped


class TimeoutCaseEquivalenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.current={path:(ROOT/path).read_bytes() for path in scoped.APPROVED_TIMEOUT_CEILINGS}

    def test_only_exact_audited_pairs_project_to_the_original_script_digest(self):
        self.assertEqual(len(self.current),2)
        for path,data in self.current.items():
            before,after,ceiling=scoped.APPROVED_TIMEOUT_CEILINGS[path]
            original=data.replace(b'-maximum-test-execution-time-allowance 1800',('-maximum-test-execution-time-allowance '+str(ceiling)).encode())
            self.assertEqual(scoped.hashlib.sha256(original).hexdigest(),before)
            self.assertEqual(scoped.hashlib.sha256(data).hexdigest(),after)
            self.assertEqual(scoped.shared_content_digest(path,'100644',original),before)
            self.assertEqual(scoped.shared_content_digest(path,'100644',data),before)

    def test_defaults_timeouts_enabled_selectors_and_unknown_script_edits_invalidate(self):
        for path,data in self.current.items():
            before,after,ceiling=scoped.APPROVED_TIMEOUT_CEILINGS[path]
            variants=[data+b'\n# another source edit\n',
                      data.replace(b'-test-timeouts-enabled YES',b'-test-timeouts-enabled NO'),
                      data.replace(b'-maximum-test-execution-time-allowance 1800',b'-maximum-test-execution-time-allowance 3600')]
            default=b'-default-test-execution-time-allowance '+(b'420' if path.endswith('ci.sh') else b'600')
            variants.append(data.replace(default,b'-default-test-execution-time-allowance 1800'))
            for changed in variants:
                self.assertNotEqual(changed,data)
                raw=scoped.hashlib.sha256(changed).hexdigest()
                self.assertEqual(scoped.shared_content_digest(path,'100644',changed),raw)
                self.assertNotEqual(raw,before)

    def test_changed_mode_wrong_path_and_manually_extended_allowlist_cannot_bypass_source_validation(self):
        for path,data in self.current.items():
            raw=scoped.hashlib.sha256(data).hexdigest()
            self.assertEqual(scoped.shared_content_digest(path,'100755',data),raw)
            self.assertEqual(scoped.shared_content_digest('scripts/other.sh','100644',data),raw)
            modified=data+b'\nexit 0\n'; changed=scoped.hashlib.sha256(modified).hexdigest()
            before,after,ceiling=scoped.APPROVED_TIMEOUT_CEILINGS[path]
            with mock.patch.dict(scoped.APPROVED_TIMEOUT_CEILINGS,{path:(before,changed,ceiling)}):
                self.assertEqual(scoped.shared_content_digest(path,'100644',modified),changed)

    def test_ipad_gallery_ceiling_and_every_original_selector_are_unchanged(self):
        data=self.current['scripts/ipad_screenshots.sh']
        games,gallery=data.split(b'else\n  # Reuse the existing test target',1)
        self.assertEqual(games.count(b'-maximum-test-execution-time-allowance 1800'),1)
        self.assertEqual(gallery.count(b'-maximum-test-execution-time-allowance 720'),1)
        self.assertNotIn(b'-maximum-test-execution-time-allowance 1800',gallery)
        self.assertEqual(data.count(b'-only-testing:ChaiClassicsUITests/ChaiClassicsVisualSmokeTests/testIPad'),4)

    def test_real_source_pair_changes_only_the_long_shogi_case_not_the_other_seventy(self):
        # HEAD is the immutable candidate whose four real partitions are still
        # running. Unit comparisons do not claim those runs have passed.
        sha=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
        old=scoped.historical.git_tree(sha); new=dict(old)
        for path,data in self.current.items():new[path]=('100644',data)
        path='UITests/ChaiClassicsV030UITests.swift'; new[path]=('100644',(ROOT/path).read_bytes())
        previous=scoped.fingerprints(old); current=scoped.fingerprints(new)
        changed={name for name in previous if previous[name]!=current[name]}
        # This holds before the change is committed; afterwards both trees
        # already contain the same bounded allowance and are identical.
        expected={'ChaiClassicsV030UITests/testShogiCompleteSessionRestoresAndConfirmsDeletion'}
        self.assertIn(changed,(set(),expected)); self.assertEqual(len(previous),71)

    def test_failed_or_missing_cases_never_count_as_covered_under_either_ceiling(self):
        test='ChaiClassicsV030UITests/testShogiCompleteSessionRestoresAndConfirmsDeletion'
        for status in ('failed','skipped',None):self.assertFalse(scoped.covered(test,{'status':status}))
        self.assertFalse(scoped.covered(test,None))


if __name__=='__main__':unittest.main()
