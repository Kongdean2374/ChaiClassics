import XCTest
import UIKit

/// Runs real menu, board, save, result, and replay flows. Near-win data is created
/// through legal core moves in the DEBUG-Simulator bootstrap's isolated store.
final class ChaiClassicsV020UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 420
        XCUIDevice.shared.orientation = .portrait
    }

    private let playable = ["sudoku", "minesweeper", "sliding", "tictactoe", "connectfour", "twentyfour", "memory", "maze"]
    private let singlePreviews = ["nonogram", "kakuro", "klotski", "gomoku", "reversi", "snake", "fallingblocks", "brickbreaker"]
    private let solitaire = ["klondike", "spider", "freecell", "pyramid", "tripeaks"]
    private var homeIDs: Set<String> {
        Set(playable.map { "game." + $0 } + singlePreviews.map { "catalog." + $0 } + ["catalog.solitaire"])
    }

    private func launch(_ profile: String, fixture: String? = nil, language: String = "en", appearance: String = "light", extra: [String] = [], seeds: [String: Data] = [:], storageNotice: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["--ui-testing", "--ui-profile", profile, "--ui-language", language, "--ui-appearance", appearance] + extra
        if let fixture { arguments += ["--ui-near-win", fixture] }
        for (namespace, data) in seeds { app.launchEnvironment["CHAI_UI_SEED_" + namespace.uppercased()] = data.base64EncodedString() }
        app.launchArguments = arguments + ["--ui-reset"]
        app.launch()
        app.launchArguments = arguments
        if storageNotice { dismissStorageNotice(app) }
        XCTAssertTrue(app.buttons["game.sudoku"].waitForExistence(timeout: 10))
        return app
    }

    private func dismissStorageNotice(_ app: XCUIApplication) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons.firstMatch.tap()
    }

    private func legacySeeds() throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: ["sudoku", "minesweeper", "sliding"].map { namespace in
            let resource = try XCTUnwrap(Bundle(for: ChaiClassicsV020UITests.self).url(forResource: "v010-" + namespace, withExtension: "json"))
            return (namespace, try Data(contentsOf: resource))
        })
    }

    private func back(_ app: XCUIApplication) {
        let button = app.buttons["navigation.back"]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }

    private func visibleArea(_ app: XCUIApplication) -> CGRect {
        let navigation = app.navigationBars.firstMatch
        let top = navigation.exists ? navigation.frame.maxY + 4 : app.frame.minY + 50
        return CGRect(x: app.frame.minX, y: top, width: app.frame.width, height: app.frame.maxY - top - 28)
    }

    /// Scroll at the viewport's edge so a maze-board swipe cannot become a move.
    private func scroll(_ app: XCUIApplication, down: Bool) {
        let scrollView = app.scrollViews.firstMatch
        let frame = scrollView.exists ? scrollView.frame : app.frame
        let usable = visibleArea(app).intersection(frame)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let x = frame.minX + 3
        let lower = origin.withOffset(CGVector(dx: x, dy: usable.maxY - 36))
        let upper = origin.withOffset(CGVector(dx: x, dy: usable.minY + 40))
        if down { upper.press(forDuration: 0.05, thenDragTo: lower) }
        else { lower.press(forDuration: 0.05, thenDragTo: upper) }
    }

    private func show(_ element: XCUIElement, app: XCUIApplication, requireHittable: Bool = true) {
        for attempt in 0..<24 {
            let area = visibleArea(app)
            if element.exists {
                let frame = element.frame
                if frame.width > 0 && frame.height > 0 && area.contains(CGPoint(x: frame.midX, y: frame.midY)) && (!requireHittable || element.isHittable) { return }
                if frame.height > 0 && frame.minY < area.minY { scroll(app, down: true); continue }
            }
            // A lazy list may omit a control above its viewport entirely.
            // Search downward first, then return upward if it was not present.
            scroll(app, down: attempt >= 12)
        }
        XCTFail("Could not reach control: " + element.identifier)
    }

    private func open(_ game: String, app: XCUIApplication) {
        let card = app.buttons["game." + game]
        show(card, app: app); card.tap()
    }

    private func tap(_ id: String, app: XCUIApplication) {
        // Native confirmation popovers can expose the same action more than
        // once on iPad. Resolve one element before reading its frame or tapping.
        let button = app.buttons.matching(identifier: id).firstMatch
        show(button, app: app); button.tap()
    }

    private func choose(_ id: String, option: String, app: XCUIApplication) {
        let picker = app.descendants(matching: .any).matching(identifier: id).firstMatch
        show(picker, app: app); picker.tap()
        let choice = app.buttons.matching(NSPredicate(format: "label == %@", option)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "Missing picker option: " + option)
        choice.tap()
    }

    private func pauseResume(_ prefix: String, app: XCUIApplication) {
        tap(prefix + ".pause", app: app)
        XCTAssertTrue(app.buttons["game.resume"].waitForExistence(timeout: 5))
        tap("game.resume", app: app)
    }

    private func restore(_ game: String, app: XCUIApplication) {
        back(app); back(app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["game.sudoku"].waitForExistence(timeout: 10))
        open(game, app: app)
        tap(game + ".continue", app: app)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func assertNoHomeProgress(_ card: XCUIElement) {
        for forbidden in ["001", "35 moves", "35 步", "進行中", "In progress", "已填", "旗標數", "elapsedSeconds", "catalog.description.", "catalog.status."] {
            XCTAssertFalse(card.label.contains(forbidden), card.identifier + " leaks progress or a localization key: " + forbidden)
        }
    }

    private func assertThreeColumns(_ app: XCUIApplication, width: CGFloat? = nil, prefix: String = "game.", ids: [String] = ["sudoku", "minesweeper", "sliding"]) {
        let cards = ids.map { app.buttons[prefix + $0] }
        for card in cards {
            XCTAssertTrue(card.waitForExistence(timeout: 5)); XCTAssertGreaterThanOrEqual(card.frame.width, 80)
            XCTAssertTrue(visibleArea(app).contains(card.frame), "Card is clipped: " + card.identifier)
        }
        XCTAssertEqual(cards[0].frame.minY, cards[1].frame.minY, accuracy: 2)
        XCTAssertEqual(cards[1].frame.minY, cards[2].frame.minY, accuracy: 2)
        XCTAssertLessThan(cards[0].frame.maxX, cards[1].frame.minX)
        XCTAssertLessThan(cards[1].frame.maxX, cards[2].frame.minX)
        if let width { XCTAssertEqual(cards[2].frame.maxX - cards[0].frame.minX, width - 32, accuracy: 2) }
    }

    private func inspectCatalog(language: String) {
        let app = launch("v020-catalog", language: language)
        assertThreeColumns(app)
        var seen: Set<String> = []
        for _ in 0..<12 {
            let area = visibleArea(app)
            let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'game.' OR identifier BEGINSWITH 'catalog.'"))
            for card in cards.allElementsBoundByIndex where card.exists && area.contains(CGPoint(x: card.frame.midX, y: card.frame.midY)) {
                XCTAssertTrue(homeIDs.contains(card.identifier), "Unexpected Home card: " + card.identifier)
                assertNoHomeProgress(card)
                XCTAssertTrue(card.label.contains(language == "en" ? (card.identifier.hasPrefix("game.") ? "Playable" : "Coming soon") : (card.identifier.hasPrefix("game.") ? "可遊玩" : "尚未推出")))
                seen.insert(card.identifier)
            }
            if seen == homeIDs { break }
            scroll(app, down: false)
        }
        XCTAssertEqual(seen, homeIDs, "Every one of the 17 cards must be reachable by scrolling.")
        capture(app, "v020-catalog-bottom-" + language)
        // Return to the beginning once; previews are then visited in catalog order.
        for _ in 0..<10 {
            if app.buttons["game.sudoku"].exists && visibleArea(app).contains(app.buttons["game.sudoku"].frame) { break }
            scroll(app, down: true)
        }
        let names: [String: (String, String)] = [
            "nonogram": ("Nonogram", "數織"), "kakuro": ("Kakuro", "數和"), "klotski": ("Klotski", "華容道"),
            "gomoku": ("Gomoku", "五子棋"), "reversi": ("Reversi", "黑白棋"),
            "klondike": ("Klondike Solitaire", "經典接龍"), "spider": ("Spider Solitaire", "蜘蛛接龍"),
            "freecell": ("FreeCell", "新接龍"), "pyramid": ("Pyramid Solitaire", "金字塔接龍"), "tripeaks": ("TriPeaks Solitaire", "三峰接龍"),
            "snake": ("Snake", "貪吃蛇"), "fallingblocks": ("Falling Blocks", "落塊拼圖"), "brickbreaker": ("Brick Breaker", "打磚塊")
        ]
        func visit(_ id: String) {
            tap("catalog." + id, app: app)
            let title = app.staticTexts["comingSoon.title"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            XCTAssertEqual(title.label, language == "en" ? names[id]!.0 : names[id]!.1)
            let status = app.descendants(matching: .any).matching(identifier: "comingSoon.status").firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 5))
            XCTAssertTrue(status.label.contains(language == "en" ? "Coming soon" : "尚未推出"))
            XCTAssertFalse(app.buttons["menu.start"].exists)
            app.buttons["comingSoon.back"].tap()
        }
        for id in singlePreviews.prefix(5) { visit(id) }
        tap("catalog.solitaire", app: app)
        assertThreeColumns(app, prefix: "catalog.", ids: Array(solitaire.prefix(3)))
        var children: Set<String> = []
        for id in solitaire {
            let card = app.buttons["catalog." + id]
            show(card, app: app)
            XCTAssertTrue(card.label.contains(language == "en" ? "Coming soon" : "尚未推出"))
            children.insert(id); visit(id)
        }
        XCTAssertEqual(children.count, 5)
        capture(app, "v020-solitaire-" + language)
        back(app)
        for id in singlePreviews.suffix(3) { visit(id) }
    }

    func testCompleteCatalogAndThirteenComingSoonPagesInEnglish() { inspectCatalog(language: "en") }
    func testCompleteCatalogAndThirteenComingSoonPagesInTraditionalChinese() { inspectCatalog(language: "zh-Hant") }

    func testAllEightPlayableCardsOpenRealMenus() {
        let app = launch("v020-catalog")
        let controls = ["sudoku": "sudoku.difficulty.easy", "minesweeper": "mines.start", "sliding": "sliding.start",
                        "tictactoe": "tictactoe.start", "connectfour": "connectfour.start", "twentyfour": "twentyfour.start", "memory": "memory.start", "maze": "maze.start"]
        for game in playable {
            open(game, app: app)
            let start = app.buttons[controls[game]!]
            show(start, app: app); XCTAssertTrue(start.isEnabled)
            XCTAssertFalse(app.staticTexts["comingSoon.title"].exists)
            back(app)
        }
    }

    func testTicTacToeLocalRoundRestoresWinsAndReplays() {
        let app = launch("v020-tictactoe")
        open("tictactoe", app: app)
        choose("tictactoe.mode", option: "Two players on this device", app: app)
        tap("tictactoe.start", app: app)
        for cell in [0, 3, 1, 4] { tap("tictactoe.cell.\(cell)", app: app) }
        XCTAssertTrue(app.staticTexts["tictactoe.moves"].label.contains("4"))
        pauseResume("tictactoe", app: app)
        restore("tictactoe", app: app)
        XCTAssertTrue(app.staticTexts["tictactoe.moves"].label.contains("4"))
        XCTAssertTrue(app.buttons["tictactoe.cell.0"].label.contains("X"))
        XCTAssertTrue(app.buttons["tictactoe.cell.3"].label.contains("O"))
        tap("tictactoe.cell.2", app: app)
        XCTAssertTrue(app.staticTexts["tictactoe.result"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tictactoe.cell.5"].isEnabled)
        show(app.staticTexts["tictactoe.result"], app: app, requireHittable: false)
        capture(app, "v020-tictactoe-win")
        tap("tictactoe.replay", app: app)
        XCTAssertFalse(app.staticTexts["tictactoe.result"].exists)
        XCTAssertTrue(app.staticTexts["tictactoe.moves"].label.contains("0"))
        XCTAssertTrue(app.buttons["tictactoe.cell.0"].isEnabled)
    }

    func testConnectFourLocalRoundRestoresWinsAndReplays() {
        let app = launch("v020-connectfour")
        open("connectfour", app: app)
        choose("connectfour.mode", option: "Two players on this device", app: app)
        tap("connectfour.start", app: app)
        for column in [0, 1, 0, 1, 0, 1] { tap("connectfour.column.\(column)", app: app) }
        XCTAssertTrue(app.staticTexts["connectfour.moves"].label.contains("6"))
        pauseResume("connectfour", app: app)
        restore("connectfour", app: app)
        XCTAssertTrue(app.staticTexts["connectfour.moves"].label.contains("6"))
        tap("connectfour.column.0", app: app)
        XCTAssertTrue(app.staticTexts["connectfour.result"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["connectfour.column.2"].isEnabled)
        show(app.staticTexts["connectfour.result"], app: app, requireHittable: false)
        capture(app, "v020-connectfour-win")
        tap("connectfour.replay", app: app)
        XCTAssertFalse(app.staticTexts["connectfour.result"].exists)
        XCTAssertTrue(app.staticTexts["connectfour.moves"].label.contains("0"))
        XCTAssertTrue(app.buttons["connectfour.column.0"].isEnabled)
    }

    private func expectMoves(_ count: Int, game: String, app: XCUIApplication, timeout: TimeInterval = 20) {
        let metric = app.staticTexts.matching(identifier: game + ".moves").firstMatch
        let expected = "\(count) moves"
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            metric.exists && metric.label == expected
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: timeout), .completed,
                       "\(game) must report exactly \(expected) after real player/AI input.")
    }

    private func expectHumanTurn(_ game: String, computerFirst: Bool, app: XCUIApplication) {
        let turn = app.staticTexts.matching(identifier: game + ".turn").firstMatch
        let expected = game == "tictactoe" ? "You to play · \(computerFirst ? "O" : "X")" : "Your turn"
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            turn.exists && turn.label == expected
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed,
                       "The actual AI reply must return control to the human player.")
    }

    private func assertMovesStay(_ count: Int, game: String, app: XCUIApplication) {
        let metric = app.staticTexts.matching(identifier: game + ".moves").firstMatch
        let unexpected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            metric.exists && metric.label != "\(count) moves"
        }, object: nil)
        unexpected.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpected], timeout: 1), .completed,
                       "Pausing or navigating must not submit an extra AI move.")
    }

    /// No seeds or AI overrides are used: each configuration starts through the
    /// real single-player menu, then waits for the production background task.
    private func inspectSinglePlayerAI(_ game: String) {
        executionTimeAllowance = 600
        let cellPrefix = game == "tictactoe" ? "tictactoe.cell." : "connectfour.column."
        let cellCount = game == "tictactoe" ? 9 : 7
        for difficulty in ["Easy", "Normal", "Hard"] {
            for computerFirst in [false, true] {
                let app = launch("v020-" + game)
                open(game, app: app)
                choose(game + ".mode", option: "Play the computer", app: app)
                choose(game + ".difficulty", option: difficulty, app: app)
                let first = game == "tictactoe"
                    ? (computerFirst ? "Computer first (X)" : "You first (X)")
                    : (computerFirst ? "Computer first · star" : "You first · star")
                choose(game + ".first", option: first, app: app)
                tap(game + ".start", app: app)

                // In a computer-first round this cannot pass until a genuine
                // opening move has been computed, saved, and rendered.
                expectMoves(computerFirst ? 1 : 0, game: game, app: app)
                expectHumanTurn(game, computerFirst: computerFirst, app: app)
                let controls = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", cellPrefix))
                let hasLegalInput = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    controls.allElementsBoundByIndex.contains { $0.exists && $0.isEnabled }
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [hasLegalInput], timeout: 10), .completed)
                guard let legal = controls.allElementsBoundByIndex.first(where: { $0.exists && $0.isEnabled }) else {
                    XCTFail("No legal human input after AI opening: \(game), \(difficulty)")
                    app.terminate()
                    return
                }
                show(legal, app: app); legal.tap()

                let replyMoves = computerFirst ? 3 : 2
                expectMoves(replyMoves, game: game, app: app)
                expectHumanTurn(game, computerFirst: computerFirst, app: app)
                XCTAssertFalse(app.staticTexts[game + ".result"].exists)
                let board = (0..<cellCount).map { app.buttons[cellPrefix + String($0)].label }
                pauseResume(game, app: app)
                expectMoves(replyMoves, game: game, app: app)
                expectHumanTurn(game, computerFirst: computerFirst, app: app)
                assertMovesStay(replyMoves, game: game, app: app)
                XCTAssertEqual(board, (0..<cellCount).map { app.buttons[cellPrefix + String($0)].label })

                back(app)
                let resume = app.buttons.matching(identifier: game + ".continue").firstMatch
                XCTAssertTrue(resume.waitForExistence(timeout: 5))
                XCTAssertTrue(resume.label.contains("\(replyMoves) moves"))
                tap(game + ".continue", app: app)
                expectMoves(replyMoves, game: game, app: app)
                expectHumanTurn(game, computerFirst: computerFirst, app: app)
                assertMovesStay(replyMoves, game: game, app: app)
                XCTAssertEqual(board, (0..<cellCount).map { app.buttons[cellPrefix + String($0)].label })
                capture(app, "v020-\(game)-ai-\(difficulty.lowercased())-\(computerFirst ? "computer-first" : "human-first")")
                app.terminate()
            }
        }
    }

    func testTicTacToeAIRepliesAtEveryDifficultyWithEitherFirstPlayer() {
        inspectSinglePlayerAI("tictactoe")
    }

    func testConnectFourAIRepliesAtEveryDifficultyWithEitherFirstPlayer() {
        inspectSinglePlayerAI("connectfour")
    }

    func testTwentyFourRestoresExactCardsCompletesAndStartsNextPuzzle() {
        let app = launch("v020-twentyfour", fixture: "twentyfour")
        open("twentyfour", app: app)
        choose("twentyfour.difficulty", option: "Easy", app: app)
        tap("twentyfour.continue", app: app)
        let labels = [3, 5].map { app.buttons["twentyfour.card.\($0)"].label }
        pauseResume("twentyfour", app: app)
        restore("twentyfour", app: app)
        XCTAssertEqual(labels, [3, 5].map { app.buttons["twentyfour.card.\($0)"].label })
        tap("twentyfour.card.3", app: app); tap("twentyfour.card.5", app: app)
        tap("twentyfour.operator.multiply", app: app); tap("twentyfour.apply", app: app)
        XCTAssertTrue(app.staticTexts["twentyfour.complete"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["twentyfour.solved"].label.contains("1"))
        show(app.staticTexts["twentyfour.complete"], app: app, requireHittable: false)
        capture(app, "v020-twentyfour-win")
        tap("twentyfour.next", app: app)
        XCTAssertFalse(app.staticTexts["twentyfour.complete"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'twentyfour.card.'")).count, 4)
        XCTAssertTrue(app.staticTexts["twentyfour.solved"].label.contains("1"))
    }

    func testMemoryRestoresMatchesHidesUnturnedCardsCompletesAndReplays() {
        let app = launch("v020-memory", fixture: "memory")
        open("memory", app: app); tap("memory.mode.easy", app: app); tap("memory.continue", app: app)
        XCTAssertTrue(app.staticTexts["memory.pairs"].label.contains("7/8"))
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.card.'"))
        let remaining = cards.allElementsBoundByIndex.filter(\.isEnabled).map(\.identifier)
        XCTAssertEqual(remaining.count, 2)
        for id in remaining { XCTAssertTrue(app.buttons[id].label.contains("face down")) }
        tap(remaining[0], app: app)
        pauseResume("memory", app: app)
        XCTAssertTrue(app.buttons[remaining[0]].label.contains("face down"))
        restore("memory", app: app)
        XCTAssertTrue(app.staticTexts["memory.pairs"].label.contains("7/8"))
        for id in remaining { XCTAssertTrue(app.buttons[id].label.contains("face down")); tap(id, app: app) }
        XCTAssertTrue(app.staticTexts["memory.complete"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["memory.pairs"].label.contains("8/8"))
        show(app.staticTexts["memory.complete"], app: app, requireHittable: false)
        capture(app, "v020-memory-win")
        tap("memory.newDeck", app: app)
        XCTAssertFalse(app.staticTexts["memory.complete"].exists)
        XCTAssertTrue(app.staticTexts["memory.pairs"].label.contains("0/8"))
        XCTAssertEqual(cards.count, 16)
        XCTAssertTrue(cards.allElementsBoundByIndex.allSatisfy { $0.isEnabled && $0.label.contains("face down") })
    }

    func testMazeRestoresPositionResumesCompletesAndGeneratesNextMaze() {
        let app = launch("v020-maze", fixture: "maze")
        open("maze", app: app)
        choose("maze.difficulty", option: "Easy · 9×9", app: app)
        tap("maze.continue", app: app)
        XCTAssertTrue(app.staticTexts["maze.moves"].label.contains("42"))
        tap("maze.right", app: app)
        XCTAssertTrue(app.staticTexts["maze.moves"].label.contains("43"))
        let position = app.staticTexts["maze.position"].label
        restore("maze", app: app)
        XCTAssertTrue(app.buttons["game.resume"].waitForExistence(timeout: 5))
        tap("game.resume", app: app)
        XCTAssertEqual(app.staticTexts["maze.position"].label, position)
        XCTAssertTrue(app.staticTexts["maze.moves"].label.contains("43"))
        tap("maze.down", app: app)
        XCTAssertTrue(app.staticTexts["maze.complete"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["maze.moves"].label.contains("44"))
        show(app.staticTexts["maze.complete"], app: app, requireHittable: false)
        capture(app, "v020-maze-win")
        tap("maze.next", app: app)
        XCTAssertFalse(app.staticTexts["maze.complete"].exists)
        XCTAssertTrue(app.staticTexts["maze.moves"].label.contains("0"))
        XCTAssertTrue(app.staticTexts["maze.position"].label.contains("Row 1, column 1"))
    }

    func testNewPuzzleModesStartRealBoards() {
        for game in ["twentyfour", "memory", "maze"] {
            let app = launch("v020-" + game)
            open(game, app: app)
            if game == "memory" { tap("memory.mode.hard", app: app) }
            else { choose(game + ".difficulty", option: game == "maze" ? "Hard · 21×21" : "Hard", app: app) }
            tap(game + ".start", app: app)
            if game == "memory" {
                XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.card.'")).count, 36)
                XCTAssertTrue(app.staticTexts["memory.pairs"].label.contains("0/18"))
            } else if game == "twentyfour" {
                XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'twentyfour.card.'")).count, 4)
                XCTAssertFalse(app.buttons["twentyfour.apply"].isEnabled)
            } else {
                XCTAssertTrue(app.staticTexts["maze.position"].label.contains("21×21"))
                XCTAssertTrue(app.staticTexts["maze.moves"].label.contains("0"))
            }
            pauseResume(game, app: app)
            capture(app, "v020-" + game + "-hard-new-game")
            app.terminate()
        }
    }

    func testCorruptNewSaveRecoveryPreservesAllThreeLegacySaves() throws {
        var seeds = try legacySeeds()
        seeds["memory"] = Data("broken-save".utf8)
        let app = launch("v020-memory", seeds: seeds, storageNotice: true)
        open("memory", app: app)
        show(app.buttons["memory.start"], app: app, requireHittable: false)
        XCTAssertFalse(app.buttons["memory.start"].isEnabled)
        tap("storage.recover.memory", app: app)
        let confirm = app.buttons.matching(identifier: "storage.confirmRecovery.memory").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertFalse(app.buttons["storage.recover.memory"].exists)
        XCTAssertTrue(app.buttons["memory.start"].isEnabled)
        tap("memory.start", app: app)
        XCTAssertTrue(app.buttons["memory.card.0"].waitForExistence(timeout: 5))
        back(app); back(app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["game.sudoku"].waitForExistence(timeout: 10))
        open("sudoku", app: app); tap("sudoku.continue", app: app)
        XCTAssertTrue((app.buttons["sudoku.cell.1"].value as? String ?? "").contains("2, 7"))
        back(app); back(app)
        open("minesweeper", app: app); tap("mines.continue", app: app)
        XCTAssertTrue(app.buttons["mines.cell.30"].label.contains("Flagged"))
        back(app); back(app)
        open("sliding", app: app); tap("sliding.continue", app: app)
        XCTAssertTrue(app.staticTexts["sliding.moves"].label.contains("35 moves"))
    }

    func testFutureSchemaRemainsProtectedAcrossRelaunch() throws {
        var seeds = try legacySeeds()
        seeds["memory"] = Data("{\"schemaVersion\":999,\"payload\":{\"future\":true}}".utf8)
        let app = launch("v020-memory", seeds: seeds, storageNotice: true)
        for iteration in 0..<2 {
            if iteration == 1 {
                app.terminate(); app.launch(); dismissStorageNotice(app)
                XCTAssertTrue(app.buttons["game.sudoku"].waitForExistence(timeout: 10))
            }
            open("memory", app: app)
            XCTAssertFalse(app.buttons["storage.recover.memory"].exists)
            show(app.buttons["memory.start"], app: app, requireHittable: false)
            XCTAssertFalse(app.buttons["memory.start"].isEnabled)
            XCTAssertFalse(app.buttons["memory.continue"].exists)
            back(app)
            open("sliding", app: app)
            XCTAssertTrue(app.buttons["sliding.continue"].label.contains("35 moves"))
            back(app)
        }
    }

    private func inspectViewport(_ width: Int) {
        for language in ["zh-Hant", "en"] {
            for appearance in ["light", "dark"] {
                let app = launch("v020-layout", language: language, appearance: appearance,
                                 extra: ["--uitest-viewport-width", String(width)])
                XCTAssertGreaterThanOrEqual(app.frame.width, CGFloat(width), "The simulator must accommodate the requested real layout width.")
                assertThreeColumns(app, width: CGFloat(width))
                for id in playable.prefix(3) { assertNoHomeProgress(app.buttons["game." + id]) }
                capture(app, "v020-viewport-\(width)-\(language)-\(appearance)-home-top")
                tap("catalog.solitaire", app: app)
                assertThreeColumns(app, width: CGFloat(width), prefix: "catalog.", ids: Array(solitaire.prefix(3)))
                capture(app, "v020-viewport-\(width)-\(language)-\(appearance)-solitaire")
                back(app)
                show(app.buttons["catalog.brickbreaker"], app: app)
                XCTAssertTrue(app.buttons["catalog.brickbreaker"].isHittable)
                capture(app, "v020-viewport-\(width)-\(language)-\(appearance)-home-bottom")
                app.terminate()
            }
        }
    }

    func testCatalogLayoutAt320PointViewport() { inspectViewport(320) }
    func testCatalogLayoutAt375PointViewport() { inspectViewport(375) }
    func testCatalogLayoutAt390PointViewport() { inspectViewport(390) }
    func testCatalogLayoutAt430PointViewport() { inspectViewport(430) }

    func testAccessibilityTypeAdaptsCatalogAndSupportsReducedMotion() {
        for (size, columns) in [("accessibility3", 2), ("accessibility5", 1)] {
            for language in ["zh-Hant", "en"] {
                let app = launch("v020-layout", language: language, appearance: "dark",
                                 extra: ["--uitest-viewport-width", "320", "--ui-content-size", size, "--ui-reduce-motion"])
                let first = app.buttons["game.sudoku"], second = app.buttons["game.minesweeper"]
                XCTAssertTrue(first.waitForExistence(timeout: 5))
                XCTAssertGreaterThan(first.frame.width, 130)
                assertNoHomeProgress(first)
                let firstFrame = first.frame
                if columns == 2 {
                    XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 2)
                    XCTAssertLessThan(first.frame.maxX, second.frame.minX)
                } else {
                    show(second, app: app)
                    XCTAssertEqual(firstFrame.minX, second.frame.minX, accuracy: 2)
                    XCTAssertEqual(firstFrame.width, second.frame.width, accuracy: 2)
                    XCTAssertGreaterThan(firstFrame.width, 260)
                }
                capture(app, "v020-viewport-320-\(language)-\(size)-reduced-motion")
                app.terminate()
            }
        }
    }
}
