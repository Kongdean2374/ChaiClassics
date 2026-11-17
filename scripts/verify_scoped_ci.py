#!/usr/bin/env python3
"""Accumulate real per-case UI evidence only while its strict source fingerprint matches.

Partial coverage is a diagnostic success, never release authorization. All GitHub operations
are reads; full Core/build checks and final exact-SHA visual/iPad evidence remain required.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from xml.parsers.expat import ExpatError

import ui_test_scope as scopes
import verify_candidate as candidate
import verify_incremental_ci as historical

require = candidate.require
BRANCHES = ('main', 'develop/0.2.0', 'develop/0.2.1', 'develop/0.2.2', 'develop/0.3.0')
MAX_RUNS = 20
FAST_SENTINEL = 'ChaiClassicsUITests/testHomeHasExactlyThreeColumns'
ZOOM_BOARD_FILE = 'App/ZoomBoard.swift'
PRIVACY_MANIFEST_FILE = 'App/Resources/PrivacyInfo.xcprivacy'
# Exact reviewed XML bytes: 9d74409's UserDefaults-only declaration, then the
# declaration-only addition of the already used relative SystemBootTime API.
APPROVED_PRIVACY_MANIFESTS = {
    '6452295a6ad29254c92c668038f2c6a2cfd440c07cda81f814e996ac215b8415': False,
    '23ac8b6d794ba1806448fbc70f698f6864d32bbf8ba339af668b63dc44383947': True,
}
PRIVACY_GAMEPLAY_DIGEST = '6452295a6ad29254c92c668038f2c6a2cfd440c07cda81f814e996ac215b8415'
# Exact audited script pairs differing only in the maximum XCTest allowance.
# Defaults, enabled timeouts, selectors, Simulator arguments and exit handling
# are identical. A real pass at the earlier ceiling remains a real pass;
# failed/missing cases still cannot carry forward. Any other edit fails closed.
APPROVED_TIMEOUT_CEILINGS = {
    'scripts/ci.sh': (
        'c7165f3cb81c288364f151aa637bb0b9f1477631d833d20941484de54b20433a',
        '2e1252ec7bd4cd555a4320b85626bf754d14877c71b5326e80a1abdbb92d25bd', 600),
    'scripts/ipad_screenshots.sh': (
        '84ab95e08fd2103f38e03e741e79db1b74ba6f1263862b8a5fd18916db839f87',
        '7978a7bd5c9d6e7336a80b7fd84abef7271581239e3e4015c1e39fea66abd00e', 720),
}
# Exact CI-only preflight addition. It warms the already selected device, before
# the unchanged XCTest command. No erase, retry, selectors or result handling.
# Both complete source hashes and removal back to the exact baseline are required.
APPROVED_CI_BOOTSTRAP = (
    '2e1252ec7bd4cd555a4320b85626bf754d14877c71b5326e80a1abdbb92d25bd',
    '99d12fc7647d1d9d9cba8b2fb486f5e709dfbf7649625498cc9d8476eb49daef',
    b'# CHAI_CI_EXPLICIT_BOOT_V1: selected-device-only, no erase or test retry.\n# The real part_a run failed before any case began while XCTest waited for AX.\n# Warm the same Simulator before starting its automation session, as Visual Smoke does.\nCHAI_SIM_UDID="${CHAI_SIM_DESTINATION##*,id=}"\nmkdir -p build\nxcrun simctl bootstatus "$CHAI_SIM_UDID" -b 2>&1 | tee build/simulator-boot.log\nopen -a Simulator --args -CurrentDeviceUDID "$CHAI_SIM_UDID"\n')
GAME_FILES = {
    'sudoku': {'Core/Sudoku.swift', 'App/SudokuView.swift'},
    'mines': {'Core/Minesweeper.swift', 'App/MinesView.swift', ZOOM_BOARD_FILE},
    'sliding': {'Core/SlidingPuzzle.swift', 'Core/SlidingInput.swift', 'App/SlidingView.swift'},
    'tictactoe': {'Core/TicTacToe.swift', 'App/TicTacToeView.swift'},
    'connectfour': {'Core/ConnectFour.swift', 'Core/ConnectFourPresentation.swift', 'App/ConnectFourView.swift'},
    'twentyfour': {'Core/TwentyFour.swift', 'Core/TwentyFourInput.swift', 'Core/Rational.swift', 'App/TwentyFourView.swift'},
    'memory': {'Core/MemoryMatch.swift', 'App/MemoryView.swift'},
    'maze': {'Core/Maze.swift', 'Core/MazeMotion.swift', 'App/MazeView.swift'},
}
# Reviewed 0.3.0 views expose no global extensions or static hooks. Family
# renderers and the shared new-game menu belong to every consuming game.
for game, engine, family in (
    ('nonogram','Nonogram','Puzzle'),('kakuro','Kakuro','Puzzle'),('klotski','Klotski','Puzzle'),
    ('gomoku','Gomoku','Strategy'),('reversi','Reversi','Strategy'),('xiangqi','Xiangqi','Strategy'),
    ('banqi','Banqi','Strategy'),('chess','Chess','Strategy'),('shogi','Shogi','Strategy'),
    ('klondike','Solitaire','Solitaire'),('spider','Solitaire','Solitaire'),('freecell','Solitaire','Solitaire'),
    ('pyramid','Solitaire','Solitaire'),('tripeaks','Solitaire','Solitaire'),('snake','Snake','Arcade'),
    ('fallingblocks','FallingBlocks','Arcade'),('brickbreaker','BrickBreaker','Arcade')):
    GAME_FILES[game] = {'Core/' + engine + '.swift', 'App/Expanded' + family + 'View.swift', 'App/ExpandedGameMenuView.swift'}
ALL_GAME_FILES = set().union(*GAME_FILES.values())
SHARED_SESSION_FILES = {
    'App/AppModel.swift', 'App/ChaiClassicsApp.swift', 'App/GameSessionComponents.swift',
    'App/GameSettingsView.swift', 'App/PlayHistoryView.swift', 'App/GameDataDocument.swift',
    'App/NewGameComponents.swift', 'Core/GameSessionData.swift', 'Core/GamePlayPreferences.swift',
    'Core/GameDataArchive.swift', 'Core/GameDataTransferStore.swift',
}

# Reviewed flows only: an edited or unknown mixed body falls back to every game.
# All Core files remain shared: startup/fixtures can restore every game even on Home.
# Shared helpers, fixtures, assets, preferences and animation clocks remain shared.
BODY_PROFILES = {
    'ChaiClassicsUITests/testHomeHasExactlyThreeColumns': (
        '927bb66520b4a9b6b8f266592efd0e33775b6b9754e3802566ce5b39c558ecd0', ()),
    'ChaiClassicsUITests/testLegacyFlagModeStillRevealsOnSingleTap': (
        '6c58baae7146279029c2026199016aaeb7bdabb5ee70009f17f5e835f80f9ad1', ('sudoku', 'mines', 'sliding')),
    'ChaiClassicsUITests/testThemeLanguagePreferencesAndLegacySummariesPersist': (
        '6205cb7e0011e46bdcb7eba4369c41fdd2b816afd7780acac8e3ce8d1d3995d3', ('sudoku', 'mines', 'sliding')),
    'ChaiClassicsUITests/testEnglishIsAppliedToAllGamesAndAccessibility': (
        '3bb3ee5d9d4505574d479f1731032805e3772d507318d6ecb131ea7ea47de454', ('sudoku', 'mines', 'sliding')),
    'ChaiClassicsUITests/testBundledLegalAndSupportInBothLanguages': (
        '09861290de9e19b9a5544e2f30d10f99218615b4eb7e3e2673fb6f2567670e7f', ()),
    'ChaiClassicsV020UITests/testCompleteCatalogAndThirteenComingSoonPagesInEnglish': (
        'efb196fb65141eb89d33a365a76e44865a680c822600206f9eec5acc601df9fe', ('nonogram', 'kakuro', 'klotski', 'gomoku', 'reversi', 'xiangqi', 'banqi', 'chess', 'shogi', 'klondike', 'spider', 'freecell', 'pyramid', 'tripeaks', 'snake', 'fallingblocks', 'brickbreaker')),
    'ChaiClassicsV020UITests/testCompleteCatalogAndThirteenComingSoonPagesInTraditionalChinese': (
        '49bae2235581390c0a5e46680bb9f687424c105a42f164d56944dc7f7653adda', ('nonogram', 'kakuro', 'klotski', 'gomoku', 'reversi', 'xiangqi', 'banqi', 'chess', 'shogi', 'klondike', 'spider', 'freecell', 'pyramid', 'tripeaks', 'snake', 'fallingblocks', 'brickbreaker')),
    'ChaiClassicsV020UITests/testAllEightPlayableCardsOpenRealMenus': (
        '6eec36cee283ee14ba5fef2b7325880d65b2625a29cc48b9df942a6a9bab7559', ('sudoku', 'mines', 'sliding', 'tictactoe', 'connectfour', 'twentyfour', 'memory', 'maze', 'nonogram', 'kakuro', 'klotski', 'gomoku', 'reversi', 'xiangqi', 'banqi', 'chess', 'shogi', 'klondike', 'spider', 'freecell', 'pyramid', 'tripeaks', 'snake', 'fallingblocks', 'brickbreaker')),
    'ChaiClassicsV020UITests/testNewPuzzleModesStartRealBoards': (
        '660c3dd75917b4f42f62093f1bcec423a0196a425d5b1ae31072d1ad71168f13', ('twentyfour', 'memory', 'maze')),
    'ChaiClassicsV020UITests/testCorruptNewSaveRecoveryPreservesAllThreeLegacySaves': (
        '5a3b6f9296906861f9b3ef46d72f8462675d5834ed1f6d2ffb5be3fa225a534a', ('sudoku', 'mines', 'sliding', 'memory')),
    'ChaiClassicsV020UITests/testFutureSchemaRemainsProtectedAcrossRelaunch': (
        '76e37e79752b099450f43f29905948adb73f9d86265074a86465ca723d8214d8', ('memory', 'sliding')),
    'ChaiClassicsV020UITests/testCatalogLayoutAt320PointViewport': (
        '2abbc9a2e4cb5015df14e5a6c8fb145f41178430e451d97f63ab8abac7844f40', ()),
    'ChaiClassicsV020UITests/testCatalogLayoutAt375PointViewport': (
        'f32d2b9e8880d30177c959425c09bb7fdf83f2a759af7ab6cd63202c8dda443e', ()),
    'ChaiClassicsV020UITests/testCatalogLayoutAt390PointViewport': (
        '7f67ebf94089c5e2f7338e1a2c527b736343f3fbe03dc67c59b5ddc9fb43352b', ()),
    'ChaiClassicsV020UITests/testCatalogLayoutAt430PointViewport': (
        '8d5c69b188ea4db8ea9f44b528a4d3c580bcb101ff3dad88c68728cddbdaa00c', ()),
    'ChaiClassicsV020UITests/testAccessibilityTypeAdaptsCatalogAndSupportsReducedMotion': (
        '3f4bc97949c1db678c664a3e3b8590abc865fc0561ed0aa7162299b54d82593b', ()),
    'ChaiClassicsVisualSmokeTests/testFreshWinCelebratesOnceAndRestoredWinDoesNotReplay': (
        'ab8fb0bcfdd3660120c3ec452c77a9e2e6d0962a33238eef079ae068258baf4e', ('sliding',)),
    'ChaiClassicsVisualSmokeTests/testReducedMotionSuppressesCelebrationButStillCompletesGame': (
        '70c41d41386e486704ba65b90e4d642b01d43d6cd44c0dd9a7606b29296139eb', ('sliding',)),
    'ChaiClassicsVisualSmokeTests/testLowPowerSuppressesCelebrationButStillCompletesGame': (
        'd61c0385dafb936cc689eb2a99a09bfa0054600f25f224fa476b2d9e75893cba', ('sliding',)),
    'ChaiClassicsVisualSmokeTests/testScreenshotGallery': (
        'f8a38dbe244404a8be9bfc98697845333bb4994c013953c3a02b56b3b8782a01', ('sudoku', 'mines', 'sliding')),
    'ChaiClassicsVisualSmokeTests/testIPadHomeScreenshot': (
        '0a295220bc79d7c54d99c7bad3f761924e0e9323d078a717e6fe4c4b5ba69397', ('klondike',)),
    'ChaiClassicsVisualSmokeTests/testIPadSudokuScreenshot': (
        '4d9a5ef4e6cb0700fedb363d282e73def865c5840ca194bc3370bb0ccbe403e9', ('sudoku',)),
    'ChaiClassicsVisualSmokeTests/testIPadMinesweeperScreenshot': (
        '6ee463fcd1df8d56d3a9017cc64c0c1148cb5f9120333beab2db18d0f1bbdb52', ('mines',)),
    'ChaiClassicsVisualSmokeTests/testIPadSlidingPuzzleScreenshot': (
        'dc44b6a2007ac9c0642246cdeef782a9dea80a7ead2fc3125db02618d8d67516', ('sliding',)),
}
PURE_EVIDENCE_SCRIPTS = {'scripts/verify_scoped_ci.py', 'scripts/verify_candidate.py'}


# Reviewed v0.2.2 Visual flows: a case body AND all shared helpers must match.
# The previous helper digest retains genuine pre-migration source provenance.
VISUAL_SCAFFOLD_DIGEST = 'a586522c98c7ddca791c5bb9b18b9b755d2899c9e607c4f1f1e8bb22afa9a74a'
PREVIOUS_VISUAL_SCAFFOLD_DIGEST = '40dfb0eaa2ebcf7f8e10b2b438ea41d25517d46af3a59128d65b3e2c0c5e397d'
SESSION_BODY_PROFILES = {
    'ChaiClassicsVisualSmokeTests/testConnectFourCommonSessionLifecycleAndContinueDeletion': (
        '9e0fc4ba55dd67eef4952176ddf79c5d38ea70eda73b4e1ca16dd2ba8402bdd5', ('connectfour', 'sliding')),
    'ChaiClassicsVisualSmokeTests/testFreshWinCelebratesOnceAndRestoredWinDoesNotReplay': (
        'ab8fb0bcfdd3660120c3ec452c77a9e2e6d0962a33238eef079ae068258baf4e', ('sliding',)),
    'ChaiClassicsVisualSmokeTests/testIPadHomeScreenshot': (
        '0a295220bc79d7c54d99c7bad3f761924e0e9323d078a717e6fe4c4b5ba69397', ('klondike',)),
    'ChaiClassicsVisualSmokeTests/testIPadMinesweeperScreenshot': (
        '6ee463fcd1df8d56d3a9017cc64c0c1148cb5f9120333beab2db18d0f1bbdb52', ('mines',)),
    'ChaiClassicsVisualSmokeTests/testIPadSlidingPuzzleScreenshot': (
        'dc44b6a2007ac9c0642246cdeef782a9dea80a7ead2fc3125db02618d8d67516', ('sliding',)),
    'ChaiClassicsVisualSmokeTests/testIPadSudokuScreenshot': (
        '4d9a5ef4e6cb0700fedb363d282e73def865c5840ca194bc3370bb0ccbe403e9', ('sudoku',)),
    'ChaiClassicsVisualSmokeTests/testLowPowerSuppressesCelebrationButStillCompletesGame': (
        'd61c0385dafb936cc689eb2a99a09bfa0054600f25f224fa476b2d9e75893cba', ('sliding',)),
    'ChaiClassicsVisualSmokeTests/testMazeCommonSessionLifecycleAndContinueDeletion': (
        '5ab88548f2be8c0a9067d5724be3dd8858bfc3e9b1a12f9c01cc37df4d925dd3', ('maze', 'sliding')),
    'ChaiClassicsVisualSmokeTests/testMemoryCommonSessionLifecycleAndContinueDeletion': (
        '4668996e5d0155662f28deac7ea6b8ddb69da149f4a5b4a913fa3380bb6637ab', ('memory', 'sliding')),
    'ChaiClassicsVisualSmokeTests/testMinesweeperCommonSessionLifecycleAndContinueDeletion': (
        '2e34e2eec5daa7d288a7531b68195f58015fdf8d0dbfba13854debadb523f41c', ('mines', 'sliding')),
    'ChaiClassicsVisualSmokeTests/testPlayHistorySearchDismissesKeyboardWithoutSwallowingActions': (
        'bc50d5283f2dd005f2bf60e7b8bdd6bc2469e5e20e5232fc78bf23c68403adf6', ('sliding',)),
    'ChaiClassicsVisualSmokeTests/testReducedMotionSuppressesCelebrationButStillCompletesGame': (
        '70c41d41386e486704ba65b90e4d642b01d43d6cd44c0dd9a7606b29296139eb', ('sliding',)),
    'ChaiClassicsVisualSmokeTests/testScreenshotGallery': (
        'f8a38dbe244404a8be9bfc98697845333bb4994c013953c3a02b56b3b8782a01', ('sudoku', 'mines', 'sliding')),
    'ChaiClassicsVisualSmokeTests/testSlidingCommonSessionLifecycleAndContinueDeletion': (
        '8fd00358e33b548c27de2427b211554980db758e27df75ac1ea72681d594c8ad', ('sliding', 'mines')),
    'ChaiClassicsVisualSmokeTests/testSudokuCommonSessionLifecycleAndContinueDeletion': (
        'f29b1f8aea7a640388d0f5a233557a0f1a8ea021ccafc2499ab316e37f98e086', ('sudoku', 'sliding')),
    'ChaiClassicsVisualSmokeTests/testTicTacToeCommonSessionLifecycleAndContinueDeletion': (
        'd5d5d41d10f25b1faeb339ddc8967935ab82bdbf881200a673240a4c26386f7b', ('tictactoe', 'sliding')),
    'ChaiClassicsVisualSmokeTests/testTwentyFourCommonSessionLifecycleAndContinueDeletion': (
        'c0b71e13e44bfabb3710c756fef51d73fced51c3b39217e69904cdf93c344268', ('twentyfour', 'sliding')),
}


def dependencies(test, body=None, *, helper_fingerprint=None):
    if test in SESSION_BODY_PROFILES:
        expected_body, games = SESSION_BODY_PROFILES[test]
        actual_body = hashlib.sha256(body.encode()).hexdigest() if isinstance(body, str) else None
        if helper_fingerprint == VISUAL_SCAFFOLD_DIGEST and actual_body == expected_body:
            return set().union(*(GAME_FILES[game] for game in games))
        if helper_fingerprint == PREVIOUS_VISUAL_SCAFFOLD_DIGEST and test in BODY_PROFILES:
            expected_body, games = BODY_PROFILES[test]
            if actual_body == expected_body:
                return set().union(*(GAME_FILES[game] for game in games))
        return ALL_GAME_FILES
    if test in BODY_PROFILES:
        expected_body, games = BODY_PROFILES[test]
        if isinstance(body, str) and hashlib.sha256(body.encode()).hexdigest() == expected_body:
            return set().union(*(GAME_FILES[game] for game in games))
        return ALL_GAME_FILES
    method = test.split('/')[-1].lower()
    if method.startswith('testboardgamethinking'):
        return GAME_FILES['tictactoe'] | GAME_FILES['connectfour']
    for game in GAME_FILES:
        if method.startswith('test' + game):
            return GAME_FILES[game]
    # Unknown/mixed journeys, catalog, settings, legal and visual checks depend on all games.
    return ALL_GAME_FILES


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def shared_content_digest(path, mode, data):
    """Project only exact audited declarations and ceiling-only execution pairs.

    Unsupported XML (including duplicate keys), reasons, modes and formatting
    retain their raw hash, as do all other execution changes. Defaults, selectors,
    enabled timeouts and failed-case treatment are never relaxed.
    """
    raw = hashlib.sha256(data).hexdigest()
    if mode == '100644' and path == 'scripts/ci.sh':
        before, after, block = APPROVED_CI_BOOTSTRAP
        if raw == after and data.count(block) == 1:
            normalized = data.replace(block, b'', 1)
            if hashlib.sha256(normalized).hexdigest() == before:
                data, raw = normalized, before
    if mode == '100644' and path in APPROVED_TIMEOUT_CEILINGS:
        before, after, ceiling = APPROVED_TIMEOUT_CEILINGS[path]
        if raw in (before, after):
            normalized = data.replace(b'-maximum-test-execution-time-allowance 1800',
                                      ('-maximum-test-execution-time-allowance ' + str(ceiling)).encode())
            if hashlib.sha256(normalized).hexdigest() == before:
                return before
    if path != PRIVACY_MANIFEST_FILE or mode != '100644' or raw not in APPROVED_PRIVACY_MANIFESTS:
        return raw
    expected_apis = [{'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryUserDefaults',
                      'NSPrivacyAccessedAPITypeReasons': ['CA92.1']}]
    if APPROVED_PRIVACY_MANIFESTS[raw]:
        expected_apis.append({'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategorySystemBootTime',
                              'NSPrivacyAccessedAPITypeReasons': ['35F9.1']})
    try:
        manifest = plistlib.loads(data)
    except (ValueError, TypeError, plistlib.InvalidFileException, ExpatError):
        return raw
    if (type(manifest) is not dict or set(manifest) != {
            'NSPrivacyTracking', 'NSPrivacyCollectedDataTypes', 'NSPrivacyAccessedAPITypes'}
            or manifest['NSPrivacyTracking'] is not False
            or manifest['NSPrivacyCollectedDataTypes'] != []
            or manifest['NSPrivacyAccessedAPITypes'] != expected_apis):
        return raw
    return PRIVACY_GAMEPLAY_DIGEST


def zoom_board_is_mines_only(tree):
    """Audit this Git tree, not the current checkout, before narrowing the helper.

    Only the reviewed two top-level types and nested host/coordinator are known.
    New consumers, globals, shared state/hooks, imports or declarations fall back
    to a shared resource until separately reviewed. Ordinary per-instance board
    layout/accessibility fixes can still be scoped to the sole Mines consumer.
    """
    if ZOOM_BOARD_FILE not in tree or tree[ZOOM_BOARD_FILE][0] != '100644':
        return False
    try:
        source = tree[ZOOM_BOARD_FILE][1].decode('utf-8')
        consumers = {path for path, (_mode, data) in tree.items()
                     if path.endswith('.swift') and path != ZOOM_BOARD_FILE
                     and re.search(r'\b(?:ZoomBoard|CenteredBoardScrollView)\b', data.decode('utf-8'))}
        mask = historical.swift_mask(source)
    except (UnicodeDecodeError, candidate.CandidateError):
        return False
    if consumers != {'App/MinesView.swift'}:
        return False
    # Mask only complete top-level bodies; any additional declaration survives
    # and prevents this exact reviewed outer structure from matching.
    outer, cursor = [], 0
    while cursor < len(mask):
        if mask[cursor] != '{':
            outer.append(mask[cursor]); cursor += 1; continue
        depth, cursor = 1, cursor + 1
        while cursor < len(mask) and depth:
            depth += (mask[cursor] == '{') - (mask[cursor] == '}'); cursor += 1
        if depth:
            return False
        outer.append('{BODY}')
    structure = (r'\s*import\s+SwiftUI\s+import\s+UIKit\s+import\s+ChaiCore\s+'
                 r'struct\s+ZoomBoard\s*<\s*Content\s*:\s*View\s*>\s*:\s*UIViewRepresentable\s*\{BODY\}\s*'
                 r'final\s+class\s+CenteredBoardScrollView\s*:\s*UIScrollView\s*\{BODY\}\s*')
    if re.fullmatch(structure, ''.join(outer)) is None:
        return False
    declarations = re.findall(r'\b(?:struct|class|enum|actor|protocol|extension)\s+(\w+)', mask)
    if declarations != ['ZoomBoard', 'HostedContent', 'Coordinator', 'CenteredBoardScrollView']:
        return False
    if (re.search(r'\b(?:static|class)\s+(?:let|var|subscript)\b', mask)
            or re.findall(r'\bstatic\s+func\s+(\w+)', mask) != ['dismantleUIView']
            or re.search(r'\bclass\s+func\b|\b(?:UserDefaults|UIApplication|NotificationCenter|ProcessInfo|FileManager|URLSession)\b', mask)
            or re.search(r'\.\s*(?:shared|standard|appearance)\b', mask)
            or any(attribute not in {'Environment', 'ViewBuilder', 'escaping'} for attribute in re.findall(r'@\s*(\w+)', mask))):
        return False
    return True


def fingerprints(tree):
    """Include literal assertions, shared helpers/resources/prefs/clocks and project/runtime tooling.

    Only known game-local views may be omitted for an unrelated journey. Every Core file
    remains shared because startup restores all games. Reviewed mixed profiles require
    their exact test body. Pure evidence tools are independently rebuilt,
    not application runtime; all other unknown source files are shared by default. Other test bodies are masked; all signatures/setup/helper
    bytes remain shared, so editing C's test body alone does not invalidate unchanged A/B.
    """
    methods, scaffolds, shared, helper_fingerprints = {}, [], [], {}
    mines_only_zoom = zoom_board_is_mines_only(tree)
    for path, (mode, data) in sorted(tree.items()):
        require(mode in ('100644', '100755'), 'Source symlinks/submodules cannot establish scoped evidence.')
        if path.startswith('UITests/') and path.endswith('.swift'):
            source = data.decode('utf-8')
            bodies = historical.functions(source)
            scaffold = source
            for name, (start, end) in sorted(bodies.items(), key=lambda item: item[1][0], reverse=True):
                if name.startswith('test'):
                    identity = Path(path).stem + '/' + name
                    require(identity not in methods, 'Duplicate UI test identity.')
                    methods[identity] = source[start:end]
                    scaffold = scaffold[:start] + '{TEST_BODY}' + scaffold[end:]
            helper_fingerprints[Path(path).stem] = hashlib.sha256(scaffold.encode()).hexdigest()
            scaffolds.append((path, mode, helper_fingerprints[Path(path).stem]))
        elif (path in SHARED_SESSION_FILES or path not in ALL_GAME_FILES or path.startswith('Core/')
              or (path == ZOOM_BOARD_FILE and not mines_only_zoom)) and path not in PURE_EVIDENCE_SCRIPTS and not path.startswith(('docs/', 'tests/')) and path != 'README.md':
            shared.append((path, mode, shared_content_digest(path, mode, data)))
    require(methods, 'No declared UI tests available for fingerprints.')
    require(scopes.required_session_tests_for_paths(tree).issubset(methods),
            'Session runtime requires all eight lifecycle journeys and the history interaction journey.')
    result = {}
    for test, body in sorted(methods.items()):
        local = [(path, tree[path][0], hashlib.sha256(tree[path][1]).hexdigest())
                 for path in sorted(dependencies(test, body, helper_fingerprint=helper_fingerprints.get(test.split('/')[0]))) if path in tree]
        result[test] = digest({'version': 1, 'shared': shared, 'helpers': scaffolds, 'local': local, 'test_body': body})
    return result


def parse_runs(value):
    if not value.strip():
        return []
    require(re.fullmatch(r'[0-9]+(?:\s*,\s*[0-9]+)*', value.strip()) is not None, 'Source runs must be positive comma-separated workflow IDs.')
    runs = [int(item) for item in value.split(',')]
    require(len(runs) <= MAX_RUNS and len(set(runs)) == len(runs) and all(run > 0 for run in runs), 'Invalid, duplicate or excessive source runs.')
    return runs


def validate_source_metadata(run, jobs, repo, run_id):
    require(run.get('id') == run_id and run.get('head_branch') in BRANCHES, 'Wrong scoped source run or branch.')
    candidate.validate_workflow_identity(run, 'ci', repo, run.get('head_sha', ''), run['head_branch'])
    require(run.get('status') == 'completed' and run.get('conclusion') in ('success', 'failure'), 'Source run has not completed.')
    entries = jobs.get('jobs', [])
    require(jobs.get('total_count') == len(entries) and {job.get('name') for job in entries} == candidate.JOBS['ci'], 'Incomplete scoped source jobs.')
    require(all(job.get('conclusion') == 'success' for job in entries if job['name'] != 'test'), 'Source tooling/codesign jobs did not pass.')
    test = next(job for job in entries if job['name'] == 'test')
    require(test.get('conclusion') in ('success', 'failure'), 'Source UI job was skipped/cancelled.')
    steps = {step.get('name'): step for step in test.get('steps', [])}
    for name in ('Verify puzzles, save compatibility and generated project', 'Run Swift game and save tests', 'Build iOS Simulator app'):
        require(steps.get(name, {}).get('conclusion') == 'success', 'Every scoped source must actually pass current verification, Core tests and build.')
    ui_steps = {'Run all iOS UI tests', 'Run selected iOS UI tests'}
    require(any(steps.get(name, {}).get('conclusion') in ('success', 'failure') for name in ui_steps), 'Source did not execute a UI step.')
    require(all(step.get('conclusion') in ('success', 'skipped') or
                (name in ui_steps and step.get('conclusion') == 'failure') for name, step in steps.items()), 'Source failed outside UI execution.')


def load_source_results(repo, run_id, read):
    return historical.load_results(repo, run_id, read, include_selection=True)


def gather_sources(repo, ids, sha, current_run, *, read=candidate.github, results_reader=None,
                   root=candidate.ROOT, tree_reader=None, ancestor=None):
    results_reader = results_reader or load_source_results
    tree_reader = tree_reader or (lambda commit: historical.git_tree(commit, root))
    ancestor = ancestor or (lambda commit: subprocess.run(['git', 'merge-base', '--is-ancestor', commit, sha], cwd=root,
                                                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0)
    pending, records = list(ids), {}
    while pending:
        run_id = pending.pop(0)
        require(type(run_id) is int and 0 < run_id < current_run, 'Only earlier workflow run IDs may supply coverage.')
        if run_id in records:
            continue
        require(len(records) < MAX_RUNS - 1, 'Scoped source chain exceeds its bounded run limit.')
        prefix = f'repos/{repo}/actions/runs/{run_id}'
        run = read(prefix)
        validate_source_metadata(run, read(prefix + '/jobs?per_page=100&filter=latest'), repo, run_id)
        commit = run.get('head_sha', '')
        require(re.fullmatch(r'[0-9a-f]{40}', commit) is not None and ancestor(commit), 'Source commit is not an ancestor of the target.')
        raw = results_reader(repo, run_id, read)
        summary, actual = raw[:2]
        selection = raw[2] if len(raw) > 2 else None
        historical.summary_matches(summary, actual)
        source_fingerprints = fingerprints(tree_reader(commit))
        require(set(actual).issubset(source_fingerprints), 'Source log contains an undeclared case.')
        require(all(status in ('passed', 'failed', 'skipped') for status in actual.values()), 'Invalid actual source status.')
        records[run_id] = {'run_id': run_id, 'sha': commit, 'summary': summary, 'actual': actual, 'fingerprints': source_fingerprints}
        if selection is not None:
            require(isinstance(selection, dict) and selection.get('source_commit') == commit,
                    'Original selected-scope report differs from the source commit.')
            prior = selection.get('source_runs', [])
            require(isinstance(prior, list) and len(prior) < MAX_RUNS and
                    all(type(value) is int and 0 < value < run_id for value in prior), 'Invalid pre-execution source index.')
            pending.extend(value for value in prior if value not in records)
            if selection.get('scope') in scopes.PART_SCOPES:
                partition = set(scopes.resolve(selection['scope'], source_fingerprints))
                require(set(actual).issubset(partition), 'Raw source cases do not belong to their source-declared partition.')
                if run.get('conclusion') == 'success':
                    require(set(actual) == partition, 'Successful source partition omitted required actual cases.')
        # A prior partial ledger is an index only. Every referenced run is independently
        # reloaded from GitHub raw results and source trees; its claimed pass is never trusted.
        artifacts = read(prefix + '/artifacts?per_page=100')
        require(artifacts.get('total_count') == len(artifacts.get('artifacts', [])), 'Incomplete source artifact list.')
        if any(item.get('name') == 'candidate-ci-evidence' for item in artifacts.get('artifacts', [])):
            artifacts['_repo'] = repo
            ledger = candidate.artifact_evidence(artifacts, 'ci', read)
            if ledger.get('schema') == 3:
                inherited = ledger.get('source_runs')
                require(isinstance(inherited, list) and len(inherited) <= MAX_RUNS and
                        all(type(value) is int and 0 < value <= run_id for value in inherited), 'Invalid source ledger index.')
                pending.extend(value for value in inherited if value != run_id and value not in records)
    return [records[key] for key in sorted(records)]


def inherited_coverage(target_fingerprints, records):
    coverage = {}
    for record in sorted(records, key=lambda item: item['run_id']):
        require(set(record['fingerprints']).issubset(target_fingerprints), 'Previously required UI cases were removed; scoped coverage cannot shrink the suite.')
        for test, status in record['actual'].items():
            if record['fingerprints'].get(test) == target_fingerprints.get(test) and test in target_fingerprints:
                # Later failures override earlier passes. A flaky or failed case must rerun.
                coverage[test] = {'status': status, 'source_run': record['run_id'], 'source_commit': record['sha'],
                                  'fingerprint': target_fingerprints[test]}
    return coverage


def covered(test, item):
    expected = 'skipped' if test.split('/')[-1] in candidate.IPAD_TESTS else 'passed'
    return item is not None and item.get('status') == expected


def planned_tests(target_fingerprints, records):
    coverage = inherited_coverage(target_fingerprints, records)
    missing = sorted(test for test in target_fingerprints if not covered(test, coverage.get(test)))
    # Never turn an empty selector into an accidentally unfiltered or fictional green run.
    return missing or [FAST_SENTINEL if FAST_SENTINEL in target_fingerprints else
                       next(test for test in sorted(target_fingerprints) if test.split('/')[-1] not in candidate.IPAD_TESTS)]


def make_evidence(sha, current_run, scope, summary, actual, tree, records):
    require(scope != 'beta' or not records, 'Beta critical UI evidence must execute directly without inherited coverage.')
    target = fingerprints(tree)
    selected = planned_tests(target, records) if scope == 'affected' else scopes.resolve(
        scope, sorted(target), include_sessions=bool(scopes.required_session_tests_for_paths(tree)))
    require(set(actual) == set(selected), 'Actual cases differ from the requested scoped selection.')
    normalized = historical.summary_matches(summary, actual)
    require(all(covered(test, {'status': status}) for test, status in actual.items()), 'Current scoped execution failed or unexpectedly skipped.')
    coverage = inherited_coverage(target, records)
    for test, status in actual.items():
        coverage[test] = {'status': status, 'source_run': current_run, 'source_commit': sha, 'fingerprint': target[test]}
    uncovered = sorted(test for test in target if not covered(test, coverage.get(test)))
    return {'schema': 3, 'kind': 'ci', 'verification': 'dependency-scoped', 'source_commit': sha, 'current_run': current_run,
            'scope': scope, 'source_runs': sorted({current_run} | {record['run_id'] for record in records}),
            'expected_tests': sorted(target), 'current_summary': normalized, 'executed_current_tests': dict(sorted(actual.items())),
            'fingerprints': target, 'coverage': dict(sorted(coverage.items())), 'uncovered_tests': uncovered, 'complete': not uncovered}


def validate_evidence(evidence, repo, sha, current_run, *, read=candidate.github, root=candidate.ROOT,
                      results_reader=None, tree_reader=None, ancestor=None):
    results_reader = results_reader or load_source_results
    require(isinstance(evidence, dict) and evidence.get('schema') == 3 and evidence.get('verification') == 'dependency-scoped', 'Unsupported scoped evidence.')
    prefix = f'repos/{repo}/actions/runs/{current_run}'
    run, jobs = read(prefix), read(prefix + '/jobs?per_page=100&filter=latest')
    validate_source_metadata(run, jobs, repo, current_run)
    candidate.validate_run(run, jobs, 'ci', repo, sha, run['head_branch'], ui_step='Run selected iOS UI tests')
    require(any(step.get('name') == 'Validate incremental candidate XCTest evidence' and step.get('conclusion') == 'success'
                for job in jobs['jobs'] if job['name'] == 'test' for step in job.get('steps', [])), 'Current scoped evidence was not captured successfully.')
    ids = evidence.get('source_runs')
    require(isinstance(ids, list) and current_run in ids and len(ids) <= MAX_RUNS, 'Missing current run or excessive source ledger.')
    records = gather_sources(repo, [value for value in ids if value != current_run], sha, current_run, read=read,
                             root=root, results_reader=results_reader, tree_reader=tree_reader, ancestor=ancestor)
    summary, actual = results_reader(repo, current_run, read)[:2]
    tree = (tree_reader or (lambda commit: historical.git_tree(commit, root)))(sha)
    rebuilt = make_evidence(sha, current_run, evidence.get('scope'), summary, actual, tree, records)
    require(evidence == rebuilt, 'Scoped ledger differs from actual raw execution, dependencies or source provenance.')
    require(rebuilt['complete'], 'Scoped coverage is partial; changed, failed or missing cases still require execution.')
    return rebuilt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('plan', 'capture'))
    parser.add_argument('--source-runs', default='')
    parser.add_argument('--scope', choices=tuple(scopes.SCOPES) + tuple(scopes.PART_SCOPES) + ('affected',))
    parser.add_argument('--summary', type=Path)
    parser.add_argument('--log', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        repo = os.environ.get('GITHUB_REPOSITORY', 'Kongdean2374/ChaiClassics')
        require(repo == 'Kongdean2374/ChaiClassics', 'Untrusted scoped repository.')
        sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=candidate.ROOT, text=True).strip()
        require(not subprocess.check_output(['git', 'diff', '--name-only', 'HEAD'], cwd=candidate.ROOT, text=True).strip(), 'Uncommitted tracked source cannot establish evidence.')
        current_run = int(os.environ['GITHUB_RUN_ID'])
        run = candidate.github(f'repos/{repo}/actions/runs/{current_run}')
        require(run.get('id') == current_run and run.get('head_branch') in BRANCHES, 'Untrusted current scope run.')
        candidate.validate_workflow_identity(run, 'ci', repo, sha, run['head_branch'])
        records = gather_sources(repo, parse_runs(args.source_runs), sha, current_run)
        tree = historical.git_tree(sha)
        if args.mode == 'plan':
            result = {'source_commit': sha, 'tests': planned_tests(fingerprints(tree), records)}
        else:
            require(args.scope is not None and args.summary is not None and args.log is not None, 'Capture requires scope and actual summary/log.')
            result = make_evidence(sha, current_run, args.scope, json.loads(args.summary.read_text()), candidate.parse_test_log(args.log.read_text()), tree, records)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    except (candidate.CandidateError, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print('Scoped evidence failed: ' + (str(error) if isinstance(error, candidate.CandidateError) else 'Required source/execution evidence is unavailable.'), file=sys.stderr)
        return 1
    if args.mode == 'capture':
        print(f"Actual current cases: {len(result['executed_current_tests'])}; complete coverage: {result['complete']}; uncovered: {len(result['uncovered_tests'])}. No full-current-run or release claim.")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
