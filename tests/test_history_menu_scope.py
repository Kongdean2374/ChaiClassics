"""Retain exact unvisited-menu cases; exercised history and unknown code rerun.

Fixtures prove dependency boundaries, never supply native XCTest results.
"""
from pathlib import Path
import hashlib
import subprocess
import sys
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import verify_scoped_ci as scoped
import verify_candidate as candidate


class HistoryMenuScopeTests(unittest.TestCase):
    path = 'App/PlayHistoryView.swift'

    @classmethod
    def setUpClass(cls):
        sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        cls.after = scoped.historical.git_tree(sha)
        # Read actual audited runtime/UI sources, including while developing a
        # pure verifier update. Production reads immutable Git trees only.
        cls.after[cls.path] = ('100644', (ROOT / cls.path).read_bytes())
        for path in (ROOT / 'UITests').glob('*.swift'):
            cls.after[str(path.relative_to(ROOT))] = ('100644', path.read_bytes())
        before_hash, after_hash, old_block, new_block, inserted = scoped.APPROVED_HISTORY_MENU
        new = cls.after[cls.path][1].decode()
        old = new.replace(new_block, old_block, 1).replace(inserted, '', 1)
        assert hashlib.sha256(old.encode()).hexdigest() == before_hash
        assert hashlib.sha256(new.encode()).hexdigest() == after_hash
        cls.before = dict(cls.after)
        cls.before[cls.path] = ('100644', old.encode())

    def test_only_eight_catalog_cases_and_four_phone_captures_retain_their_dependencies(self):
        before, after = scoped.fingerprints(self.before), scoped.fingerprints(self.after)
        same = {name for name in before if before[name] == after[name]}
        self.assertEqual(same, set(scoped.HISTORY_UNVISITED_BODIES))
        self.assertEqual(len(same), 12)
        self.assertTrue(set(candidate.VISUAL_FOCUS_TESTS).issubset(same))
        self.assertEqual(len(before), 71)
        self.assertNotEqual(before['ChaiClassicsVisualSmokeTests/testPlayHistorySearchDismissesKeyboardWithoutSwallowingActions'],
                            after['ChaiClassicsVisualSmokeTests/testPlayHistorySearchDismissesKeyboardWithoutSwallowingActions'])
        for game, method in scoped.scopes.EXPANDED_SESSION_TESTS.items():
            name = 'ChaiClassicsV030UITests/' + method
            self.assertNotEqual(before[name], after[name], game + ' visits the real history screen')

    def test_exact_forward_projection_protects_all_shared_formatting_and_other_view_bytes(self):
        source = self.before[self.path][1].decode()
        current = self.after[self.path][1].decode()
        anchor = '@MainActor enum GameRecordText {'
        self.assertEqual(source[source.index(anchor):], current[current.index(anchor):])
        for changed in [current + '\nlet unreviewedGlobal = 1\n',
                        current.replace('let value = max(0, seconds)', 'let value = max(1, seconds)'),
                        current.replace('searching = false', 'searching = true', 1)]:
            updated = dict(self.after)
            updated[self.path] = ('100644', changed.encode())
            before, after = scoped.fingerprints(self.before), scoped.fingerprints(updated)
            self.assertTrue(all(before[name] != after[name] for name in before))

    def test_unknown_runtime_changes_on_both_sides_cannot_borrow_the_history_audit(self):
        for path in ['App/AppModel.swift', 'App/UITestBootstrap.swift', 'App/UnknownHistoryHook.swift',
                     'Core/SaveStore.swift', 'UITests/Fixtures/injected.json']:
            before, after = dict(self.before), dict(self.after)
            mode, raw = before.get(path, ('100644', b''))
            before[path] = after[path] = (mode, raw + b'\n// additional runtime\n')
            a, b = scoped.fingerprints(before), scoped.fingerprints(after)
            with self.subTest(path=path):
                self.assertTrue(all(a[name] != b[name] for name in scoped.HISTORY_UNVISITED_BODIES))

    def test_unknown_helpers_global_hooks_and_added_ui_files_disable_every_exemption(self):
        for path in ['UITests/ChaiClassicsUITests.swift', 'UITests/ChaiClassicsV020UITests.swift',
                     'UITests/ChaiClassicsVisualSmokeTests.swift', 'UITests/ChaiClassicsV030UITests.swift',
                     'UITests/UnknownHooks.swift']:
            before, after = dict(self.before), dict(self.after)
            mode, raw = before.get(path, ('100644', b''))
            before[path] = after[path] = (mode, raw + b'\nprivate func additionalHook() {}\n')
            a, b = scoped.fingerprints(before), scoped.fingerprints(after)
            with self.subTest(path=path):
                self.assertTrue(all(a[name] != b[name] for name in scoped.HISTORY_UNVISITED_BODIES))

    def test_a_changed_catalog_body_cannot_keep_an_old_unvisited_path_claim(self):
        before, after = dict(self.before), dict(self.after)
        path = 'UITests/ChaiClassicsV020UITests.swift'
        mode, raw = before[path]; source = raw.decode()
        name = 'testAllEightPlayableCardsOpenRealMenus'
        start, _end = scoped.historical.functions(source)[name]
        changed = (source[:start + 1] + '\napp.buttons["settings.history"].tap()\n' + source[start + 1:]).encode()
        before[path] = after[path] = (mode, changed)
        a, b = scoped.fingerprints(before), scoped.fingerprints(after)
        identity = 'ChaiClassicsV020UITests/' + name
        self.assertNotEqual(a[identity], b[identity])
        self.assertEqual(sum(a[key] == b[key] for key in scoped.HISTORY_UNVISITED_BODIES), 11)

    def test_a_forged_after_hash_cannot_bypass_the_complete_forward_content_check(self):
        changed = self.after[self.path][1] + b'\nlet globalHook = 1\n'
        pair = list(scoped.APPROVED_HISTORY_MENU)
        pair[1] = hashlib.sha256(changed).hexdigest()
        updated = dict(self.after); updated[self.path] = ('100644', changed)
        with mock.patch.object(scoped, 'APPROVED_HISTORY_MENU', tuple(pair)):
            a, b = scoped.fingerprints(self.before), scoped.fingerprints(updated)
            self.assertTrue(all(a[name] != b[name] for name in a))

    def test_wrong_history_mode_or_missing_file_does_not_retain_source_cases(self):
        a = scoped.fingerprints(self.before)
        for mode in ['100755']:
            updated = dict(self.after); updated[self.path] = (mode, updated[self.path][1])
            b = scoped.fingerprints(updated)
            self.assertTrue(all(a[name] != b[name] for name in a))
        updated = dict(self.after); del updated[self.path]
        b = scoped.fingerprints(updated)
        self.assertTrue(all(a[name] != b[name] for name in a))

    def test_actual_failed_history_is_not_covered_and_later_catalog_failures_still_override(self):
        old, new = scoped.fingerprints(self.before), scoped.fingerprints(self.after)
        catalog = sorted(name for name in scoped.HISTORY_UNVISITED_BODIES if name.startswith('ChaiClassicsV020UITests/'))
        history = 'ChaiClassicsVisualSmokeTests/testPlayHistorySearchDismissesKeyboardWithoutSwallowingActions'
        source = {'run_id': 1, 'sha': 'a' * 40, 'fingerprints': old,
                  'actual': {**{name: 'passed' for name in catalog}, history: 'failed'}}
        coverage = scoped.inherited_coverage(new, [source])
        self.assertEqual(set(coverage), set(catalog))
        self.assertTrue(all(scoped.covered(name, coverage[name]) for name in catalog))
        self.assertIn(history, scoped.planned_tests(new, [source]))
        newer = {'run_id': 2, 'sha': 'b' * 40, 'fingerprints': new, 'actual': {catalog[0]: 'failed'}}
        self.assertIn(catalog[0], scoped.planned_tests(new, [source, newer]))


if __name__ == '__main__':
    unittest.main()
