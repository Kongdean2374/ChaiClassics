"""Measured XCTest overhead changes overall bounds, never game-speed assertions."""
import hashlib
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
import verify_scoped_ci as scoped

class UIAllowanceEquivalenceTests(unittest.TestCase):
    def test_only_exact_ci_default_increase_retains_original_actual_passes(self):
        path='scripts/ci.sh';data=(ROOT/path).read_bytes();before,after=scoped.APPROVED_CI_DEFAULT_ALLOWANCE
        original=data.replace(b'-default-test-execution-time-allowance 600',b'-default-test-execution-time-allowance 420')
        self.assertEqual(hashlib.sha256(data).hexdigest(),after)
        self.assertEqual(hashlib.sha256(original).hexdigest(),before)
        canonical=scoped.APPROVED_TIMEOUT_CEILINGS[path][0]
        self.assertEqual(scoped.shared_content_digest(path,'100644',data),canonical)
        self.assertEqual(scoped.shared_content_digest(path,'100644',original),canonical)

    def test_other_ci_defaults_commands_or_modes_cannot_enter_the_audited_pair(self):
        path='scripts/ci.sh';data=(ROOT/path).read_bytes();before,after=scoped.APPROVED_CI_DEFAULT_ALLOWANCE
        for changed in [data+b'\nexit 0\n',data.replace(b'-default-test-execution-time-allowance 600',b'-default-test-execution-time-allowance 3600'),data.replace(b'-test-timeouts-enabled YES',b'-test-timeouts-enabled NO')]:
            raw=hashlib.sha256(changed).hexdigest()
            with mock.patch.object(scoped,'APPROVED_CI_DEFAULT_ALLOWANCE',(before,raw)):
                self.assertEqual(scoped.shared_content_digest(path,'100644',changed),raw)
        self.assertEqual(scoped.shared_content_digest(path,'100755',data),after)

    def scaffold(self,source):
        for name,(a,b) in sorted(scoped.historical.functions(source).items(),key=lambda x:x[1][0],reverse=True):
            if name.startswith('test'):source=source[:a]+'{TEST_BODY}'+source[b:]
        return source

    def test_exact_v020_whole_case_allowances_preserve_all_literal_assertions_and_other_cases(self):
        path='UITests/ChaiClassicsV020UITests.swift';current=(ROOT/path).read_text()
        original=current.replace('executionTimeAllowance = 600','executionTimeAllowance = 420')
        self.assertEqual(current.count('executionTimeAllowance = 600'),2)
        before,after=scoped.APPROVED_V020_CASE_ALLOWANCE
        self.assertEqual(hashlib.sha256(self.scaffold(original).encode()).hexdigest(),before)
        self.assertEqual(hashlib.sha256(self.scaffold(current).encode()).hexdigest(),after)
        self.assertEqual(scoped.historical.assertions(original),scoped.historical.assertions(current))
        sha=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
        old=scoped.historical.git_tree(sha);new=dict(old)
        old[path]=('100644',original.encode());new[path]=('100644',current.encode())
        self.assertEqual(scoped.fingerprints(old),scoped.fingerprints(new))
        self.assertIn('XCTAssertLessThan', (ROOT/'Tests/ChaiCoreTests/TicTacToeTests.swift').read_text())

    def test_unknown_scaffold_setup_ai_logic_global_hook_and_modes_cannot_use_budget_equivalence(self):
        path='UITests/ChaiClassicsV020UITests.swift';source=self.scaffold((ROOT/path).read_text())
        before,after=scoped.APPROVED_V020_CASE_ALLOWANCE
        for changed in [source+'\n// outside edit\n',source.replace('executionTimeAllowance = 600','executionTimeAllowance = 900',1),source.replace('for computerFirst in [false, true]','for computerFirst in [false]')]:
            raw=hashlib.sha256(changed.encode()).hexdigest()
            self.assertNotEqual(raw,after)
            with mock.patch.object(scoped,'APPROVED_V020_CASE_ALLOWANCE',(before,raw)):
                self.assertEqual(scoped.scaffold_budget_digest(path,'100644',changed),raw)
        self.assertEqual(scoped.scaffold_budget_digest(path,'100755',source),after)
        self.assertEqual(scoped.scaffold_budget_digest('UITests/Other.swift','100644',source),after)

    def test_failed_missing_and_cancelled_cases_never_become_covered(self):
        for state in ['failed','cancelled',None]:
            self.assertFalse(scoped.covered('ChaiClassicsUITests/testHomeHasExactlyThreeColumns',{'status':state}))

if __name__=='__main__':unittest.main()
