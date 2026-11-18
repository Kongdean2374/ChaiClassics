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
        ('7978a7bd5c9d6e7336a80b7fd84abef7271581239e3e4015c1e39fea66abd00e', 'bd822a320c43f61b46b9851031406013eeaf65b35fec89ebb3a135424946436c'), 720),
}
# Exact CI-only preflight addition. It warms the already selected device, before
# the unchanged XCTest command. No erase, retry, selectors or result handling.
# Both complete source hashes and removal back to the exact baseline are required.
APPROVED_CI_BOOTSTRAP = (
    '2e1252ec7bd4cd555a4320b85626bf754d14877c71b5326e80a1abdbb92d25bd',
    '99d12fc7647d1d9d9cba8b2fb486f5e709dfbf7649625498cc9d8476eb49daef',
    b'# CHAI_CI_EXPLICIT_BOOT_V1: selected-device-only, no erase or test retry.\n# The real part_a run failed before any case began while XCTest waited for AX.\n# Warm the same Simulator before starting its automation session, as Visual Smoke does.\nCHAI_SIM_UDID="${CHAI_SIM_DESTINATION##*,id=}"\nmkdir -p build\nxcrun simctl bootstatus "$CHAI_SIM_UDID" -b 2>&1 | tee build/simulator-boot.log\nopen -a Simulator --args -CurrentDeviceUDID "$CHAI_SIM_UDID"\n')
# One audited correction to a private helper in this final XCTest class.
# Its other 54 cases cannot call this private method; only the 17 owner-class
# methods must rerun. Any other scaffold bytes/mode still invalidate globally.
APPROVED_V030_TOOLBAR_HELPER = (
    'f4c2ac8d31ad66ad5cb947667c3d84cdf109c8b955a0a5c70e0e18514812293c',
    'd9303f96ad82db23b25ac3651d9cf26d6e28ad5c981823316f6f70c1aa129cb1',
    '            if element.exists, element.isHittable, safe.contains(CGPoint(x:element.frame.midX,y:element.frame.midY)) { return }\n',
    '            if element.exists, element.isHittable {\n                let target = element.frame\n                // Navigation controls belong to the native bar, above scroll content.\n                if let navigation, navigation.frame.contains(target), window.contains(target) { return }\n                if safe.contains(CGPoint(x:target.midX,y:target.midY)) { return }\n            }\n')
