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
            let window = app.frame
            let navigation = app.navigationBars.allElementsBoundByIndex.last(where: { $0.isHittable })
            let top = max(window.minY+45,navigation?.frame.maxY ?? window.minY)
            let safe = CGRect(x:window.minX+4,y:top,width:window.width-8,height:window.maxY-24-top)
            if element.exists, element.isHittable, safe.contains(CGPoint(x:element.frame.midX,y:element.frame.midY)) { return }
            let game = element.exists ? element.identifier.split(separator:".").first.map(String.init) ?? "" : ""
            let board = app.scrollViews.matching(identifier:game+".zoomBoard").firstMatch
            let origin = app.coordinate(withNormalizedOffset:.zero)
            if element.exists, board.exists {
                let viewport = board.frame.intersection(safe).insetBy(dx:10,dy:10), target = element.frame
                if !viewport.isNull, viewport.width>50, viewport.height>50,
                   !viewport.contains(CGPoint(x:target.midX,y:target.midY)) {
                    var dx: CGFloat = 0, dy: CGFloat = 0
                    if target.midX<viewport.minX { dx = min(viewport.width*0.55,viewport.minX-target.midX+20) }
                    if target.midX>viewport.maxX { dx = -min(viewport.width*0.55,target.midX-viewport.maxX+20) }
                    if target.midY<viewport.minY { dy = min(viewport.height*0.4,viewport.minY-target.midY+20) }
                    if target.midY>viewport.maxY { dy = -min(viewport.height*0.4,target.midY-viewport.maxY+20) }
                    let start = CGPoint(x:dx<0 ? viewport.maxX-10 : dx>0 ? viewport.minX+10 : viewport.midX,
                                        y:dy<0 ? viewport.maxY-10 : dy>0 ? viewport.minY+10 : viewport.midY)
                    origin.withOffset(CGVector(dx:start.x-window.minX,dy:start.y-window.minY)).press(forDuration:0.1,
                        thenDragTo:origin.withOffset(CGVector(dx:start.x+dx-window.minX,dy:start.y+dy-window.minY)),withVelocity:.slow,thenHoldForDuration:0.1)
                    continue
                }
            }
            // Form virtualizes rows: a below-screen History link need not
            // exist in the snapshot until its actual list has been scrolled.
            let lists = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
            let list = lists.last(where: { $0.isHittable })
            let outer = app.scrollViews.allElementsBoundByIndex
                .filter { !$0.identifier.hasSuffix(".zoomBoard") && $0.isHittable }
                .max(by: { $0.frame.height<$1.frame.height })
            // A presented settings Form can coexist with its background menu.
            // Use the foreground scroll container's real bounds, including an
            // iPad's centered content or a constrained layout-test viewport.
            let container = list?.frame ?? outer?.frame ?? safe
            let viewport = container.intersection(safe)
            guard !viewport.isNull, viewport.height>90 else { break }
            let down = element.exists ? element.frame.midY<viewport.minY : attempt>=9
            var distance = viewport.height*0.3
            if element.exists {
                let overhang = down ? viewport.minY-element.frame.minY : element.frame.maxY-viewport.maxY
                distance = min(distance,max(28,overhang+12))
            }
            let x = max(window.minX+5,container.minX+5), startY = down ? viewport.minY+30 : viewport.maxY-30
            origin.withOffset(CGVector(dx:x-window.minX,dy:startY-window.minY)).press(forDuration:0.1,
                thenDragTo:origin.withOffset(CGVector(dx:x-window.minX,dy:startY+(down ? distance : -distance)-window.minY)),
                withVelocity:.slow,thenHoldForDuration:0.1)
        }
        let identifier = element.exists ? element.identifier : "missing-control"
        attachUIEvidence(app,name:"v030-unreachable-"+identifier)
        XCTFail("Control is not visible and actionable: "+identifier)
    }
    private func tap(_ id: String,_ app: XCUIApplication,double: Bool = false) {
        var button = app.buttons.matching(identifier:id).firstMatch
        // A promotion confirmation can export a native UIAction label instead
        // of its SwiftUI identifier. Both paths select the same real action.
        if id=="shogi.promotion.1", !button.waitForExistence(timeout:2) { button = app.buttons["Promote"].firstMatch }
        reach(button,app)
        XCTAssertTrue(button.waitForExistence(timeout:5),"Missing button: "+id)
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
        reach(legal,app)
        XCTAssertTrue(app.scrollViews["reversi.zoomBoard"].frame.contains(occupied.frame))
        occupied.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
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
