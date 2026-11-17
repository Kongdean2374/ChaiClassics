import XCTest
@testable import ChaiCore

final class V030FixtureTests: XCTestCase {
    func testAllSeventeenFrozenUIFixturesDecodeAsValidIndependentRunningSaves() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("v030-frozen-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let store = try SaveStore(directory:folder)
        for game in GameID.allCases where game.isExpanded {
            let url = try XCTUnwrap(Bundle.module.url(forResource:"v030-"+game.rawValue,withExtension:"json",subdirectory:"Fixtures"))
            let data = try Data(contentsOf:url), json = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
            let plan = try XCTUnwrap(json["testPlan"] as? [String:Any])
            XCTAssertEqual(json["schemaVersion"] as? Int,1); XCTAssertEqual(plan["game"] as? String,game.rawValue)
            XCTAssertNotNil(plan["actions"] as? [String]); XCTAssertTrue(["won","lost","completed"].contains(plan["outcome"] as? String ?? ""))
            try data.write(to:folder.appendingPathComponent(game.rawValue+".json"))
            let board = try XCTUnwrap(store.load(ExpandedGameSave.self,namespace:game.rawValue))
            XCTAssertEqual(board.gameID,game); XCTAssertTrue(board.isValidSave,game.rawValue)
            XCTAssertNil(board.outcome,game.rawValue); XCTAssertEqual(board.elapsedSeconds,12)
        }
        let transfer = try GameDataTransferStore(directory:folder)
        let archive = try transfer.validateArchive(transfer.exportArchive(preferences:.init()))
        XCTAssertEqual(archive.games.compactMap(\.payload).count,17)
    }
    func testEnteringKingDeclarationRequiresEnemyCampTenPiecesPointsAndNoCheck() throws {
        let original = ShogiBoard(); XCTAssertFalse(original.canDeclareEnteringKing)
        var cells = Array(repeating:0,count:81); cells[4] = 8; cells[76] = -8
        for i in [0,1,2,3,5,6,7,8,9,10] { cells[i] = 9 }
        var hands = [[0,8,4,4,4,4,2,2],Array(repeating:0,count:8)]
        var board = try v030Fixture(original,["cells":cells,"hands":hands]); XCTAssertTrue(board.isValidSave); XCTAssertTrue(board.canDeclareEnteringKing)
        XCTAssertTrue(board.declareEnteringKing()); XCTAssertEqual(board.result,.won(.first)); XCTAssertFalse(board.declareEnteringKing())
        cells[22] = -7; hands[0][7] = 1
        let checked = try v030Fixture(original,["cells":cells,"hands":hands]); XCTAssertTrue(checked.isValidSave)
        XCTAssertTrue(checked.isInCheck(.first)); XCTAssertFalse(checked.canDeclareEnteringKing)
        cells[22] = 0; hands[0][7] = 2; cells[10] = 0; hands[0][1] += 1
        let short = try v030Fixture(original,["cells":cells,"hands":hands]); XCTAssertTrue(short.isValidSave); XCTAssertFalse(short.canDeclareEnteringKing)
    }
}