APPROVED_CI_JOB_TIMEOUT = ('de7240119cf78c8f32cb1808eed6e0cffb3fb02b2c05a4ad15234ad4f4bec37f', 'eb2e8c4b0fd12b3b3298d0767706b0fceffeaf203f8a73008de4fbc933ebf815')
APPROVED_IPAD_JOB_BUDGET = ('edc902f4bfb8fd2079c4c87f8ff440e708ff05044506820e80ab39392322b1d3', '766f7ac020bafcbc3369abc4c25c4c221dd2923b125dbae47ba6cc1939e1eb92')
APPROVED_V020_CASE_ALLOWANCE = ('eb479e2277033521ebb2dd6ebe58f9ef79ef34f07d58de98f7926f7b3f74ee25', 'b6326fba442492b2927237e4fe5c5a08eb1d1d1416a5b699cd979b35e1a86fe3')
APPROVED_CI_DEFAULT_ALLOWANCE = ('99d12fc7647d1d9d9cba8b2fb486f5e709dfbf7649625498cc9d8476eb49daef', 'da404efc21b0114c9827542f46ee4a3d44583b00c9fee8e3a2f31b3d58792414')
APPROVED_IPAD_SUDOKU_ALLOWANCE = ('4d9a5ef4e6cb0700fedb363d282e73def865c5840ca194bc3370bb0ccbe403e9', '2a85dcd2a715c03fad1f19c270084bb890071650e5dada8154196b60b465e234', '        // Native Intel snapshots of 81 cells plus all controls exceed 600s.\n        // Retain every interaction and geometry assertion with a bounded case.\n        executionTimeAllowance = 1800\n')
# Only these exact twelve bodies never open PlayHistoryView. The enclosing
# helpers remain separately protected, including shared GameRecordText callers.
HISTORY_AUDITED_SCAFFOLDS = {'UITests/ChaiClassicsUITests.swift': '11c21725b0a740ed488735f4e83d431313282c00253e446c14703551278166e0', 'UITests/ChaiClassicsV020UITests.swift': 'eb479e2277033521ebb2dd6ebe58f9ef79ef34f07d58de98f7926f7b3f74ee25', 'UITests/ChaiClassicsV030UITests.swift': 'f4c2ac8d31ad66ad5cb947667c3d84cdf109c8b955a0a5c70e0e18514812293c', 'UITests/ChaiClassicsVisualSmokeTests.swift': 'a586522c98c7ddca791c5bb9b18b9b755d2899c9e607c4f1f1e8bb22afa9a74a'}
HISTORY_AUDITED_RUNTIME_DIGEST = 'be51b3b73ff97ac10096a1d9e226c3220810db156c3772aa3146d90e1f251c0c'
HISTORY_UNVISITED_BODIES = {'ChaiClassicsV020UITests/testAccessibilityTypeAdaptsCatalogAndSupportsReducedMotion': '3f4bc97949c1db678c664a3e3b8590abc865fc0561ed0aa7162299b54d82593b', 'ChaiClassicsV020UITests/testAllEightPlayableCardsOpenRealMenus': 'd7e0669876ff6a8d3e17361efdedc2e57611f32f5aba090614026ebcdcc3cfd8', 'ChaiClassicsV020UITests/testCatalogLayoutAt320PointViewport': '2abbc9a2e4cb5015df14e5a6c8fb145f41178430e451d97f63ab8abac7844f40', 'ChaiClassicsV020UITests/testCatalogLayoutAt375PointViewport': 'f32d2b9e8880d30177c959425c09bb7fdf83f2a759af7ab6cd63202c8dda443e', 'ChaiClassicsV020UITests/testCatalogLayoutAt390PointViewport': '7f67ebf94089c5e2f7338e1a2c527b736343f3fbe03dc67c59b5ddc9fb43352b', 'ChaiClassicsV020UITests/testCatalogLayoutAt430PointViewport': '8d5c69b188ea4db8ea9f44b528a4d3c580bcb101ff3dad88c68728cddbdaa00c', 'ChaiClassicsV020UITests/testCompleteCatalogAndThirteenComingSoonPagesInEnglish': '3fa34303a6fd20e54ca1f4a395bc8d2ed0f5538fc2714ab7ff7637712c8e92ed', 'ChaiClassicsV020UITests/testCompleteCatalogAndThirteenComingSoonPagesInTraditionalChinese': 'cb130d2facc1279e5b075e4d4aea3ed6bba381406a515685df7ac08f4792e378', 'ChaiClassicsVisualSmokeTests/testFreshWinCelebratesOnceAndRestoredWinDoesNotReplay': 'ab8fb0bcfdd3660120c3ec452c77a9e2e6d0962a33238eef079ae068258baf4e', 'ChaiClassicsVisualSmokeTests/testLowPowerSuppressesCelebrationButStillCompletesGame': 'd61c0385dafb936cc689eb2a99a09bfa0054600f25f224fa476b2d9e75893cba', 'ChaiClassicsVisualSmokeTests/testReducedMotionSuppressesCelebrationButStillCompletesGame': '70c41d41386e486704ba65b90e4d642b01d43d6cd44c0dd9a7606b29296139eb', 'ChaiClassicsVisualSmokeTests/testScreenshotGallery': 'f8a38dbe244404a8be9bfc98697845333bb4994c013953c3a02b56b3b8782a01'}
APPROVED_HISTORY_MENU = ('1a45577c164e464391d018c62286a56d55701c81489ddc79df931409fef00b0e', '64f62fd1126b26a0da82c87e705e13ab8d58bc4a62852ff2ee54d6ece7e3759b', '    private var filterMenu: some View {\n        Menu {\n            ForEach(HistoryFilterKind.allCases) { kind in\n                Button(model.t(kind.titleKey)) {\n                    searching = false\n                    guard presentation == nil else { return }\n                    presentation = .filter(kind)\n                }.accessibilityIdentifier("history.filter." + kind.rawValue)\n            }\n            Divider()\n            Button(model.t("history.resetFilters"), action: resetFilters)\n        } label: {\n            Label(model.t("history.filters"), systemImage: "line.3.horizontal.decrease.circle")\n        }.accessibilityIdentifier("history.filters")\n            .simultaneousGesture(TapGesture().onEnded { searching = false })\n    }\n', '    private var filterMenu: some View {\n        HistoryFilterMenu(title: model.t("history.filters"),\n            choices: HistoryFilterKind.allCases.map { ($0.rawValue, model.t($0.titleKey)) },\n            resetTitle: model.t("history.resetFilters"),\n            onOpen: { searching = false },\n            onSelect: { value in\n                searching = false\n                guard presentation == nil, let kind = HistoryFilterKind(rawValue: value) else { return }\n                presentation = .filter(kind)\n            }, onReset: resetFilters)\n            .frame(width: 44, height: 44)\n    }\n', '/// Observe the native menu-opening event. SwiftUI tap gestures can be cancelled\n/// when UIKit presents the menu, leaving the search field as first responder.\nprivate struct HistoryFilterMenu: UIViewRepresentable {\n    let title: String\n    let choices: [(String, String)]\n    let resetTitle: String\n    let onOpen: () -> Void\n    let onSelect: (String) -> Void\n    let onReset: () -> Void\n\n    func makeCoordinator() -> Coordinator { Coordinator() }\n    func makeUIView(context: Context) -> UIButton {\n        let button = UIButton(type: .system)\n        var configuration = UIButton.Configuration.plain()\n        configuration.image = UIImage(systemName: "line.3.horizontal.decrease.circle")\n        button.configuration = configuration\n        button.showsMenuAsPrimaryAction = true\n        button.accessibilityIdentifier = "history.filters"\n        button.addTarget(context.coordinator, action: #selector(Coordinator.openingMenu(_:)), for: .menuActionTriggered)\n        return button\n    }\n    func updateUIView(_ button: UIButton, context: Context) {\n        let coordinator = context.coordinator\n        coordinator.onOpen = onOpen; coordinator.onSelect = onSelect; coordinator.onReset = onReset\n        button.accessibilityLabel = title\n        let signature = [title, resetTitle] + choices.flatMap { [$0.0, $0.1] }\n        // A focus update must not replace a menu that UIKit is opening.\n        guard signature != coordinator.signature else { return }\n        coordinator.signature = signature\n        let filters: [UIMenuElement] = choices.map { value, label in\n            UIAction(title: label, identifier: UIAction.Identifier("history.filter." + value)) { _ in\n                coordinator.onSelect?(value)\n            }\n        }\n        let reset = UIAction(title: resetTitle) { _ in coordinator.onReset?() }\n        button.menu = UIMenu(children: filters + [UIMenu(options: .displayInline, children: [reset])])\n    }\n    @MainActor final class Coordinator: NSObject {\n        var signature: [String] = []\n        var onOpen: (() -> Void)?\n        var onSelect: ((String) -> Void)?\n        var onReset: (() -> Void)?\n        @objc func openingMenu(_ button: UIButton) {\n            button.window?.endEditing(true)\n            onOpen?()\n        }\n    }\n}\n\n')
# Exact additive dependency-partition support; existing selectors/actions stay protected.
APPROVED_DEPENDENCY_PARTITIONS = {'.github/workflows/ci.yml': ('eb2e8c4b0fd12b3b3298d0767706b0fceffeaf203f8a73008de4fbc933ebf815', '0d66bf3889abdfe3ec51570d925786060721b387614613ba082d9f5d8d60d1bc', ((b"          Path('ui-selection.json').write_text(json.dumps({'scope': os.environ['CHAI_UI_SCOPE'], 'source_commit': os.environ['GITHUB_SHA'], 'source_runs': parse_runs(os.environ['CHAI_CI_SOURCE_RUNS'])}) + '\\n')\n", b"          from ui_test_scope import PART_SCOPES\n          scope = os.environ['CHAI_UI_SCOPE']\n          runs = parse_runs(os.environ['CHAI_CI_SOURCE_RUNS'])\n          selection = {'scope': scope, 'source_commit': os.environ['GITHUB_SHA'], 'source_runs': runs}\n          if scope in PART_SCOPES and runs:\n              selection['partition'] = 'affected-v1'\n          Path('ui-selection.json').write_text(json.dumps(selection) + '\\n')\n"), (b"        if: inputs.full_ui == true && env.CHAI_UI_SCOPE == 'affected'\n", b"        if: inputs.full_ui == true && (env.CHAI_UI_SCOPE == 'affected' || (startsWith(env.CHAI_UI_SCOPE, 'part_') && inputs.baseline_run != ''))\n"))), 'scripts/ui_test_scope.py': ('2ae25b203d1ea6046eb03d10bc2216a6dd8f2f1dda360898a330522aee119918', '8ffc23ee1a159501140de8a29cc4e832af1547cf6cbb21bf2d8709f15c78b4d0', ((b'', b'import os\n'), (b'def affected_selectors():\n', b"def affected_selectors(scope='affected'):\n"), (b"    if plan.get('source_commit') != sha or not isinstance(tests, list) or not tests or not all(isinstance(test, str) for test in tests) or len(set(tests)) != len(tests):\n", b"    if plan.get('scope', 'affected') != scope or plan.get('source_commit') != sha or not isinstance(tests, list) or not tests or not all(isinstance(test, str) for test in tests) or len(set(tests)) != len(tests):\n"), (b'    if len(argv) == 1 and argv[0] in PART_SCOPES:\n', b"    if len(argv) == 1 and argv[0] in PART_SCOPES and not os.environ.get('CHAI_CI_SOURCE_RUNS', '').strip():\n"), (b"    if argv == ['affected']:\n", b"    if argv == ['affected'] or (len(argv) == 1 and argv[0] in PART_SCOPES):\n"), (b'            methods = affected_selectors()\n', b'            methods = affected_selectors(argv[0])\n')))}
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
        '2a85dcd2a715c03fad1f19c270084bb890071650e5dada8154196b60b465e234', ('sudoku',)),
    'ChaiClassicsVisualSmokeTests/testLowPowerSuppressesCelebrationButStillCompletesGame': (
        'd61c0385dafb936cc689eb2a99a09bfa0054600f25f224fa476b2d9e75893cba', ('sliding',)),
    'ChaiClassicsVisualSmokeTests/testMazeCommonSessionLifecycleAndContinueDeletion': (
        '5ab88548f2be8c0a9067d5724be3dd8858bfc3e9b1a12f9c01cc37df4d925dd3', ('maze', 'sliding')),
    'ChaiClassicsVisualSmokeTests/testMemoryCommonSessionLifecycleAndContinueDeletion': (
        'f3b6e7a1bd48cfcff6bd70a5d70077e388d531f28f27e9a5890e99d74f9a2746', ('memory', 'sliding')),
    'ChaiClassicsVisualSmokeTests/testMinesweeperCommonSessionLifecycleAndContinueDeletion': (
        '8e96921261e240240f51fcc3a63e83d592a67d86dda99d1a143666f3a08af2a4', ('mines', 'sliding')),
    'ChaiClassicsVisualSmokeTests/testPlayHistorySearchDismissesKeyboardWithoutSwallowingActions': (
        '71e9f2098f36f2dad1c04b60fd37328065d83f1bd3e432687e33acf68cd1c328', ('sliding',)),
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


