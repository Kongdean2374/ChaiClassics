import XCTest
import UIKit

/// Each method drives a real game, native dialogs, process relaunch, results,
/// history and confirmed progress deletion. The same cases run on phone/iPad.
final class ChaiClassicsV030UITests: XCTestCase {
    private let boardGames: Set<String> = ["gomoku","reversi","xiangqi","banqi","chess","shogi"]
    private let solitaire: Set<String> = ["klondike","spider","freecell","pyramid","tripeaks"]
    override func setUpWithError() throws {
        continueAfterFailure = false; executionTimeAllowance = 600
        XCUIDevice.shared.orientation = .portrait
    }
    private func node(_ id: String,_ app: XCUIApplication) -> XCUIElement { app.descendants(matching:.any).matching(identifier:id).firstMatch }
    private func wait(_ message: String,timeout: TimeInterval = 15,_ condition: @escaping ()->Bool) {
        let expectation = XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in condition()},object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:timeout),.completed,message)
    }
    private func reach(_ element: XCUIElement,_ app: XCUIApplication) {
        for attempt in 0..<18 {
            let safe = app.frame.insetBy(dx:0,dy:45)
            if element.exists, element.isHittable, safe.contains(CGPoint(x:element.frame.midX,y:element.frame.midY)) { return }
            let origin = app.coordinate(withNormalizedOffset:.zero)
            let low = origin.withOffset(CGVector(dx:3,dy:app.frame.maxY-95))
            let high = origin.withOffset(CGVector(dx:3,dy:max(190,app.navigationBars.firstMatch.frame.maxY+70)))
            let down = element.exists ? element.frame.midY<high.screenPoint.y : attempt>=9
            if down { high.press(forDuration:0.05,thenDragTo:low) } else { low.press(forDuration:0.05,thenDragTo:high) }
        }
        attach(app,"unreachable-"+element.identifier); XCTFail("Control is not visible and actionable: "+element.identifier)
    }
    private func tap(_ id: String,_ app: XCUIApplication,double: Bool = false) {
        var button = app.buttons.matching(identifier:id).firstMatch
        // A promotion confirmation can export a native UIAction label instead
        // of its SwiftUI identifier. Both paths select the same real action.
        if id=="shogi.promotion.1", !button.waitForExistence(timeout:2) { button = app.buttons["Promote"].firstMatch }
        XCTAssertTrue(button.waitForExistence(timeout:20),"Missing button: "+id)
        reach(button,app)
        wait("Button never became enabled: "+id,timeout:15) { button.exists && button.isEnabled }
        if double { button.doubleTap() } else { button.tap() }
    }
    private func open(_ game: String,_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout:15))
        if boardGames.contains(game) { tap("catalog.boardgames",app) }
        if solitaire.contains(game) { tap("catalog.solitaire",app) }
        tap("game."+game,app)
        XCTAssertTrue(app.buttons[game+".menu.settings"].waitForExistence(timeout:15))
    }
    private func attach(_ app: XCUIApplication,_ stage: String) {
        let image = XCTAttachment(screenshot:app.screenshot()); image.name = "v030-"+stage; image.lifetime = .keepAlways; add(image)
    }
    private func requestDeletion(_ game: String,_ app: XCUIApplication) {
        let current = app.buttons[game+".continue"]; reach(current,app); current.swipeLeft()
        XCTAssertFalse(app.buttons[game+".session.pause"].exists,"A swipe must not activate Continue.")
        var action = app.buttons[game+".continue.delete"].firstMatch
        if !action.waitForExistence(timeout:2) { action = app.buttons["Delete progress"].firstMatch }
        XCTAssertTrue(action.waitForExistence(timeout:10)); XCTAssertTrue(action.isHittable); action.tap()
        XCTAssertTrue(app.buttons[game+".delete.confirm"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons[game+".delete.cancel"].isEnabled)
    }
    private func cancelDeletion(_ game: String,_ app: XCUIApplication) {
        let current = app.buttons[game+".continue"], original = current.label
        current.swipeRight(); XCTAssertTrue(current.exists); XCTAssertFalse(app.buttons[game+".session.pause"].exists)
        requestDeletion(game,app)
        tap(game+".delete.cancel",app,double:true)
        wait("Cancel must dismiss the real confirmation") { !app.buttons[game+".delete.confirm"].exists }
        XCTAssertTrue(current.exists); XCTAssertEqual(current.label,original)
        app.terminate(); app.launch(); open(game,app)
        XCTAssertTrue(current.waitForExistence(timeout:10)); XCTAssertEqual(current.label,original,"Cancelled deletion must retain the real disk save.")
    }
    private func records(_ game: String,_ app: XCUIApplication,expected: Int) {
        tap(game+".menu.settings",app); tap("gameSettings.history",app)
        let rows = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'history.record.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout:15)); XCTAssertEqual(rows.count,expected)
        attach(app,game+"-history")
        app.terminate(); app.launch(); open(game,app)
    }
    private func exercise(_ game: String) throws {
        let resource = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"v030-"+game,withExtension:"json"))
        let data = try Data(contentsOf:resource)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        let plan = try XCTUnwrap(json["testPlan"] as? [String:Any]), actions = try XCTUnwrap(plan["actions"] as? [String])
        let app = XCUIApplication()
        let arguments = ["--ui-testing","--ui-profile","v030-"+game,"--ui-language","en","--ui-appearance","dark"]
        app.launchArguments = arguments+["--ui-reset"]; app.launchEnvironment["CHAI_UI_SEED_"+game.uppercased()] = data.base64EncodedString()
        app.launch(); app.launchArguments = arguments; app.launchEnvironment["CHAI_UI_SEED_"+game.uppercased()] = nil
        open(game,app)
        try XCTContext.runActivity(named:"Swipe and cancelled deletion preserve progress after process restart") { _ in
            cancelDeletion(game,app)
        }
        tap(game+".continue",app)
        XCTAssertTrue(app.buttons[game+".session.resume"].waitForExistence(timeout:15))
        XCTAssertEqual(node(game+".session.paused.elapsed",app).value as? String,"0:00:12")
        tap(game+".session.exit",app,double:true)
        XCTAssertTrue(app.buttons[game+".continue"].waitForExistence(timeout:15))
        app.terminate(); app.launch(); open(game,app); tap(game+".continue",app)
        XCTAssertTrue(app.buttons[game+".session.resume"].waitForExistence(timeout:15))
        XCTAssertEqual(node(game+".session.paused.elapsed",app).value as? String,"0:00:12")
        tap(game+".session.resume",app,double:true)
        wait("Resume must dismiss the pause overlay") { !app.buttons[game+".session.resume"].exists }
        attach(app,game+"-restored-board")
        for action in actions { tap(action,app) }
        let result = node(game+".session.result",app)
        XCTAssertTrue(result.waitForExistence(timeout:20),"Real engine operations must reach a result.")
        XCTAssertNotNil(node(game+".session.result.moves",app).value as? String)
        XCTAssertTrue(app.buttons[game+".session.done"].isEnabled); XCTAssertTrue(app.buttons[game+".session.review"].isEnabled)
        attach(app,game+"-result")
        tap(game+".session.review",app)
        wait("Review must hide the result") { !result.exists }
        attach(app,game+"-board-review")
        app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        XCTAssertTrue(result.waitForExistence(timeout:10)); tap(game+".session.done",app,double:true)
        XCTAssertTrue(app.buttons[game+".continue"].waitForExistence(timeout:15))
        records(game,app,expected:1)
        let preserved = app.buttons[game+".continue"].label
        tap(game+".start",app)
        XCTAssertTrue(app.buttons[game+".new.cancel"].waitForExistence(timeout:45)); tap(game+".new.cancel",app,double:true)
        wait("Cancel must dismiss new-game confirmation") { !app.buttons[game+".new.cancel"].exists }
        XCTAssertEqual(app.buttons[game+".continue"].label,preserved,"Cancelled new game must not overwrite a finished board.")
        tap(game+".start",app); XCTAssertTrue(app.buttons[game+".new.confirm"].waitForExistence(timeout:45))
        tap(game+".new.confirm",app,double:true)
        XCTAssertTrue(app.buttons[game+".session.pause"].waitForExistence(timeout:20))
        attach(app,game+"-fresh-board")
        if boardGames.contains(game) {
            let opening: [String:[Int]] = ["gomoku":[112],"reversi":[19],"chess":[52,36],"xiangqi":[54,45],"shogi":[54,45],"banqi":[0]]
            for cell in try XCTUnwrap(opening[game]) { tap(game+".cell.\(cell)",app) }
            wait("The real offline computer must complete its reply",timeout:35) {
                (Int(self.node(game+".moves",app).value as? String ?? "") ?? 0)>=2
            }
            XCTAssertFalse(node(game+".session.result",app).exists)
            attach(app,game+"-computer-reply")
        }
        tap(game+".session.pause",app); XCTAssertTrue(app.buttons[game+".session.exit"].waitForExistence(timeout:10))
        tap(game+".session.exit",app)
        XCTAssertTrue(app.buttons[game+".continue"].waitForExistence(timeout:15))
        cancelDeletion(game,app)
        requestDeletion(game,app); tap(game+".delete.confirm",app,double:true)
        wait("Only confirmed deletion may remove Continue") { !app.buttons[game+".continue"].exists }
        app.terminate(); app.launch(); open(game,app)
        XCTAssertFalse(app.buttons[game+".continue"].exists,"Deleted progress must not return from a seed or backup.")
        records(game,app,expected:2) // The real result plus one abandoned new round.
    }
    func testNonogramCompleteSessionRestoresAndConfirmsDeletion() throws { try exercise("nonogram") }
    func testKakuroCompleteSessionRestoresAndConfirmsDeletion() throws { try exercise("kakuro") }
    func testKlotskiCompleteSessionRestoresAndConfirmsDeletion() throws { try exercise("klotski") }
    func testGomokuCompleteSessionRestoresAndConfirmsDeletion() throws { try exercise("gomoku") }
    func testReversiCompleteSessionRestoresAndConfirmsDeletion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--ui-profile","v030-reversi","--ui-reset","--ui-language","en","--ui-appearance","dark"]
        app.launch(); open("reversi",app); tap("reversi.start",app); tap("reversi.new.confirm",app)
        let legal = app.buttons["reversi.cell.19"], occupied = app.buttons["reversi.cell.27"]
        wait("Black must initially have a legal opening") { legal.exists && legal.isEnabled }
        XCTAssertFalse(occupied.isEnabled,"An occupied Reversi disc is not a selectable chess piece.")
        reach(occupied,app); occupied.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        XCTAssertTrue(legal.isEnabled,"An ignored occupied-disc tap must not hide legal destinations.")
        XCTAssertEqual(node("reversi.moves",app).value as? String,"0")
        tap("reversi.cell.19",app)
        wait("A legal move must still work after tapping an occupied disc",timeout:35) {
            (Int(self.node("reversi.moves",app).value as? String ?? "") ?? 0)>=2
        }
        attach(app,"reversi-occupied-disc-regression"); app.terminate()
        try exercise("reversi")
    }
    func testXiangqiCompleteSessionRestoresAndConfirmsDeletion() throws { try exercise("xiangqi") }
    func testBanqiCompleteSessionRestoresAndConfirmsDeletion() throws {
        // Mirror a valid position so player one owns Black. This checks the
        // assignment after restoration without depending on a random reveal.
        let resource = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"v030-banqi",withExtension:"json"))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:resource)) as? [String:Any])
        var payload = try XCTUnwrap(envelope["payload"] as? [String:Any])
        var state = try XCTUnwrap(payload["state"] as? [String:Any]), associated = try XCTUnwrap(state["banqi"] as? [String:Any])
        var board = try XCTUnwrap(associated["_0"] as? [String:Any])
        board["pieces"] = try XCTUnwrap(board["pieces"] as? [Int]).map { -$0 }
        board["firstPlayerColor"] = -1; board["moves"] = 62
        associated["_0"] = board; state["banqi"] = associated; payload["state"] = state; envelope["payload"] = payload
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--ui-profile","v030-banqi","--ui-reset","--ui-language","en","--ui-appearance","dark"]
        app.launchEnvironment["CHAI_UI_SEED_BANQI"] = try JSONSerialization.data(withJSONObject:envelope).base64EncodedString()
        app.launch(); app.launchEnvironment["CHAI_UI_SEED_BANQI"] = nil
        open("banqi",app); tap("banqi.continue",app); tap("banqi.session.resume",app)
        wait("The restored player-one assignment must visibly identify Black") {
            self.node("banqi.turn",app).label.unicodeScalars.contains { $0.value==0x26AB }
        }
        XCTAssertTrue(app.buttons["banqi.cell.0"].label.unicodeScalars.contains { $0.value==0x26AB })
        attach(app,"banqi-black-first-orientation")
        tap("banqi.cell.0",app); tap("banqi.cell.1",app)
        XCTAssertTrue(app.buttons["banqi.session.done"].waitForExistence(timeout:15)); app.terminate()
        try exercise("banqi")
    }
    func testChessCompleteSessionRestoresAndConfirmsDeletion() throws { try exercise("chess") }
    func testShogiCompleteSessionRestoresAndConfirmsDeletion() throws { try exercise("shogi") }
    func testKlondikeCompleteSessionRestoresAndConfirmsDeletion() throws { try exercise("klondike") }
    func testSpiderCompleteSessionRestoresAndConfirmsDeletion() throws { try exercise("spider") }
    func testFreecellCompleteSessionRestoresAndConfirmsDeletion() throws { try exercise("freecell") }
    func testPyramidCompleteSessionRestoresAndConfirmsDeletion() throws { try exercise("pyramid") }
    func testTripeaksCompleteSessionRestoresAndConfirmsDeletion() throws { try exercise("tripeaks") }
    func testSnakeCompleteSessionRestoresAndConfirmsDeletion() throws { try exercise("snake") }
    func testFallingBlocksCompleteSessionRestoresAndConfirmsDeletion() throws { try exercise("fallingblocks") }
    func testBrickBreakerCompleteSessionRestoresAndConfirmsDeletion() throws { try exercise("brickbreaker") }
}
