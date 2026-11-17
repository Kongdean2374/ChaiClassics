#!/usr/bin/env python3
"""Source-bound XCTest selections; 'full' emits no filter and retains every test."""
import json
from pathlib import Path
import re
import subprocess
import sys

V = 'ChaiClassicsUITests/ChaiClassicsV020UITests/'
L = 'ChaiClassicsUITests/ChaiClassicsUITests/'
S = 'ChaiClassicsUITests/ChaiClassicsVisualSmokeTests/'
SESSION_LIFECYCLE_TESTS = {
    'sudoku': 'testSudokuCommonSessionLifecycleAndContinueDeletion',
    'mines': 'testMinesweeperCommonSessionLifecycleAndContinueDeletion',
    'sliding': 'testSlidingCommonSessionLifecycleAndContinueDeletion',
    'tictactoe': 'testTicTacToeCommonSessionLifecycleAndContinueDeletion',
    'connectfour': 'testConnectFourCommonSessionLifecycleAndContinueDeletion',
    'twentyfour': 'testTwentyFourCommonSessionLifecycleAndContinueDeletion',
    'memory': 'testMemoryCommonSessionLifecycleAndContinueDeletion',
    'maze': 'testMazeCommonSessionLifecycleAndContinueDeletion',
}
HISTORY_TEST = 'testPlayHistorySearchDismissesKeyboardWithoutSwallowingActions'
SESSION_VISUAL_TESTS = tuple(SESSION_LIFECYCLE_TESTS.values()) + (HISTORY_TEST,)
SESSION_RUNTIME_FILES = ('App/GameSessionComponents.swift', 'Core/GameSessionData.swift')
EXPANDED_RUNTIME_FILES = ('App/ExpandedGameMenuView.swift', 'Core/ExpandedGameSave.swift')
EXPANDED_SESSION_TESTS = {
    game: 'test' + title + 'CompleteSessionRestoresAndConfirmsDeletion'
    for game, title in (
        ('nonogram','Nonogram'),('kakuro','Kakuro'),('klotski','Klotski'),
        ('gomoku','Gomoku'),('reversi','Reversi'),('xiangqi','Xiangqi'),
        ('banqi','Banqi'),('chess','Chess'),('shogi','Shogi'),
        ('klondike','Klondike'),('spider','Spider'),('freecell','Freecell'),
        ('pyramid','Pyramid'),('tripeaks','Tripeaks'),('snake','Snake'),
        ('fallingblocks','FallingBlocks'),('brickbreaker','BrickBreaker'))
}
PART_SCOPES = {f'part_{name}': index for index, name in enumerate('abcd')}
SCOPES = {
    'full': [],
    'beta': [S + SESSION_LIFECYCLE_TESTS['sudoku'], S + SESSION_LIFECYCLE_TESTS['sliding'], S + HISTORY_TEST],
    'sliding': [L + 'testSlidingCanStartAndRestore',
                L + 'testSlidingSwipesInAllFourDirectionsAndRestoresExactlyOneMove',
                S + 'testFreshWinCelebratesOnceAndRestoredWinDoesNotReplay'],
    'memory': [V + 'testMemoryRestoresMatchesHidesUnturnedCardsCompletesAndReplays',
               V + 'testCorruptNewSaveRecoveryPreservesAllThreeLegacySaves',
               V + 'testNewPuzzleModesStartRealBoards', V + 'testMemoryFlipMismatchGatesAndReducedMotionPreserveNativeCards'],
    'tictactoe': [V + 'testTicTacToeLocalRoundRestoresWinsAndReplays', V + 'testTicTacToeAIRepliesAtEveryDifficultyWithEitherFirstPlayer', V + 'testBoardGameThinkingAndDropGatesRejectExtraInput'],
    'connectfour': [V + 'testConnectFourLocalRoundRestoresWinsAndReplays', V + 'testConnectFourAIRepliesAtEveryDifficultyWithEitherFirstPlayer', V + 'testBoardGameThinkingAndDropGatesRejectExtraInput'],
    'twentyfour': [V + 'testTwentyFourRestoresExactCardsCompletesAndStartsNextPuzzle', V + 'testTwentyFourOrderedInputHistoryAndZeroDivision'],
    'maze': [V + 'testMazeRestoresPositionResumesCompletesAndGeneratesNextMaze', V + 'testMazeJoystickMovesContinuouslyStopsAndRestoresCell'],
    'catalog': [V + name for name in ['testCompleteCatalogAndThirteenComingSoonPagesInEnglish',
               'testCompleteCatalogAndThirteenComingSoonPagesInTraditionalChinese', 'testAllEightPlayableCardsOpenRealMenus',
               'testCatalogLayoutAt320PointViewport', 'testCatalogLayoutAt375PointViewport',
               'testCatalogLayoutAt390PointViewport', 'testCatalogLayoutAt430PointViewport',
               'testAccessibilityTypeAdaptsCatalogAndSupportsReducedMotion']],
    'legacy': ['ChaiClassicsUITests/ChaiClassicsUITests'],
}
for game, method in SESSION_LIFECYCLE_TESTS.items():
    if game in SCOPES:
        SCOPES[game].append(S + method)
    if game in ('sudoku', 'mines', 'sliding'):
        SCOPES['legacy'].append(S + method)