def dependency_partition_baseline(path, mode, data):
    pair = APPROVED_DEPENDENCY_PARTITIONS.get(path)
    if mode != '100644' or pair is None or hashlib.sha256(data).hexdigest() != pair[1]:
        return data
    normalized = data
    for old_block, new_block in pair[2]:
        if not new_block or normalized.count(new_block) != 1:
            return data
        normalized = normalized.replace(new_block, old_block, 1)
    return normalized if hashlib.sha256(normalized).hexdigest() == pair[0] else data


def shared_content_digest(path, mode, data):
    """Project only exact audited declarations and ceiling-only execution pairs.

    Unsupported XML (including duplicate keys), reasons, modes and formatting
    retain their raw hash, as do all other execution changes. Defaults, selectors,
    enabled timeouts and failed-case treatment are never relaxed.
    """
    data = dependency_partition_baseline(path, mode, data)
    raw = hashlib.sha256(data).hexdigest()
    if mode == '100644' and path == '.github/workflows/ipad-screenshots.yml':
        before, after = APPROVED_IPAD_JOB_BUDGET
        if raw == after:
            normalized = data.replace(b'    timeout-minutes: 330\n', b'    timeout-minutes: 240\n', 1)
            normalized = normalized.replace(b'        id: boot\n        timeout-minutes: 15\n', b'        id: boot\n        timeout-minutes: 10\n', 1)
            normalized = normalized.replace(b'        id: ui\n        timeout-minutes: 60\n', b'        id: ui\n        timeout-minutes: 25\n', 1)
            if hashlib.sha256(normalized).hexdigest() == before:
                return before
    if mode == '100644' and path == '.github/workflows/ci.yml':
        before, after = APPROVED_CI_JOB_TIMEOUT
        if raw == after and data.count(b'    timeout-minutes: 180\n') == 1:
            normalized = data.replace(b'    timeout-minutes: 180\n', b'    timeout-minutes: 90\n', 1)
            if hashlib.sha256(normalized).hexdigest() == before:
                return before
    if mode == '100644' and path == 'scripts/ci.sh':
        before, after = APPROVED_CI_DEFAULT_ALLOWANCE
        if raw == after:
            normalized = data.replace(b'-default-test-execution-time-allowance 600', b'-default-test-execution-time-allowance 420')
            if hashlib.sha256(normalized).hexdigest() == before:
                data, raw = normalized, before
    if mode == '100644' and path == 'scripts/ci.sh':
        before, after, block = APPROVED_CI_BOOTSTRAP
        if raw == after and data.count(block) == 1:
            normalized = data.replace(block, b'', 1)
            if hashlib.sha256(normalized).hexdigest() == before:
                data, raw = normalized, before
    if mode == '100644' and path in APPROVED_TIMEOUT_CEILINGS:
        before, after, ceiling = APPROVED_TIMEOUT_CEILINGS[path]
        if raw == before or raw in (after if isinstance(after, tuple) else (after,)):
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


