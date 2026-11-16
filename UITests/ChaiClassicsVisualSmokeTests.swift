import XCTest

/// Focused 0.1.3 smoke selection; the existing full game/regression suite remains intact.
final class ChaiClassicsVisualSmokeTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

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
        let window = app.frame
        let usable = CGRect(x: window.minX + 10, y: window.minY + 150, width: window.width - 20, height: window.height - 240)
        for _ in 0..<5 {
            if element.exists {
                let frame = element.frame
                if frame.width > 0 && frame.height > 0 && usable.contains(frame) { return }
                if frame.height > 0 && frame.minY < usable.minY { app.swipeDown(); continue }
            }
            app.swipeUp()
        }
        XCTFail("Control did not become fully visible: " + element.identifier)
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
        app.buttons["sliding.confirmRestart"].tap()
        XCTAssertFalse(app.staticTexts["sliding.complete"].exists)
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
}
