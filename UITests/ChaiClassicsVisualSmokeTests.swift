import XCTest
import UIKit

/// Original image galleries plus real shared-session, deletion, and history flows.
final class ChaiClassicsVisualSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // Also request the measured allowance when this class is included in
        // manual full UI. Xcode still enforces that invocation's maximum cap.
        executionTimeAllowance = 300
    }

    private func launch(profile: String, suppressionFlag: String? = nil, allGames: Bool = false,
                        fixture: String? = nil, language: String? = nil) throws -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["--ui-testing", "--ui-celebration-probe", "--ui-profile", profile]
        if let suppressionFlag { arguments.append(suppressionFlag) }
        if let fixture { arguments += ["--ui-near-win", fixture] }
        if let language { arguments += ["--ui-language", language] }
        app.launchArguments = arguments + ["--ui-reset"]
        let namespaces = allGames ? ["sudoku", "minesweeper", "sliding"] : ["sliding"]
        for namespace in namespaces {
            let seed = try XCTUnwrap(Bundle(for: ChaiClassicsVisualSmokeTests.self).url(forResource: "v010-" + namespace, withExtension: "json"))
            app.launchEnvironment["CHAI_UI_SEED_" + namespace.uppercased()] = try Data(contentsOf: seed).base64EncodedString()
        }
        app.launch()
        app.launchArguments = arguments // A second launch must retain the actual won save.
        // Re-launch must prove disk preservation, never recreate a deleted save.
        for namespace in namespaces { app.launchEnvironment["CHAI_UI_SEED_"+namespace.uppercased()] = nil }
        XCTAssertTrue(app.buttons["game.sliding"].waitForExistence(timeout: 10))
        return app
    }

    private func node(_ id: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitUI(_ message: String, timeout: TimeInterval = 15, _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
    }

    private func clockSeconds(_ value: String) -> Int? {
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 3, let hours = Int(components[0]), let minutes = Int(components[1]),
              let seconds = Int(components[2]), hours >= 0, (0..<60).contains(minutes),
              (0..<60).contains(seconds) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    private func tap(_ id: String, app: XCUIApplication) {
        let button = app.buttons.matching(identifier: id).firstMatch
        if id == "history.filters" || id == "history.keyboard.done" || id == "history.search.clear" || id == "gameSettings.done" || id.hasSuffix(".menu.settings") || id.hasSuffix(".session.settings") || id.hasSuffix(".session.pause") {
            let exists = button.waitForExistence(timeout: 10)
            if !exists { attachUIEvidence(app, name: "fixed-action-missing-" + id) }
            XCTAssertTrue(exists, "Missing action: " + id)
            guard exists else { return }
            let frame = button.frame
            let visible = frame.width > 0 && frame.height > 0 && app.frame.contains(frame)
            if !visible { attachUIEvidence(app, name: "fixed-action-clipped-" + id) }
            XCTAssertTrue(visible, "Fixed action must be fully visible without scrolling: " + id)
            let hittable = button.isHittable
            if !hittable { attachUIEvidence(app, name: "fixed-action-not-hittable-" + id) }
            XCTAssertTrue(hittable, "Fixed action must be tappable: " + id)
        } else {
            scrollFullyIntoView(button, app: app)
            XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing action: " + id)
        }
        if !button.isEnabled { waitUI("Action must become enabled: " + id) { button.exists && button.isEnabled } }
        button.tap()
    }

    private func tapNativeMenuItem(_ label: String, app: XCUIApplication) {
        // A SwiftUI Menu becomes native UIActions. Select its displayed action
        // without assuming SwiftUI's identifier or the exported element role.
        let matches = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            matches.allElementsBoundByIndex.contains { $0.isHittable && $0.isEnabled }
        }, object: nil)
        let result = XCTWaiter.wait(for: [ready], timeout: 10)
        if result != .completed { attachUIEvidence(app, name: "native-menu-action-missing-" + label) }
        XCTAssertEqual(result, .completed, "The native menu must expose its displayed action: " + label)
        guard let item = matches.allElementsBoundByIndex.first(where: { $0.isHittable && $0.isEnabled }) else {
            attachUIEvidence(app, name: "native-menu-action-disappeared-" + label)
            XCTFail("The native menu action disappeared before selection: " + label)
            return
        }
        let frame = item.frame
        let visible = frame.width > 0 && frame.height > 0 && app.frame.contains(frame)
        if !visible { attachUIEvidence(app, name: "native-menu-action-clipped-" + label) }
        XCTAssertTrue(visible, "The native menu action must be fully visible: " + label)
        let hittable = item.isHittable
        if !hittable { attachUIEvidence(app, name: "native-menu-action-not-hittable-" + label) }
        XCTAssertTrue(hittable)
        item.tap()
    }

    private func continueID(_ game: String) -> String {
        (game == "minesweeper" ? "mines" : game) + ".continue"
    }

    private func continueDeleteAction(_ game: String, app: XCUIApplication) -> XCUIElement? {
        let identified = app.buttons.matching(identifier: game + ".continue.delete")
        if let action = identified.allElementsBoundByIndex.first(where: { $0.isHittable && $0.isEnabled }) {
            return action
        }
        // Native Form swipe actions can export their displayed label without
        // the SwiftUI identifier. Sudoku retains its custom ScrollView action.
        let native = app.buttons.matching(NSPredicate(format: "label IN %@", ["Delete progress", "刪除進度"]))
        return native.allElementsBoundByIndex.first { $0.isHittable && $0.isEnabled }
    }

    private func tapContinueDelete(_ game: String, current: XCUIElement, app: XCUIApplication) {
        if continueDeleteAction(game, app: app) == nil {
            scrollFullyIntoView(current, app: app)
            current.swipeLeft()
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.continueDeleteAction(game, app: app) != nil
        }, object: nil)
        let result = XCTWaiter.wait(for: [ready], timeout: 10)
        if result != .completed { attachUIEvidence(app, name: "continue-delete-action-missing-" + game) }
        XCTAssertEqual(result, .completed, "A real left swipe must reveal the enabled Delete progress action.")
        XCTAssertFalse(app.buttons[game+".session.pause"].exists,"Swiping Continue must never navigate into the game.")
        XCTAssertFalse(app.buttons[game+".delete.confirm"].exists,"A swipe alone must not request deletion.")
        guard let action = continueDeleteAction(game, app: app) else {
            attachUIEvidence(app, name: "continue-delete-action-disappeared-" + game)
            XCTFail("The Continue deletion action disappeared before selection.")
            return
        }
        let frame = action.frame
        let visible = frame.width > 0 && frame.height > 0 && app.frame.contains(frame)
        if !visible { attachUIEvidence(app, name: "continue-delete-action-clipped-" + game) }
        XCTAssertTrue(visible, "The actual deletion action must be fully visible.")
        let hittable = action.isHittable
        if !hittable { attachUIEvidence(app, name: "continue-delete-action-not-hittable-" + game) }
        XCTAssertTrue(hittable)
        action.tap()
    }

    private func openMenu(_ game: String, app: XCUIApplication) {
        if ["tictactoe", "connectfour"].contains(game) {
            tap("catalog.boardgames", app: app)
            XCTAssertTrue(node("catalog.folder.boardgames", app: app).waitForExistence(timeout: 10))
        }
        tap("game." + game, app: app)
        XCTAssertTrue(app.buttons[game + ".menu.settings"].waitForExistence(timeout: 10))
    }

    private func resumeSession(_ game: String, app: XCUIApplication, doubleTap: Bool = false) {
        let resume = app.buttons[game + ".session.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        if doubleTap { resume.doubleTap() } else { resume.tap() }
        waitUI("Resume must return to the actual game.") {
            !resume.exists && self.node(game + ".timer", app: app).exists && app.buttons[game + ".session.pause"].isEnabled
        }
    }

    private func openSavedSession(_ game: String, app: XCUIApplication, ended: Bool = false) {
        openMenu(game, app: app)
        tap(continueID(game), app: app)
        if ended {
            XCTAssertTrue(node(game + ".session.result", app: app).waitForExistence(timeout: 10))
        } else {
            XCTAssertTrue(app.buttons[game + ".session.resume"].waitForExistence(timeout: 10))
            resumeSession(game, app: app)
        }
    }

    private func openSavedSliding(_ app: XCUIApplication, ended: Bool = false) {
        openSavedSession("sliding", app: app, ended: ended)
        if !ended { XCTAssertTrue(app.buttons["sliding.tile.8"].waitForExistence(timeout: 5)) }
    }

    private func goHome(_ app: XCUIApplication) {
        for _ in 0..<4 {
            if app.buttons["settings.open"].exists { return }
            back(app)
        }
        XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 10))
    }

    private func assertResult(_ game: String, app: XCUIApplication, moves: Int? = nil) {
        XCTAssertTrue(node(game + ".session.result", app: app).waitForExistence(timeout: 15))
        for field in ["elapsed", "moves", "difficulty"] {
            let value = node(game + ".session.result." + field, app: app)
            XCTAssertTrue(value.exists)
            XCTAssertNotNil(value.value as? String)
        }
        if let moves { XCTAssertEqual(node(game + ".session.result.moves", app: app).value as? String, String(moves)) }
        XCTAssertTrue(app.buttons[game + ".session.done"].isEnabled)
        XCTAssertTrue(app.buttons[game + ".session.review"].isEnabled)
    }

    private func reviewAndReopenResult(_ game: String, app: XCUIApplication) {
        let elapsed = node(game + ".session.result.elapsed", app: app).value as? String
        let moves = node(game + ".session.result.moves", app: app).value as? String
        tap(game + ".session.review", app: app)
        let shield = node(game + ".session.reviewBoard", app: app)
        XCTAssertTrue(shield.waitForExistence(timeout: 10))
        XCTAssertFalse(node(game + ".session.result", app: app).exists)
        shield.tap()
        assertResult(game, app: app)
        XCTAssertEqual(node(game + ".session.result.elapsed", app: app).value as? String, elapsed)
        XCTAssertEqual(node(game + ".session.result.moves", app: app).value as? String, moves)
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
        assertResult("sliding", app: app, moves: 36)
    }

    private func screenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func back(_ app: XCUIApplication) {
        // A settings sheet retains the underlying game's navigation bar in
        // the accessibility tree. Choose the frontmost actionable bar.
        let bars = app.navigationBars.allElementsBoundByIndex
        let navigation = bars.last(where: { $0.isHittable }) ?? app.navigationBars.firstMatch
        let button = navigation.buttons.matching(identifier:"navigation.back").firstMatch
        XCTAssertTrue(button.waitForExistence(timeout:10)); XCTAssertTrue(button.isHittable); button.tap()
    }

    private func scrollFullyIntoView(_ element: XCUIElement, app: XCUIApplication) {
        for attempt in 0..<18 {
            // Navigation can finish changing from a large Home title to an
            // inline destination title during this search. Never cache its frame.
            let window = app.frame
            let navigation = app.navigationBars.firstMatch
            let top = navigation.exists ? navigation.frame.maxY : window.minY
            var usable = CGRect(x: window.minX + 10, y: top, width: window.width - 20, height: window.maxY - 20 - top)
            let scrollView = app.scrollViews.firstMatch
            let list = app.tables.firstMatch
            let container = scrollView.exists ? scrollView.frame : (list.exists ? list.frame : window)
            usable = usable.intersection(container)
            var distance = usable.height * 0.3
            var towardTop = attempt >= 9
            if element.exists {
                let frame = element.frame
                if frame.width > 0 && frame.height > 0 && usable.contains(frame) {
                    let hittable = element.isHittable
                    if !hittable { attachUIEvidence(app, name: "visible-control-not-hittable-" + element.identifier) }
                    XCTAssertTrue(hittable, "Fully visible control must be tappable: " + element.identifier)
                    return
                }
                if frame.height > 0 {
                    towardTop = frame.minY < usable.minY
                    let overhang = towardTop ? usable.minY - frame.minY : frame.maxY - usable.maxY
                    distance = min(usable.height * 0.3, max(28, overhang + 12))
                }
            }
            guard !usable.isNull, usable.height > 80 else { break }
            // Full-screen swipes jumped past a 283-point Home card, then jumped
            // back past it in the opposite direction. Move only its overhang,
            // using the scroll viewport's gutter to avoid gameplay gestures.
            let x = max(window.minX + 4, container.minX + 4)
            let startY = towardTop ? usable.minY + 32 : usable.maxY - 32
            let endY = startY + (towardTop ? distance : -distance)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: x - window.minX, dy: startY - window.minY))
            let end = origin.withOffset(CGVector(dx: x - window.minX, dy: endY - window.minY))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
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
        tap("sliding.session.pause", app: app)
        XCTAssertTrue(app.buttons["sliding.session.resume"].waitForExistence(timeout: 5))
        screenshot(app, name: "visual-013-sliding-pause-light")
        resumeSession("sliding", app: app)
        finishSeed(app, capturesWin: true)
        // Count is a Debug-Simulator probe of actual starts. The short-lived,
        // noninteractive effect can end before XCTest finishes waiting for idle.
        expectProbe(app, starts: 1)
        expectProbe(app, starts: 1, active: false)
        screenshot(app, name: "visual-013-fresh-win")

        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["game.sliding"].waitForExistence(timeout: 10))
        openSavedSliding(app, ended: true)
        assertResult("sliding", app: app, moves: 36)
        expectProbe(app, starts: 0, active: false)
        reviewAndReopenResult("sliding", app: app)
        expectProbe(app, starts: 0, active: false)
        tap("sliding.session.done", app: app)
        tap("sliding.start", app: app)
        XCTAssertTrue(app.buttons["sliding.new.confirm"].waitForExistence(timeout: 5))
        tap("sliding.new.cancel", app: app)
        XCTAssertTrue(app.buttons["sliding.continue"].label.contains("36"))
        tap("sliding.start", app: app)
        let agree = app.buttons["sliding.new.confirm"]
        XCTAssertTrue(agree.waitForExistence(timeout: 5)); agree.doubleTap()
        let restarted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !self.node("sliding.session.result", app: app).exists &&
            app.staticTexts["sliding.moves"].label == "0 步" &&
            app.buttons["sliding.session.pause"].isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restarted], timeout: 10), .completed)
        XCTAssertFalse(node("sliding.session.result", app: app).exists)
        XCTAssertEqual(app.staticTexts["sliding.moves"].label, "0 步")
        let tiles = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'sliding.tile.'"))
        XCTAssertEqual(tiles.count, 9)
        XCTAssertEqual(tiles.allElementsBoundByIndex.filter { $0.label == "空格" }.count, 1)
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
            XCTAssertTrue(app.buttons[game + ".session.resume"].waitForExistence(timeout: 10))
            resumeSession(game, app: app)
            XCTAssertTrue(app.buttons[playElement].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons[game + ".session.settings"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["navigation.back"].isHittable)
            screenshot(app, name: "visual-013-" + game + "-play-dark")
            if game == "sliding" {
                tap("sliding.session.pause", app: app)
                XCTAssertTrue(app.buttons["sliding.session.resume"].waitForExistence(timeout: 5))
                screenshot(app, name: "visual-013-sliding-pause-dark")
                resumeSession("sliding", app: app)
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
        XCTAssertTrue(app.buttons[game + ".session.resume"].waitForExistence(timeout: 10))
        resumeSession(game, app: app)
        // Prove navigation independently of a cell's accessibility traits.
        XCTAssertTrue(app.buttons[game + ".session.settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[firstCell].waitForExistence(timeout: 5))
    }

    private func assertIPadPauseResume(_ app: XCUIApplication, prefix: String, firstCell: String) {
        let game = prefix == "mines" ? "minesweeper" : prefix
        let pause = app.buttons[game + ".session.pause"]
        assertIPadVisible(pause, app: app)
        XCTAssertTrue(pause.isEnabled); pause.tap()
        let resume = app.buttons[game + ".session.resume"]
        assertIPadVisible(resume, app: app)
        // The board stays rendered under blur; the modal owns accessibility focus.
        XCTAssertFalse(app.buttons[firstCell].exists)
        resumeSession(game, app: app)
        XCTAssertTrue(app.buttons[firstCell].waitForExistence(timeout: 5))
        XCTAssertTrue(pause.isEnabled)
    }

    private func assertIPadSettingsRoundTrip(_ app: XCUIApplication, game: String, firstCell: String) {
        let settings = app.buttons[game + ".session.settings"]
        assertIPadVisible(settings, app: app, toolbar: true); settings.tap()
        XCTAssertTrue(app.buttons["gameSettings.done"].waitForExistence(timeout: 10))
        tap("gameSettings.done", app: app)
        XCTAssertTrue(app.buttons[game + ".session.resume"].waitForExistence(timeout: 10))
        resumeSession(game, app: app)
        XCTAssertTrue(app.buttons[firstCell].waitForExistence(timeout: 10))
    }

    private func assertIPadCaptureReady(_ app: XCUIApplication, prefix: String? = nil) {
        if let prefix {
            let game = prefix == "mines" ? "minesweeper" : prefix
            assertIPadVisible(app.buttons[game + ".session.settings"], app: app, toolbar: true)
            assertIPadVisible(app.buttons["navigation.back"], app: app, toolbar: true)
            XCTAssertFalse(app.buttons[game + ".session.resume"].exists)
            XCTAssertFalse(node(game + ".session.result", app: app).exists)
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
            "testNavigationStrategy": page == "Home" ? "Settings selected through native controls; game entry not exercised in this case." : "Tap the saved Continue row, resume through the shared paused notice, and require session settings and an actionable saved cell.",
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

        let expected = Set(["sudoku", "minesweeper", "sliding", "twentyfour", "memory", "maze", "nonogram", "kakuro", "klotski", "snake", "fallingblocks", "brickbreaker"].map { "game."+$0 } + ["catalog.boardgames","catalog.solitaire"])
        var seen: Set<String> = []
        for _ in 0..<8 {
            let visible = app.frame.insetBy(dx: 0, dy: 50)
            let entries = app.buttons.matching(NSPredicate(format: "identifier IN %@", Array(expected)))
            for entry in entries.allElementsBoundByIndex where visible.contains(CGPoint(x: entry.frame.midX, y: entry.frame.midY)) {
                XCTAssertFalse(entry.label.contains("進行中"))
                if entry.identifier == "catalog.boardgames" {
                    XCTAssertTrue(entry.label.contains("8 款可遊玩"))
                } else if entry.identifier == "catalog.solitaire" {
                    XCTAssertTrue(entry.label.contains("5 款可遊玩"))
                } else {
                    XCTAssertTrue(entry.label.contains("可遊玩"))
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
        let solitaire = ["klondike", "spider", "freecell", "pyramid", "tripeaks"].map { app.buttons["game." + $0] }
        for card in solitaire {
            scrollFullyIntoView(card, app: app)
            assertIPadVisible(card, app: app)
            XCTAssertTrue(card.label.contains("可遊玩"))
        }
        XCTAssertEqual(solitaire[0].frame.minY, solitaire[1].frame.minY, accuracy: 2)
        XCTAssertEqual(solitaire[1].frame.minY, solitaire[2].frame.minY, accuracy: 2)
        XCTAssertLessThan(solitaire[0].frame.minX, solitaire[1].frame.minX)
        XCTAssertLessThan(solitaire[1].frame.minX, solitaire[2].frame.minX)
        screenshot(app, name: "v020-iPad-solitaire")
        scrollFullyIntoView(solitaire[0],app:app); solitaire[0].tap()
        XCTAssertTrue(app.buttons["klondike.menu.settings"].waitForExistence(timeout:10))
        let start = app.buttons["klondike.start"]; scrollFullyIntoView(start,app:app); XCTAssertTrue(start.isEnabled)
        XCTAssertFalse(app.staticTexts["comingSoon.title"].exists)
        screenshot(app,name:"v030-iPad-klondike-menu")
        back(app); back(app)

        let boardFolder = app.buttons["catalog.boardgames"]
        scrollFullyIntoView(boardFolder, app: app); boardFolder.tap()
        XCTAssertTrue(app.navigationBars["棋類遊戲"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "catalog.folder.boardgames").firstMatch.waitForExistence(timeout: 5))
        let boardIDs = ["game.tictactoe", "game.connectfour", "game.gomoku", "game.reversi", "game.xiangqi", "game.banqi", "game.chess", "game.shogi"]
        var boardEntries: Set<String> = []
        for id in boardIDs {
            let card = app.buttons[id]
            scrollFullyIntoView(card, app: app)
            assertIPadVisible(card, app: app)
            XCTAssertTrue(card.label.contains("可遊玩"))
            XCTAssertFalse(card.label.contains("進行中"))
            boardEntries.insert(card.identifier)
        }
        XCTAssertEqual(boardEntries, Set(boardIDs))
        XCTAssertEqual(boardEntries.count, 8)
        XCTAssertEqual(app.staticTexts.matching(identifier: "catalog.folder.availability").firstMatch.label, "8 款可遊玩")
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
        // Native Intel snapshots of 81 cells plus all controls exceed 600s.
        // Retain every interaction and geometry assertion with a bounded case.
        executionTimeAllowance = 1800
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
        let preservedNotes = app.buttons["sudoku.cell.1"].value as? String
        XCTAssertTrue(preservedNotes?.contains("2, 7") == true)
        attachUIEvidence(app, name: "v022-iPad-sudoku-before-settings")
        assertIPadSettingsRoundTrip(app, game: "sudoku", firstCell: "sudoku.cell.0")
        XCTAssertEqual(seededBlueDigit.value as? String, "4")
        XCTAssertEqual(empty.value as? String, "空白")
        XCTAssertEqual(app.buttons["sudoku.cell.1"].value as? String, preservedNotes)
        XCTAssertFalse(node("sudoku.session.result", app: app).exists)
        assertIPadCaptureReady(app, prefix: "sudoku")
        attachUIEvidence(app, name: "v022-iPad-sudoku-settings-kept-progress")
        screenshot(app, name: "02_iPad_Sudoku")
        try attachIPadLayout(app, page: "Sudoku", grid: corners,
                             controls: digits + [app.segmentedControls["sudoku.tools"], app.buttons["sudoku.erase"], app.buttons["sudoku.session.pause"], app.buttons["sudoku.session.settings"], app.buttons["navigation.back"]])
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
        assertIPadSettingsRoundTrip(app, game: "minesweeper", firstCell: "mines.cell.30")
        XCTAssertTrue(flag.label.contains("旗標"))
        XCTAssertFalse(node("minesweeper.session.result", app: app).exists)
        assertIPadCaptureReady(app, prefix: "mines")
        screenshot(app, name: "03_iPad_Minesweeper")
        try attachIPadLayout(app, page: "Minesweeper", grid: corners,
                             controls: [node("minesweeper.timer", app: app), app.buttons["minesweeper.session.pause"], app.buttons["minesweeper.session.settings"], app.buttons["navigation.back"]], viewport: viewport)
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
        XCTAssertFalse(node("sliding.session.result", app: app).exists)
        assertIPadPauseResume(app, prefix: "sliding", firstCell: "sliding.tile.7")
        assertIPadSettingsRoundTrip(app, game: "sliding", firstCell: "sliding.tile.7")
        XCTAssertEqual(app.staticTexts["sliding.moves"].label, "36 步")
        let reverseMove = app.buttons["sliding.tile.7"]
        assertIPadVisible(reverseMove, app: app); XCTAssertTrue(reverseMove.isEnabled)
        reverseMove.swipeLeft()
        XCTAssertEqual(app.staticTexts["sliding.moves"].label, "37 步")
        XCTAssertEqual(tiles.matching(identifier: "sliding.tile.7").firstMatch.label, "空格")
        XCTAssertEqual(tiles.matching(identifier: "sliding.tile.6").firstMatch.label, "方塊 7")
        XCTAssertFalse(node("sliding.session.result", app: app).exists)
        assertIPadCaptureReady(app, prefix: "sliding")
        screenshot(app, name: "04_iPad_SlidingPuzzle")
        try attachIPadLayout(app, page: "SlidingPuzzle", grid: corners,
                             controls: [app.staticTexts["sliding.moves"], node("sliding.timer", app: app), app.buttons["sliding.session.pause"], app.buttons["sliding.session.settings"], app.buttons["navigation.back"]])
        back(app); XCTAssertTrue(app.buttons["sliding.continue"].waitForExistence(timeout: 5))
        back(app); XCTAssertTrue(app.buttons["game.sliding"].waitForExistence(timeout: 5))
    }

    private func boardSnapshot(_ game: String, app: XCUIApplication) -> [String] {
        let ids: [String]
        switch game {
        case "sudoku": ids = [0, 1, 2, 3, 8, 40, 80].map { "sudoku.cell.\($0)" }
        case "minesweeper": ids = [0, 1, 30, 40, 80].map { "mines.cell.\($0)" }
        case "sliding": ids = (0..<9).map { "sliding.tile.\($0)" } + ["sliding.moves"]
        case "tictactoe": ids = (0..<9).map { "tictactoe.cell.\($0)" } + ["tictactoe.moves"]
        case "connectfour": ids = (0..<7).map { "connectfour.column.\($0)" } + ["connectfour.moves"]
        case "twentyfour": ids = ["twentyfour.card.3", "twentyfour.card.5", "twentyfour.stage"]
        case "memory": ids = (0..<16).map { "memory.card.\($0)" } + ["memory.moves", "memory.pairs"]
        case "maze": ids = ["maze.position", "maze.moves"]
        default: XCTFail("Unknown session fixture"); return []
        }
        return ids.map { id in
            let element = node(id, app: app)
            XCTAssertTrue(element.exists, "Missing saved board element: " + id)
            return id + ":" + element.label + ":" + (element.value as? String ?? "")
        }
    }

    private func finishSessionFixture(_ game: String, app: XCUIApplication) {
        switch game {
        case "sudoku":
            tap("sudoku.cell.1", app: app)
            tap("sudoku.digit.3", app: app)
        case "minesweeper": tap("mines.cell.0", app: app)
        case "sliding": app.buttons["sliding.tile.8"].swipeLeft()
        case "tictactoe": tap("tictactoe.cell.2", app: app)
        case "connectfour": tap("connectfour.column.3", app: app)
        case "twentyfour":
            tap("twentyfour.card.3", app: app); tap("twentyfour.operator.multiply", app: app)
            tap("twentyfour.card.5", app: app); tap("twentyfour.apply", app: app)
        case "memory":
            let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.card.'"))
            XCTAssertEqual(cards.count, 16)
            let unturned = cards.allElementsBoundByIndex.filter(\.isEnabled)
            XCTAssertEqual(unturned.count, 2)
            for card in unturned {
                XCTAssertTrue(card.label.contains("face down")); card.tap()
            }
        case "maze": tap("maze.right", app: app); tap("maze.down", app: app)
        default: XCTFail("Unknown completion fixture")
        }
        assertResult(game, app: app)
    }

    private func exerciseSharedSession(_ game: String) throws {
        executionTimeAllowance = 360
        let app = try launch(profile: "v022-session-" + game, allGames: true,
                             fixture: game == "sliding" ? nil : game, language: "en")
        openSavedSession(game, app: app)
        if game == "memory" {
            let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.card.'"))
            XCTAssertEqual(cards.count, 16)
            XCTAssertEqual(cards.allElementsBoundByIndex.filter(\.isEnabled).count, 2)
        }
        let beforePause = boardSnapshot(game, app: app)
        let clock = node(game + ".timer", app: app)
        let firstTime = try XCTUnwrap(clock.value as? String, "The shared clock must expose its displayed duration as an accessibility value.")
        let firstSeconds = try XCTUnwrap(clockSeconds(firstTime), "The shared clock must provide a valid H:MM:SS duration.")
        waitUI("The shared clock value must advance during actual play.", timeout: 10) {
            guard clock.exists, let current = clock.value as? String,
                  let seconds = self.clockSeconds(current) else { return false }
            return seconds > firstSeconds
        }
        tap(game + ".session.pause", app: app)
        let pausedClock = node(game + ".session.paused.elapsed", app: app)
        XCTAssertTrue(pausedClock.waitForExistence(timeout: 10))
        let frozenTime = pausedClock.value as? String
        XCTAssertNotNil(frozenTime)
        let changedWhilePaused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            pausedClock.exists && pausedClock.value as? String != frozenTime
        }, object: nil)
        changedWhilePaused.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changedWhilePaused], timeout: 1.5), .completed)
        screenshot(app, name: "v022-" + game + "-paused-blurred-board")
        // A single compound event exercises the shell's actual touch isolation.
        // It must not submit a second touch to the board under the resume button.
        resumeSession(game, app: app, doubleTap: true)
        XCTAssertEqual(boardSnapshot(game, app: app), beforePause)
        tap(game + ".session.settings", app: app)
        XCTAssertTrue(app.buttons["gameSettings.done"].waitForExistence(timeout: 10))
        tap("gameSettings.done", app: app)
        XCTAssertTrue(app.buttons[game + ".session.resume"].waitForExistence(timeout: 10))
        resumeSession(game, app: app)
        XCTAssertEqual(boardSnapshot(game, app: app), beforePause)
        finishSessionFixture(game, app: app)
        screenshot(app, name: "v022-" + game + "-shared-result")
        reviewAndReopenResult(game, app: app)
        let done = app.buttons[game + ".session.done"]
        done.doubleTap()
        let current = app.buttons.matching(identifier: continueID(game)).firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 10), "Done must return to the game's menu.")
        current.swipeRight()
        XCTAssertTrue(current.exists,"A rightward swipe must stay on the menu.")
        XCTAssertFalse(app.buttons[game+".session.pause"].exists)
        XCTAssertFalse(node(game + ".session.result", app: app).exists)
        let savedDetailBeforeRequest = current.label
        tapContinueDelete(game, current: current, app: app)
        XCTAssertTrue(app.buttons[game + ".delete.confirm"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[game + ".delete.confirm"].isEnabled)
        XCTAssertTrue(app.buttons[game + ".delete.cancel"].isEnabled)
        tap(game + ".delete.cancel", app: app)
        waitUI("Cancel must dismiss the actual deletion confirmation.") { !app.buttons[game + ".delete.confirm"].exists }
        XCTAssertTrue(current.exists, "Cancelling deletion must preserve the saved round.")
        XCTAssertEqual(current.label,savedDetailBeforeRequest,"Requesting deletion must not change the saved progress.")
        app.terminate(); app.launch()
        openMenu(game,app:app)
        XCTAssertTrue(current.waitForExistence(timeout:10),"Cancellation must preserve actual on-disk progress after a fresh process.")
        XCTAssertEqual(current.label,savedDetailBeforeRequest)
        tapContinueDelete(game, current: current, app: app)
        let confirm = app.buttons[game + ".delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.doubleTap()
        waitUI("Confirmed deletion must remove only this Continue row.") { !current.exists }
        screenshot(app, name: "v022-" + game + "-continue-deleted")

        // Finishing, reviewing, reopening, double-Done, and deleting the board
        // must all leave exactly one actual completion record.
        tap(game + ".menu.settings", app: app)
        tap("gameSettings.history", app: app)
        let records = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history.record.'"))
        XCTAssertTrue(records.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(records.count, 1)
        screenshot(app, name: "v022-" + game + "-single-retained-history-record")
        back(app); tap("gameSettings.done", app: app)
        goHome(app)
        let otherGame = game == "sliding" ? "minesweeper" : "sliding"
        openMenu(otherGame, app: app)
        let otherSave = app.buttons[continueID(otherGame)]
        XCTAssertTrue(otherSave.waitForExistence(timeout: 10), "Deleting one namespace must preserve the other released saves.")
        XCTAssertTrue(otherSave.label.contains(otherGame == "sliding" ? "35" : "1 flags / 10 mines"))
        if game == "sudoku" {
            goHome(app); openMenu("sudoku", app: app)
            tap("sudoku.difficulty.medium", app: app)
            let sentinel = app.buttons["sudoku.medium.0001"]
            XCTAssertTrue(sentinel.waitForExistence(timeout: 10))
            XCTAssertTrue(sentinel.label.contains("In progress"), "Deleting the current Sudoku puzzle must retain other puzzle boards.")
            sentinel.tap()
            XCTAssertTrue(app.buttons["sudoku.session.resume"].waitForExistence(timeout: 10))
        }
    }

    func testSudokuCommonSessionLifecycleAndContinueDeletion() throws { try exerciseSharedSession("sudoku") }
    func testMinesweeperCommonSessionLifecycleAndContinueDeletion() throws {
        // The real result button is visible below the disabled zoom-board viewport.
        // Use its foreground dialog, preserving the complete shared-session journey.
        let game = "minesweeper"
        func reviewMinesResult(_ game: String, app: XCUIApplication) {
        let elapsed = node(game + ".session.result.elapsed", app: app).value as? String
        let moves = node(game + ".session.result.moves", app: app).value as? String
        let review = app.buttons[game + ".session.review"]
        let dialog = app.scrollViews.matching(identifier: game + ".session.result").firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 10))
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        let window = app.frame
        let top = app.navigationBars.firstMatch.frame.maxY
        let viewport = CGRect(x: window.minX + 10, y: top, width: window.width - 20,
                              height: window.maxY - 20 - top).intersection(dialog.frame)
        XCTAssertTrue(viewport.contains(review.frame), "Review must fit the actual foreground result viewport.")
        XCTAssertTrue(review.isHittable); XCTAssertTrue(review.isEnabled)
        review.tap()
        let shield = node(game + ".session.reviewBoard", app: app)
        XCTAssertTrue(shield.waitForExistence(timeout: 10))
        XCTAssertFalse(node(game + ".session.result", app: app).exists)
        shield.tap()
        assertResult(game, app: app)
        XCTAssertEqual(node(game + ".session.result.elapsed", app: app).value as? String, elapsed)
        XCTAssertEqual(node(game + ".session.result.moves", app: app).value as? String, moves)
            }

        executionTimeAllowance = 1800
        let app = try launch(profile: "v022-session-" + game, allGames: true,
                             fixture: game == "sliding" ? nil : game, language: "en")
        openSavedSession(game, app: app)
        if game == "memory" {
            let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.card.'"))
            XCTAssertEqual(cards.count, 16)
            XCTAssertEqual(cards.allElementsBoundByIndex.filter(\.isEnabled).count, 2)
        }
        let beforePause = boardSnapshot(game, app: app)
        let clock = node(game + ".timer", app: app)
        let firstTime = try XCTUnwrap(clock.value as? String, "The shared clock must expose its displayed duration as an accessibility value.")
        let firstSeconds = try XCTUnwrap(clockSeconds(firstTime), "The shared clock must provide a valid H:MM:SS duration.")
        waitUI("The shared clock value must advance during actual play.", timeout: 10) {
            guard clock.exists, let current = clock.value as? String,
                  let seconds = self.clockSeconds(current) else { return false }
            return seconds > firstSeconds
        }
        tap(game + ".session.pause", app: app)
        let pausedClock = node(game + ".session.paused.elapsed", app: app)
        XCTAssertTrue(pausedClock.waitForExistence(timeout: 10))
        let frozenTime = pausedClock.value as? String
        XCTAssertNotNil(frozenTime)
        let changedWhilePaused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            pausedClock.exists && pausedClock.value as? String != frozenTime
        }, object: nil)
        changedWhilePaused.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changedWhilePaused], timeout: 1.5), .completed)
        screenshot(app, name: "v022-" + game + "-paused-blurred-board")
        // A single compound event exercises the shell's actual touch isolation.
        // It must not submit a second touch to the board under the resume button.
        resumeSession(game, app: app, doubleTap: true)
        XCTAssertEqual(boardSnapshot(game, app: app), beforePause)
        tap(game + ".session.settings", app: app)
        XCTAssertTrue(app.buttons["gameSettings.done"].waitForExistence(timeout: 10))
        tap("gameSettings.done", app: app)
        XCTAssertTrue(app.buttons[game + ".session.resume"].waitForExistence(timeout: 10))
        resumeSession(game, app: app)
        XCTAssertEqual(boardSnapshot(game, app: app), beforePause)
        finishSessionFixture(game, app: app)
        screenshot(app, name: "v022-" + game + "-shared-result")
        reviewMinesResult(game, app: app)
        let done = app.buttons[game + ".session.done"]
        done.doubleTap()
        let current = app.buttons.matching(identifier: continueID(game)).firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 10), "Done must return to the game's menu.")
        current.swipeRight()
        XCTAssertTrue(current.exists,"A rightward swipe must stay on the menu.")
        XCTAssertFalse(app.buttons[game+".session.pause"].exists)
        XCTAssertFalse(node(game + ".session.result", app: app).exists)
        let savedDetailBeforeRequest = current.label
        tapContinueDelete(game, current: current, app: app)
        XCTAssertTrue(app.buttons[game + ".delete.confirm"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[game + ".delete.confirm"].isEnabled)
        XCTAssertTrue(app.buttons[game + ".delete.cancel"].isEnabled)
        tap(game + ".delete.cancel", app: app)
        waitUI("Cancel must dismiss the actual deletion confirmation.") { !app.buttons[game + ".delete.confirm"].exists }
        XCTAssertTrue(current.exists, "Cancelling deletion must preserve the saved round.")
        XCTAssertEqual(current.label,savedDetailBeforeRequest,"Requesting deletion must not change the saved progress.")
        app.terminate(); app.launch()
        openMenu(game,app:app)
        XCTAssertTrue(current.waitForExistence(timeout:10),"Cancellation must preserve actual on-disk progress after a fresh process.")
        XCTAssertEqual(current.label,savedDetailBeforeRequest)
        tapContinueDelete(game, current: current, app: app)
        let confirm = app.buttons[game + ".delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.doubleTap()
        waitUI("Confirmed deletion must remove only this Continue row.") { !current.exists }
        screenshot(app, name: "v022-" + game + "-continue-deleted")

        // Finishing, reviewing, reopening, double-Done, and deleting the board
        // must all leave exactly one actual completion record.
        tap(game + ".menu.settings", app: app)
        tap("gameSettings.history", app: app)
        let records = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history.record.'"))
        XCTAssertTrue(records.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(records.count, 1)
        screenshot(app, name: "v022-" + game + "-single-retained-history-record")
        back(app); tap("gameSettings.done", app: app)
        goHome(app)
        let otherGame = game == "sliding" ? "minesweeper" : "sliding"
        openMenu(otherGame, app: app)
        let otherSave = app.buttons[continueID(otherGame)]
        XCTAssertTrue(otherSave.waitForExistence(timeout: 10), "Deleting one namespace must preserve the other released saves.")
        XCTAssertTrue(otherSave.label.contains(otherGame == "sliding" ? "35" : "1 flags / 10 mines"))
        if game == "sudoku" {
            goHome(app); openMenu("sudoku", app: app)
            tap("sudoku.difficulty.medium", app: app)
            let sentinel = app.buttons["sudoku.medium.0001"]
            XCTAssertTrue(sentinel.waitForExistence(timeout: 10))
            XCTAssertTrue(sentinel.label.contains("In progress"), "Deleting the current Sudoku puzzle must retain other puzzle boards.")
            sentinel.tap()
            XCTAssertTrue(app.buttons["sudoku.session.resume"].waitForExistence(timeout: 10))
        }
        }
    func testSlidingCommonSessionLifecycleAndContinueDeletion() throws { try exerciseSharedSession("sliding") }
    func testTicTacToeCommonSessionLifecycleAndContinueDeletion() throws { try exerciseSharedSession("tictactoe") }
    func testConnectFourCommonSessionLifecycleAndContinueDeletion() throws { try exerciseSharedSession("connectfour") }
    func testTwentyFourCommonSessionLifecycleAndContinueDeletion() throws { try exerciseSharedSession("twentyfour") }
    func testMemoryCommonSessionLifecycleAndContinueDeletion() throws {
        // The unchanged complete journey measured 432s on Intel; retain every assertion.
        let game = "memory"

        executionTimeAllowance = 1800
        let app = try launch(profile: "v022-session-" + game, allGames: true,
                             fixture: game == "sliding" ? nil : game, language: "en")
        openSavedSession(game, app: app)
        if game == "memory" {
            let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.card.'"))
            XCTAssertEqual(cards.count, 16)
            XCTAssertEqual(cards.allElementsBoundByIndex.filter(\.isEnabled).count, 2)
        }
        let beforePause = boardSnapshot(game, app: app)
        let clock = node(game + ".timer", app: app)
        let firstTime = try XCTUnwrap(clock.value as? String, "The shared clock must expose its displayed duration as an accessibility value.")
        let firstSeconds = try XCTUnwrap(clockSeconds(firstTime), "The shared clock must provide a valid H:MM:SS duration.")
        waitUI("The shared clock value must advance during actual play.", timeout: 10) {
            guard clock.exists, let current = clock.value as? String,
                  let seconds = self.clockSeconds(current) else { return false }
            return seconds > firstSeconds
        }
        tap(game + ".session.pause", app: app)
        let pausedClock = node(game + ".session.paused.elapsed", app: app)
        XCTAssertTrue(pausedClock.waitForExistence(timeout: 10))
        let frozenTime = pausedClock.value as? String
        XCTAssertNotNil(frozenTime)
        let changedWhilePaused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            pausedClock.exists && pausedClock.value as? String != frozenTime
        }, object: nil)
        changedWhilePaused.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changedWhilePaused], timeout: 1.5), .completed)
        screenshot(app, name: "v022-" + game + "-paused-blurred-board")
        // A single compound event exercises the shell's actual touch isolation.
        // It must not submit a second touch to the board under the resume button.
        resumeSession(game, app: app, doubleTap: true)
        XCTAssertEqual(boardSnapshot(game, app: app), beforePause)
        tap(game + ".session.settings", app: app)
        XCTAssertTrue(app.buttons["gameSettings.done"].waitForExistence(timeout: 10))
        tap("gameSettings.done", app: app)
        XCTAssertTrue(app.buttons[game + ".session.resume"].waitForExistence(timeout: 10))
        resumeSession(game, app: app)
        XCTAssertEqual(boardSnapshot(game, app: app), beforePause)
        finishSessionFixture(game, app: app)
        screenshot(app, name: "v022-" + game + "-shared-result")
        reviewAndReopenResult(game, app: app)
        let done = app.buttons[game + ".session.done"]
        done.doubleTap()
        let current = app.buttons.matching(identifier: continueID(game)).firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 10), "Done must return to the game's menu.")
        current.swipeRight()
        XCTAssertTrue(current.exists,"A rightward swipe must stay on the menu.")
        XCTAssertFalse(app.buttons[game+".session.pause"].exists)
        XCTAssertFalse(node(game + ".session.result", app: app).exists)
        let savedDetailBeforeRequest = current.label
        tapContinueDelete(game, current: current, app: app)
        XCTAssertTrue(app.buttons[game + ".delete.confirm"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[game + ".delete.confirm"].isEnabled)
        XCTAssertTrue(app.buttons[game + ".delete.cancel"].isEnabled)
        tap(game + ".delete.cancel", app: app)
        waitUI("Cancel must dismiss the actual deletion confirmation.") { !app.buttons[game + ".delete.confirm"].exists }
        XCTAssertTrue(current.exists, "Cancelling deletion must preserve the saved round.")
        XCTAssertEqual(current.label,savedDetailBeforeRequest,"Requesting deletion must not change the saved progress.")
        app.terminate(); app.launch()
        openMenu(game,app:app)
        XCTAssertTrue(current.waitForExistence(timeout:10),"Cancellation must preserve actual on-disk progress after a fresh process.")
        XCTAssertEqual(current.label,savedDetailBeforeRequest)
        tapContinueDelete(game, current: current, app: app)
        let confirm = app.buttons[game + ".delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.doubleTap()
        waitUI("Confirmed deletion must remove only this Continue row.") { !current.exists }
        screenshot(app, name: "v022-" + game + "-continue-deleted")

        // Finishing, reviewing, reopening, double-Done, and deleting the board
        // must all leave exactly one actual completion record.
        tap(game + ".menu.settings", app: app)
        tap("gameSettings.history", app: app)
        let records = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history.record.'"))
        XCTAssertTrue(records.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(records.count, 1)
        screenshot(app, name: "v022-" + game + "-single-retained-history-record")
        back(app); tap("gameSettings.done", app: app)
        goHome(app)
        let otherGame = game == "sliding" ? "minesweeper" : "sliding"
        openMenu(otherGame, app: app)
        let otherSave = app.buttons[continueID(otherGame)]
        XCTAssertTrue(otherSave.waitForExistence(timeout: 10), "Deleting one namespace must preserve the other released saves.")
        XCTAssertTrue(otherSave.label.contains(otherGame == "sliding" ? "35" : "1 flags / 10 mines"))
        if game == "sudoku" {
            goHome(app); openMenu("sudoku", app: app)
            tap("sudoku.difficulty.medium", app: app)
            let sentinel = app.buttons["sudoku.medium.0001"]
            XCTAssertTrue(sentinel.waitForExistence(timeout: 10))
            XCTAssertTrue(sentinel.label.contains("In progress"), "Deleting the current Sudoku puzzle must retain other puzzle boards.")
            sentinel.tap()
            XCTAssertTrue(app.buttons["sudoku.session.resume"].waitForExistence(timeout: 10))
        }
        }
    func testMazeCommonSessionLifecycleAndContinueDeletion() throws { try exerciseSharedSession("maze") }

    func testPlayHistorySearchDismissesKeyboardWithoutSwallowingActions() throws {
        // The complete real journey reached 307s before Xcode's 300s watchdog.
        // Keep every keyboard/filter/record action under a bounded case budget.
        executionTimeAllowance = 900
        let app = try launch(profile: "v022-history", allGames: true, language: "en")
        openSavedSliding(app)
        finishSessionFixture("sliding", app: app)
        tap("sliding.session.done", app: app); goHome(app)
        app.buttons["settings.open"].tap()
        tap("settings.history", app: app)
        let search = app.textFields["history.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("sliding")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        let records = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history.record.'"))
        XCTAssertEqual(records.count, 1)
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Tapping inside the search field must keep the keyboard.")
        let historyList = node("history.list", app: app)
        XCTAssertTrue(historyList.waitForExistence(timeout: 10))
        let blankPoint = CGPoint(x: app.frame.maxX - 6, y: search.frame.maxY + 30)
        XCTAssertTrue(historyList.frame.contains(blankPoint), "The dismissal tap must land inside the actual history list.")
        XCTAssertFalse(search.frame.contains(blankPoint))
        XCTAssertLessThan(blankPoint.y, app.keyboards.firstMatch.frame.minY)
        XCTAssertTrue(records.allElementsBoundByIndex.allSatisfy { !$0.frame.contains(blankPoint) },
                      "The blank-gutter tap must not target a record action.")
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: blankPoint.x - app.frame.minX, dy: blankPoint.y - app.frame.minY)).tap()
        waitUI("Tapping the list's blank gutter must dismiss the keyboard.") { app.keyboards.count == 0 }
        XCTAssertEqual(search.value as? String, "sliding")
        XCTAssertEqual(records.count, 1)
        XCTAssertFalse(app.navigationBars["Record details"].exists)
        screenshot(app, name: "v022-history-blank-area-dismissed-keyboard")
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        tap("history.filters", app: app)
        waitUI("Opening filters must dismiss the keyboard without swallowing the filter action.") { app.keyboards.count == 0 }
        tapNativeMenuItem("Sort order", app: app)
        XCTAssertTrue(app.navigationBars["Sort order"].waitForExistence(timeout: 10))
        let order = app.buttons.matching(NSPredicate(format: "label == %@", "Moves: fewest first")).firstMatch
        XCTAssertTrue(order.waitForExistence(timeout: 10)); order.tap()
        waitUI("Selecting an actual sort option must close its sheet.") { !app.navigationBars["Sort order"].exists }
        search.tap(); search.typeText(" qzx-no-record")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(records.count, 0)
        tap("history.search.clear", app: app)
        XCTAssertEqual(records.count, 1)
        search.tap(); search.typeText("sliding")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        records.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Record details"].waitForExistence(timeout: 10), "A record tap must still open its real detail sheet.")
        XCTAssertEqual(app.keyboards.count, 0)
        XCTAssertTrue(app.navigationBars["Record details"].exists)
        screenshot(app, name: "v022-history-record-opened-with-keyboard-dismissed")
        app.navigationBars["Record details"].buttons["Done"].tap()
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        tap("history.keyboard.done", app: app)
        waitUI("The keyboard toolbar Done action must dismiss the keyboard.") { app.keyboards.count == 0 }
        XCTAssertEqual(records.count, 1)
    }
}