def canonical_xctest_allowance_body(path, identity, mode, body):
    # A pass under the exact earlier 600s budget also meets the later 1800s
    # bound. Every assertion/action byte, and the enclosing scaffold, stay protected.
    if (path != 'UITests/ChaiClassicsVisualSmokeTests.swift'
            or identity != 'ChaiClassicsVisualSmokeTests/testIPadSudokuScreenshot'
            or mode != '100644'):
        return body
    before, after, block = APPROVED_IPAD_SUDOKU_ALLOWANCE
    if hashlib.sha256(body.encode()).hexdigest() == after and body.count(block) == 1:
        normalized = body.replace(block, '', 1)
        if hashlib.sha256(normalized.encode()).hexdigest() == before:
            return normalized
    return body


def history_menu_digest(identity, body, helper_fingerprint, mode, data, *, audited_context=False):
    """Retain only exact unvisited-menu changes; shared formatter bytes stay bound."""
    raw = hashlib.sha256(data).hexdigest()
    expected = HISTORY_UNVISITED_BODIES.get(identity)
    required_helper = (APPROVED_V020_CASE_ALLOWANCE[0] if identity.startswith('ChaiClassicsV020UITests/')
                       else VISUAL_SCAFFOLD_DIGEST)
    if (not audited_context or mode != '100644' or expected is None or helper_fingerprint != required_helper
            or hashlib.sha256(body.encode()).hexdigest() != expected):
        return raw
    before, after, old_block, new_block, inserted = APPROVED_HISTORY_MENU
    if raw == before:
        try:
            source = data.decode('utf-8')
        except UnicodeDecodeError:
            return raw
        anchor = '/// List rows can move independently'
        if source.count(old_block) == 1 and source.count(anchor) == 1:
            normalized = source.replace(old_block, new_block, 1).replace(anchor, inserted + anchor, 1)
            if hashlib.sha256(normalized.encode()).hexdigest() == after:
                return after
    return raw


