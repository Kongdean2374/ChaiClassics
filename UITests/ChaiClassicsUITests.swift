import XCTest
import UIKit

extension XCTestCase {
    /// Tap the intended segment using the native control's geometry, independent
    /// of individual child accessibility bounds. Require the actual selection
    /// before allowing a subsequent game input.
    func selectNativeSegment(_ identifier: String, label: String, index: Int, app: XCUIApplication,
                             file: StaticString = #filePath, line: UInt = #line) {
        let control = app.segmentedControls.matching(identifier: identifier).firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 5), file: file, line: line)
        let segments = control.buttons
        let count = segments.count
        guard index >= 0, index < count else {
            XCTFail("Missing native segment: " + label, file: file, line: line)
            return
        }
        let target = segments.element(boundBy: index)
        XCTAssertEqual(target.label, label, file: file, line: line)
        XCTAssertTrue(control.isHittable, file: file, line: line)
        control.coordinate(withNormalizedOffset: CGVector(dx: (CGFloat(index) + 0.5) / CGFloat(count), dy: 0.5)).tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            target.exists && target.isSelected
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                       "Native segment did not select: " + label, file: file, line: line)
    }

    func nativeConfirmationButton(_ identifier: String, app: XCUIApplication) -> XCUIElement {
        // Recent iOS versions expose nested Buttons with the same identifier.
        // Restrict the query to the presented native sheet, then select one.
        app.sheets.buttons.matching(identifier: identifier).firstMatch
    }

    func attachUIEvidence(_ app: XCUIApplication, name: String) {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func tapNativeConfirmation(_ identifier: String, app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) {
        let action = nativeConfirmationButton(identifier, app: app)
        XCTAssertTrue(action.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(action.isEnabled, file: file, line: line)
        XCTAssertTrue(action.isHittable, file: file, line: line)
        action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !action.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed,
                       "Native confirmation did not dismiss: " + identifier, file: file, line: line)
    }

    func cancelNativeConfirmation(_ identifier: String, app: XCUIApplication,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let action = nativeConfirmationButton(identifier, app: app)
        XCTAssertTrue(action.waitForExistence(timeout: 5), file: file, line: line)
        let cancel = app.sheets.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
        if cancel.exists {
            cancel.tap()
        } else {
            // A native popover omits its Cancel row. Dismiss outside its sheet;
            // the subsequent board assertions still prove that no reset ran.
            XCTAssertTrue(app.popovers.firstMatch.exists, file: file, line: line)
            let sheet = app.sheets.containing(.button, identifier: identifier).firstMatch
            let frame = app.frame
            let point = CGPoint(x: frame.minX + frame.width * 0.04, y: frame.minY + frame.height * 0.94)
            XCTAssertFalse(sheet.frame.contains(point), file: file, line: line)
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x - frame.minX, dy: point.y - frame.minY)).tap()
        }
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !action.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed,
                       "Cancel must dismiss the native confirmation.", file: file, line: line)
    }

    func confirmNewGame(_ game: String, app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        let confirm = app.buttons.matching(identifier: game + ".new.confirm").firstMatch
        let cancel = app.buttons.matching(identifier: game + ".new.cancel").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(cancel.exists, file: file, line: line)
        XCTAssertTrue(confirm.isEnabled && confirm.isHittable, file: file, line: line)
        confirm.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !confirm.exists }, object: nil)
        let result = XCTWaiter.wait(for:[dismissed],timeout:20)
        if result != .completed { attachUIEvidence(app,name:"new-game-confirmation-did-not-dismiss-"+game) }
        XCTAssertEqual(result,.completed,file:file,line:line)
        waitForSessionInput(game, app: app, file: file, line: line)
    }

    func cancelNewGame(_ game: String, app: XCUIApplication,
                       file: StaticString = #filePath, line: UInt = #line) {
        let confirm = app.buttons.matching(identifier: game + ".new.confirm").firstMatch
        let cancel = app.buttons.matching(identifier: game + ".new.cancel").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(cancel.isHittable, file: file, line: line)
        cancel.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !confirm.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed, file: file, line: line)
    }

    func resumePausedGame(_ game: String, app: XCUIApplication,
                       file: StaticString = #filePath, line: UInt = #line) {
        let resume = app.buttons.matching(identifier: game + ".session.resume").firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 10), "Continue must enter the paused session.", file: file, line: line)
        XCTAssertTrue(app.buttons[game + ".session.exit"].exists, file: file, line: line)
        XCTAssertTrue(resume.isEnabled && resume.isHittable, file: file, line: line)
        resume.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !resume.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed, file: file, line: line)
        waitForSessionInput(game, app: app, file: file, line: line)
    }

    func waitForSessionInput(_ game: String, app: XCUIApplication,
                             file: StaticString = #filePath, line: UInt = #line) {
        let pause = app.buttons.matching(identifier: game + ".session.pause").firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            pause.exists && pause.isEnabled && pause.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed,
                       "The modal touch gate must settle before board input.", file: file, line: line)
    }

    func assertPausedClock(_ game: String, boardIdentifier: String, app: XCUIApplication,
                           file: StaticString = #filePath, line: UInt = #line) {
        let elapsed = app.descendants(matching: .any).matching(identifier: game + ".session.paused.elapsed").firstMatch
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5), file: file, line: line)
        let frozen = elapsed.value as? String
        XCTAssertNotNil(frozen, file: file, line: line)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: boardIdentifier).firstMatch.exists,
                       "The board remains rendered under the pause blur but must be hidden from accessibility.", file: file, line: line)
        let changes = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !elapsed.exists || (elapsed.value as? String) != frozen
        }, object: nil)
        changes.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changes], timeout: 2.1), .completed,
                       "The actual paused elapsed value must remain exactly frozen.", file: file, line: line)
        XCTAssertEqual(elapsed.value as? String, frozen, file: file, line: line)
    }

    @discardableResult
    func requireSessionResult(_ game: String, moves: Int, app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let result = app.descendants(matching: .any).matching(identifier: game + ".session.result").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), file: file, line: line)
        let moveCount = app.descendants(matching: .any).matching(identifier: game + ".session.result.moves").firstMatch
        XCTAssertTrue(moveCount.exists, file: file, line: line)
        XCTAssertEqual(moveCount.value as? String, String(moves),
                       "The visible result must retain the exact final move count.", file: file, line: line)
        for action in ["done", "review"] {
            let button = app.buttons[game + ".session." + action]
            XCTAssertTrue(button.exists && button.isHittable, file: file, line: line)
            XCTAssertTrue(app.frame.contains(button.frame), file: file, line: line)
            XCTAssertEqual(button.frame.midX, app.frame.midX, accuracy: 3,
                           "Result actions must stay centered on iPhone and iPad.", file: file, line: line)
        }
        return result
    }

    func reviewAndReopenSessionResult(_ game: String, moves: Int, app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) {
        app.buttons[game + ".session.review"].tap()
        let shield = app.descendants(matching: .any).matching(identifier: game + ".session.reviewBoard").firstMatch
        XCTAssertTrue(shield.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertFalse(app.buttons[game + ".session.done"].exists, file: file, line: line)
        shield.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        requireSessionResult(game, moves: moves, app: app, file: file, line: line)
    }
}

