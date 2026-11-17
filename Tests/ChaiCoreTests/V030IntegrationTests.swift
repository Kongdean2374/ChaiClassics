import XCTest
@testable import ChaiCore

final class V030IntegrationTests: XCTestCase {
    private func directory() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent("v030-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:value,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:value) }; return value
    }
    func testEveryNewGameHasTypedIndependentSaveSnapshotAndArchiveRoundTrip() throws {
        let directory = try directory(), store = try SaveStore(directory:directory), transfer = try GameDataTransferStore(directory:directory)
        let games = GameID.allCases.filter(\.isExpanded); XCTAssertEqual(games.count,17)
        var expected: [GameID:ExpandedGameSave] = [:]
        var metadata = GameSessionData()
        for (i,game) in games.enumerated() {
            var board = try XCTUnwrap(ExpandedGameSave(game:game,seed:UInt64(i),difficulty:.easy,mode:.localTwoPlayer)); board.elapsedSeconds = 31+i
            XCTAssertTrue(board.isValidSave,game.rawValue); XCTAssertNil(board.outcome,game.rawValue)
            XCTAssertEqual(board.state.gameID,game); XCTAssertEqual(board.snapshot.elapsedSeconds,31+i)
            expected[game] = board; try store.save(board,namespace:game.rawValue)
            metadata.sessions[game] = GameSessionState(gameID:game,difficulty:board.snapshot.difficulty,mode:board.snapshot.mode,phase:.paused,elapsedSeconds:31+i,moves:board.state.moves)
            var prefs = GamePlayPreferences(); prefs.expanded = .init(); prefs.expanded?.showGhost = i%2==0; metadata.gamePreferences[game] = prefs
        }
        try transfer.saveSessionData(metadata)
        let data = try transfer.exportArchive(preferences:.init())
        let target = try self.directory(), imported = try GameDataTransferStore(directory:target); try imported.applyArchive(data)
        let recovered = try SaveStore(directory:target)
        for game in games { XCTAssertEqual(try recovered.load(ExpandedGameSave.self,namespace:game.rawValue),expected[game]) }
        XCTAssertEqual(try imported.loadSessionData(),metadata)
        XCTAssertNil(ExpandedGameSave(game:.sudoku,seed:0)); XCTAssertNil(ExpandedGameSave(game:.memory,seed:0))
    }
    func testReleasedEightGameBackupRestoresWithoutErasingNewNamespacesOrHistory() throws {
        let catalog = try SudokuPuzzle.bundled(), directory = try directory(), transfer = try GameDataTransferStore(directory:directory)
        let board = try XCTUnwrap(ExpandedGameSave(game:.gomoku,seed:24,difficulty:.easy))
        try SaveStore(directory:directory).save(board,namespace:"gomoku")
        var metadata = GameSessionData(); metadata.sessions[.gomoku] = .init(gameID:.gomoku,difficulty:"easy",mode:"singlePlayer",phase:.paused)
        let record = GamePlayRecord(sessionID:UUID(),gameID:.chess,startedAt:Date(timeIntervalSince1970:100),finishedAt:Date(timeIntervalSince1970:120),elapsedSeconds:20,moves:4,result:.draw)
        _ = try metadata.append(record); try transfer.saveSessionData(metadata)
        let entries = GameID.allCases.filter { GameID.legacyGames.contains($0) }.map { GameArchiveEntry(gameID:$0,payload:nil) }
        let old = GameDataArchive(scope:.all,preferences:.init(),games:entries,metadata:.init())
        XCTAssertTrue(old.isValid(catalog:catalog)); try transfer.applyArchive(JSONEncoder().encode(old))
        XCTAssertEqual(try SaveStore(directory:directory).load(ExpandedGameSave.self,namespace:"gomoku"),board)
        XCTAssertEqual(try transfer.loadSessionData(),metadata)
        let truncated = GameDataArchive(scope:.all,preferences:.init(),games:Array(entries.dropLast()),metadata:.init())
        XCTAssertFalse(truncated.isValid(catalog:catalog))
    }
    func testReleasedPreferencesWithNoExpandedKeyStillDecodeAndValidate() throws {
        var value = GamePlayPreferences(); value.mazeSpeed = 1.2; value.memoryRevealSeconds = 0.9
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as? [String:Any]); object.removeValue(forKey:"expanded")
        let decoded = try JSONDecoder().decode(GamePlayPreferences.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertEqual(decoded,value); XCTAssertTrue(decoded.isValid); XCTAssertNil(decoded.expanded)
    }
    func testMismatchedGamePayloadCannotWriteAnotherGame() throws {
        let directory = try directory(), transfer = try GameDataTransferStore(directory:directory)
        let board = try XCTUnwrap(ExpandedGameSave(game:.reversi,seed:2))
        let bad = GameDataArchive(scope:.game(.chess),preferences:nil,games:[.init(gameID:.chess,payload:.expanded(board))],metadata:.init())
        XCTAssertThrowsError(try transfer.applyArchive(JSONEncoder().encode(bad)))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)
    }
    func testSolitaireUndoSurvivesReloadAndRejectsIllegalActionWithoutAddingHistory() throws {
        for variant in SolitaireVariant.allCases where variant != .freecell {
            var board = SolitaireBoard(variant:variant,seed:11), original = board
            XCTAssertTrue(board.draw()); XCTAssertTrue(board.canUndo)
            board = try JSONDecoder().decode(SolitaireBoard.self,from:JSONEncoder().encode(board)); XCTAssertTrue(board.undo())
            original = try v030Fixture(original,["moves":2]); XCTAssertEqual(board,original)
            XCTAssertFalse(board.undo()); XCTAssertFalse(board.move(from:.column(999),index:0,to:.foundation(0))); XCTAssertFalse(board.canUndo)
        }
    }
    func testExpandedSessionsUseTheSamePauseResultReviewAndRecordStateMachine() throws {
        for game in GameID.allCases where game.isExpanded {
            var data = GameSessionData(), state = GameSessionState(gameID:game)
            XCTAssertEqual(state.advance(by:1.5,expectedSessionID:state.id),1)
            XCTAssertTrue(state.pause()); XCTAssertEqual(state.advance(by:9,expectedSessionID:state.id),0); XCTAssertTrue(state.resume())
            let record = try XCTUnwrap(state.finish(result:.won,elapsedSeconds:2,moves:7)); XCTAssertTrue(try data.append(record)); XCTAssertFalse(try data.append(record))
            XCTAssertTrue(state.review()); XCTAssertTrue(state.showResult()); XCTAssertTrue(state.close())
            data.sessions[game] = state; XCTAssertTrue(data.isValid); XCTAssertEqual(data.statistics[game]?.won,1)
        }
    }
}
