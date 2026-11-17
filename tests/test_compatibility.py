import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import check_compatibility as compatibility


def puzzle(difficulty, number, digit=0):
    return {'id': f'sudoku.{difficulty}.{number:04d}', 'difficulty': difficulty,
            'number': number, 'givens': [digit] * 81}


class CompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.previous = [puzzle('easy', 1), puzzle('easy', 2), puzzle('medium', 1), puzzle('hard', 1)]
        self.sha = 'a' * 40

    def test_unchanged_and_per_difficulty_append_are_accepted(self):
        self.assertEqual(compatibility.compare_puzzles(self.previous, self.previous), {'existing': 4, 'appended': 0})
        current = self.previous + [puzzle('easy', 3), puzzle('easy', 4), puzzle('medium', 2), puzzle('hard', 2)]
        self.assertEqual(compatibility.compare_puzzles(self.previous, current), {'existing': 4, 'appended': 4})

    def test_removed_and_rewritten_released_records_are_rejected(self):
        variants = [self.previous[1:], copy.deepcopy(self.previous)]
        variants[1][0]['givens'][0] = 1
        for current in variants:
            with self.assertRaises(compatibility.CompatibilityError):
                compatibility.compare_puzzles(self.previous, current)

    def test_duplicate_ids_cannot_be_hidden_by_dictionary_indexing(self):
        for previous, current in [(self.previous + [self.previous[0]], self.previous),
                                  (self.previous, self.previous + [self.previous[0]])]:
            with self.assertRaisesRegex(compatibility.CompatibilityError, 'duplicate stable ID'):
                compatibility.compare_puzzles(previous, current)

    def test_lower_numbers_insertion_and_reordering_are_rejected(self):
        previous = [puzzle('easy', 1), puzzle('easy', 3), puzzle('medium', 1)]
        cases = [
            previous + [puzzle('easy', 2)],
            previous + [puzzle('easy', 5), puzzle('easy', 4)],
            [previous[2], previous[0], previous[1]],
            [previous[0], puzzle('easy', 2), previous[1], previous[2]],
        ]
        for current in cases:
            with self.assertRaises(compatibility.CompatibilityError):
                compatibility.compare_puzzles(previous, current)

    def test_invalid_types_numbers_ids_and_difficulty_are_rejected(self):
        mutations = [
            {'number': 0}, {'number': True}, {'number': '1'}, {'difficulty': 'future'},
            {'id': 'renamed'}, {'id': None},
        ]
        for change in mutations:
            current = copy.deepcopy(self.previous)
            current[0].update(change)
            with self.assertRaises(compatibility.CompatibilityError):
                compatibility.compare_puzzles(self.previous, current)
        for invalid in [None, {}, 'pack', [None]]:
            with self.assertRaises(compatibility.CompatibilityError):
                compatibility.compare_puzzles(self.previous, invalid)

    def test_manifest_fallback_keeps_released_clues_and_ids(self):
        manifest = [{key: value for key, value in entry.items() if key != 'givens'} |
                    {'sha256': hashlib.sha256(bytes(entry['givens'])).hexdigest()} for entry in self.previous]
        self.assertEqual(compatibility.verify_manifest(manifest, self.previous), {'existing': 4, 'appended': 0})
        for mutate in [lambda p: p.pop(), lambda p: p[0]['givens'].__setitem__(0, 2),
                       lambda p: p[0].update(givens=[False] * 81)]:
            current = copy.deepcopy(self.previous); mutate(current)
            with self.assertRaises(compatibility.CompatibilityError):
                compatibility.verify_manifest(manifest, current)

    def test_absent_or_github_initial_zero_base_uses_manifest_without_git_reads(self):
        def never(*_args):
            self.fail('No-base fallback must not invoke Git.')
        self.assertIsNone(compatibility.load_baseline('', git=never))
        self.assertIsNone(compatibility.load_baseline('0' * 40, git=never))

    def test_invalid_supplied_base_fails_instead_of_passing_as_pre_pack(self):
        for base in ['main', '--help', 'short', '0', 'g' * 40]:
            with self.assertRaisesRegex(compatibility.CompatibilityError, 'full 40-character'):
                compatibility.load_baseline(base, git=lambda *_: self.fail('Invalid SHA must fail before Git.'))
        for result in [subprocess.CompletedProcess([], 128, '', 'missing'), subprocess.CompletedProcess([], 0, 'tag\n', '')]:
            with self.assertRaisesRegex(compatibility.CompatibilityError, 'commit is unavailable'):
                compatibility.load_baseline(self.sha, git=lambda *_: result)

    def test_genuine_pre_pack_commit_is_the_only_supplied_base_fallback(self):
        calls = []
        def git(args, _root):
            calls.append(args)
            return subprocess.CompletedProcess(args, 0, 'commit\n' if args[0] == 'cat-file' else '', '')
        self.assertIsNone(compatibility.load_baseline(self.sha, git=git))
        self.assertEqual([args[0] for args in calls], ['cat-file', 'ls-tree'])

    def test_valid_base_loads_pack_and_tree_blob_errors_fail(self):
        def git(args, _root):
            outputs = {'cat-file': 'commit\n', 'ls-tree': compatibility.PACK_PATH + '\n', 'show': json.dumps(self.previous)}
            return subprocess.CompletedProcess(args, 0, outputs[args[0]], '')
        self.assertEqual(compatibility.load_baseline(self.sha, git=git), self.previous)
        for failed in ['ls-tree', 'show']:
            def broken(args, root):
                return subprocess.CompletedProcess(args, 128, '', '') if args[0] == failed else git(args, root)
            with self.assertRaises(compatibility.CompatibilityError):
                compatibility.load_baseline(self.sha, git=broken)
        def malformed(args, root):
            return subprocess.CompletedProcess(args, 0, '{invalid', '') if args[0] == 'show' else git(args, root)
        with self.assertRaisesRegex(compatibility.CompatibilityError, 'JSON is invalid'):
            compatibility.load_baseline(self.sha, git=malformed)

    def test_cli_returns_failure_for_unavailable_supplied_baseline(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / 'Core/Resources').mkdir(parents=True)
        (root / 'docs').mkdir()
        (root / compatibility.PACK_PATH).write_text(json.dumps(self.previous))
        manifest = [{key: value for key, value in entry.items() if key != 'givens'} |
                    {'sha256': hashlib.sha256(bytes(entry['givens'])).hexdigest()} for entry in self.previous]
        (root / compatibility.MANIFEST_PATH).write_text(json.dumps(manifest))
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(compatibility.main({}, root), 0)
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            result = compatibility.main({'COMPATIBILITY_BASE': self.sha}, root,
                                        git=lambda *_: subprocess.CompletedProcess([], 128, '', 'unavailable'))
        self.assertEqual(result, 1)
        self.assertIn('fetch its history', stderr.getvalue())


if __name__ == '__main__':
    unittest.main()
