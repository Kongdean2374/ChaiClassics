"""A passed whole gallery may retain its real source across exact CI boot preflight only."""
from pathlib import Path
import subprocess
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import verify_candidate as candidate
import verify_scoped_ci as scoped
ROOT=Path(__file__).resolve().parents[1]

class ScreenshotBootEquivalenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sha=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
        cls.target=scoped.historical.git_tree(sha)
        # Shallow release-tooling checkouts retain all required runtime sources;
        # this fixture models the exact boot block removal, not a fake UI pass.
        cls.target['scripts/ci.sh']=('100644',(ROOT/'scripts/ci.sh').read_bytes())
        cls.original=dict(cls.target)
        before,after,block=scoped.APPROVED_CI_BOOTSTRAP
        data=cls.original['scripts/ci.sh'][1]
        cls.original['scripts/ci.sh']=('100644',data.replace(block,b'',1))
        cls.protected=candidate.expected_tests('ipad',ROOT)+candidate.ipad_game_tests(ROOT)

    def verify(self,before=None,after=None,**kwargs):
        before=self.original if before is None else before
        after=self.target if after is None else after
        return candidate.verify_tooling_only_equivalence('a'*40,'b'*40,ROOT,
            tree_reader=lambda sha:before if sha=='a'*40 else after,
            ancestor=lambda:True,tested_cases=self.protected,**kwargs)

    def test_only_exact_ci_boot_delta_preserves_every_one_of_the_twenty_six_actual_tests(self):
        proof=self.verify()
        self.assertEqual(len(proof['tested_cases']),26)
        self.assertEqual(proof['tested_cases'],sorted(self.protected))
        execution=proof['audited_execution_equivalence']
        self.assertEqual(set(execution),{'scripts/ci.sh'})
        self.assertEqual(execution['scripts/ci.sh']['canonical_sha256'],scoped.APPROVED_TIMEOUT_CEILINGS['scripts/ci.sh'][0])
        self.assertNotEqual(execution['scripts/ci.sh']['source_sha256'],execution['scripts/ci.sh']['target_sha256'])

    def test_app_shared_helper_fixture_and_protected_assertion_changes_still_require_new_run(self):
        for path in ['App/MinesView.swift','App/GameSessionComponents.swift','App/ZoomBoard.swift',
                     'UITests/ChaiClassicsVisualSmokeTests.swift','Tests/ChaiCoreTests/Fixtures/v030-shogi.json']:
            changed=dict(self.target);mode,data=changed[path];changed[path]=(mode,data+b'\n// unreviewed change\n')
            with self.subTest(path=path),self.assertRaises(candidate.CandidateError):self.verify(after=changed)
        path='UITests/ChaiClassicsVisualSmokeTests.swift';changed=dict(self.target);mode,data=changed[path]
        source=data.decode();start,end=scoped.historical.functions(source)['testIPadMinesweeperScreenshot']
        changed[path]=(mode,(source[:start+1]+'\nXCTAssertTrue(false)\n'+source[start+1:]).encode())
        with self.assertRaises(candidate.CandidateError):self.verify(after=changed)

    def test_any_other_execution_change_or_mode_cannot_reuse_a_whole_ipad_run(self):
        path='scripts/ci.sh';data=self.target[path][1]
        for mode,changed in [('100755',data),('100644',data+b'\nexit 0\n'),
                             ('100644',data.replace(b'simctl bootstatus',b'simctl erase')),
                             ('100644',data.replace(b'-test-timeouts-enabled YES',b'-test-timeouts-enabled NO')),
                             ('100644',data.replace(b'"${CHAI_UI_ARGS[@]}"',b'-only-testing:Fake/test'))]:
            updated=dict(self.target);updated[path]=(mode,changed)
            with self.subTest(mode=mode,tail=changed[-20:]),self.assertRaises(candidate.CandidateError):self.verify(after=updated)

    def test_absent_selection_or_missing_runtime_cannot_use_execution_equivalence(self):
        with self.assertRaises(candidate.CandidateError):
            candidate.verify_tooling_only_equivalence('a'*40,'b'*40,ROOT,
                tree_reader=lambda sha:self.original if sha=='a'*40 else self.target,ancestor=lambda:True)
        missing=dict(self.target);missing.pop('fastlane/Fastfile')
        with self.assertRaises(candidate.CandidateError):self.verify(after=missing)

if __name__=='__main__':unittest.main()