final class ChaiClassicsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ profile: String, legacy: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        let base = ["--ui-testing", "--ui-profile", profile]
        app.launchArguments = base + ["--ui-reset"]
        if legacy {
            for namespace in ["sudoku", "minesweeper", "sliding"] {
                let url = Bundle(for: ChaiClassicsUITests.self).url(forResource: "v010-" + namespace, withExtension: "json")!
                app.launchEnvironment["CHAI_UI_SEED_" + namespace.uppercased()] = try! Data(contentsOf: url).base64EncodedString()
            }
        }
        app.launch()
        app.launchArguments = base // Relaunch must retain test progress and preferences.
        XCTAssertTrue(app.buttons["game.sudoku"].waitForExistence(timeout: 10))
        return app
    }
    private func back(_ app: XCUIApplication) { app.buttons["navigation.back"].tap() }
    private func startMines(_ app: XCUIApplication) {
        let start = app.buttons["mines.start"]
        scrollFullyIntoView(start, app: app); start.tap()
        confirmNewGame("minesweeper", app: app)
    }
    private func startSliding(_ app: XCUIApplication) {
        let start = app.buttons["sliding.start"]
        scrollFullyIntoView(start, app: app); start.tap()
        confirmNewGame("sliding", app: app)
    }
    private func externalLink(_ identifier: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func scrollFullyIntoView(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<6 {
            let window = app.frame
            let navigation = app.navigationBars.firstMatch
            let top = navigation.exists ? navigation.frame.maxY : window.minY
            // The destination may replace a ScrollView with a native Form while
            // navigation is settling. Window/navigation bounds remain valid.
            let usable = CGRect(x: window.minX + 10, y: top, width: window.width - 20, height: window.maxY - 20 - top)
            if element.exists {
                let frame = element.frame
                if frame.width > 0 && frame.height > 0 && usable.contains(frame) {
                    XCTAssertTrue(element.isHittable); return
                }
                if frame.height > 0 && frame.minY < usable.minY { app.swipeDown(); continue }
            }
            app.swipeUp()
        }
        let identifier = element.exists ? element.identifier : "missing-control"
        attachUIEvidence(app, name: "scroll-visibility-failure-" + identifier)
        XCTFail("Control did not become fully visible: " + identifier)
    }
    private func visibleMinesCell(_ app: XCUIApplication, viewport: XCUIElement, columns: Int, rows: Int) -> XCUIElement {
        // Read transformed geometry; asking XCTest to hit-test offscreen UIKit
        // elements can itself throw before a visible cell has been reached.
        let origin = app.buttons["mines.cell.0"].frame
        guard origin.width > 0 && origin.height > 0 && origin.minX.isFinite && origin.minY.isFinite else {
            XCTFail("Missing transformed board geometry"); return app.buttons["mines.cell.0"]
        }
        let center = CGPoint(x: viewport.frame.midX, y: viewport.frame.midY)
        let column = max(0, min(columns - 1, Int(floor((center.x - origin.minX) / origin.width))))
        let row = max(0, min(rows - 1, Int(floor((center.y - origin.minY) / origin.height))))
        let cell = app.buttons["mines.cell.\(row * columns + column)"]
        XCTAssertTrue(cell.frame.contains(center))
        XCTAssertTrue(viewport.frame.insetBy(dx: 2, dy: 2).contains(cell.frame))
        XCTAssertTrue(cell.isHittable)
        return cell
    }
    private func blueInkPixels(in element: XCUIElement, app: XCUIApplication) throws -> Int {
        let shot = app.screenshot().image
        let full = try XCTUnwrap(shot.cgImage)
        let scale = CGFloat(full.width) / app.frame.width
        let frame = element.frame.insetBy(dx: 5, dy: 5)
        let region = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
        let image = try XCTUnwrap(full.cropping(to: region))
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { (data: UnsafeMutableRawBufferPointer) -> Int in
            let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            guard let context = CGContext(data: data.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) else {
                XCTFail("Unable to inspect screenshot colors"); return 0
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            let bytes = data.bindMemory(to: UInt8.self)
            var count = 0
            for i in stride(from: 0, to: bytes.count, by: 4) {
                let red = Int(bytes[i]), blue = Int(bytes[i + 2])
                if blue > 140 && red < 130 && blue > red + 50 { count += 1 }
            }
            return count
        }
    }
    func testSudokuNavigationAndRestoration() throws {
        let app = launch("sudoku")
        app.buttons["game.sudoku"].tap()
        app.buttons["sudoku.difficulty.easy"].tap()
        XCTAssertFalse(app.buttons["sudoku.easy.0002"].isEnabled)
        app.buttons["sudoku.easy.0001"].tap()
        confirmNewGame("sudoku", app: app)
        let cell = app.buttons["sudoku.cell.1"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5)); cell.tap()
        selectNativeSegment("sudoku.tools", label: "鉛筆", index: 1, app: app)
        app.buttons["sudoku.digit.2"].tap(); app.buttons["sudoku.digit.7"].tap()
        XCTAssertTrue((cell.value as? String ?? "").contains("2, 7"))
        XCTAssertGreaterThan(try blueInkPixels(in: cell, app: app), 5)
        selectNativeSegment("sudoku.tools", label: "答案筆", index: 0, app: app)
        app.buttons["sudoku.digit.8"].tap()
        XCTAssertEqual(cell.value as? String, "8") // Answer entry clears pencil notes.
        XCTAssertGreaterThan(try blueInkPixels(in: cell, app: app), 5)
        XCTAssertEqual(try blueInkPixels(in: app.buttons["sudoku.cell.0"], app: app), 0)
        screenshot(app,"sudoku-blue-player-ink")
        app.buttons["sudoku.erase"].tap(); XCTAssertEqual(cell.value as? String, "空白")
        selectNativeSegment("sudoku.tools", label: "鉛筆", index: 1, app: app)
        app.buttons["sudoku.digit.7"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["鉛筆"].isSelected)
        app.terminate(); app.launch()
        app.buttons["game.sudoku"].tap(); app.buttons["sudoku.continue"].tap(); resumePausedGame("sudoku", app: app)
        XCTAssertTrue(app.buttons["sudoku.cell.80"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["鉛筆"].isSelected)
        XCTAssertTrue((app.buttons["sudoku.cell.1"].value as? String ?? "").contains("7"))
        XCTAssertFalse(app.buttons["提示"].exists); XCTAssertFalse(app.buttons["答案"].exists)
    }
    func testHomeHasExactlyThreeColumns() {
        let app = launch("base")
        let cards = ["game.sudoku", "game.minesweeper", "game.sliding"].map { app.buttons[$0] }
        for card in cards {
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            XCTAssertTrue(card.label.contains("可遊玩"))
            XCTAssertFalse(card.label.contains("進行中"))
        }
        XCTAssertEqual(cards[0].frame.minY, cards[1].frame.minY, accuracy: 2)
        XCTAssertEqual(cards[1].frame.minY, cards[2].frame.minY, accuracy: 2)
        XCTAssertLessThan(cards[0].frame.minX, cards[1].frame.minX)
        XCTAssertLessThan(cards[1].frame.minX, cards[2].frame.minX)
        XCTAssertGreaterThanOrEqual(cards[0].frame.width, 80)
        screenshot(app,"home-zh-Hant")
    }
    func testMinesFirstRevealAndRestoration() {
        let app = launch("mines")
        app.buttons["game.minesweeper"].tap(); startMines(app)
        let first = app.buttons["mines.cell.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(app.segmentedControls.count, 0)
        first.press(forDuration: 0.8)
        XCTAssertTrue(first.label.contains("旗標")); XCTAssertFalse(first.label.contains("已揭開"))
        first.tap(); XCTAssertTrue(first.label.contains("旗標"))
        first.press(forDuration: 0.8); XCTAssertTrue(first.label.contains("未揭開"))
        first.tap(); XCTAssertTrue(first.label.contains("已揭開"))
        XCTAssertFalse(app.buttons["minesweeper.session.done"].exists)
        first.press(forDuration: 0.8); XCTAssertTrue(first.label.contains("已揭開"))
        app.terminate(); app.launch()
        app.buttons["game.minesweeper"].tap(); app.buttons["mines.continue"].tap(); resumePausedGame("minesweeper", app: app)
        XCTAssertTrue(app.buttons["mines.cell.0"].label.contains("已揭開"))
    }
    func testSlidingCanStartAndRestore() {
        let app = launch("sliding")
        app.buttons["game.sliding"].tap(); startSliding(app)
        XCTAssertTrue(app.buttons["sliding.tile.0"].waitForExistence(timeout: 5))
        let labels = (0..<9).map { app.buttons["sliding.tile.\($0)"].label }
        app.terminate(); app.launch()
        app.buttons["game.sliding"].tap(); app.buttons["sliding.continue"].tap(); resumePausedGame("sliding", app: app)
        XCTAssertEqual(labels, (0..<9).map { app.buttons["sliding.tile.\($0)"].label })
        back(app)
        scrollFullyIntoView(app.buttons["sliding.start"], app: app); app.buttons["sliding.start"].tap()
        cancelNewGame("sliding", app: app)
        app.buttons["sliding.continue"].tap(); resumePausedGame("sliding", app: app)
        XCTAssertEqual(labels, (0..<9).map { app.buttons["sliding.tile.\($0)"].label })
        app.buttons["sliding.session.pause"].tap()
        assertPausedClock("sliding", boardIdentifier: "sliding.tile.0", app: app)
        screenshot(app, "v022-sliding-paused-board-under-blur")
        resumePausedGame("sliding", app: app)
        XCTAssertEqual(labels, (0..<9).map { app.buttons["sliding.tile.\($0)"].label })
    }
    func testSlidingSwipesInAllFourDirectionsAndRestoresExactlyOneMove() {
        let app = launch("sliding", legacy: true)
        app.buttons["game.sliding"].tap(); app.buttons["sliding.continue"].tap(); resumePausedGame("sliding", app: app)
        let original = (0..<9).map { app.buttons["sliding.tile.\($0)"].label }
        let moves = app.staticTexts["sliding.moves"]
        XCTAssertTrue(moves.label.contains("35"))
        app.buttons["sliding.tile.4"].swipeDown(); XCTAssertTrue(moves.label.contains("36"))
        XCTAssertEqual(app.buttons["sliding.tile.7"].label, "方塊 5")
        app.buttons["sliding.tile.7"].swipeUp(); XCTAssertTrue(moves.label.contains("37"))
        app.buttons["sliding.tile.6"].swipeRight(); XCTAssertTrue(moves.label.contains("38"))
        app.buttons["sliding.tile.7"].swipeLeft(); XCTAssertTrue(moves.label.contains("39"))
        XCTAssertEqual(original, (0..<9).map { app.buttons["sliding.tile.\($0)"].label })
        app.buttons["sliding.tile.4"].swipeUp() // Away from the blank must not become a tap.
        XCTAssertTrue(moves.label.contains("39"))
        app.terminate(); app.launch()
        app.buttons["game.sliding"].tap(); app.buttons["sliding.continue"].tap(); resumePausedGame("sliding", app: app)
        XCTAssertTrue(app.staticTexts["sliding.moves"].label.contains("39"))
        XCTAssertEqual(original, (0..<9).map { app.buttons["sliding.tile.\($0)"].label })
    }
    func testMinesSizeCountDifficultyEstimateAndRandomStart() {
        let app = launch("mines")
        app.buttons["game.minesweeper"].tap()
        XCTAssertTrue(app.staticTexts["mines.estimatedDifficulty"].label.contains("簡單"))
        app.segmentedControls["mines.size"].buttons["16×16"].tap()
        XCTAssertTrue(app.staticTexts["mines.estimatedDifficulty"].label.contains("中等"))
        let count = app.steppers["mines.mineCount"]
        scrollFullyIntoView(count, app: app)
        count.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(count.label.contains("41"))
        startMines(app)
        XCTAssertTrue(app.buttons["mines.cell.255"].exists)
        XCTAssertEqual(app.segmentedControls.count, 0)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "16×16")).firstMatch.exists)
    }
    func testLegacyFlagModeStillRevealsOnSingleTap() {
        let app = launch("legacy",legacy: true)
        XCTAssertFalse(app.buttons["game.sliding"].label.contains("35"))
        XCTAssertFalse(app.buttons["game.sudoku"].label.contains("001"))
        XCTAssertFalse(app.buttons["game.sudoku"].label.contains("進行中"))
        app.buttons["game.sliding"].tap()
        XCTAssertTrue(app.buttons["sliding.continue"].label.contains("35"))
        back(app)
        app.buttons["game.sudoku"].tap()
        XCTAssertTrue(app.buttons["sudoku.continue"].label.contains("001"))
        back(app)
        app.buttons["game.minesweeper"].tap(); app.buttons["mines.continue"].tap(); resumePausedGame("minesweeper", app: app)
        XCTAssertTrue(app.buttons["mines.cell.30"].label.contains("旗標"))
        let cell = app.buttons["mines.cell.40"]
        XCTAssertTrue(cell.label.contains("未揭開")); cell.tap()
        XCTAssertTrue(cell.label.contains("已揭開")); XCTAssertFalse(cell.label.contains("旗標"))
        XCTAssertTrue(app.buttons["mines.cell.30"].label.contains("旗標"))
        back(app)
        scrollFullyIntoView(app.buttons["mines.start"], app: app); app.buttons["mines.start"].tap()
        cancelNewGame("minesweeper", app: app)
        app.buttons["mines.continue"].tap(); resumePausedGame("minesweeper", app: app)
        XCTAssertTrue(cell.label.contains("已揭開"))
        XCTAssertTrue(app.buttons["mines.cell.30"].label.contains("旗標"))
        app.terminate(); app.launch()
        app.buttons["game.minesweeper"].tap(); app.buttons["mines.continue"].tap(); resumePausedGame("minesweeper", app: app)
        XCTAssertTrue(app.buttons["mines.cell.40"].label.contains("已揭開"))
        XCTAssertTrue(app.buttons["mines.cell.30"].label.contains("旗標"))
    }
    func testMinesBoardCenteredAndLargeBoardZoomKeepsHitCoordinates() {
        let app = launch("large")
        app.buttons["game.minesweeper"].tap(); startMines(app)
        let viewport = app.scrollViews["mines.zoomBoard"]
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        let first = app.buttons["mines.cell.0"], lastColumn = app.buttons["mines.cell.8"]
        XCTAssertEqual((first.frame.minX + lastColumn.frame.maxX) / 2, viewport.frame.midX, accuracy: 3)
        XCTAssertGreaterThanOrEqual(first.frame.width, 32)
        XCTAssertLessThan(abs(app.buttons["mines.cell.80"].frame.maxY - viewport.frame.maxY), 6)
        screenshot(app,"mines-centered-9x9")
        back(app); app.segmentedControls["mines.size"].buttons["30×16"].tap(); startMines(app)
        let before = app.buttons["mines.cell.0"].frame.width
        viewport.pinch(withScale: 1.8, velocity: 1)
        let zoomed = NSPredicate { _,_ in app.buttons["mines.cell.0"].frame.width > before * 1.2 }
        expectation(for: zoomed,evaluatedWith: nil); waitForExpectations(timeout: 5)
        let target = visibleMinesCell(app, viewport: viewport, columns: 30, rows: 16)
        let identifier = target.identifier
        target.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons[identifier].label.contains("旗標"))
        app.buttons[identifier].tap(); XCTAssertTrue(app.buttons[identifier].label.contains("旗標"))
        let beforePan = target.identifier
        viewport.swipeLeft()
        let afterPan = visibleMinesCell(app, viewport: viewport, columns: 30, rows: 16).identifier
        XCTAssertNotEqual(beforePan, afterPan)
        XCTAssertTrue(viewport.exists)
        screenshot(app,"mines-large-zoomed")
    }
    func testThemeLanguagePreferencesAndLegacySummariesPersist() {
        let app = launch("settings",legacy: true)
        app.buttons["settings.open"].tap()
        app.segmentedControls["settings.appearance"].buttons["淺色"].tap()
        XCTAssertTrue(app.staticTexts["settings.resolvedAppearance"].label.contains("淺色"))
        app.segmentedControls["settings.appearance"].buttons["深色"].tap()
        XCTAssertTrue(app.staticTexts["settings.resolvedAppearance"].label.contains("深色"))
        app.segmentedControls["settings.appearance"].buttons["系統"].tap()
        XCTAssertTrue(app.segmentedControls["settings.appearance"].buttons["系統"].isSelected)
        app.segmentedControls["settings.appearance"].buttons["深色"].tap()
        app.segmentedControls["settings.language"].buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        scrollFullyIntoView(app.segmentedControls["settings.graphics"], app: app)
        selectNativeSegment("settings.graphics", label: "Low", index: 0, app: app)
        let haptics = app.switches["settings.haptics"], awake = app.switches["settings.awake"]
        XCTAssertEqual(haptics.value as? String, "1"); XCTAssertEqual(awake.value as? String, "0")
        // iOS 26 exposes the whole Form row as the Switch's AX frame. A row-
        // center tap hits its label, while the native thumb is at the trailing edge.
        scrollFullyIntoView(haptics, app: app)
        haptics.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(haptics.value as? String, "0")
        scrollFullyIntoView(awake, app: app)
        awake.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(awake.value as? String, "1")
        screenshot(app, "settings-native-switches-changed")
        back(app)
        XCTAssertFalse(app.buttons["game.sudoku"].label.contains("Easy 001"))
        XCTAssertFalse(app.buttons["game.sliding"].label.contains("35 moves"))
        app.buttons["game.sudoku"].tap()
        XCTAssertTrue(app.buttons["sudoku.continue"].label.contains("Easy 001"))
        back(app)
        app.buttons["game.sliding"].tap()
        XCTAssertTrue(app.buttons["sliding.continue"].label.contains("35 moves"))
        back(app)
        screenshot(app,"home-en-dark")
        app.terminate(); app.launch()
        XCTAssertFalse(app.buttons["game.sliding"].label.contains("35 moves"))
        app.buttons["game.sliding"].tap()
        XCTAssertTrue(app.buttons["sliding.continue"].label.contains("35 moves"))
        back(app)
        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.segmentedControls["settings.appearance"].buttons["Dark"].isSelected)
        XCTAssertTrue(app.segmentedControls["settings.language"].buttons["English"].isSelected)
        XCTAssertEqual(app.switches["settings.haptics"].value as? String,"0")
        XCTAssertEqual(app.switches["settings.awake"].value as? String,"1")
        scrollFullyIntoView(app.segmentedControls["settings.graphics"], app: app)
        XCTAssertTrue(app.segmentedControls["settings.graphics"].buttons["Low"].isSelected)
        selectNativeSegment("settings.graphics", label: "High", index: 2, app: app)
        back(app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 10))
        app.buttons["settings.open"].tap()
        scrollFullyIntoView(app.segmentedControls["settings.graphics"], app: app)
        XCTAssertTrue(app.segmentedControls["settings.graphics"].buttons["High"].isSelected)
        back(app)
        for game in ["sudoku", "minesweeper", "sliding", "twentyfour", "memory", "maze"] {
            let card = app.buttons["game." + game]
            scrollFullyIntoView(card, app: app)
            XCTAssertTrue(card.isEnabled, "Graphics quality must preserve every playable entry.")
        }
        let boardGames = app.buttons["catalog.boardgames"]
        scrollFullyIntoView(boardGames, app: app); boardGames.tap()
        XCTAssertTrue(app.navigationBars["Board Games"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["game.tictactoe"].isEnabled)
        XCTAssertTrue(app.buttons["game.connectfour"].isEnabled)
        back(app)
        scrollFullyIntoView(app.buttons["game.sliding"], app: app); app.buttons["game.sliding"].tap()
        XCTAssertTrue(app.buttons["sliding.continue"].label.contains("35 moves"))
    }
    func testEnglishIsAppliedToAllGamesAndAccessibility() {
        // Intel measured the complete language tour at 451 seconds.
        executionTimeAllowance = 600
        let app = launch("settings",legacy: true)
        app.buttons["settings.open"].tap(); app.segmentedControls["settings.language"].buttons["English"].tap(); back(app)
        app.buttons["game.sudoku"].tap(); app.buttons["sudoku.continue"].tap(); resumePausedGame("sudoku", app: app)
        XCTAssertTrue(app.segmentedControls["sudoku.tools"].buttons["Pencil"].isSelected)
        XCTAssertTrue(app.buttons["sudoku.cell.1"].label.contains("Row 1"))
        XCTAssertTrue((app.buttons["sudoku.cell.1"].value as? String ?? "").contains("Notes: 2, 7"))
        XCTAssertFalse(app.buttons["Hint"].exists); XCTAssertFalse(app.buttons["Show answer"].exists)
        back(app); back(app)
        app.buttons["game.minesweeper"].tap(); app.buttons["mines.continue"].tap(); resumePausedGame("minesweeper", app: app)
        XCTAssertTrue(app.buttons["mines.cell.0"].label.contains("Revealed"))
        XCTAssertTrue(app.buttons["mines.cell.30"].label.contains("Flagged"))
        back(app); back(app)
        app.buttons["game.sliding"].tap(); app.buttons["sliding.continue"].tap(); resumePausedGame("sliding", app: app)
        XCTAssertTrue(app.buttons["sliding.tile.0"].label.contains("Tile 1"))
        XCTAssertTrue(app.staticTexts["sliding.moves"].label.contains("35 moves"))
    }
    func testBundledLegalAndSupportInBothLanguages() {
        // The complete offline bilingual tour measured 457s on Intel. Keep
        // its document/link assertions within an explicit bounded allowance.
        executionTimeAllowance = 600
        let app = launch("legal")
        app.buttons["settings.open"].tap()
        for english in [false,true] {
            if english {
                let languagePicker = app.segmentedControls["settings.language"]
                // Returning from Support preserves the lower Form position;
                // the language picker above it may be omitted from the AX tree.
                for _ in 0..<6 {
                    if languagePicker.exists { break }
                    app.swipeDown()
                }
                scrollFullyIntoView(languagePicker, app: app)
                attachUIEvidence(app, name: "v021-legal-return-to-language-picker")
                languagePicker.buttons["English"].tap()
            }
            // Verify optional external destinations are accessible without
            // opening a browser or mail app during an offline policy test.
            for identifier in ["settings.website", "settings.email"] {
                let link = externalLink(identifier, app: app)
                scrollFullyIntoView(link, app: app)
                XCTAssertTrue(link.exists); XCTAssertTrue(link.isHittable)
            }
            for document in ["privacy","terms","support"] {
                let entry = app.buttons["legal." + document]
                scrollFullyIntoView(entry, app: app)
                entry.tap()
                let page = app.descendants(matching: .any).matching(identifier: "document." + document).firstMatch
                XCTAssertTrue(page.waitForExistence(timeout: 5))
                if document != "support" {
                    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@",english ? "Document version: 0.2.1" : "文件版本：0.2.1")).firstMatch.exists)
                }
                let online = externalLink("legal.online." + document, app: app)
                scrollFullyIntoView(online, app: app)
                XCTAssertTrue(online.exists); XCTAssertTrue(online.isHittable)
                if document == "support" {
                    let email = externalLink("support.email", app: app)
                    scrollFullyIntoView(email, app: app)
                    XCTAssertTrue(email.exists); XCTAssertTrue(email.isHittable)
                    let address = app.staticTexts["support.email.address"]
                    scrollFullyIntoView(address, app: app)
                    XCTAssertEqual(address.label, "a090825159@icloud.com")
                    let copy = app.buttons["support.email.copy"]
                    scrollFullyIntoView(copy, app: app)
                    XCTAssertTrue(copy.exists); XCTAssertTrue(copy.isHittable)
                    copy.tap()
                    XCTAssertTrue(copy.label.contains(english ? "copied" : "已複製"))
                }
                back(app)
            }
        }
    }
}
