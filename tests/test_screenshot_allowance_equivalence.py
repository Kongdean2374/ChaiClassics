"""Whole successful iPad runs retain provenance across exact time allowances.

These are source-equivalence tests, not simulator results. Actual workflow,
26-case summary, original attachments and PNG checks remain mandatory.
"""
import hashlib
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import verify_candidate as candidate
import verify_scoped_ci as scoped


class ScreenshotAllowanceEquivalenceTests(unittest.TestCase):
    path = 'UITests/ChaiClassicsVisualSmokeTests.swift'
    case = 'ChaiClassicsVisualSmokeTests/testIPadSudokuScreenshot'

    @classmethod
    def setUpClass(cls):
        sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        cls.target = scoped.historical.git_tree(sha)
        for path in (ROOT / 'UITests').glob('*.swift'):
            cls.target[str(path.relative_to(ROOT))] = ('100644', path.read_bytes())
        cls.protected = candidate.expected_tests('ipad', ROOT) + candidate.ipad_game_tests(ROOT)

    def setUp(self):
        self.after = dict(self.target)
        self.before = dict(self.after)
        _old, _new, block = scoped.APPROVED_IPAD_SUDOKU_ALLOWANCE
        mode, raw = self.before[self.path]
        self.before[self.path] = (mode, raw.replace(block.encode(), b'', 1))
        path = 'UITests/ChaiClassicsV020UITests.swift'
        mode, raw = self.before[path]
        self.before[path] = (mode, raw.replace(b'executionTimeAllowance = 600', b'executionTimeAllowance = 420'))

    def verify(self, **kwargs):
        return candidate.verify_tooling_only_equivalence('a' * 40, 'b' * 40, ROOT,
            tree_reader=lambda sha: self.before if sha == 'a' * 40 else self.after,
            ancestor=lambda: True, tested_cases=self.protected, **kwargs)

    def test_only_exact_allowances_preserve_all_twenty_six_protected_bodies(self):
        proof = self.verify()
        self.assertEqual(len(proof['tested_cases']), 26)
        self.assertEqual(proof['tested_cases'], sorted(self.protected))
        self.assertEqual(proof['source_commit'], 'a' * 40)
        projection = proof['audited_xctest_allowances']
        self.assertEqual(projection['source'], {})
        self.assertEqual(set(projection['target']), {
            'method:' + self.case, 'scaffold:UITests/ChaiClassicsV020UITests.swift'})
        entry = projection['target']['method:' + self.case]
        old, new, _block = scoped.APPROVED_IPAD_SUDOKU_ALLOWANCE
        self.assertEqual(entry, {'raw_sha256': new, 'canonical_sha256': old})
        old_source = self.before[self.path][1].decode()
        new_source = self.after[self.path][1].decode()
        self.assertEqual(scoped.historical.assertions(old_source), scoped.historical.assertions(new_source))

    def test_changed_action_assertion_or_budget_cannot_enter_the_exact_body_pair(self):
        source = self.after[self.path][1].decode()
        start, end = scoped.historical.functions(source)['testIPadSudokuScreenshot']
        body = source[start:end]
        self.assertNotEqual(scoped.canonical_xctest_allowance_body(self.path, self.case, '100644', body), body)
        for changed in [body.replace('executionTimeAllowance = 1800', 'executionTimeAllowance = 9600'),
                        body[:1] + '\nXCTAssertTrue(false)\n' + body[1:],
                        body[:1] + '\napp.terminate()\n' + body[1:]]:
            raw = hashlib.sha256(changed.encode()).hexdigest()
            old, _new, block = scoped.APPROVED_IPAD_SUDOKU_ALLOWANCE
            # Even changing the allowlisted after-hash cannot bypass the
            # independent original-body comparison.
            with mock.patch.object(scoped, 'APPROVED_IPAD_SUDOKU_ALLOWANCE', (old, raw, block)):
                self.assertEqual(scoped.canonical_xctest_allowance_body(self.path, self.case, '100644', changed), changed)
            self.after[self.path] = ('100644', (source[:start] + changed + source[end:]).encode())
            with self.assertRaises(candidate.CandidateError):
                self.verify()

    def test_path_identity_and_mode_cannot_borrow_another_cases_allowance(self):
        source = self.after[self.path][1].decode()
        start, end = scoped.historical.functions(source)['testIPadSudokuScreenshot']
        body = source[start:end]
        for path, identity, mode in [('UITests/Other.swift', self.case, '100644'),
                                     (self.path, 'ChaiClassicsVisualSmokeTests/testIPadHomeScreenshot', '100644'),
                                     (self.path, self.case, '100755')]:
            self.assertEqual(scoped.canonical_xctest_allowance_body(path, identity, mode, body), body)

    def test_runtime_helper_setup_and_game_assertion_changes_still_require_a_fresh_whole_run(self):
        baseline = dict(self.after)
        for path in ['App/MinesView.swift', 'Core/SaveStore.swift',
                     'UITests/ChaiClassicsV030UITests.swift', 'UITests/ChaiClassicsV020UITests.swift']:
            self.after = dict(baseline)
            mode, raw = self.after[path]
            self.after[path] = (mode, raw + b'\n// changed helper or runtime\n')
            with self.subTest(path=path), self.assertRaises(candidate.CandidateError):
                self.verify()
        self.after = dict(baseline)
        path = 'UITests/ChaiClassicsV030UITests.swift'
        source = self.after[path][1].decode()
        name = next(case.split('/')[1] for case in self.protected if case.startswith('ChaiClassicsV030UITests/'))
        start, _end = scoped.historical.functions(source)[name]
        self.after[path] = ('100644', (source[:start + 1] + '\nXCTAssertTrue(false)\n' + source[start + 1:]).encode())
        with self.assertRaises(candidate.CandidateError):
            self.verify()

    def test_ci_case_fingerprints_still_require_fresh_execution_of_the_changed_sudoku_body(self):
        before = scoped.fingerprints(self.before)
        after = scoped.fingerprints(self.target)
        self.assertNotEqual(before[self.case], after[self.case])
        self.assertEqual([name for name in before if before[name] != after[name]], [self.case])
        for status in ['failed', 'cancelled', None]:
            self.assertFalse(scoped.covered(self.case, {'status': status}))


if __name__ == '__main__':
    unittest.main()
