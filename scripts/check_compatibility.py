#!/usr/bin/env python3
"""Verify stable puzzle identities against a real commit and the released v1 manifest.

A supplied COMPATIBILITY_BASE must name an existing commit. A missing baseline
uses the immutable release manifest; it never turns an invalid commit into a pass.
The independent solver and grading checks remain in verify_sudoku.py.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PACK_PATH = 'Core/Resources/sudoku-v1.json'
MANIFEST_PATH = 'docs/sudoku-manifest-v1.json'


class CompatibilityError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise CompatibilityError(message)


def index_puzzles(puzzles, label):
    """Reject duplicate IDs/numbers before a dictionary could hide corruption."""
    require(isinstance(puzzles, list), label + ' puzzle pack must be an array.')
    by_id = {}
    numbers = {}
    for puzzle in puzzles:
        require(isinstance(puzzle, dict), label + ' puzzle must be an object.')
        identifier, difficulty, number = (puzzle.get(key) for key in ('id', 'difficulty', 'number'))
        require(isinstance(difficulty, str) and difficulty in ('easy', 'medium', 'hard')
                and type(number) is int and number > 0, label + ' puzzle has invalid difficulty or number.')
        require(identifier == f'sudoku.{difficulty}.{number:04d}', label + ' puzzle has an invalid stable ID.')
        require(identifier not in by_id, label + ' pack contains duplicate stable ID ' + identifier + '.')
        by_id[identifier] = puzzle
        sequence = numbers.setdefault(difficulty, [])
        require(not sequence or number > sequence[-1], label + ' puzzle numbers must stay in increasing order within each difficulty.')
        sequence.append(number)
    return by_id


def compare_puzzles(previous, current):
    """Keep every released record intact and append only higher per-level numbers."""
    old = index_puzzles(previous, 'Baseline')
    new = index_puzzles(current, 'Current')
    for identifier, puzzle in old.items():
        require(identifier in new, 'Removed stable ID ' + identifier + '.')
        require(new[identifier] == puzzle, 'Modified released puzzle ' + identifier + '.')
    retained = [puzzle['id'] for puzzle in current if puzzle['id'] in old]
    require(retained == list(old), 'Released puzzle order changed; keep existing records in their original order.')
    maxima = {}
    for puzzle in previous:
        maxima[puzzle['difficulty']] = max(maxima.get(puzzle['difficulty'], 0), puzzle['number'])
    for identifier, puzzle in new.items():
        if identifier not in old:
            require(puzzle['number'] > maxima.get(puzzle['difficulty'], 0),
                    'New puzzle must append after the previous maximum for ' + puzzle['difficulty'] + '.')
    return {'existing': len(old), 'appended': len(new) - len(old)}


def verify_manifest(manifest, current):
    """The first released pack stays protected even when CI has no parent SHA."""
    released = index_puzzles(manifest, 'Release manifest')
    puzzles = index_puzzles(current, 'Current')
    for identifier, entry in released.items():
        require(identifier in puzzles, 'Removed released v1 stable ID ' + identifier + '.')
        puzzle = puzzles[identifier]
        givens = puzzle.get('givens')
        require(isinstance(givens, list) and len(givens) == 81
                and all(type(value) is int and 0 <= value <= 9 for value in givens),
                'Invalid clues for released puzzle ' + identifier + '.')
        digest = hashlib.sha256(bytes(givens)).hexdigest()
        require((puzzle['difficulty'], puzzle['number'], digest) ==
                (entry['difficulty'], entry['number'], entry.get('sha256')),
                'Modified released v1 puzzle ' + identifier + '.')
    return {'existing': len(released), 'appended': len(puzzles) - len(released)}


def git_read(arguments, root):
    return subprocess.run(['git', *arguments], cwd=root, capture_output=True, text=True, check=False)


def load_baseline(base, root=ROOT, git=git_read):
    """None means a genuine no-parent or pre-pack baseline, not an invalid ref."""
    base = base.strip()
    if not base or base == '0' * 40:
        return None
    require(re.fullmatch(r'[0-9a-fA-F]{40}', base) is not None,
            'COMPATIBILITY_BASE must be a full 40-character commit SHA.')
    kind = git(['cat-file', '-t', base], root)
    require(kind.returncode == 0 and kind.stdout.strip() == 'commit',
            'COMPATIBILITY_BASE commit is unavailable; fetch its history before verification.')
    tree = git(['ls-tree', '--name-only', base, '--', PACK_PATH], root)
    require(tree.returncode == 0, 'Could not inspect the compatibility baseline tree.')
    if not tree.stdout.strip():
        return None  # This verified commit genuinely predates the first puzzle pack.
    require(tree.stdout.strip() == PACK_PATH, 'Unexpected compatibility baseline path.')
    blob = git(['show', f'{base}:{PACK_PATH}'], root)
    require(blob.returncode == 0, 'Could not read the compatibility baseline puzzle pack.')
    try:
        puzzles = json.loads(blob.stdout)
    except ValueError:
        raise CompatibilityError('Compatibility baseline puzzle JSON is invalid.') from None
    index_puzzles(puzzles, 'Baseline')
    return puzzles


def main(environ=None, root=ROOT, git=git_read):
    environment = os.environ if environ is None else environ
    try:
        current = json.loads((root / PACK_PATH).read_text())
        manifest = json.loads((root / MANIFEST_PATH).read_text())
        fallback = verify_manifest(manifest, current)
        baseline = load_baseline(environment.get('COMPATIBILITY_BASE', ''), root, git)
        result = fallback if baseline is None else compare_puzzles(baseline, current)
    except (CompatibilityError, OSError, ValueError, subprocess.SubprocessError) as error:
        reason = str(error) if isinstance(error, CompatibilityError) else 'Required puzzle or Git baseline data could not be read.'
        print('Compatibility failed: ' + reason, file=sys.stderr)
        return 1
    source = 'immutable released v1 manifest' if baseline is None else 'actual base commit and immutable v1 manifest'
    print(f'Compatibility passed against {source}: {result["existing"]} existing IDs unchanged; {result["appended"]} appended.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
