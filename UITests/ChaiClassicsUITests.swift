import XCTest
import UIKit

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
    }
    private func startSliding(_ app: XCUIApplication) {
        let start = app.buttons["sliding.start"]
        scrollFullyIntoView(start, app: app); start.tap()
    }
    private func externalLink(_ identifier: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func scrollFullyIntoView(_ element: XCUIElement, app: XCUIApplication) {
        let window = app.frame
        let usable = CGRect(x: window.minX + 10, y: window.minY + 150, width: window.width - 20, height: window.height - 240)
        for _ in 0..<6 {
            if element.exists {
                let frame = element.frame
                if frame.width > 0 && frame.height > 0 && usable.contains(frame) {
                    XCTAssertTrue(element.isHittable); return
                }
                if frame.height > 0 && frame.minY < usable.minY { app.swipeDown(); continue }
            }
            app.swipeUp()
        }
        XCTFail("Control did not become fully visible: " + element.identifier)
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
        let cell = app.buttons["sudoku.cell.1"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5)); cell.tap()
        app.segmentedControls["sudoku.tools"].buttons["鉛筆"].tap()
        app.buttons["sudoku.digit.2"].tap(); app.buttons["sudoku.digit.7"].tap()
        XCTAssertTrue((cell.value as? String ?? "").contains("2, 7"))
        XCTAssertGreaterThan(try blueInkPixels(in: cell, app: app), 5)
        app.segmentedControls["sudoku.tools"].buttons["答案筆"].tap(); app.buttons["sudoku.digit.8"].tap()
        XCTAssertEqual(cell.value as? String, "8") // Answer entry clears pencil notes.
        XCTAssertGreaterThan(try blueInkPixels(in: cell, app: app), 5)
        XCTAssertEqual(try blueInkPixels(in: app.buttons["sudoku.cell.0"], app: app), 0)
        screenshot(app,"sudoku-blue-player-ink")
        app.buttons["sudoku.erase"].tap(); XCTAssertEqual(cell.value as? String, "空白")
        app.segmentedControls["sudoku.tools"].buttons["鉛筆"].tap(); app.buttons["sudoku.digit.7"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["鉛筆"].isSelected)
        app.terminate(); app.launch()
        app.buttons["game.sudoku"].tap(); app.buttons["sudoku.continue"].tap()
        XCTAssertTrue(app.buttons["sudoku.cell.80"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["鉛筆"].isSelected)
        XCTAssertTrue((app.buttons["sudoku.cell.1"].value as? String ?? "").contains("7"))
        XCTAssertFalse(app.buttons["提示"].exists); XCTAssertFalse(app.buttons["答案"].exists)
    }
    func testHomeHasExactlyThreeColumns() {
        let app = launch("base")
        let cards = ["game.sudoku", "game.minesweeper", "game.sliding"].map { app.buttons[$0] }
        for card in cards { XCTAssertTrue(card.waitForExistence(timeout: 10)); XCTAssertTrue(card.label.contains("尚未開始")) }
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
        if app.buttons["mines.confirmNew"].waitForExistence(timeout: 1) { app.buttons["mines.confirmNew"].tap() }
        let first = app.buttons["mines.cell.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(app.segmentedControls.count, 0)
        first.press(forDuration: 0.8)
        XCTAssertTrue(first.label.contains("旗標")); XCTAssertFalse(first.label.contains("已揭開"))
        first.tap(); XCTAssertTrue(first.label.contains("旗標"))
        first.press(forDuration: 0.8); XCTAssertTrue(first.label.contains("未揭開"))
        first.tap(); XCTAssertTrue(first.label.contains("已揭開"))
        XCTAssertFalse(app.staticTexts["mines.lost"].exists)
        first.press(forDuration: 0.8); XCTAssertTrue(first.label.contains("已揭開"))
        app.terminate(); app.launch()
        app.buttons["game.minesweeper"].tap(); app.buttons["mines.continue"].tap()
        XCTAssertTrue(app.buttons["mines.cell.0"].label.contains("已揭開"))
    }
    func testSlidingCanStartAndRestore() {
        let app = launch("sliding")
        app.buttons["game.sliding"].tap(); startSliding(app)
        if app.buttons["sliding.confirmNew"].waitForExistence(timeout: 1) { app.buttons["sliding.confirmNew"].tap() }
        XCTAssertTrue(app.buttons["sliding.tile.0"].waitForExistence(timeout: 5))
        let labels = (0..<9).map { app.buttons["sliding.tile.\($0)"].label }
        app.terminate(); app.launch()
        app.buttons["game.sliding"].tap(); app.buttons["sliding.continue"].tap()
        XCTAssertEqual(labels, (0..<9).map { app.buttons["sliding.tile.\($0)"].label })
        app.buttons["sliding.restart"].tap(); app.buttons["取消"].tap()
        XCTAssertEqual(labels, (0..<9).map { app.buttons["sliding.tile.\($0)"].label })
        app.buttons["sliding.pause"].tap(); XCTAssertTrue(app.buttons["繼續"].exists)
        app.buttons["sliding.pause"].tap(); XCTAssertTrue(app.buttons["sliding.tile.0"].exists)
    }
    func testSlidingSwipesInAllFourDirectionsAndRestoresExactlyOneMove() {
        let app = launch("sliding", legacy: true)
        app.buttons["game.sliding"].tap(); app.buttons["sliding.continue"].tap()
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
        app.buttons["game.sliding"].tap(); app.buttons["sliding.continue"].tap()
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
        XCTAssertTrue(app.buttons["game.sliding"].label.contains("35"))
        XCTAssertTrue(app.buttons["game.sudoku"].label.contains("001"))
        XCTAssertTrue(app.buttons["game.sudoku"].label.contains("進行中"))
        app.buttons["game.minesweeper"].tap(); app.buttons["mines.continue"].tap()
        XCTAssertTrue(app.buttons["mines.cell.30"].label.contains("旗標"))
        let cell = app.buttons["mines.cell.40"]
        XCTAssertTrue(cell.label.contains("未揭開")); cell.tap()
        XCTAssertTrue(cell.label.contains("已揭開")); XCTAssertFalse(cell.label.contains("旗標"))
        XCTAssertTrue(app.buttons["mines.cell.30"].label.contains("旗標"))
        app.buttons["mines.restart"].tap(); app.buttons["取消"].tap()
        XCTAssertTrue(cell.label.contains("已揭開"))
        app.terminate(); app.launch()
        app.buttons["game.minesweeper"].tap(); app.buttons["mines.continue"].tap()
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
        back(app); app.segmentedControls["mines.size"].buttons["30×16"].tap(); startMines(app); app.buttons["mines.confirmNew"].tap()
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
        XCTAssertTrue(app.buttons["game.sudoku"].label.contains("Easy 001"))
        XCTAssertTrue(app.buttons["game.sliding"].label.contains("35 moves"))
        screenshot(app,"home-en-dark")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["game.sliding"].label.contains("35 moves"))
        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.segmentedControls["settings.appearance"].buttons["Dark"].isSelected)
        XCTAssertTrue(app.segmentedControls["settings.language"].buttons["English"].isSelected)
        XCTAssertEqual(app.switches["settings.haptics"].value as? String,"0")
        XCTAssertEqual(app.switches["settings.awake"].value as? String,"1")
    }
    func testEnglishIsAppliedToAllGamesAndAccessibility() {
        let app = launch("settings",legacy: true)
        app.buttons["settings.open"].tap(); app.segmentedControls["settings.language"].buttons["English"].tap(); back(app)
        app.buttons["game.sudoku"].tap(); app.buttons["sudoku.continue"].tap()
        XCTAssertTrue(app.segmentedControls["sudoku.tools"].buttons["Pencil"].isSelected)
        XCTAssertTrue(app.buttons["sudoku.cell.1"].label.contains("Row 1"))
        XCTAssertTrue((app.buttons["sudoku.cell.1"].value as? String ?? "").contains("Notes: 2, 7"))
        XCTAssertFalse(app.buttons["Hint"].exists); XCTAssertFalse(app.buttons["Show answer"].exists)
        back(app); back(app)
        app.buttons["game.minesweeper"].tap(); app.buttons["mines.continue"].tap()
        XCTAssertTrue(app.buttons["mines.cell.0"].label.contains("Revealed"))
        XCTAssertTrue(app.buttons["mines.cell.30"].label.contains("Flagged"))
        back(app); back(app)
        app.buttons["game.sliding"].tap(); app.buttons["sliding.continue"].tap()
        XCTAssertTrue(app.buttons["sliding.tile.0"].label.contains("Tile 1"))
        XCTAssertTrue(app.staticTexts["sliding.moves"].label.contains("35 moves"))
    }
    func testBundledLegalAndSupportInBothLanguages() {
        let app = launch("legal")
        app.buttons["settings.open"].tap()
        for english in [false,true] {
            if english {
                scrollFullyIntoView(app.segmentedControls["settings.language"], app: app)
                app.segmentedControls["settings.language"].buttons["English"].tap()
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
                    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@",english ? "Document version: 0.1.2" : "文件版本：0.1.2")).firstMatch.exists)
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
