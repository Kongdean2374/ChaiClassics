import XCTest
import UIKit

/// Runs real menu, board, save, result review, and confirmed new-session flows. Near-win data is created
/// through legal core moves in the DEBUG-Simulator bootstrap's isolated store.
final class ChaiClassicsV020UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 420
        XCUIDevice.shared.orientation = .portrait
    }

    private let playable = ["sudoku", "minesweeper", "sliding", "tictactoe", "connectfour", "twentyfour", "memory", "maze", "nonogram", "kakuro", "klotski", "gomoku", "reversi", "xiangqi", "banqi", "chess", "shogi", "klondike", "spider", "freecell", "pyramid", "tripeaks", "snake", "fallingblocks", "brickbreaker"]
    private let boardPlayable = ["tictactoe", "connectfour", "gomoku", "reversi", "xiangqi", "banqi", "chess", "shogi"]
    private let boardPreviews = ["gomoku", "reversi", "xiangqi", "banqi", "chess", "shogi"]
    private let singlePreviews = ["nonogram", "kakuro", "klotski", "snake", "fallingblocks", "brickbreaker"]
    private let solitaire = ["klondike", "spider", "freecell", "pyramid", "tripeaks"]
    private var homeIDs: Set<String> {
        Set(playable.filter { !boardPlayable.contains($0) && !solitaire.contains($0) }.map { "game."+$0 }
            + ["catalog.boardgames","catalog.solitaire"])
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
        if extra.contains("--ui-content-size") {
            XCTAssertTrue(app.staticTexts["home.accessibleTitle"].waitForExistence(timeout: 10))
        } else {
            XCTAssertTrue(app.buttons["game.sudoku"].waitForExistence(timeout: 10))
        }
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
        let board = app.descendants(matching:.any).matching(identifier:"catalog.folder.boardgames").firstMatch
        let cards = app.descendants(matching:.any).matching(identifier:"catalog.folder.solitaire").firstMatch
        if board.exists && !boardPlayable.contains(game) || cards.exists && !solitaire.contains(game) { back(app) }
        if boardPlayable.contains(game) && !board.exists { tap("catalog.boardgames",app:app) }
        if solitaire.contains(game) && !cards.exists { tap("catalog.solitaire",app:app) }
        let card = app.buttons["game."+game]; show(card,app:app); card.tap()
    }

    private func tap(_ id: String, app: XCUIApplication) {
        // Native confirmation popovers can expose the same action more than
        // once on iPad. Resolve one element before reading its frame or tapping.
        let button = app.buttons.matching(identifier: id).firstMatch
        show(button, app: app)
        if !button.isEnabled {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in button.exists && button.isEnabled }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed,
                           "The real transition must finish before the next input: " + id)
        }
        button.tap()
    }

    private func choose(_ id: String, option: String, app: XCUIApplication) {
        let picker = app.descendants(matching: .any).matching(identifier: id).firstMatch
        show(picker, app: app); picker.tap()
        let choice = app.buttons.matching(NSPredicate(format: "label == %@", option)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "Missing picker option: " + option)
        choice.tap()
    }

    private func startNew(_ game: String, app: XCUIApplication) {
        tap((game == "minesweeper" ? "mines" : game) + ".start", app: app)
        confirmNewGame(game, app: app)
    }

    private func continueGame(_ game: String, app: XCUIApplication) {
        tap((game == "minesweeper" ? "mines" : game) + ".continue", app: app)
        resumePausedGame(game, app: app)
    }

    private func boardSignature(_ game: String, app: XCUIApplication) -> [String] {
        if game == "maze" {
            return [app.staticTexts["maze.position"].label, app.staticTexts["maze.moves"].label]
        }
        let prefix: String
        switch game {
        case "tictactoe": prefix = "tictactoe.cell."
        case "connectfour": prefix = "connectfour.column."
        case "memory": prefix = "memory.card."
        case "twentyfour": prefix = "twentyfour.card."
        default: prefix = game + ".tile."
        }
        return app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByIndex.map { element in
                // Unmatched Memory reveals are deliberately cleared by pause;
                // matched identities and every real card Button must persist.
                let label = game == "memory" && !element.label.hasSuffix(", matched") ? "unmatched" : element.label
                return element.identifier + ":" + label
            }.sorted()
    }

    private func pauseResume(_ prefix: String, app: XCUIApplication) {
        let signature = boardSignature(prefix, app: app)
        tap((prefix == "mines" ? "minesweeper" : prefix) + ".session.pause", app: app)
        let probe = prefix == "maze" ? "maze.board" : prefix == "connectfour" ? "connectfour.column.0" :
            prefix == "tictactoe" ? "tictactoe.cell.0" : prefix == "memory" ? "memory.card.0" : "twentyfour.cards"
        assertPausedClock(prefix, boardIdentifier: probe, app: app)
        capture(app, "v022-" + prefix + "-paused-board-under-blur")
        resumePausedGame(prefix, app: app)
        XCTAssertEqual(boardSignature(prefix, app: app), signature,
                       "Resume must preserve the actual board and completed moves.")
    }

    private func restore(_ game: String, app: XCUIApplication) {
        back(app); back(app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["game.sudoku"].waitForExistence(timeout: 10))
        open(game, app: app)
        continueGame(game, app: app)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func finishReviewAndReturnToMenu(_ game: String, moves: Int, app: XCUIApplication, screenshot: String) {
        requireSessionResult(game, moves: moves, app: app)
        let prefix = game == "tictactoe" ? "tictactoe.cell." : game == "connectfour" ? "connectfour.column." :
            game == "memory" ? "memory.card." : game == "twentyfour" ? "twentyfour.card." : "maze."
        let hiddenBoard = game == "maze" ? "maze.board" : prefix + (game == "twentyfour" ? "6" : "0")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: hiddenBoard).firstMatch.exists,
                       "The centered result must own accessibility focus.")
        capture(app, screenshot)
        reviewAndReopenSessionResult(game, moves: moves, app: app)
        tap(game + ".session.done", app: app)
        let saved = app.buttons.matching(identifier: game + ".continue").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "Done must return to this game's menu.")
        let summary = saved.label
        // A completed save reopens its immutable result, without a Resume path.
        tap(game + ".continue", app: app)
        requireSessionResult(game, moves: moves, app: app)
        XCTAssertFalse(app.buttons[game + ".session.resume"].exists)
        tap(game + ".session.done", app: app)
        XCTAssertEqual(saved.label, summary)
    }

    private func requireMemoryButtons(_ count: Int, app: XCUIApplication) {
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.card.'"))
        let appeared = cards.firstMatch.waitForExistence(timeout: 10)
        // Keep the real accessibility roles and labels as evidence. In
        // particular, a generic element must not stand in for a card Button.
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "v020-memory-\(count)-card-button-hierarchy"
        hierarchy.lifetime = .keepAlways; add(hierarchy)
        capture(app, "v020-memory-\(count)-card-button-readiness")
        XCTAssertTrue(appeared, "Memory cards must be exposed as real accessibility Buttons.")
        XCTAssertEqual(cards.count, count)
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
                if card.identifier == "catalog.boardgames" {
                    XCTAssertTrue(card.label.contains(language == "en" ? "8 playable" : "8 款可遊玩"))
                } else if card.identifier == "catalog.solitaire" {
                    XCTAssertTrue(card.label.contains(language == "en" ? "5 playable" : "5 款可遊玩"))
                } else {
                    XCTAssertTrue(card.label.contains(language == "en" ? "Playable" : "可遊玩"))
                }
                seen.insert(card.identifier)
            }
            if seen == homeIDs { break }
            scroll(app, down: false)
        }
        XCTAssertEqual(homeIDs.count, 14)
        XCTAssertEqual(seen, homeIDs, "Every one of the 14 Home cards must be reachable by scrolling.")
        capture(app, "v020-catalog-bottom-" + language)
        // Return to the beginning once; previews are then visited in catalog order.
        for _ in 0..<10 {
            if app.buttons["game.sudoku"].exists && visibleArea(app).contains(app.buttons["game.sudoku"].frame) { break }
            scroll(app, down: true)
        }
        let names: [String: (String, String)] = [
            "nonogram": ("Nonogram", "數織"), "kakuro": ("Kakuro", "數和"), "klotski": ("Klotski", "華容道"),
            "gomoku": ("Gomoku", "五子棋"), "reversi": ("Reversi", "黑白棋"),
            "xiangqi": ("Xiangqi", "象棋"), "banqi": ("Banqi", "暗棋"), "chess": ("Chess", "西洋棋"), "shogi": ("Shogi", "將棋"),
            "klondike": ("Klondike Solitaire", "經典接龍"), "spider": ("Spider Solitaire", "蜘蛛接龍"),
            "freecell": ("FreeCell", "新接龍"), "pyramid": ("Pyramid Solitaire", "金字塔接龍"), "tripeaks": ("TriPeaks Solitaire", "三峰接龍"),
            "snake": ("Snake", "貪吃蛇"), "fallingblocks": ("Falling Blocks", "落塊拼圖"), "brickbreaker": ("Brick Breaker", "打磚塊")
        ]
        var visitedPreviews: Set<String> = []
        func visit(_ id: String) {
            tap("game."+id,app:app)
            XCTAssertTrue(app.navigationBars[language == "en" ? names[id]!.0 : names[id]!.1].waitForExistence(timeout:10))
            let start = app.buttons[id+".start"]; show(start,app:app); XCTAssertTrue(start.isEnabled)
            XCTAssertFalse(app.staticTexts["comingSoon.title"].exists)
            visitedPreviews.insert(id); back(app)
        }

        for id in singlePreviews.prefix(3) { visit(id) }
        tap("catalog.boardgames", app: app)
        XCTAssertTrue(app.navigationBars[language == "en" ? "Board Games" : "棋類遊戲"].waitForExistence(timeout: 10))
        assertThreeColumns(app, prefix: "", ids: ["game.tictactoe", "game.connectfour", "game.gomoku"])
        let availability = app.staticTexts.matching(identifier: "catalog.folder.availability").firstMatch
        XCTAssertEqual(availability.label, language == "en" ? "8 playable" : "8 款可遊玩")
        let boardIDs = Set(boardPlayable.map { "game."+$0 })
        var seenBoard: Set<String> = []
        for id in boardPlayable.map({ "game."+$0 }) {
            let card = app.buttons[id]
            show(card, app: app)
            XCTAssertTrue(card.isHittable)
            assertNoHomeProgress(card)
            seenBoard.insert(card.identifier)
        }
        XCTAssertEqual(seenBoard, boardIDs)
        XCTAssertEqual(seenBoard.count, 8)
        for id in boardPreviews { visit(id) }
        capture(app, "v021-boardgames-" + language)
        back(app)
        tap("catalog.solitaire", app: app)
        assertThreeColumns(app, prefix: "game.", ids: Array(solitaire.prefix(3)))
        var children: Set<String> = []
        for id in solitaire {
            let card = app.buttons["game." + id]
            show(card, app: app)
            XCTAssertTrue(card.label.contains(language == "en" ? "Playable" : "可遊玩"))
            children.insert(id); visit(id)
        }
        XCTAssertEqual(children.count, 5)
        capture(app, "v020-solitaire-" + language)
        back(app)
        for id in singlePreviews.suffix(3) { visit(id) }
        XCTAssertEqual(visitedPreviews, Set(singlePreviews + solitaire + boardPreviews))
        XCTAssertEqual(visitedPreviews.count, 17)
    }

    func testCompleteCatalogAndThirteenComingSoonPagesInEnglish() { inspectCatalog(language: "en") }
    func testCompleteCatalogAndThirteenComingSoonPagesInTraditionalChinese() { inspectCatalog(language: "zh-Hant") }

    func testAllEightPlayableCardsOpenRealMenus() {
        let app = launch("v020-catalog")
        let controls = ["sudoku": "sudoku.difficulty.easy", "minesweeper": "mines.start", "sliding": "sliding.start",
                        "tictactoe": "tictactoe.start", "connectfour": "connectfour.start", "twentyfour": "twentyfour.start", "memory": "memory.start", "maze": "maze.start"]
        for game in playable {
            open(game, app: app)
            let start = app.buttons[controls[game] ?? game+".start"]
            show(start, app: app); XCTAssertTrue(start.isEnabled)
            XCTAssertFalse(app.staticTexts["comingSoon.title"].exists)
            back(app)
        }
    }

    func testTicTacToeLocalRoundRestoresWinsAndReplays() {
        let app = launch("v020-tictactoe")
        open("tictactoe", app: app)
        choose("tictactoe.mode", option: "Two players on this device", app: app)
        startNew("tictactoe", app: app)
        for cell in [0, 3, 1, 4] { tap("tictactoe.cell.\(cell)", app: app) }
        XCTAssertTrue(app.staticTexts["tictactoe.moves"].label.contains("4"))
        pauseResume("tictactoe", app: app)
        restore("tictactoe", app: app)
        XCTAssertTrue(app.staticTexts["tictactoe.moves"].label.contains("4"))
        XCTAssertTrue(app.buttons["tictactoe.cell.0"].label.contains("X"))
        XCTAssertTrue(app.buttons["tictactoe.cell.3"].label.contains("O"))
        tap("tictactoe.cell.2", app: app)
        finishReviewAndReturnToMenu("tictactoe", moves: 5, app: app, screenshot: "v020-tictactoe-win")
        choose("tictactoe.mode", option: "Two players on this device", app: app)
        startNew("tictactoe", app: app)
        XCTAssertFalse(app.buttons["tictactoe.session.done"].exists)
        XCTAssertTrue(app.staticTexts["tictactoe.moves"].label.contains("0"))
        XCTAssertTrue(app.buttons["tictactoe.cell.0"].isEnabled)
    }

    func testConnectFourLocalRoundRestoresWinsAndReplays() {
        let app = launch("v020-connectfour")
        open("connectfour", app: app)
        choose("connectfour.mode", option: "Two players on this device", app: app)
        startNew("connectfour", app: app)
        for column in [0, 1, 0, 1, 0, 1] { tap("connectfour.column.\(column)", app: app) }
        XCTAssertTrue(app.staticTexts["connectfour.moves"].label.contains("6"))
        pauseResume("connectfour", app: app)
        restore("connectfour", app: app)
        XCTAssertTrue(app.staticTexts["connectfour.moves"].label.contains("6"))
        tap("connectfour.column.0", app: app)
        finishReviewAndReturnToMenu("connectfour", moves: 7, app: app, screenshot: "v020-connectfour-win")
        choose("connectfour.mode", option: "Two players on this device", app: app)
        startNew("connectfour", app: app)
        XCTAssertFalse(app.buttons["connectfour.session.done"].exists)
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

    private func expectUI(_ message: String, timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
    }

    private func expectBoardInputReady(_ game: String, app: XCUIApplication) {
        let prefix = game == "tictactoe" ? "tictactoe.cell." : "connectfour.column."
        let controls = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        expectUI("The visible player turn must accept input after the actual animation settles.") {
            controls.allElementsBoundByIndex.contains { $0.exists && $0.isEnabled }
        }
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
    private func inspectSinglePlayerAI(_ game: String,difficulty: String) {
        executionTimeAllowance = 420
        let cellPrefix = game == "tictactoe" ? "tictactoe.cell." : "connectfour.column."
        let cellCount = game == "tictactoe" ? 9 : 7
        do {
            for computerFirst in [false, true] {
                let app = launch("v020-" + game)
                open(game, app: app)
                choose(game + ".mode", option: "Play the computer", app: app)
                choose(game + ".difficulty", option: difficulty, app: app)
                let first = game == "tictactoe"
                    ? (computerFirst ? "Computer first (X)" : "You first (X)")
                    : (computerFirst ? "Computer first · star" : "You first · star")
                choose(game + ".first", option: first, app: app)
                startNew(game, app: app)

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
                expectBoardInputReady(game, app: app)
                XCTAssertFalse(app.buttons[game + ".session.done"].exists)
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
                continueGame(game, app: app)
                expectMoves(replyMoves, game: game, app: app)
                expectHumanTurn(game, computerFirst: computerFirst, app: app)
                assertMovesStay(replyMoves, game: game, app: app)
                XCTAssertEqual(board, (0..<cellCount).map { app.buttons[cellPrefix + String($0)].label })
                capture(app, "v020-\(game)-ai-\(difficulty.lowercased())-\(computerFirst ? "computer-first" : "human-first")")
                app.terminate()
            }
        }
    }

    // Each case retains both first-player choices and every pause/relaunch
    // assertion. An Intel run needs ~140s per round; six rounds in one case
    // exhausted XCTest's 600s cap during Hard, despite the earlier rounds passing.
    func testTicTacToeAIEasyRepliesWithEitherFirstPlayer() { inspectSinglePlayerAI("tictactoe",difficulty:"Easy") }
    func testTicTacToeAINormalRepliesWithEitherFirstPlayer() { inspectSinglePlayerAI("tictactoe",difficulty:"Normal") }
    func testTicTacToeAIHardRepliesWithEitherFirstPlayer() { inspectSinglePlayerAI("tictactoe",difficulty:"Hard") }
    func testConnectFourAIEasyRepliesWithEitherFirstPlayer() { inspectSinglePlayerAI("connectfour",difficulty:"Easy") }
    func testConnectFourAINormalRepliesWithEitherFirstPlayer() { inspectSinglePlayerAI("connectfour",difficulty:"Normal") }
    func testConnectFourAIHardRepliesWithEitherFirstPlayer() { inspectSinglePlayerAI("connectfour",difficulty:"Hard") }

    func testBoardGameThinkingAndDropGatesRejectExtraInput() {
        // The cells/drop assertions below are specific to these two released
        // games. The expanded catalog also has six different board APIs.
        for game in ["tictactoe","connectfour"] {
            let app = launch("v021-" + game)
            open(game, app: app)
            if game == "tictactoe" {
                choose(game + ".mode", option: "Play the computer", app: app)
                choose(game + ".difficulty", option: "Hard", app: app)
                choose(game + ".first", option: "You first (X)", app: app)
            } else {
                choose(game + ".mode", option: "Two players on this device", app: app)
            }
            startNew(game, app: app)
            expectBoardInputReady(game, app: app)
            let prefix = game == "tictactoe" ? "tictactoe.cell." : "connectfour.column."
            let first = app.buttons[prefix + "0"]
            show(first, app: app)
            // One XCTest compound event supplies both touches. Separate commands
            // can outlast a valid short animation on a busy simulator.
            first.doubleTap()
            if game == "connectfour" {
                // Local play makes the second touch a legal next-player move
                // unless the actual falling-disc input gate rejects it.
                expectBoardInputReady(game, app: app)
                expectMoves(1, game: game, app: app)
                assertMovesStay(1, game: game, app: app)
                tap(prefix + "1", app: app)
            }
            expectMoves(2, game: game, app: app)
            expectBoardInputReady(game, app: app)
            if game == "tictactoe" {
                expectHumanTurn(game, computerFirst: false, app: app)
                let cells = (0..<9).map { app.buttons[prefix + String($0)].label }
                XCTAssertEqual(cells.filter { $0.contains("Empty") }.count, 7)
                XCTAssertTrue(app.buttons[prefix + "0"].label.hasSuffix("X"))
            }
            let board = (0..<(game == "tictactoe" ? 9 : 7)).map { app.buttons[prefix + String($0)].label }
            assertMovesStay(2, game: game, app: app)
            pauseResume(game, app: app)
            restore(game, app: app)
            expectMoves(2, game: game, app: app)
            expectBoardInputReady(game, app: app)
            assertMovesStay(2, game: game, app: app)
            XCTAssertEqual(board, (0..<(game == "tictactoe" ? 9 : 7)).map { app.buttons[prefix + String($0)].label })
            capture(app, "v021-" + game + "-thinking-input-gate")
            app.terminate()
        }
    }

    func testMemoryFlipMismatchGatesAndReducedMotionPreserveNativeCards() {
        for reducedMotion in [false, true] {
            let app = launch("v021-memory", fixture: "memory-fresh",
                             extra: reducedMotion ? ["--ui-reduce-motion"] : [])
            open("memory", app: app); continueGame("memory", app: app)
            requireMemoryButtons(16, app: app)
            let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.card.'"))
            XCTAssertTrue(cards.allElementsBoundByIndex.allSatisfy { $0.isEnabled && $0.label.contains("face down") })
            // Legal seed24: index0 Flame, index1 Sun, index2 Moon; Sun's pair is3.
            // Core presentation tests cover third-card gating through reveal,
            // hold, and close. Compound UI events verify duplicate touches and
            // stable results without trying to sample a subsecond phase.
            let first = app.buttons["memory.card.0"], second = app.buttons["memory.card.1"]
            show(first, app: app); first.doubleTap()
            expectUI("A duplicate first-card touch must leave one revealed card and no counted turn.") {
                first.label.contains("Flame, face up") && second.label.contains("face down") && app.staticTexts["memory.moves"].label == "Moves 0"
            }
            show(second, app: app); second.doubleTap()
            XCTAssertTrue(app.buttons["memory.card.2"].label.contains("face down"), "An unselected card must not reveal during a mismatch turn.")
            expectUI("The completed reveal, hold, and close must restore both unmatched cards.") {
                app.buttons["memory.card.0"].label.contains("face down") && app.buttons["memory.card.1"].label.contains("face down") && app.buttons["memory.card.2"].isEnabled
            }
            XCTAssertEqual(app.staticTexts["memory.moves"].label, "Moves 1")
            XCTAssertEqual(app.staticTexts["memory.pairs"].label, "Pairs 0/8")
            tap("memory.card.1", app: app); tap("memory.card.3", app: app)
            expectUI("A real matching flip must leave two native disabled cards.") {
                !app.buttons["memory.card.1"].isEnabled && !app.buttons["memory.card.3"].isEnabled && app.buttons["memory.card.0"].isEnabled
            }
            XCTAssertTrue(app.buttons["memory.card.1"].label.contains("Sun, matched"))
            XCTAssertEqual(app.staticTexts["memory.moves"].label, "Moves 2")
            XCTAssertEqual(app.staticTexts["memory.pairs"].label, "Pairs 1/8")
            tap("memory.card.0", app: app)
            pauseResume("memory", app: app)
            XCTAssertTrue(app.buttons["memory.card.0"].label.contains("face down"))
            restore("memory", app: app)
            requireMemoryButtons(16, app: app)
            XCTAssertEqual(app.staticTexts["memory.moves"].label, "Moves 2")
            XCTAssertEqual(cards.allElementsBoundByIndex.filter(\.isEnabled).count, 14)
            XCTAssertTrue(app.buttons["memory.card.2"].label.contains("face down"))
            capture(app, "v021-memory-flip-" + (reducedMotion ? "reduced" : "normal"))
            app.terminate()
        }
    }

    func testMazeJoystickMovesContinuouslyStopsAndRestoresCell() {
        for reducedMotion in [false, true] {
            let app = launch("v021-maze", fixture: "maze-joystick",
                             extra: reducedMotion ? ["--ui-reduce-motion"] : [])
            open("maze", app: app); continueGame("maze", app: app)
            let joystick = app.descendants(matching: .any).matching(identifier: "maze.joystick").firstMatch
            XCTAssertTrue(joystick.waitForExistence(timeout: 10))
            show(joystick, app: app)
            XCTAssertEqual(joystick.frame.width, 120, accuracy: 1)
            XCTAssertEqual(joystick.frame.height, 120, accuracy: 1)
            let center = joystick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let blockedDiagonal = joystick.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.15))
            center.press(forDuration: 0.02, thenDragTo: blockedDiagonal, withVelocity: .fast, thenHoldForDuration: 0.3)
            expectMoves(0, game: "maze", app: app)
            let down = joystick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            center.press(forDuration: 0.02, thenDragTo: down, withVelocity: .fast, thenHoldForDuration: 2)
            // Seed42 has exactly two open cells below the start, then a wall.
            expectMoves(2, game: "maze", app: app)
            XCTAssertTrue(app.staticTexts["maze.position"].label.contains("Row 3, column 1"))
            expectUI("Lifting the real joystick must return it to the stopped state.") { joystick.value as? String == "Stopped" }
            assertMovesStay(2, game: "maze", app: app)
            center.press(forDuration: 0.02, thenDragTo: down, withVelocity: .fast, thenHoldForDuration: 0.4)
            expectMoves(2, game: "maze", app: app)
            pauseResume("maze", app: app)
            restore("maze", app: app)
            expectMoves(2, game: "maze", app: app)
            XCTAssertTrue(app.staticTexts["maze.position"].label.contains("Row 3, column 1"))
            show(joystick, app: app)
            let returnCenter = joystick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let up = joystick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            returnCenter.press(forDuration: 0.02, thenDragTo: up, withVelocity: .fast, thenHoldForDuration: 2)
            expectMoves(4, game: "maze", app: app)
            XCTAssertTrue(app.staticTexts["maze.position"].label.contains("Row 1, column 1"))
            expectUI("Releasing the opposite-direction gesture must stop movement.") { joystick.value as? String == "Stopped" }
            assertMovesStay(4, game: "maze", app: app)
            capture(app, "v021-maze-joystick-" + (reducedMotion ? "reduced" : "normal"))
            app.terminate()
        }
    }

    func testTwentyFourOrderedInputHistoryAndZeroDivision() {
        let app = launch("v021-twentyfour", fixture: "twentyfour-fresh")
        open("twentyfour", app: app); continueGame("twentyfour", app: app)
        let originalCards = (0..<4).map { app.buttons["twentyfour.card.\($0)"].label }
        for operation in ["add", "subtract", "multiply", "divide"] {
            XCTAssertFalse(app.buttons["twentyfour.operator." + operation].isEnabled)
            XCTAssertFalse(app.buttons["twentyfour.operator." + operation].isSelected)
        }
        XCTAssertFalse(app.buttons["twentyfour.apply"].isEnabled)
        tap("twentyfour.card.0", app: app)
        XCTAssertEqual(app.staticTexts["twentyfour.stage"].label, "2 · Choose an operator")
        tap("twentyfour.card.1", app: app)
        XCTAssertEqual(app.buttons["twentyfour.card.1"].value as? String, "First number")
        XCTAssertEqual(app.buttons["twentyfour.card.0"].value as? String, "Not selected")
        tap("twentyfour.operator.add", app: app)
        XCTAssertEqual(app.staticTexts["twentyfour.stage"].label, "3 · Choose your second number")
        tap("twentyfour.card.0", app: app)
        XCTAssertEqual(app.buttons["twentyfour.card.0"].value as? String, "Second number")
        let timer = app.staticTexts["twentyfour.timer"], beforeTick = app.staticTexts["twentyfour.timer"].label
        expectUI("A real timer tick must not clear the pending input.", timeout: 10) { timer.label != beforeTick }
        XCTAssertTrue(app.buttons["twentyfour.operator.add"].isSelected)
        XCTAssertEqual(app.buttons["twentyfour.card.1"].value as? String, "First number")
        XCTAssertEqual(app.buttons["twentyfour.card.0"].value as? String, "Second number")
        tap("twentyfour.apply", app: app)
        let result = app.buttons["twentyfour.card.4"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); show(result, app: app)
        XCTAssertEqual(result.frame.minY, app.buttons["twentyfour.card.2"].frame.minY, accuracy: 2)
        XCTAssertLessThan(result.frame.minX, app.buttons["twentyfour.card.2"].frame.minX)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'twentyfour.card.'")).count, 3)
        // Assert the real readable calculation. SwiftUI propagates the history
        // container's identifier to its noninteractive combined text rows.
        let history0 = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2 + 1 = 3")).firstMatch
        show(history0, app: app, requireHittable: false)
        XCTAssertTrue(history0.label.contains("2 + 1 = 3"))
        let firstHistory = XCTAttachment(string: app.debugDescription)
        firstHistory.name = "v021-twentyfour-readable-first-calculation"
        firstHistory.lifetime = .keepAlways; add(firstHistory)
        capture(app, "v021-twentyfour-first-calculation")
        tap("twentyfour.card.4", app: app); tap("twentyfour.operator.divide", app: app)
        tap("twentyfour.card.3", app: app); tap("twentyfour.apply", app: app)
        XCTAssertTrue(app.buttons["twentyfour.card.5"].waitForExistence(timeout: 5))
        let history1 = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3 ÷ 4 = 3/4")).firstMatch
        show(history1, app: app, requireHittable: false)
        XCTAssertTrue(history1.label.contains("3 ÷ 4 = 3/4"))
        tap("twentyfour.undo", app: app)
        expectUI("Undo must remove the last real calculation and restore its operands.") {
            !history1.exists && app.buttons["twentyfour.card.4"].exists && app.buttons["twentyfour.card.3"].exists
        }
        tap("twentyfour.card.4", app: app); tap("twentyfour.clear", app: app)
        XCTAssertEqual(app.staticTexts["twentyfour.stage"].label, "1 · Choose your first number")
        let undo = app.buttons.matching(identifier: "twentyfour.undo").firstMatch
        show(undo, app: app)
        XCTAssertTrue(undo.isEnabled && undo.isHittable)
        undo.tap()
        let emptyHistory = app.staticTexts.matching(NSPredicate(format: "label == %@", "Each calculation will appear here. Undo removes the last step.")).firstMatch
        show(emptyHistory, app: app, requireHittable: false)
        XCTAssertTrue(emptyHistory.exists)
        XCTAssertFalse(history0.exists); XCTAssertFalse(history1.exists)
        let resetHistory = XCTAttachment(string: app.debugDescription)
        resetHistory.name = "v022-twentyfour-undo-visible-empty-calculation-history"
        resetHistory.lifetime = .keepAlways; add(resetHistory)
        capture(app, "v022-twentyfour-undo-empty-history")
        for _ in 0..<6 {
            if app.buttons["twentyfour.card.0"].exists { break }
            app.swipeDown()
        }
        show(app.buttons["twentyfour.card.0"], app: app)
        expectUI("Undoing every real calculation must restore the original four cards and clear history.") {
            !history0.exists && app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'twentyfour.card.'")).count == 4
        }
        XCTAssertEqual((0..<4).map { app.buttons["twentyfour.card.\($0)"].label }, originalCards)
        capture(app, "v021-twentyfour-ordered-input-and-history")
        app.terminate()

        let zero = launch("v021-twentyfour", fixture: "twentyfour-zero")
        open("twentyfour", app: zero); continueGame("twentyfour", app: zero)
        tap("twentyfour.card.3", app: zero); tap("twentyfour.operator.divide", app: zero)
        tap("twentyfour.card.5", app: zero)
        let explanation = zero.staticTexts["twentyfour.zeroDivision"]
        show(explanation, app: zero, requireHittable: false)
        XCTAssertTrue(explanation.label.contains("Cannot divide by zero"))
        XCTAssertFalse(zero.buttons["twentyfour.apply"].isEnabled)
        XCTAssertEqual(zero.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'twentyfour.card.'")).count, 2)
        tap("twentyfour.swap", app: zero)
        XCTAssertTrue(zero.buttons["twentyfour.apply"].isEnabled)
        XCTAssertFalse(explanation.exists)
        capture(zero, "v021-twentyfour-zero-division-order")
    }

    func testTwentyFourRestoresExactCardsCompletesAndStartsNextPuzzle() {
        let app = launch("v020-twentyfour", fixture: "twentyfour")
        open("twentyfour", app: app)
        choose("twentyfour.difficulty", option: "Easy", app: app)
        continueGame("twentyfour", app: app)
        let labels = [3, 5].map { app.buttons["twentyfour.card.\($0)"].label }
        pauseResume("twentyfour", app: app)
        restore("twentyfour", app: app)
        XCTAssertEqual(labels, [3, 5].map { app.buttons["twentyfour.card.\($0)"].label })
        tap("twentyfour.card.3", app: app); tap("twentyfour.operator.multiply", app: app)
        tap("twentyfour.card.5", app: app); tap("twentyfour.apply", app: app)
        finishReviewAndReturnToMenu("twentyfour", moves: 3, app: app, screenshot: "v020-twentyfour-win")
        XCTAssertTrue(app.buttons["twentyfour.continue"].label.contains("3 operations · 1 solved"))
        startNew("twentyfour", app: app)
        XCTAssertFalse(app.buttons["twentyfour.session.done"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'twentyfour.card.'")).count, 4)
        XCTAssertEqual(app.staticTexts["twentyfour.solved"].label, "0 solved")
    }

    func testMemoryRestoresMatchesHidesUnturnedCardsCompletesAndReplays() {
        let app = launch("v020-memory", fixture: "memory")
        open("memory", app: app); tap("memory.mode.easy", app: app); continueGame("memory", app: app)
        XCTAssertTrue(app.staticTexts["memory.pairs"].label.contains("7/8"))
        requireMemoryButtons(16, app: app)
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
        finishReviewAndReturnToMenu("memory", moves: 8, app: app, screenshot: "v020-memory-win")
        XCTAssertTrue(app.buttons["memory.continue"].label.contains("8/8"))
        tap("memory.mode.easy", app: app)
        startNew("memory", app: app)
        XCTAssertFalse(app.buttons["memory.session.done"].exists)
        XCTAssertTrue(app.staticTexts["memory.pairs"].label.contains("0/8"))
        XCTAssertEqual(cards.count, 16)
        XCTAssertTrue(cards.allElementsBoundByIndex.allSatisfy { $0.isEnabled && $0.label.contains("face down") })
    }

    func testMazeRestoresPositionResumesCompletesAndGeneratesNextMaze() {
        let app = launch("v020-maze", fixture: "maze")
        open("maze", app: app)
        choose("maze.difficulty", option: "Easy · 9×9", app: app)
        continueGame("maze", app: app)
        XCTAssertTrue(app.staticTexts["maze.moves"].label.contains("42"))
        tap("maze.right", app: app)
        XCTAssertTrue(app.staticTexts["maze.moves"].label.contains("43"))
        let position = app.staticTexts["maze.position"].label
        restore("maze", app: app)
        XCTAssertEqual(app.staticTexts["maze.position"].label, position)
        XCTAssertTrue(app.staticTexts["maze.moves"].label.contains("43"))
        tap("maze.down", app: app)
        finishReviewAndReturnToMenu("maze", moves: 44, app: app, screenshot: "v020-maze-win")
        choose("maze.difficulty", option: "Easy · 9×9", app: app)
        startNew("maze", app: app)
        XCTAssertFalse(app.buttons["maze.session.done"].exists)
        XCTAssertTrue(app.staticTexts["maze.moves"].label.contains("0"))
        XCTAssertTrue(app.staticTexts["maze.position"].label.contains("Row 1, column 1"))
    }

    func testNewPuzzleModesStartRealBoards() {
        for game in ["twentyfour", "memory", "maze"] {
            let app = launch("v020-" + game)
            open(game, app: app)
            if game == "memory" { tap("memory.mode.hard", app: app) }
            else { choose(game + ".difficulty", option: game == "maze" ? "Hard · 21×21" : "Hard", app: app) }
            startNew(game, app: app)
            if game == "memory" {
                requireMemoryButtons(36, app: app)
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
        tapNativeConfirmation("storage.confirmRecovery.memory", app: app)
        XCTAssertFalse(app.buttons["storage.recover.memory"].exists)
        XCTAssertTrue(app.buttons["memory.start"].isEnabled)
        startNew("memory", app: app)
        XCTAssertTrue(app.buttons["memory.card.0"].waitForExistence(timeout: 5))
        back(app); back(app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["game.sudoku"].waitForExistence(timeout: 10))
        open("sudoku", app: app); continueGame("sudoku", app: app)
        XCTAssertTrue((app.buttons["sudoku.cell.1"].value as? String ?? "").contains("2, 7"))
        back(app); back(app)
        open("minesweeper", app: app); continueGame("minesweeper", app: app)
        XCTAssertTrue(app.buttons["mines.cell.30"].label.contains("Flagged"))
        back(app); back(app)
        open("sliding", app: app); continueGame("sliding", app: app)
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
                tap("catalog.boardgames", app: app)
                assertThreeColumns(app, width: CGFloat(width), prefix: "", ids: ["game.tictactoe", "game.connectfour", "game.gomoku"])
                capture(app, "v021-viewport-\(width)-\(language)-\(appearance)-boardgames")
                back(app)
                tap("catalog.solitaire", app: app)
                assertThreeColumns(app, width: CGFloat(width), prefix: "game.", ids: Array(solitaire.prefix(3)))
                capture(app, "v020-viewport-\(width)-\(language)-\(appearance)-solitaire")
                back(app)
                show(app.buttons["game.brickbreaker"], app: app)
                XCTAssertTrue(app.buttons["game.brickbreaker"].isHittable)
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
                let title = language == "en" ? "Classic Games" : "經典小遊戲"
                let fullTitle = app.staticTexts.matching(identifier: "home.accessibleTitle").firstMatch
                XCTAssertTrue(fullTitle.waitForExistence(timeout: 5))
                XCTAssertEqual(fullTitle.label, title)
                XCTAssertTrue(visibleArea(app).contains(fullTitle.frame), "The complete multiline Home title must fit inside the visible scroll viewport.")
                attachUIEvidence(app, name: "v020-viewport-320-\(language)-\(size)-full-title")
                show(first, app: app)
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
