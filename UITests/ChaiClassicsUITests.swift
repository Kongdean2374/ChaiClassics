import XCTest

final class ChaiClassicsUITests: XCTestCase {
    func testSudokuNavigationAndRestoration() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["game.sudoku"].waitForExistence(timeout: 10))
        app.buttons["game.sudoku"].tap()
        app.buttons["簡單"].tap()
        app.buttons["sudoku.easy.0001"].tap()
        XCTAssertTrue(app.buttons["sudoku.cell.0"].waitForExistence(timeout: 5))
        app.buttons["鉛筆"].tap()
        app.terminate()
        app.launch()
        app.buttons["game.sudoku"].tap()
        app.buttons["sudoku.continue"].tap()
        XCTAssertTrue(app.buttons["sudoku.cell.80"].exists)
    }
}
