import XCTest

final class ChaiClassicsUITests: XCTestCase {
    func testSudokuNavigationAndRestoration() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["game.sudoku"].waitForExistence(timeout: 10))
        app.buttons["game.sudoku"].tap()
        app.buttons["簡單"].tap()
        app.buttons["sudoku.easy.0001"].tap()
        XCTAssertTrue(app.buttons["sudoku.cell.1"].waitForExistence(timeout: 5))
        app.buttons["sudoku.cell.1"].tap()
        app.segmentedControls.buttons["鉛筆"].tap()
        app.buttons["sudoku.digit.7"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["鉛筆"].isSelected)
        app.terminate()
        app.launch()
        app.buttons["game.sudoku"].tap()
        app.buttons["sudoku.continue"].tap()
        XCTAssertTrue(app.buttons["sudoku.cell.80"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["鉛筆"].isSelected)
        XCTAssertFalse(app.buttons["提示"].exists)
        XCTAssertFalse(app.buttons["答案"].exists)
    }
    func testHomeHasExactlyThreeColumns() {
        let app = XCUIApplication(); app.launch()
        let cards = ["game.sudoku", "game.minesweeper", "game.sliding"].map { app.buttons[$0] }
        for card in cards { XCTAssertTrue(card.waitForExistence(timeout: 10)) }
        XCTAssertEqual(cards[0].frame.minY, cards[1].frame.minY, accuracy: 2)
        XCTAssertEqual(cards[1].frame.minY, cards[2].frame.minY, accuracy: 2)
        XCTAssertLessThan(cards[0].frame.minX, cards[1].frame.minX)
        XCTAssertLessThan(cards[1].frame.minX, cards[2].frame.minX)
    }
    func testMinesFirstRevealAndRestoration() {
        let app = XCUIApplication(); app.launch()
        app.buttons["game.minesweeper"].tap()
        app.buttons["mines.easy"].tap()
        if app.buttons["開始新遊戲"].waitForExistence(timeout: 2) { app.buttons["開始新遊戲"].tap() }
        let first = app.buttons["mines.cell.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.press(forDuration: 0.8)
        XCTAssertTrue(first.label.contains("旗標"))
        first.tap(); XCTAssertTrue(first.label.contains("旗標")) // Tap does not reveal a flagged cell.
        first.press(forDuration: 0.8)
        first.tap(); XCTAssertTrue(first.label.contains("已揭開"))
        XCTAssertFalse(app.staticTexts["mines.lost"].exists)
        app.terminate(); app.launch()
        app.buttons["game.minesweeper"].tap(); app.buttons["mines.continue"].tap()
        XCTAssertTrue(app.buttons["mines.cell.0"].label.contains("已揭開"))
    }
    func testSlidingCanStartAndRestore() {
        let app = XCUIApplication(); app.launch()
        app.buttons["game.sliding"].tap(); app.buttons["sliding.start"].tap()
        if app.buttons["開始新遊戲"].waitForExistence(timeout: 2) { app.buttons["開始新遊戲"].tap() }
        XCTAssertTrue(app.buttons["sliding.tile.0"].waitForExistence(timeout: 5))
        let labels = (0..<9).map { app.buttons["sliding.tile.\($0)"].label }
        app.terminate(); app.launch()
        app.buttons["game.sliding"].tap(); app.buttons["sliding.continue"].tap()
        XCTAssertEqual(labels, (0..<9).map { app.buttons["sliding.tile.\($0)"].label })
    }
}
