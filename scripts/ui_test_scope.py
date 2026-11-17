#!/usr/bin/env python3
"""Fixed XCTest selections; 'full' emits no filter and retains every test."""
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
SCOPES = {
    'full': [],
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


def required_session_tests(root):
    """Keep released source fixtures verifiable, but require every new runtime journey."""
    return required_session_tests_for_paths(path for path in SESSION_RUNTIME_FILES if (root / path).is_file())


def required_session_tests_for_paths(paths):
    return {'ChaiClassicsVisualSmokeTests/' + name for name in SESSION_VISUAL_TESTS} if set(SESSION_RUNTIME_FILES).intersection(paths) else set()

def resolve(scope, tests, *, include_sessions=True):
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
