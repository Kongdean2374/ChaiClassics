import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import verify_candidate as candidate


class EvidenceToolingEquivalenceTests(unittest.TestCase):
    source_sha = 'a' * 40
    target_sha = 'b' * 40

    def setUp(self):
        paths = ['App/Info.plist', 'App/MemoryView.swift', 'App/Resources/en.lproj/Localizable.strings',
                 'App/Assets.xcassets/Art.imageset/Art.png', 'Core/SaveStore.swift', 'Core/MemoryMatch.swift',
                 'Package.swift', 'Gemfile.lock', 'ChaiClassics.xcodeproj/project.pbxproj',
                 'UITests/ChaiClassicsVisualSmokeTests.swift', 'scripts/ci.sh', 'scripts/create_project.py',
                 'scripts/ui_test_scope.py', 'scripts/verify_incremental_ci.py',
                 '.github/workflows/ci.yml', '.github/workflows/ipad-screenshots.yml', 'fastlane/Fastfile']
        self.before = {path: ('100644', ('protected:' + path).encode()) for path in paths}
        self.before['scripts/verify_candidate.py'] = ('100644', b'old verifier')
        self.before['scripts/verify_scoped_ci.py'] = ('100644', b'old dependency proof')
        self.after = copy.deepcopy(self.before)
        self.after['scripts/verify_candidate.py'] = ('100644', b'new verifier')

    def verify(self, **kwargs):
        trees = {self.source_sha: self.before, self.target_sha: self.after}
        return candidate.verify_tooling_only_equivalence(self.source_sha, self.target_sha,
                    tree_reader=lambda sha: trees[sha], ancestor=lambda: True, **kwargs)

    def test_only_pure_evidence_and_documentation_changes_retain_actual_source(self):
        self.after['scripts/verify_scoped_ci.py'] = ('100644', b'new independently checked dependency proof')
        self.after['tests/test_proof.py'] = ('100644', b'new regression tests')
        self.after['docs/provenance.md'] = ('100644', b'actual source provenance')
        proof = self.verify()
        self.assertEqual(proof['source_commit'], self.source_sha)
        self.assertEqual(proof['target_commit'], self.target_sha)
        self.assertEqual(len(proof['runtime_digest']), 64)
        self.assertIn('scripts/verify_scoped_ci.py', proof['changed_paths'])

    def test_any_runtime_test_helper_asset_execution_or_signing_change_requires_fresh_screenshots(self):
        for path in self.before:
            if path in candidate.PURE_EVIDENCE_SCRIPTS:
                continue
            with self.subTest(path=path):
                self.after = copy.deepcopy(self.before)
                self.after['scripts/verify_candidate.py'] = ('100644', b'new verifier')
                self.after[path] = ('100644', b'changed runtime or XCTest')
                with self.assertRaises(candidate.CandidateError):
                    self.verify()

    def test_runtime_additions_removals_and_mode_changes_are_rejected(self):
        for mutation in ('addition', 'removal', 'mode'):
            with self.subTest(mutation=mutation):
                self.after = copy.deepcopy(self.before)
                if mutation == 'addition': self.after['App/Injected.swift'] = ('100644', b'new code')
                if mutation == 'removal': del self.after['App/MemoryView.swift']
                if mutation == 'mode': self.after['scripts/ci.sh'] = ('100755', self.before['scripts/ci.sh'][1])
                with self.assertRaises(candidate.CandidateError): self.verify()

    def test_missing_protected_source_and_symbolic_links_cannot_establish_equivalence(self):
        del self.before['Core/SaveStore.swift']; del self.after['Core/SaveStore.swift']
        with self.assertRaises(candidate.CandidateError): self.verify()
        self.setUp()
        self.after['docs/link'] = ('120000', b'../App/MemoryView.swift')
        with self.assertRaises(candidate.CandidateError): self.verify()

    def test_non_ancestor_or_malformed_sha_cannot_relabel_a_screenshot(self):
        with self.assertRaises(candidate.CandidateError):
            candidate.verify_tooling_only_equivalence(self.source_sha, self.target_sha, ancestor=lambda: False)
        for sha in ['main', 'a' * 7, '', 'x' * 40, None, 123, False]:
            with self.subTest(sha=sha), self.assertRaises(candidate.CandidateError):
                candidate.verify_tooling_only_equivalence(sha, self.target_sha)


if __name__ == '__main__':
    unittest.main()