def history_menu_audited_context(tree, external_scaffolds):
    if external_scaffolds != HISTORY_AUDITED_SCAFFOLDS:
        return False
    records = [(path, mode, shared_content_digest(path, mode, data))
               for path, (mode, data) in sorted(tree.items())
               if path != 'App/PlayHistoryView.swift'
               and not (path.startswith('UITests/') and path.endswith('.swift'))
               and path not in PURE_EVIDENCE_SCRIPTS and not path.startswith(('docs/', 'tests/'))
               and path != 'README.md']
    return digest(records) == HISTORY_AUDITED_RUNTIME_DIGEST


def scaffold_budget_digest(path, mode, scaffold):
    raw = hashlib.sha256(scaffold.encode()).hexdigest()
    if path == 'UITests/ChaiClassicsV020UITests.swift' and mode == '100644':
        before, after = APPROVED_V020_CASE_ALLOWANCE
        if raw == after and scaffold.count('executionTimeAllowance = 600') == 2:
            normalized = scaffold.replace('executionTimeAllowance = 600', 'executionTimeAllowance = 420')
            if hashlib.sha256(normalized.encode()).hexdigest() == before:
                return before
    return raw


def external_scaffold_digest(path, mode, scaffold):
    raw = scaffold_budget_digest(path, mode, scaffold)
    if path != 'UITests/ChaiClassicsV030UITests.swift' or mode != '100644':
        return raw
    before, after, old_block, new_block = APPROVED_V030_TOOLBAR_HELPER
    if raw == before:
        return before
    if raw == after and scaffold.count(new_block) == 1:
        normalized = scaffold.replace(new_block, old_block, 1)
        if hashlib.sha256(normalized.encode()).hexdigest() == before:
            return before
    return raw


