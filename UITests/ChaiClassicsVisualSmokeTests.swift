import XCTest
import UIKit

/// Focused 0.1.3 smoke selection; the existing full game/regression suite remains intact.
final class ChaiClassicsVisualSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // Also request the measured allowance when this class is included in
        // manual full UI. Xcode still enforces that invocation's maximum cap.
        executionTimeAllowance = 300
    }

    private func launch(profile: String, suppressionFlag: String? = nil, allGames: Bool = false) throws -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["--ui-testing", "--ui-celebration-probe", "--ui-profile", profile]
        if let suppressionFlag { arguments.append(suppressionFlag) }
        app.launchArguments = arguments + ["--ui-reset"]
        let namespaces = allGames ? ["sudoku", "minesweeper", "sliding"] : ["sliding"]
        for namespace in namespaces {
            let seed = try XCTUnwrap(Bundle(for: ChaiClassicsVisualSmokeTests.self).url(forResource: "v010-" + namespace, withExtension: "json"))
            app.launchEnvironment["CHAI_UI_SEED_" + namespace.uppercased()] = try Data(contentsOf: seed).base64EncodedString()
        }
        app.launch()
        app.launchArguments = arguments // A second launch must retain the actual won save.
        XCTAssertTrue(app.buttons["game.sliding"].waitForExistence(timeout: 10))
        return app
    }

    private func openSavedSliding(_ app: XCUIApplication) {
        app.buttons["game.sliding"].tap()
        let resume = app.buttons["sliding.continue"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        scrollFullyIntoView(resume, app: app); resume.tap()
        XCTAssertTrue(app.buttons["sliding.tile.8"].waitForExistence(timeout: 5))
    }

    private func expectProbe(_ app: XCUIApplication, starts: Int, active: Bool? = nil) {
        let probe = app.staticTexts["uitest.celebration.probe"]
        let expectedStarts = "starts=\(starts);"
        let expectedActive = active.map { "active=\($0 ? 1 : 0)" }
        let matches = NSPredicate { _, _ in
            guard probe.exists, let value = probe.value as? String else { return false }
            guard value.contains(expectedStarts) else { return false }
            if let expectedActive { return value.contains(expectedActive) }
            return true
        }
        expectation(for: matches, evaluatedWith: nil)
        waitForExpectations(timeout: 6)
    }

    private func finishSeed(_ app: XCUIApplication, capturesWin: Bool = false) {
        app.buttons["sliding.tile.8"].swipeLeft()
        if capturesWin { screenshot(app, name: "visual-013-winning-banner") }
        XCTAssertTrue(app.staticTexts["sliding.complete"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["sliding.moves"].label.contains("36"))
        XCTAssertFalse(app.buttons["sliding.pause"].isEnabled)
    }

    private func screenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func back(_ app: XCUIApplication) { app.buttons["navigation.back"].tap() }

    private func scrollFullyIntoView(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<5 {
            // Navigation can finish changing from a large Home title to an
            // inline destination title during this search. Never cache its frame.
            let window = app.frame
            let navigation = app.navigationBars.firstMatch
            let top = navigation.exists ? navigation.frame.maxY : window.minY
            let usable = CGRect(x: window.minX + 10, y: top, width: window.width - 20, height: window.maxY - 20 - top)
            if element.exists {
                let frame = element.frame
                if frame.width > 0 && frame.height > 0 && usable.contains(frame) { return }
                if frame.height > 0 && frame.minY < usable.minY { app.swipeDown(); continue }
            }
            app.swipeUp()
        }
        let identifier = element.exists ? element.identifier : "missing-control"
        attachUIEvidence(app, name: "scroll-visibility-failure-" + identifier)
        XCTFail("Control did not become fully visible: " + identifier)
    }

    func testFreshWinCelebratesOnceAndRestoredWinDoesNotReplay() throws {
        let app = try launch(profile: "visual-normal")
        screenshot(app, name: "visual-013-home-light")
        openSavedSliding(app)
        expectProbe(app, starts: 0, active: false)
        screenshot(app, name: "visual-013-sliding-play-light")
        app.buttons["sliding.pause"].tap()
        XCTAssertTrue(app.buttons["game.resume"].waitForExistence(timeout: 5))
        screenshot(app, name: "visual-013-sliding-pause-light")
        app.buttons["game.resume"].tap()
        finishSeed(app, capturesWin: true)
        // Count is a Debug-Simulator probe of actual starts. The short-lived,
        // noninteractive effect can end before XCTest finishes waiting for idle.
        expectProbe(app, starts: 1)
        expectProbe(app, starts: 1, active: false)
        screenshot(app, name: "visual-013-fresh-win")

        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["game.sliding"].waitForExistence(timeout: 10))
        openSavedSliding(app)
        XCTAssertTrue(app.staticTexts["sliding.complete"].exists)
        expectProbe(app, starts: 0, active: false)

        app.buttons["sliding.restart"].tap()
        tapNativeConfirmation("sliding.confirmRestart", app: app)
        let restarted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.staticTexts["sliding.complete"].exists &&
            app.staticTexts["sliding.moves"].label == "0 步" &&
            app.buttons["sliding.tile.7"].isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restarted], timeout: 10), .completed)
        XCTAssertFalse(app.staticTexts["sliding.complete"].exists)
        XCTAssertEqual(app.staticTexts["sliding.moves"].label, "0 步")
        XCTAssertEqual(app.buttons["sliding.tile.6"].label, "空格")
        expectProbe(app, starts: 0, active: false)
    }

    func testReducedMotionSuppressesCelebrationButStillCompletesGame() throws {
        let app = try launch(profile: "visual-reduced", suppressionFlag: "--ui-reduce-motion")
        openSavedSliding(app)
        expectProbe(app, starts: 0, active: false)
        finishSeed(app)
        expectProbe(app, starts: 0, active: false)
        screenshot(app, name: "visual-013-reduced-motion-win")
    }

    func testLowPowerSuppressesCelebrationButStillCompletesGame() throws {
        let app = try launch(profile: "visual-lowpower", suppressionFlag: "--ui-low-power")
        openSavedSliding(app)
        expectProbe(app, starts: 0, active: false)
        finishSeed(app)
        expectProbe(app, starts: 0, active: false)
        screenshot(app, name: "visual-013-low-power-win")
    }

    func testScreenshotGallery() throws {
        let app = try launch(profile: "visual-gallery", allGames: true)
        app.buttons["settings.open"].tap()
        app.segmentedControls["settings.appearance"].buttons["深色"].tap()
        XCTAssertTrue(app.staticTexts["settings.resolvedAppearance"].label.contains("深色"))
        screenshot(app, name: "visual-013-settings-dark")
        let support = app.buttons["legal.support"]
        scrollFullyIntoView(support, app: app); support.tap()
        let page = app.descendants(matching: .any).matching(identifier: "document.support").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        screenshot(app, name: "visual-013-support-dark")
        back(app); back(app)
        screenshot(app, name: "visual-013-home-dark")

        for (game, playElement) in [("sudoku", "sudoku.cell.1"), ("minesweeper", "mines.cell.30"), ("sliding", "sliding.tile.8")] {
            app.buttons["game." + game].tap()
            let title = ["sudoku": "數獨", "minesweeper": "踩地雷", "sliding": "滑塊拼圖"][game]!
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
            let menuBack = app.buttons.matching(identifier: "navigation.back").firstMatch
            XCTAssertTrue(menuBack.waitForExistence(timeout: 5)); XCTAssertTrue(menuBack.isHittable)
            screenshot(app, name: "visual-013-" + game + "-menu-dark")
            let continueID = game == "minesweeper" ? "mines.continue" : game + ".continue"
            let resume = app.buttons[continueID]
            scrollFullyIntoView(resume, app: app); resume.tap()
            XCTAssertTrue(app.buttons[playElement].waitForExistence(timeout: 5))
            let prefix = game == "minesweeper" ? "mines" : game
            XCTAssertTrue(app.buttons[prefix + ".restart"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["navigation.back"].isHittable)
            screenshot(app, name: "visual-013-" + game + "-play-dark")
            if game == "sliding" {
                app.buttons["sliding.pause"].tap()
                XCTAssertTrue(app.buttons["game.resume"].waitForExistence(timeout: 5))
                screenshot(app, name: "visual-013-sliding-pause-dark")
                app.buttons["game.resume"].tap()
            }
            back(app); back(app)
        }
    }

    // These independent, manually selected cases preserve the other screenshots
    // if one game's iPad assertions fail. The original phone smoke cases above
    // remain unchanged and never execute these iPad-only interactions.
    private func launchIPadGallery() throws -> XCUIApplication {
        executionTimeAllowance = 600
        XCUIDevice.shared.orientation = .portrait
        let app = try launch(profile: "visual-gallery", allGames: true)
        XCTAssertGreaterThan(app.frame.height, app.frame.width)
        app.buttons["settings.open"].tap()
        let chinese = app.segmentedControls["settings.language"].buttons["繁體中文"]
        XCTAssertTrue(chinese.waitForExistence(timeout: 5)); chinese.tap()
        XCTAssertTrue(chinese.isSelected)
        let dark = app.segmentedControls["settings.appearance"].buttons["深色"]
        XCTAssertTrue(dark.isHittable); dark.tap()
        XCTAssertTrue(dark.isSelected)
        XCTAssertTrue(app.staticTexts["settings.resolvedAppearance"].label.contains("深色"))
        back(app)
        XCTAssertTrue(app.buttons["game.sudoku"].waitForExistence(timeout: 5))
        return app
    }

    private func assertIPadVisible(_ element: XCUIElement, app: XCUIApplication, toolbar: Bool = false, interactive: Bool = true) {
        let exists = element.waitForExistence(timeout: 5)
        XCTAssertTrue(exists, "Required iPad element is missing.")
        guard exists else { return }
        let identifier = element.identifier
        let window = app.frame
        let navigation = app.navigationBars.firstMatch
        let top = toolbar || !navigation.exists ? window.minY : navigation.frame.maxY
        let usable = CGRect(x: window.minX, y: top - 1, width: window.width,
                            height: window.maxY - 20 - top)
        let frame = element.frame
        XCTAssertGreaterThan(frame.width, 0, identifier)
        XCTAssertGreaterThan(frame.height, 0, identifier)
        XCTAssertTrue(usable.contains(frame), "Control is clipped: " + identifier)
        if interactive { XCTAssertTrue(element.isHittable, identifier) }
    }

    private func openIPadSavedGame(_ app: XCUIApplication, game: String, prefix: String, firstCell: String) {
        assertIPadVisible(app.buttons["game." + game], app: app)
        app.buttons["game." + game].tap()
        let resume = app.buttons[prefix + ".continue"]
        // No blind app.swipe here: on iPad the center is the interactive board.
        assertIPadVisible(resume, app: app)
        // ContinueCard's leading 42pt play icon has a painted background;
        // its wide Form-row center can be transparent Spacer on iPad.
        resume.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 24, dy: 0)).tap()
        // Prove navigation independently of a cell's accessibility traits.
        XCTAssertTrue(app.buttons[prefix + ".restart"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[firstCell].waitForExistence(timeout: 5))
    }

    private func assertIPadPauseResume(_ app: XCUIApplication, prefix: String, firstCell: String) {
        let pause = app.buttons[prefix + ".pause"]
        assertIPadVisible(pause, app: app)
        XCTAssertTrue(pause.isEnabled); pause.tap()
        let resume = app.buttons["game.resume"]
        assertIPadVisible(resume, app: app)
        XCTAssertFalse(app.buttons[firstCell].exists)
        resume.tap()
        XCTAssertTrue(app.buttons[firstCell].waitForExistence(timeout: 5))
        XCTAssertTrue(pause.isEnabled)
    }

    private func cancelIPadRestart(_ app: XCUIApplication, prefix: String) {
        let restart = app.buttons[prefix + ".restart"]
        assertIPadVisible(restart, app: app, toolbar: true); restart.tap()
        let confirm = app.buttons.matching(identifier: prefix + ".confirmRestart").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        // iPad confirmation popovers may omit the Cancel action. Dismiss from
        // the empty lower-left margin, outside both popover and game board.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.94)).tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: confirm)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertFalse(confirm.exists)
    }

    private func assertIPadCaptureReady(_ app: XCUIApplication, prefix: String? = nil) {
        if let prefix {
            assertIPadVisible(app.buttons[prefix + ".restart"], app: app, toolbar: true)
            assertIPadVisible(app.buttons["navigation.back"], app: app, toolbar: true)
        } else {
            assertIPadVisible(app.buttons["settings.open"], app: app, toolbar: true)
        }
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertEqual(app.sheets.count, 0)
        XCTAssertEqual(app.popovers.count, 0)
        XCTAssertEqual(app.keyboards.count, 0)
        XCTAssertGreaterThan(app.frame.height, app.frame.width)
    }

    private func attachIPadLayout(_ app: XCUIApplication, page: String, grid: [XCUIElement], controls: [XCUIElement], viewport: XCUIElement? = nil) throws {
        func rectangle(_ frame: CGRect) -> [String: Double] {
            ["x": Double(frame.minX), "y": Double(frame.minY),
             "width": Double(frame.width), "height": Double(frame.height)]
        }
        func elementGeometry(_ element: XCUIElement) -> [String: Any] {
            // Reading identifier/frame on a missing firstMatch is a fatal
            // XCTest snapshot request, including perfectly normal absent tables.
            guard element.exists else { return ["exists": false] }
            return ["identifier": element.identifier, "exists": true,
                    "frame": rectangle(element.frame)]
        }
        let bounds = grid.filter(\.exists).reduce(CGRect.null) { $0.union($1.frame) }
        var warnings = [String]()
        if !bounds.isNull && bounds.width < app.frame.width * 0.65 {
            warnings.append("BOARD_HAS_WIDE_SIDE_MARGINS_ON_13_INCH")
        }
        if !bounds.isNull && app.frame.maxY - bounds.maxY > app.frame.height * 0.20 {
            warnings.append("SPACE_BELOW_BOARD_EXCEEDS_20_PERCENT_OF_WINDOW")
        }
        if page == "Minesweeper" {
            warnings.append("COMPACT_9X9_VIEWPORT_HEIGHT_IS_CAPPED_AT_520_2_POINTS_BY_EXISTING_APP")
        }
        var report: [String: Any] = [
            "page": page, "orientation": "portrait", "language": "zh-Hant", "appearance": "dark",
            "testNavigationStrategy": page == "Home" ? "Settings selected through native controls; game entry not exercised in this case." : "Tap the Continue button's visible leading play area using button-local coordinates, then require restart and an actionable saved cell.",
            "screen": rectangle(app.frame), "navigation": elementGeometry(app.navigationBars.firstMatch),
            "table": elementGeometry(app.tables.firstMatch), "scrollContent": elementGeometry(app.scrollViews.firstMatch),
            "gridBounds": bounds.isNull ? [:] : rectangle(bounds),
            "gridSamples": grid.map(elementGeometry), "controls": controls.map(elementGeometry),
            "warnings": warnings,
            "scope": "Synthetic saved games; functional visibility assertions and measured layout, not a claim that all layouts have been reviewed."
        ]
        if let viewport { report["zoomViewport"] = elementGeometry(viewport) }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(string: String(decoding: data, as: UTF8.self))
        attachment.name = "iPad_" + page + "_layout_diagnostics"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testIPadHomeScreenshot() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires the dedicated 13-inch iPad simulator.")
        let app = try launchIPadGallery()
        let cards = ["game.sudoku", "game.minesweeper", "game.sliding"].map { app.buttons[$0] }
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier IN %@", cards.map(\.identifier))).count, 3)
        for card in cards {
            assertIPadVisible(card, app: app)
            XCTAssertTrue(card.label.contains("可遊玩"))
            XCTAssertFalse(card.label.contains("進行中"))
            XCTAssertFalse(card.label.contains("001"))
            XCTAssertFalse(card.label.contains("35"))
        }
        XCTAssertEqual(cards[0].frame.minY, cards[1].frame.minY, accuracy: 2)
        XCTAssertEqual(cards[1].frame.minY, cards[2].frame.minY, accuracy: 2)
        XCTAssertLessThan(cards[0].frame.minX, cards[1].frame.minX)
        XCTAssertLessThan(cards[1].frame.minX, cards[2].frame.minX)
        assertIPadCaptureReady(app)
        screenshot(app, name: "01_iPad_Home")
        try attachIPadLayout(app, page: "Home", grid: cards, controls: [app.buttons["settings.open"]])

        let expected = Set(["sudoku", "minesweeper", "sliding", "twentyfour", "memory", "maze"].map { "game." + $0 }
            + ["nonogram", "kakuro", "klotski", "boardgames", "solitaire", "snake", "fallingblocks", "brickbreaker"].map { "catalog." + $0 })
        var seen: Set<String> = []
        for _ in 0..<8 {
            let visible = app.frame.insetBy(dx: 0, dy: 50)
            let entries = app.buttons.matching(NSPredicate(format: "identifier IN %@", Array(expected)))
            for entry in entries.allElementsBoundByIndex where visible.contains(CGPoint(x: entry.frame.midX, y: entry.frame.midY)) {
                XCTAssertFalse(entry.label.contains("進行中"))
                if entry.identifier == "catalog.boardgames" {
                    XCTAssertTrue(entry.label.contains("2 款可遊玩 · 6 款尚未推出"))
                } else {
                    XCTAssertTrue(entry.label.contains(entry.identifier.hasPrefix("game.") ? "可遊玩" : "尚未推出"))
                }
                seen.insert(entry.identifier)
            }
            if seen == expected { break }
            app.swipeUp()
        }
        XCTAssertEqual(expected.count, 14)
        XCTAssertEqual(seen, expected, "All 14 iPad Home cards must be reachable by scrolling.")
        screenshot(app, name: "v020-iPad-home-bottom")
        let folder = app.buttons["catalog.solitaire"]
        scrollFullyIntoView(folder, app: app); folder.tap()
        let arrived = app.navigationBars["接龍"].waitForExistence(timeout: 10)
        let directory = app.descendants(matching: .any).matching(identifier: "catalog.folder.solitaire").firstMatch
        let directoryExists = directory.waitForExistence(timeout: 5)
        attachUIEvidence(app, name: "v020-iPad-solitaire-arrival")
        XCTAssertTrue(arrived, "The folder's own navigation title must arrive before inspecting card geometry.")
        XCTAssertTrue(directoryExists)
        let solitaire = ["klondike", "spider", "freecell", "pyramid", "tripeaks"].map { app.buttons["catalog." + $0] }
        for card in solitaire {
            scrollFullyIntoView(card, app: app)
            assertIPadVisible(card, app: app)
            XCTAssertTrue(card.label.contains("尚未推出"))
        }
        XCTAssertEqual(solitaire[0].frame.minY, solitaire[1].frame.minY, accuracy: 2)
        XCTAssertEqual(solitaire[1].frame.minY, solitaire[2].frame.minY, accuracy: 2)
        XCTAssertLessThan(solitaire[0].frame.minX, solitaire[1].frame.minX)
        XCTAssertLessThan(solitaire[1].frame.minX, solitaire[2].frame.minX)
        screenshot(app, name: "v020-iPad-solitaire")
        solitaire[0].tap()
        XCTAssertTrue(app.staticTexts["comingSoon.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["comingSoon.title"].label, "經典接龍")
        let status = app.descendants(matching: .any).matching(identifier: "comingSoon.status").firstMatch
        XCTAssertTrue(status.label.contains("尚未推出"))
        screenshot(app, name: "v020-iPad-coming-soon")
        app.buttons["comingSoon.back"].tap(); back(app)

        let boardFolder = app.buttons["catalog.boardgames"]
        scrollFullyIntoView(boardFolder, app: app); boardFolder.tap()
        XCTAssertTrue(app.navigationBars["棋類遊戲"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "catalog.folder.boardgames").firstMatch.waitForExistence(timeout: 5))
        let boardIDs = ["game.tictactoe", "game.connectfour", "catalog.gomoku", "catalog.reversi", "catalog.xiangqi", "catalog.banqi", "catalog.chess", "catalog.shogi"]
        var boardEntries: Set<String> = []
        for id in boardIDs {
            let card = app.buttons[id]
            scrollFullyIntoView(card, app: app)
            assertIPadVisible(card, app: app)
            XCTAssertTrue(card.label.contains(id.hasPrefix("game.") ? "可遊玩" : "尚未推出"))
            XCTAssertFalse(card.label.contains("進行中"))
            boardEntries.insert(card.identifier)
        }
        XCTAssertEqual(boardEntries, Set(boardIDs))
        XCTAssertEqual(boardEntries.count, 8)
        XCTAssertEqual(app.staticTexts.matching(identifier: "catalog.folder.availability").firstMatch.label, "2 款可遊玩 · 6 款尚未推出")
        let boardFirstRow = Array(boardIDs.prefix(3)).map { app.buttons[$0] }
        for card in boardFirstRow { scrollFullyIntoView(card, app: app) }
        XCTAssertEqual(boardFirstRow[0].frame.minY, boardFirstRow[1].frame.minY, accuracy: 2)
        XCTAssertEqual(boardFirstRow[1].frame.minY, boardFirstRow[2].frame.minY, accuracy: 2)
        screenshot(app, name: "v021-iPad-boardgames")
        back(app)
    }

    func testIPadSudokuScreenshot() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires the dedicated 13-inch iPad simulator.")
        let app = try launchIPadGallery()
        openIPadSavedGame(app, game: "sudoku", prefix: "sudoku", firstCell: "sudoku.cell.0")
        let corners = [0, 8, 72, 80].map { app.buttons["sudoku.cell.\($0)"] }
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sudoku.cell.")).count, 81)
        for corner in corners { assertIPadVisible(corner, app: app) }
        let digits = (1...9).map { app.buttons["sudoku.digit.\($0)"] }
        for digit in digits { assertIPadVisible(digit, app: app); XCTAssertTrue(digit.isEnabled) }
        let seededBlueDigit = app.buttons["sudoku.cell.2"]
        XCTAssertEqual(seededBlueDigit.value as? String, "4")
        // The upgrade fixture intentionally restores Pencil mode. Exercise it,
        // then require the real native Answer segment to select before writing.
        XCTAssertTrue(app.segmentedControls["sudoku.tools"].buttons["鉛筆"].isSelected)
        let empty = app.buttons["sudoku.cell.3"]
        XCTAssertEqual(empty.value as? String, "空白"); empty.tap()
        app.buttons["sudoku.digit.6"].tap()
        XCTAssertEqual(empty.value as? String, "候選：6")
        selectNativeSegment("sudoku.tools", label: "答案筆", index: 0, app: app)
        app.buttons["sudoku.digit.6"].tap()
        XCTAssertEqual(empty.value as? String, "6")
        app.buttons["sudoku.erase"].tap()
        XCTAssertEqual(empty.value as? String, "空白")
        assertIPadPauseResume(app, prefix: "sudoku", firstCell: "sudoku.cell.0")
        cancelIPadRestart(app, prefix: "sudoku")
        XCTAssertEqual(seededBlueDigit.value as? String, "4")
        XCTAssertEqual(empty.value as? String, "空白")
        XCTAssertFalse(app.staticTexts["sudoku.complete"].exists)
        assertIPadCaptureReady(app, prefix: "sudoku")
        screenshot(app, name: "02_iPad_Sudoku")
        try attachIPadLayout(app, page: "Sudoku", grid: corners,
                             controls: digits + [app.segmentedControls["sudoku.tools"], app.buttons["sudoku.erase"], app.buttons["sudoku.pause"], app.buttons["sudoku.restart"], app.buttons["navigation.back"]])
        back(app); XCTAssertTrue(app.buttons["sudoku.continue"].waitForExistence(timeout: 5))
        back(app); XCTAssertTrue(app.buttons["game.sudoku"].waitForExistence(timeout: 5))
    }

    func testIPadMinesweeperScreenshot() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires the dedicated 13-inch iPad simulator.")
        let app = try launchIPadGallery()
        // The known flagged cell is an actionable readiness control. Revealed
        // corners still have to exist with valid geometry, regardless of AX type.
        openIPadSavedGame(app, game: "minesweeper", prefix: "mines", firstCell: "mines.cell.30")
        let viewport = app.scrollViews["mines.zoomBoard"]
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        let cells = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "mines.cell."))
        XCTAssertEqual(cells.count, 81)
        let corners = [0, 8, 72, 80].map { cells.matching(identifier: "mines.cell.\($0)").firstMatch }
        for corner in corners {
            assertIPadVisible(corner, app: app, interactive: false)
            XCTAssertTrue(viewport.frame.insetBy(dx: -1, dy: -1).contains(corner.frame))
        }
        XCTAssertEqual((corners[0].frame.minX + corners[1].frame.maxX) / 2, viewport.frame.midX, accuracy: 3)
        XCTAssertEqual(viewport.frame.midX, app.frame.midX, accuracy: 3)
        let flag = app.buttons["mines.cell.30"]
        assertIPadVisible(flag, app: app)
        XCTAssertTrue(flag.label.contains("旗標"))
        flag.press(forDuration: 0.8); XCTAssertTrue(flag.label.contains("未揭開"))
        flag.press(forDuration: 0.8); XCTAssertTrue(flag.label.contains("旗標"))
        assertIPadPauseResume(app, prefix: "mines", firstCell: "mines.cell.30")
        cancelIPadRestart(app, prefix: "mines")
        XCTAssertTrue(flag.label.contains("旗標"))
        XCTAssertFalse(app.staticTexts["mines.won"].exists)
        XCTAssertFalse(app.staticTexts["mines.lost"].exists)
        assertIPadCaptureReady(app, prefix: "mines")
        screenshot(app, name: "03_iPad_Minesweeper")
        try attachIPadLayout(app, page: "Minesweeper", grid: corners,
                             controls: [app.staticTexts["mines.timer"], app.buttons["mines.pause"], app.buttons["mines.restart"], app.buttons["navigation.back"]], viewport: viewport)
        back(app); XCTAssertTrue(app.buttons["mines.continue"].waitForExistence(timeout: 5))
        back(app); XCTAssertTrue(app.buttons["game.minesweeper"].waitForExistence(timeout: 5))
    }

    func testIPadSlidingPuzzleScreenshot() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires the dedicated 13-inch iPad simulator.")
        let app = try launchIPadGallery()
        openIPadSavedGame(app, game: "sliding", prefix: "sliding", firstCell: "sliding.tile.8")
        let tiles = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "sliding.tile."))
        XCTAssertEqual(tiles.count, 9)
        let corners = [0, 2, 6, 8].map { tiles.matching(identifier: "sliding.tile.\($0)").firstMatch }
        // Nonadjacent and blank tiles are correctly disabled by the game.
        // Their geometry, rather than enabled/hittable state, proves visibility.
        for corner in corners { assertIPadVisible(corner, app: app, interactive: false) }
        XCTAssertEqual(app.staticTexts["sliding.moves"].label, "35 步")
        XCTAssertEqual(tiles.matching(identifier: "sliding.tile.7").firstMatch.label, "空格")
        let firstMove = app.buttons["sliding.tile.6"]
        assertIPadVisible(firstMove, app: app); XCTAssertTrue(firstMove.isEnabled)
        firstMove.swipeRight()
        XCTAssertEqual(app.buttons["sliding.tile.7"].label, "方塊 7")
        XCTAssertEqual(tiles.matching(identifier: "sliding.tile.6").firstMatch.label, "空格")
        XCTAssertEqual(app.staticTexts["sliding.moves"].label, "36 步")
        XCTAssertFalse(app.staticTexts["sliding.complete"].exists)
        assertIPadPauseResume(app, prefix: "sliding", firstCell: "sliding.tile.7")
        cancelIPadRestart(app, prefix: "sliding")
        XCTAssertEqual(app.staticTexts["sliding.moves"].label, "36 步")
        app.buttons["sliding.restart"].tap()
        let confirm = app.buttons.matching(identifier: "sliding.confirmRestart").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertFalse(confirm.exists)
        XCTAssertEqual(app.staticTexts["sliding.moves"].label, "0 步")
        XCTAssertEqual(tiles.matching(identifier: "sliding.tile.6").firstMatch.label, "空格")
        let restartedMove = app.buttons["sliding.tile.7"]
        assertIPadVisible(restartedMove, app: app); XCTAssertTrue(restartedMove.isEnabled)
        restartedMove.swipeLeft()
        XCTAssertEqual(app.staticTexts["sliding.moves"].label, "1 步")
        XCTAssertEqual(tiles.matching(identifier: "sliding.tile.7").firstMatch.label, "空格")
        XCTAssertFalse(app.staticTexts["sliding.complete"].exists)
        assertIPadCaptureReady(app, prefix: "sliding")
        screenshot(app, name: "04_iPad_SlidingPuzzle")
        try attachIPadLayout(app, page: "SlidingPuzzle", grid: corners,
                             controls: [app.staticTexts["sliding.moves"], app.staticTexts["sliding.timer"], app.buttons["sliding.pause"], app.buttons["sliding.restart"], app.buttons["navigation.back"]])
        back(app); XCTAssertTrue(app.buttons["sliding.continue"].waitForExistence(timeout: 5))
        back(app); XCTAssertTrue(app.buttons["game.sliding"].waitForExistence(timeout: 5))
    }
}
