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

class SelectedTestBodyEquivalenceTests(unittest.TestCase):
    source_sha = 'a' * 40
    target_sha = 'b' * 40
    ui_path = 'UITests/ChaiClassicsVisualSmokeTests.swift'
    case = 'ChaiClassicsVisualSmokeTests/testExecuted'

    def setUp(self):
        fixture = EvidenceToolingEquivalenceTests()
        fixture.setUp()
        self.before, self.after = fixture.before, fixture.after
        source = b'''import XCTest
let fixtureName = "stable fixture"
final class ChaiClassicsVisualSmokeTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func helper() { XCTAssertTrue(true, "helper") }
    func testExecuted() { helper(); XCTAssertTrue(true, "executed") }
    func testUnexecuted() { XCTAssertTrue(true, "other") }
}
'''
        for tree in (self.before, self.after):
            tree[self.ui_path] = ('100644', source)
            tree['UITests/ChaiClassicsUITests.swift'] = ('100644', b'func testLaterRepair() { XCTAssertTrue(true) }')
            tree['UITests/Fixtures/legacy.json'] = ('100644', b'{"unchanged":true}')

    def verify(self, tested_cases=None, *, strict=False):
        trees = {self.source_sha: self.before, self.target_sha: self.after}
        return candidate.verify_tooling_only_equivalence(self.source_sha, self.target_sha,
            tree_reader=lambda sha: trees[sha], ancestor=lambda: True,
            tested_cases=None if strict else ([self.case] if tested_cases is None else tested_cases))

    def edit(self, path, old, new):
        mode, data = self.after[path]
        self.after[path] = (mode, data.replace(old, new))

    def test_unexecuted_bodies_can_change_while_source_sha_and_protected_digest_stay_bound(self):
        unchanged = self.verify()
        self.edit(self.ui_path, b'XCTAssertTrue(true, "other")', b'XCTAssertTrue(false, "repaired other")')
        self.edit('UITests/ChaiClassicsUITests.swift', b'XCTAssertTrue(true)', b'XCTAssertEqual(1, 1)')
        proof = self.verify()
        self.assertEqual(proof['tested_cases'], [self.case])
        self.assertEqual(proof['source_commit'], self.source_sha)
        self.assertEqual(proof['target_commit'], self.target_sha)
        self.assertIn(self.ui_path, proof['changed_paths'])
        self.assertEqual(proof['runtime_digest'], unchanged['runtime_digest'])
        self.assertEqual(proof['runtime_scaffold_and_testbody_digest'], unchanged['runtime_scaffold_and_testbody_digest'])
        self.assertEqual(len(proof['runtime_scaffold_and_testbody_digest']), 64)
        with self.assertRaises(candidate.CandidateError): self.verify(strict=True)

    def test_executed_body_change_or_adding_other_to_protected_selection_is_rejected(self):
        self.edit(self.ui_path, b'XCTAssertTrue(true, "other")', b'XCTAssertTrue(false, "other")')
        with self.assertRaises(candidate.CandidateError):
            self.verify([self.case, 'ChaiClassicsVisualSmokeTests/testUnexecuted'])
        self.after[self.ui_path] = self.before[self.ui_path]
        self.edit(self.ui_path, b'XCTAssertTrue(true, "executed")', b'XCTAssertTrue(false, "executed")')
        with self.assertRaises(candidate.CandidateError): self.verify()

    def test_helpers_setup_constants_signatures_and_class_bytes_remain_protected(self):
        baseline = copy.deepcopy(self.after)
        for old, new in [(b'XCTAssertTrue(true, "helper")', b'XCTAssertTrue(false, "helper")'),
                         (b'continueAfterFailure = false', b'continueAfterFailure = true'),
                         (b'"stable fixture"', b'"new fixture"'),
                         (b'func testUnexecuted()', b'func testUnexecuted(_ argument: Int = 0)'),
                         (b'final class ', b'class ')]:
            self.after = copy.deepcopy(baseline)
            self.edit(self.ui_path, old, new)
            with self.subTest(change=old), self.assertRaises(candidate.CandidateError): self.verify()

    def test_ui_file_sets_modes_method_identities_and_balanced_syntax_cannot_change(self):
        baseline = copy.deepcopy(self.after)
        for mutation in ('file-add', 'file-remove', 'mode', 'method-add', 'method-remove', 'method-rename', 'duplicate', 'unbalanced'):
            self.after = copy.deepcopy(baseline)
            if mutation == 'file-add': self.after['UITests/Injected.swift'] = ('100644', b'func testInjected() {}')
            if mutation == 'file-remove': del self.after['UITests/ChaiClassicsUITests.swift']
            if mutation == 'mode': self.after[self.ui_path] = ('100755', self.after[self.ui_path][1])
            if mutation == 'method-add': self.edit(self.ui_path, b'func testUnexecuted()', b'func testAdded() {}\n    func testUnexecuted()')
            if mutation == 'method-remove': self.edit(self.ui_path, b'func testUnexecuted() { XCTAssertTrue(true, "other") }', b'')
            if mutation == 'method-rename': self.edit(self.ui_path, b'testUnexecuted', b'testRenamed')
            if mutation == 'duplicate': self.edit(self.ui_path, b'testUnexecuted', b'testExecuted')
            if mutation == 'unbalanced': self.edit(self.ui_path, b'func testUnexecuted() {', b'func testUnexecuted() {{')
            with self.subTest(mutation=mutation), self.assertRaises(candidate.CandidateError): self.verify()

    def test_runtime_fixture_execution_asset_and_workflow_changes_are_rejected_in_selected_mode(self):
        baseline = copy.deepcopy(self.after)
        for path in self.before:
            if path in candidate.PURE_EVIDENCE_SCRIPTS or path.endswith('.swift') and path.startswith('UITests/'):
                continue
            self.after = copy.deepcopy(baseline)
            mode, data = self.after[path]
            self.after[path] = (mode, data + b'changed')
            with self.subTest(path=path), self.assertRaises(candidate.CandidateError): self.verify()

    def test_missing_duplicate_or_invalid_protected_case_cannot_authorize_reuse(self):
        for cases in [[], [self.case, self.case], ['Unknown/testInvented'], ['not-a-case'], [123], 'Class/testString']:
            with self.subTest(cases=cases), self.assertRaises(candidate.CandidateError): self.verify(cases)


if __name__ == '__main__':
    unittest.main()