def fingerprints(tree):
    """Include literal assertions, shared helpers/resources/prefs/clocks and project/runtime tooling.

    Only known game-local views may be omitted for an unrelated journey. Every Core file
    remains shared because startup restores all games. Reviewed mixed profiles require
    their exact test body. Pure evidence tools are independently rebuilt,
    not application runtime; all other unknown source files are shared by default. Other test bodies are masked; all signatures/setup/helper
    bytes remain shared, so editing C's test body alone does not invalidate unchanged A/B.
    """
    methods, scaffolds, shared, helper_fingerprints = {}, [], [], {}
    external_scaffolds = {}
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
            helper_fingerprints[Path(path).stem] = scaffold_budget_digest(path, mode, scaffold)
            scaffolds.append((path, mode, helper_fingerprints[Path(path).stem]))
            external_scaffolds[path] = external_scaffold_digest(path, mode, scaffold)
        elif (path in SHARED_SESSION_FILES or path not in ALL_GAME_FILES or path.startswith('Core/')
              or (path == ZOOM_BOARD_FILE and not mines_only_zoom)) and path not in PURE_EVIDENCE_SCRIPTS and not path.startswith(('docs/', 'tests/')) and path != 'README.md':
            shared.append((path, mode, shared_content_digest(path, mode, data)))
    require(methods, 'No declared UI tests available for fingerprints.')
    require(scopes.required_session_tests_for_paths(tree).issubset(methods),
            'Session runtime requires all eight lifecycle journeys and the history interaction journey.')
    result = {}
    audited_history = history_menu_audited_context(tree, external_scaffolds)
    for test, body in sorted(methods.items()):
        local = [(path, tree[path][0], hashlib.sha256(tree[path][1]).hexdigest())
                 for path in sorted(dependencies(test, body, helper_fingerprint=helper_fingerprints.get(test.split('/')[0]))) if path in tree]
        case_scaffolds = [(path, mode, raw if Path(path).stem == test.split('/')[0] else external_scaffolds[path])
                          for path, mode, raw in scaffolds]
        case_shared = list(shared)
        history_path = 'App/PlayHistoryView.swift'
        if history_path in tree:
            mode, data = tree[history_path]
            history_digest = history_menu_digest(test, body, helper_fingerprints.get(test.split('/')[0]), mode, data, audited_context=audited_history)
            case_shared = [(path, shared_mode, history_digest if path == history_path else value)
                           for path, shared_mode, value in case_shared]
        result[test] = digest({'version': 1, 'shared': case_shared, 'helpers': case_scaffolds, 'local': local, 'test_body': body})
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
    pending, records, selections, source_edges, source_success = list(ids), {}, {}, {}, {}
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
        source_edges[run_id] = set()
        source_success[run_id] = run.get('conclusion') == 'success'
        if selection is not None:
            require(isinstance(selection, dict) and selection.get('source_commit') == commit,
                    'Original selected-scope report differs from the source commit.')
            prior = selection.get('source_runs', [])
            require(isinstance(prior, list) and len(prior) < MAX_RUNS and
                    all(type(value) is int and 0 < value < run_id for value in prior), 'Invalid pre-execution source index.')
            pending.extend(value for value in prior if value not in records)
            selections[run_id] = selection
            source_edges[run_id].update(prior)
            require(selection.get('partition') in (None, 'affected-v1'), 'Unknown source partition plan version.')
            require(selection.get('partition') != 'affected-v1' or
                    (selection.get('scope') in scopes.PART_SCOPES and prior), 'Dependency partition requires explicit prior sources.')
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
                source_edges[run_id].update(value for value in inherited if value != run_id)
    for run_id, selection in selections.items():
        scope = selection.get('scope')
        if scope not in scopes.PART_SCOPES:
            continue
        record = records[run_id]
        if selection.get('partition') == 'affected-v1':
            # Rebuild precisely the pre-execution source closure. The current
            # run's later ledger cannot retroactively shrink its requested part.
            prior, queue = set(), list(selection['source_runs'])
            while queue:
                source_id = queue.pop()
                if source_id in prior:
                    continue
                require(source_id in records and source_id < run_id, 'Missing or future partition source.')
                prior.add(source_id); queue.extend(source_edges[source_id] - prior)
            partition = set(planned_partition(scope, record['fingerprints'], [records[key] for key in sorted(prior)]))
        else:
            partition = set(scopes.resolve(scope, record['fingerprints']))
        require(set(record['actual']).issubset(partition), 'Raw source cases do not belong to their source-declared partition.')
        if source_success[run_id]:
            require(set(record['actual']) == partition, 'Successful source partition omitted required actual cases.')
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
    # A changed iPad-only case still skips on phone; retain a real current UI
    # sentinel alongside it, rather than emitting a skipped-only green run.
    if missing and all(test.split('/')[-1] in candidate.IPAD_TESTS for test in missing):
        sentinel = FAST_SENTINEL if FAST_SENTINEL in target_fingerprints else next(
            test for test in sorted(target_fingerprints) if test.split('/')[-1] not in candidate.IPAD_TESTS)
        return sorted([sentinel] + missing)
    # Never turn an empty selector into an accidentally unfiltered or fictional green run.
    return missing or [FAST_SENTINEL if FAST_SENTINEL in target_fingerprints else
                       next(test for test in sorted(target_fingerprints) if test.split('/')[-1] not in candidate.IPAD_TESTS)]