SCOPES['catalog'].append(S + HISTORY_TEST)
SCOPES['expanded'] = ['ChaiClassicsUITests/ChaiClassicsV030UITests/' + name for name in EXPANDED_SESSION_TESTS.values()]
for game,name in EXPANDED_SESSION_TESTS.items():
    SCOPES[game] = ['ChaiClassicsUITests/ChaiClassicsV030UITests/' + name]


def required_session_tests(root):
    """Keep released source fixtures verifiable, but require every new runtime journey."""
    return required_session_tests_for_paths(path for path in SESSION_RUNTIME_FILES + EXPANDED_RUNTIME_FILES if (root / path).is_file())


def required_session_tests_for_paths(paths):
    present = set(paths)
    required = {'ChaiClassicsVisualSmokeTests/' + name for name in SESSION_VISUAL_TESTS} if set(SESSION_RUNTIME_FILES).intersection(present) else set()
    if set(EXPANDED_RUNTIME_FILES).intersection(present):
        required.update('ChaiClassicsV030UITests/' + name for name in EXPANDED_SESSION_TESTS.values())
    return required

def resolve(scope, tests, *, include_sessions=True):
    if scope == 'beta' and not include_sessions:
        raise ValueError('Beta scope requires the shared session runtime and its real journeys.')
    if scope in PART_SCOPES:
        supplied = list(tests)
        if (not supplied or not all(isinstance(name, str) and re.fullmatch(r'[A-Za-z_]\w*/test\w+', name) for name in supplied)
                or len(supplied) != len(set(supplied))):
            raise ValueError('Partitions require unique declared XCTest identities.')
        ordered = sorted(supplied)
        selected = ordered[PART_SCOPES[scope]::len(PART_SCOPES)]
        if not selected:
            raise ValueError('A partition must select actual XCTest cases.')
        return selected
    if scope == 'full':
        return sorted(tests)
    if scope not in SCOPES:
        raise ValueError('Unknown static UI scope.')
    selected = set()
    for selector in SCOPES[scope]:
        identity = selector.split('/', 1)[1]
        if not include_sessions and identity in {'ChaiClassicsVisualSmokeTests/' + name for name in SESSION_VISUAL_TESTS}:
            continue
        matches = {test for test in tests if test == identity or test.startswith(identity + '/')}
        if not matches:
            raise ValueError('A selected UI case is no longer declared: ' + identity)
        selected.update(matches)
    return sorted(selected)


def declared_tests(root):
    tests = [path.stem + '/' + name for path in sorted((root / 'UITests').glob('*.swift'))
             for name in re.findall(r'\bfunc\s+(test\w+)\s*\(', path.read_text())]
    if not tests or len(tests) != len(set(tests)) or not required_session_tests(root).issubset(tests):
        raise ValueError('Missing, duplicate or incomplete source-declared XCTest inventory.')
    return sorted(tests)


def affected_selectors():
    root = Path(__file__).resolve().parents[1]
    plan = json.loads((root / 'build/ui-scope-plan.json').read_text())
    sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    tests = plan.get('tests')
    if plan.get('source_commit') != sha or not isinstance(tests, list) or not tests or not all(isinstance(test, str) for test in tests) or len(set(tests)) != len(tests):
        raise ValueError('Missing, empty or stale affected-case plan.')
    declared = {path.stem + '/' + name for path in (root / 'UITests').glob('*.swift')
                for name in re.findall(r'\bfunc\s+(test\w+)\s*\(', path.read_text())}
    if not all(isinstance(test, str) and test in declared for test in tests):
        raise ValueError('Affected plan contains an undeclared case.')
    return ['ChaiClassicsUITests/' + test for test in tests]


def main(argv):
    if len(argv) == 1 and argv[0] in PART_SCOPES:
        try:
            selected = resolve(argv[0], declared_tests(Path(__file__).resolve().parents[1]))
        except (OSError, ValueError) as error:
            print('Cannot select source partition: ' + str(error), file=sys.stderr)
            return 64
        for method in selected:
            print('-only-testing:ChaiClassicsUITests/' + method)
        return 0
    if argv == ['affected']:
        try:
            methods = affected_selectors()
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            print('Cannot select affected UI cases: ' + str(error), file=sys.stderr)
            return 64
        for method in methods:
            print('-only-testing:' + method)
        return 0
    if len(argv) != 1 or argv[0] not in SCOPES:
        print('Unknown UI scope; choose a listed workflow option.', file=sys.stderr)
        return 64
    for method in SCOPES[argv[0]]:
        print('-only-testing:' + method)
    return 0

if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
