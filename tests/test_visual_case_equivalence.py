"""Retain real unaffected captures without allowing changed gameplay dependencies."""
from pathlib import Path
import sys
import subprocess
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import verify_candidate as candidate
import verify_scoped_ci as scoped


class VisualCaseEquivalenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=candidate.ROOT, text=True).strip()
        cls.base = scoped.historical.git_tree(sha)
        # Unit fixtures exercise the currently audited helper digest, including
        # during uncommitted development. Production still reads immutable Git
        # trees and original ZIP evidence; this is no source-equivalence proof.
        for path in (candidate.ROOT / 'UITests').glob('*.swift'):
            name = str(path.relative_to(candidate.ROOT))
            cls.base[name] = ('100644',path.read_bytes())

    def verify_change(self, path=None, *, ancestor=True, mode=None):
        before, after = dict(self.base), dict(self.base)
        if path is not None:
            original_mode, data = after.get(path, ('100644', b''))
            after[path] = (mode or original_mode, data + b'\n// A separately reviewed change.\n')
        return candidate.verify_visual_case_equivalence('a' * 40, 'b' * 40,
            tree_reader=lambda sha: before if sha == 'a' * 40 else after,
            ancestor=lambda: ancestor)

    def test_only_unrelated_board_view_may_retain_all_four_original_source_captures(self):
        proof = self.verify_change('App/ExpandedStrategyView.swift')
        self.assertEqual(proof['verification'], 'dependency-scoped-visual')
        self.assertEqual(proof['source_commit'], 'a' * 40)
        self.assertEqual(proof['target_commit'], 'b' * 40)
        self.assertEqual(set(proof['case_fingerprints']), set(candidate.VISUAL_FOCUS_TESTS))
        self.assertEqual(proof['changed_paths'], ['App/ExpandedStrategyView.swift'])
        self.assertTrue(all(len(value) == 64 for value in proof['case_fingerprints'].values()))

    def test_identical_trees_at_distinct_ancestor_commits_preserve_the_original_source(self):
        self.assertEqual(self.verify_change()['changed_paths'], [])

    def test_shared_session_input_core_saves_assets_and_execution_changes_require_fresh_captures(self):
        for path in ('App/GameSessionComponents.swift', 'App/ContinueTouchMonitor.swift',
                     'Core/TicTacToe.swift', 'Core/SaveStore.swift', 'App/Resources/en.lproj/Localizable.strings',
                     'scripts/visual_smoke.sh', '.github/workflows/visual-smoke.yml',
                     'ChaiClassics.xcodeproj/project.pbxproj'):
            with self.subTest(path=path), self.assertRaises(candidate.CandidateError):
                self.verify_change(path)

    def test_any_of_the_three_captured_game_views_requires_fresh_phone_captures(self):
        for path in ('App/SlidingView.swift', 'App/MinesView.swift', 'App/SudokuView.swift'):
            self.assertTrue(path in self.base, 'Missing captured game source: ' + path)
            with self.subTest(path=path), self.assertRaises(candidate.CandidateError):
                self.verify_change(path)

    def test_test_helpers_setup_signatures_and_executed_bodies_cannot_change(self):
        with self.assertRaises(candidate.CandidateError):
            self.verify_change('UITests/ChaiClassicsVisualSmokeTests.swift')
        before, after = dict(self.base), dict(self.base)
        path = 'UITests/ChaiClassicsVisualSmokeTests.swift'
        mode, raw = after[path]
        source = raw.decode()
        start, _ = scoped.historical.functions(source)['testScreenshotGallery']
        after[path] = (mode, (source[:start + 1] + '\nXCTAssertTrue(false)\n' + source[start + 1:]).encode())
        with self.assertRaises(candidate.CandidateError):
            candidate.verify_visual_case_equivalence('a' * 40, 'b' * 40,
                tree_reader=lambda sha: before if sha == 'a' * 40 else after, ancestor=lambda: True)

    def test_unknown_runtime_files_symlinks_and_nonancestor_sources_fail_closed(self):
        with self.assertRaises(candidate.CandidateError): self.verify_change('App/UnknownRuntime.swift')
        with self.assertRaises(candidate.CandidateError): self.verify_change('App/ExpandedStrategyView.swift', mode='120000')
        with self.assertRaises(candidate.CandidateError): self.verify_change(ancestor=False)


if __name__ == '__main__':
    unittest.main()