def planned_partition(scope, target_fingerprints, records):
    missing = planned_tests(target_fingerprints, records)
    selected = missing[scopes.PART_SCOPES[scope]::len(scopes.PART_SCOPES)]
    if not selected or all(name.split('/')[-1] in candidate.IPAD_TESTS for name in selected):
        sentinel = FAST_SENTINEL if FAST_SENTINEL in target_fingerprints else next(
            name for name in sorted(target_fingerprints) if name.split('/')[-1] not in candidate.IPAD_TESTS)
        selected = sorted(set(selected + [sentinel]))
    return selected


def make_evidence(sha, current_run, scope, summary, actual, tree, records):
    require(scope != 'beta' or not records, 'Beta critical UI evidence must execute directly without inherited coverage.')
    target = fingerprints(tree)
    if scope in scopes.PART_SCOPES and records:
        selected = planned_partition(scope, target, records)
    elif scope == 'affected':
        selected = planned_tests(target, records)
    else:
        selected = scopes.resolve(scope, sorted(target), include_sessions=bool(scopes.required_session_tests_for_paths(tree)))
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
            scope = args.scope or os.environ.get('CHAI_UI_SCOPE', 'affected')
            require(scope == 'affected' or scope in scopes.PART_SCOPES, 'Only affected cases or source partitions can be planned.')
            target = fingerprints(tree)
            selected = planned_partition(scope, target, records) if scope in scopes.PART_SCOPES and records else (
                scopes.resolve(scope, target) if scope in scopes.PART_SCOPES else planned_tests(target, records))
            result = {'source_commit': sha, 'scope': scope, 'tests': selected}
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
