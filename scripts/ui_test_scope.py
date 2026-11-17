#!/usr/bin/env python3
"""Fixed XCTest selections; 'full' emits no filter and retains every test."""
import sys

V = 'ChaiClassicsUITests/ChaiClassicsV020UITests/'
L = 'ChaiClassicsUITests/ChaiClassicsUITests/'
S = 'ChaiClassicsUITests/ChaiClassicsVisualSmokeTests/'
SCOPES = {
    'full': [],
    'sliding': [L + 'testSlidingCanStartAndRestore',
                L + 'testSlidingSwipesInAllFourDirectionsAndRestoresExactlyOneMove',
                S + 'testFreshWinCelebratesOnceAndRestoredWinDoesNotReplay'],
    'memory': [V + 'testMemoryRestoresMatchesHidesUnturnedCardsCompletesAndReplays',
               V + 'testCorruptNewSaveRecoveryPreservesAllThreeLegacySaves',
               V + 'testNewPuzzleModesStartRealBoards'],
    'tictactoe': [V + 'testTicTacToeLocalRoundRestoresWinsAndReplays', V + 'testTicTacToeAIRepliesAtEveryDifficultyWithEitherFirstPlayer'],
    'connectfour': [V + 'testConnectFourLocalRoundRestoresWinsAndReplays', V + 'testConnectFourAIRepliesAtEveryDifficultyWithEitherFirstPlayer'],
    'twentyfour': [V + 'testTwentyFourRestoresExactCardsCompletesAndStartsNextPuzzle'],
    'maze': [V + 'testMazeRestoresPositionResumesCompletesAndGeneratesNextMaze'],
    'catalog': [V + name for name in ['testCompleteCatalogAndThirteenComingSoonPagesInEnglish',
               'testCompleteCatalogAndThirteenComingSoonPagesInTraditionalChinese', 'testAllEightPlayableCardsOpenRealMenus',
               'testCatalogLayoutAt320PointViewport', 'testCatalogLayoutAt375PointViewport',
               'testCatalogLayoutAt390PointViewport', 'testCatalogLayoutAt430PointViewport',
               'testAccessibilityTypeAdaptsCatalogAndSupportsReducedMotion']],
    'legacy': ['ChaiClassicsUITests/ChaiClassicsUITests'],
}

def main(argv):
    if len(argv) != 1 or argv[0] not in SCOPES:
        print('Unknown UI scope; choose a listed workflow option.', file=sys.stderr)
        return 64
    for method in SCOPES[argv[0]]:
        print('-only-testing:' + method)
    return 0

if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
