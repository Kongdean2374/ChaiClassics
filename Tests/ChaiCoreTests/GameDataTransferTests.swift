import XCTest
@testable import ChaiCore

final class GameDataTransferTests: XCTestCase {
    private struct InjectedFailure: Error {}
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("game-transfer-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func bytes(_ directory: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            result[file.lastPathComponent] = try Data(contentsOf: file)
        }
        return result
    }
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "v010-" + name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
    private func seedAll(_ directory: URL) throws {
        for name in ["sudoku", "minesweeper", "sliding"] {
            try fixture(name).write(to: directory.appendingPathComponent(name + ".json"))
        }
        let saves = try SaveStore(directory: directory)
        try saves.save(TicTacToeBoard(seed: 1), namespace: "tictactoe")
        try saves.save(ConnectFourBoard(seed: 2), namespace: "connectfour")
        try saves.save(TwentyFourBoard(seed: 3), namespace: "twentyfour")
        try saves.save(MemoryBoard(seed: 4), namespace: "memory")
        try saves.save(MazeBoard(difficulty: .easy, seed: 5), namespace: "maze")
        for game in GameID.allCases where game.isExpanded {
            try saves.save(try XCTUnwrap(ExpandedGameSave(game:game,seed:6,difficulty:.easy)),namespace:game.rawValue)
        }
    }
    private func edit(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    func testExportAndValidationNeverRewriteReleasedSchemaOneBytes() throws {
        let folder = try directory(); try seedAll(folder)
        let before = try bytes(folder)
        let store = try GameDataTransferStore(directory: folder)
        let archive = try store.validateArchive(store.exportArchive(preferences: AppPreferences()))
        XCTAssertEqual(archive.games.count, 25)
        XCTAssertEqual(Set(archive.games.map(\.gameID)), Set(GameID.allCases))
        XCTAssertTrue(archive.metadata.records.isEmpty)
        XCTAssertEqual(try bytes(folder), before)
        XCTAssertEqual(archive.games.first { $0.gameID == .sudoku }?.payload,
                       .sudoku(try XCTUnwrap(SaveStore(directory: folder).load(SudokuProgress.self, namespace: "sudoku"))))
    }

    func testGlobalImportRestoresAllEightTypedSavesPreferencesAndMetadata() throws {
        let source = try directory(); try seedAll(source)
        let sourceStore = try GameDataTransferStore(directory: source)
        var preferences = AppPreferences(); preferences.language = .english; preferences.appearance = .dark
        var metadata = GameSessionData(); var gamePreferences = GamePlayPreferences(); gamePreferences.haptics = false
        metadata.gamePreferences[.memory] = gamePreferences
        try sourceStore.saveSessionData(metadata)
        let data = try sourceStore.exportArchive(preferences: preferences)
        let target = try directory(), targetStore = try GameDataTransferStore(directory: target)
        let result = try targetStore.applyArchive(data)
        XCTAssertEqual(result.preferences, preferences)
        XCTAssertEqual(try targetStore.loadImportedPreferences(), preferences)
        XCTAssertEqual(try targetStore.loadSessionData(), metadata)
        let copied = try targetStore.validateArchive(targetStore.exportArchive(preferences: preferences))
        XCTAssertEqual(copied.games, try sourceStore.validateArchive(data).games)
        for game in GameID.allCases {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: target.appendingPathComponent(game.rawValue + ".json"))) as? [String: Any])
            XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        }
    }

    func testPerGameImportCannotChangeOtherSevenGamesOrGlobalPreferences() throws {
        let source = try directory(); try seedAll(source)
        let sourceStore = try GameDataTransferStore(directory: source)
        let archive = try sourceStore.exportArchive(scope: .game(.memory), preferences: AppPreferences())
        let target = try directory(); try seedAll(target)
        let store = try GameDataTransferStore(directory: target)
        var preferences = AppPreferences(); preferences.appearance = .dark
        try store.saveImportedPreferences(preferences)
        let before = try bytes(target)
        let result = try store.applyArchive(archive)
        XCTAssertNil(result.preferences)
        XCTAssertEqual(try store.loadImportedPreferences(), preferences)
        for game in GameID.allCases where game != .memory {
            XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent(game.rawValue + ".json")), before[game.rawValue + ".json"])
        }
    }

    func testMaliciousFutureDuplicateUnknownGameAndInvalidTypedPayloadRejectBeforeAnyWrite() throws {
        let folder = try directory(); try seedAll(folder)
        let store = try GameDataTransferStore(directory: folder)
        let valid = try store.exportArchive(preferences: AppPreferences())
        let before = try bytes(folder)
        var variants = [try edit(valid) { $0["version"] = 99 },
                        try edit(valid) { var games = $0["games"] as! [[String: Any]]; games[0] = games[1]; $0["games"] = games },
                        try edit(valid) { var games = $0["games"] as! [[String: Any]]; games[0]["gameID"] = "../other-app"; $0["games"] = games }]
        variants.append(try edit(valid) { object in
            var games = object["games"] as! [[String: Any]]
            let index = games.firstIndex { $0["gameID"] as? String == "minesweeper" }!
            var payload = games[index]["payload"] as! [String: Any]
            var associated = payload["minesweeper"] as! [String: Any]
            var board = associated["_0"] as! [String: Any]
            board["elapsedSeconds"] = -1
            associated["_0"] = board; payload["minesweeper"] = associated
            games[index]["payload"] = payload; object["games"] = games
        })
        let invalidBoard = MinesweeperBoard(configuration: .easy, seed: 1)
        let invalidArchive = GameDataArchive(scope: .game(.sliding), preferences: nil,
                                            games: [GameArchiveEntry(gameID: .sliding, payload: .minesweeper(invalidBoard))], metadata: GameSessionData())
        variants.append(try JSONEncoder().encode(invalidArchive))
        for data in variants {
            XCTAssertThrowsError(try store.applyArchive(data))
            XCTAssertEqual(try bytes(folder), before)
        }
    }

    func testOversizedAndMalformedArchiveRejectWithoutWrites() throws {
        let folder = try directory(), store = try GameDataTransferStore(directory: folder)
        XCTAssertThrowsError(try store.applyArchive(Data(repeating: 32, count: GameDataTransferStore.maximumArchiveBytes + 1)))
        XCTAssertThrowsError(try store.applyArchive(Data("invalid".utf8)))
        XCTAssertTrue(try bytes(folder).isEmpty)
    }

    func testRecordedResultCannotClaimCompletionForAnUnfinishedBoard() throws {
        let folder = try directory(), store = try GameDataTransferStore(directory: folder)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var state = GameSessionState(gameID: .memory, startedAt: date, difficulty: "easy")
        let record = try XCTUnwrap(state.finish(result: .completed, elapsedSeconds: 0, moves: 0, at: date.addingTimeInterval(2)))
        var metadata = GameSessionData(); try metadata.append(record); metadata.sessions[.memory] = state
        XCTAssertTrue(metadata.isValid)
        let archive = GameDataArchive(scope: .game(.memory), preferences: nil,
                                      games: [GameArchiveEntry(gameID: .memory, payload: .memory(MemoryBoard(seed: 7)))], metadata: metadata)
        XCTAssertThrowsError(try store.applyArchive(JSONEncoder().encode(archive)))
        XCTAssertTrue(try bytes(folder).isEmpty)
    }

    func testFinishedBoardOutcomeMetricsMustMatchWhileActiveCrashClockGapIsAllowed() throws {
        let folder = try directory(), store = try GameDataTransferStore(directory: folder)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var board = TicTacToeBoard(mode: .localTwoPlayer, seed: 1)
        for index in [0, 3, 1, 4, 2] { XCTAssertTrue(board.play(at: index, by: board.currentPlayer)) }
        board.elapsedSeconds = 8
        for (outcome, elapsed, accepted) in [(GameOutcome.won, 8, true), (.lost, 8, false), (.won, 9, false)] {
            var state = GameSessionState(gameID: .ticTacToe, startedAt: date, difficulty: "normal", mode: "localTwoPlayer")
            let record = try XCTUnwrap(state.finish(result: outcome, elapsedSeconds: elapsed, moves: 5, at: date.addingTimeInterval(10)))
            var metadata = GameSessionData(); try metadata.append(record); metadata.sessions[.ticTacToe] = state
            let archive = GameDataArchive(scope: .game(.ticTacToe), preferences: nil,
                                          games: [GameArchiveEntry(gameID: .ticTacToe, payload: .ticTacToe(board))], metadata: metadata)
            let encoded = try JSONEncoder().encode(archive)
            if accepted { XCTAssertNoThrow(try store.validateArchive(encoded)) }
            else { XCTAssertThrowsError(try store.validateArchive(encoded)) }
        }
        var active = GameSessionData()
        active.sessions[.memory] = GameSessionState(gameID: .memory, startedAt: date, phase: .paused, elapsedSeconds: 20)
        let archive = GameDataArchive(scope: .game(.memory), preferences: nil,
                                      games: [GameArchiveEntry(gameID: .memory, payload: .memory(MemoryBoard(seed: 7)))], metadata: active)
        XCTAssertNoThrow(try store.validateArchive(JSONEncoder().encode(archive)))
    }

    func testTransactionFailureRollsBackEveryPrimaryBackupPreferencesAndMetadataByte() throws {
        let folder = try directory(); try seedAll(folder)
        let store = try GameDataTransferStore(directory: folder)
        try store.saveSessionData(GameSessionData()); try store.saveImportedPreferences(AppPreferences())
        let valid = try store.exportArchive(preferences: AppPreferences())
        for game in GameID.allCases {
            let primary = folder.appendingPathComponent(game.rawValue + ".json")
            try Data(contentsOf: primary).write(to: primary.appendingPathExtension("backup"))
        }
        let before = try bytes(folder)
        var operations = 0
        store.beforeTransactionWrite = { _ in operations += 1; if operations == 5 { throw InjectedFailure() } }
        XCTAssertThrowsError(try store.applyArchive(valid))
        XCTAssertGreaterThan(operations, 1)
        XCTAssertEqual(try bytes(folder), before)
        store.beforeTransactionWrite = nil
        XCTAssertNoThrow(try store.applyArchive(valid))
    }

    func testInterruptedApplyingJournalRestoresOriginalsBeforeAnyLoad() throws {
        let folder = try directory(); try seedAll(folder)
        let before = try bytes(folder)
        let original = try XCTUnwrap(before["sliding.json"])
        let journal: [String: Any] = ["version": 1, "committed": false,
                                     "originals": [["name": "sliding.json", "original": original.base64EncodedString()],
                                                   ["name": "memory.json.backup"]]]
        try JSONSerialization.data(withJSONObject: journal).write(to: folder.appendingPathComponent(GameDataTransferStore.journalName))
        try Data("interrupted".utf8).write(to: folder.appendingPathComponent("sliding.json"))
        try Data("new backup".utf8).write(to: folder.appendingPathComponent("memory.json.backup"))
        _ = try GameDataTransferStore(directory: folder)
        XCTAssertEqual(try bytes(folder), before)
    }

    func testCommittedJournalKeepsCompleteNewStateAndMaliciousJournalCannotEscapeDirectory() throws {
        let folder = try directory()
        let marker = Data("new committed state".utf8)
        try marker.write(to: folder.appendingPathComponent("memory.json"))
        let journal: [String: Any] = ["version": 1, "committed": true, "originals": [["name": "memory.json"]]]
        let journalURL = folder.appendingPathComponent(GameDataTransferStore.journalName)
        try JSONSerialization.data(withJSONObject: journal).write(to: journalURL)
        _ = try GameDataTransferStore(directory: folder)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("memory.json")), marker)
        let invalid: [String: Any] = ["version": 1, "committed": false, "originals": [["name": "../escape.json"]]]
        try JSONSerialization.data(withJSONObject: invalid).write(to: journalURL)
        XCTAssertThrowsError(try GameDataTransferStore(directory: folder))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("memory.json")), marker)
    }

    func testClearGameRemovesPrimaryBackupCorruptAndCannotResurrectOnRestart() throws {
        let folder = try directory(); try seedAll(folder)
        let primary = folder.appendingPathComponent("memory.json")
        try Data(contentsOf: primary).write(to: primary.appendingPathExtension("backup"))
        try Data("old bad bytes".utf8).write(to: primary.appendingPathExtension("corrupt"))
        let beforeSliding = try Data(contentsOf: folder.appendingPathComponent("sliding.json"))
        let store = try GameDataTransferStore(directory: folder)
        try store.removeGame(.memory)
        XCTAssertNil(try SaveStore(directory: folder).load(MemoryBoard.self, namespace: "memory"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: primary.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: primary.appendingPathExtension("backup").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: primary.appendingPathExtension("corrupt").path))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("sliding.json")), beforeSliding)
    }

    func testFutureSavePrimaryOrBackupCannotBeOverwrittenByImportOrClear() throws {
        let folder = try directory(); try seedAll(folder)
        let store = try GameDataTransferStore(directory: folder)
        let archive = try store.exportArchive(preferences: AppPreferences())
        for suffix in [".json", ".json.backup"] {
            let path = folder.appendingPathComponent("memory" + suffix)
            let original = try? Data(contentsOf: path)
            try Data(#"{"schemaVersion":99,"payload":{}}"#.utf8).write(to: path)
            let before = try bytes(folder)
            XCTAssertThrowsError(try store.applyArchive(archive))
            XCTAssertThrowsError(try store.removeGame(.memory))
            XCTAssertEqual(try bytes(folder), before)
            if let original { try original.write(to: path) } else { try FileManager.default.removeItem(at: path) }
        }
    }

    func testReplaceGameCommitsAbandonmentAndDeletionTogetherOrRollsBackBoth() throws {
        let folder = try directory(); try seedAll(folder)
        let store = try GameDataTransferStore(directory: folder)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var active = GameSessionState(gameID: .memory, startedAt: date)
        var metadata = GameSessionData(); metadata.sessions[.memory] = active
        try store.saveSessionData(metadata)
        let before = try bytes(folder)
        let record = try XCTUnwrap(active.finish(result: .abandoned, elapsedSeconds: 2, moves: 1, at: date.addingTimeInterval(4)))
        try metadata.append(record); metadata.sessions[.memory] = active
        store.beforeTransactionWrite = { name in if name == "sessions-v1.json" { throw InjectedFailure() } }
        XCTAssertThrowsError(try store.replaceGame(.memory, payload: nil, metadata: metadata))
        XCTAssertEqual(try bytes(folder), before)
        XCTAssertTrue(try store.loadSessionData().records.isEmpty)
        store.beforeTransactionWrite = nil
        let result = try store.replaceGame(.memory, payload: nil, metadata: metadata)
        XCTAssertEqual(result.metadata.records, [record])
        XCTAssertNil(result.metadata.sessions[.memory])
        XCTAssertNil(try SaveStore(directory: folder).load(MemoryBoard.self, namespace: "memory"))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("sliding.json")), before["sliding.json"])
    }

    func testMetadataBackupRecoveryPreservesDamagedEvidenceAndKnownGoodBackup() throws {
        let folder = try directory(), store = try GameDataTransferStore(directory: folder)
        try store.saveSessionData(GameSessionData())
        let primary = folder.appendingPathComponent("sessions-v1.json")
        let good = try Data(contentsOf: primary)
        try good.write(to: primary.appendingPathExtension("backup"))
        let corrupt = Data("damaged metadata".utf8)
        try corrupt.write(to: primary)
        XCTAssertTrue(try store.loadSessionData().isValid)
        XCTAssertEqual(try Data(contentsOf: primary), good)
        XCTAssertEqual(try Data(contentsOf: primary.appendingPathExtension("corrupt")), corrupt)
        try store.saveSessionData(GameSessionData())
        XCTAssertEqual(try Data(contentsOf: primary.appendingPathExtension("backup")), good)
    }

    func testSudokuArchiveKeepsEveryParkedPuzzleAndRejectsMissingBoardLinkage() throws {
        let catalog = try SudokuPuzzle.bundled()
        let first = catalog[0], second = catalog[1]
        var progress = SudokuProgress()
        progress.record(SudokuBoard(puzzle: first), puzzle: first)
        progress.record(SudokuBoard(puzzle: second), puzzle: second)
        var metadata = GameSessionData()
        metadata.sessions[.sudoku] = GameSessionState(gameID: .sudoku, difficulty: first.difficulty.rawValue,
                                                     mode: first.id, elapsedSeconds: 15, elapsedFraction: 0.25, moves: 3)
        XCTAssertTrue(metadata.parkSudokuSession())
        metadata.sessions[.sudoku] = GameSessionState(gameID: .sudoku, difficulty: second.difficulty.rawValue,
                                                     mode: second.id, phase: .paused, elapsedSeconds: 7, moves: 2)
        let folder = try directory(), store = try GameDataTransferStore(directory: folder)
        let result = try store.replaceGame(.sudoku, payload: .sudoku(progress), metadata: metadata)
        XCTAssertEqual(result.metadata.sudokuSessions[first.id]?.elapsedSeconds, 15)
        XCTAssertEqual(result.metadata.sudokuSessions[first.id]?.moves, 3)
        let archive = try store.exportArchive(scope: .game(.sudoku), preferences: AppPreferences())
        XCTAssertEqual(try store.validateArchive(archive).metadata, metadata)
        var missing = progress; missing.boards[first.id] = nil
        let invalid = GameDataArchive(scope: .game(.sudoku), preferences: nil,
                                      games: [GameArchiveEntry(gameID: .sudoku, payload: .sudoku(missing))], metadata: metadata)
        let before = try bytes(folder)
        XCTAssertThrowsError(try store.applyArchive(JSONEncoder().encode(invalid)))
        XCTAssertEqual(try bytes(folder), before)
    }

    func testDeletingCurrentSudokuPreservesOtherPuzzleSidecarsAndWholeGameDeleteRemovesAll() throws {
        let catalog = try SudokuPuzzle.bundled(), first = catalog[0], second = catalog[1]
        var progress = SudokuProgress()
        progress.record(SudokuBoard(puzzle: first), puzzle: first)
        progress.record(SudokuBoard(puzzle: second), puzzle: second)
        var metadata = GameSessionData()
        metadata.sessions[.sudoku] = GameSessionState(gameID: .sudoku, mode: first.id, phase: .paused, elapsedSeconds: 15)
        XCTAssertTrue(metadata.parkSudokuSession())
        metadata.sessions[.sudoku] = GameSessionState(gameID: .sudoku, mode: second.id, phase: .paused, elapsedSeconds: 7)
        let folder = try directory(), store = try GameDataTransferStore(directory: folder)
        _ = try store.replaceGame(.sudoku, payload: .sudoku(progress), metadata: metadata)
        progress.boards[second.id] = nil; progress.currentID = nil
        let result = try store.replaceGame(.sudoku, payload: .sudoku(progress), metadata: metadata)
        XCTAssertNil(result.metadata.sessions[.sudoku])
        XCTAssertEqual(result.metadata.sudokuSessions[first.id]?.elapsedSeconds, 15)
        XCTAssertEqual(try SaveStore(directory: folder).load(SudokuProgress.self, namespace: "sudoku")?.boards.count, 1)
        _ = try store.removeGame(.sudoku, includingHistory: false, includingPreferences: false)
        XCTAssertTrue(try store.loadSessionData().sudokuSessions.isEmpty)
        XCTAssertNil(try SaveStore(directory: folder).load(SudokuProgress.self, namespace: "sudoku"))
    }

    func testMalformedParkedSudokuGameLabelsPhasesAndDuplicateSessionIDsReject() throws {
        var metadata = GameSessionData()
        let id = "sudoku.easy.0001"
        metadata.sudokuSessions[id] = GameSessionState(gameID: .memory, mode: id, phase: .paused)
        XCTAssertFalse(metadata.isValid)
        metadata.sudokuSessions = ["unknown": GameSessionState(gameID: .sudoku, mode: "unknown", phase: .paused)]
        XCTAssertFalse(metadata.isValid)
        metadata.sudokuSessions = [id: GameSessionState(gameID: .sudoku, mode: id, phase: .playing)]
        XCTAssertFalse(metadata.isValid)
        let parked = GameSessionState(gameID: .sudoku, mode: id, phase: .paused)
        metadata.sudokuSessions = [id: parked]
        metadata.sessions[.memory] = GameSessionState(gameID: .memory, id: parked.id)
        XCTAssertFalse(metadata.isValid)
        metadata.sessions = [:]
        metadata.sessions[.sudoku] = GameSessionState(gameID: .sudoku, mode: id, phase: .paused)
        XCTAssertFalse(metadata.isValid)
    }

    func testTwoStoreInstancesConcurrentSameRecordCommitExactlyOnce() throws {
        let folder = try directory()
        let first = try GameDataTransferStore(directory: folder), second = try GameDataTransferStore(directory: folder)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let record = GamePlayRecord(sessionID: UUID(), gameID: .memory, startedAt: date,
                                    finishedAt: date.addingTimeInterval(10), elapsedSeconds: 5, moves: 2, result: .won)
        let errorLock = NSLock(); var failures = 0
        DispatchQueue.concurrentPerform(iterations: 16) { index in
            do { _ = try (index.isMultiple(of: 2) ? first : second).appendRecord(record) }
            catch { errorLock.lock(); failures += 1; errorLock.unlock() }
        }
        XCTAssertEqual(failures, 0)
        let data = try first.loadSessionData()
        XCTAssertEqual(data.records, [record]); XCTAssertEqual(data.statistics[.memory]?.won, 1)
    }

    func testLegacyDuelTotalsSurviveDeletingProgressWithoutTouchingOtherSevenGames() throws {
        let folder = try directory(); try seedAll(folder)
        let store = try GameDataTransferStore(directory: folder)
        var old = DuelStatistics(); old.record(winner: .first, humanPlayer: .first)
        var metadata = GameSessionData(); metadata.legacyDuelStatistics[.ticTacToe] = old
        metadata.legacyDuelStatistics[.connectFour] = DuelStatistics()
        try store.saveSessionData(metadata)
        let before = try bytes(folder)
        _ = try store.replaceGame(.ticTacToe, payload: nil, metadata: metadata)
        let restarted = try GameDataTransferStore(directory: folder).loadSessionData()
        XCTAssertEqual(restarted.legacyDuelStatistics[.ticTacToe], old)
        XCTAssertEqual(restarted.legacyDuelStatistics[.connectFour], DuelStatistics())
        XCTAssertTrue(restarted.records.isEmpty); XCTAssertTrue(restarted.statistics.isEmpty)
        XCTAssertNil(try SaveStore(directory: folder).load(TicTacToeBoard.self, namespace: "tictactoe"))
        for game in GameID.allCases where game != .ticTacToe {
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(game.rawValue + ".json")), before[game.rawValue + ".json"])
        }
        let archive = try store.exportArchive(preferences: AppPreferences())
        let restored = try GameDataTransferStore(directory: directory()).applyArchive(archive)
        XCTAssertEqual(restored.metadata.legacyDuelStatistics, metadata.legacyDuelStatistics)
    }

    func testPerGameArchiveCannotImportAnotherGamesLegacyTotals() throws {
        let folder = try directory(); try seedAll(folder)
        let store = try GameDataTransferStore(directory: folder)
        var old = DuelStatistics(); old.record(winner: nil, humanPlayer: .first)
        var metadata = GameSessionData(); metadata.legacyDuelStatistics[.connectFour] = old
        let invalid = GameDataArchive(scope: .game(.ticTacToe), preferences: nil,
                                      games: [GameArchiveEntry(gameID: .ticTacToe, payload: .ticTacToe(TicTacToeBoard(seed: 1)))], metadata: metadata)
        let before = try bytes(folder)
        XCTAssertThrowsError(try store.applyArchive(JSONEncoder().encode(invalid)))
        XCTAssertEqual(try bytes(folder), before)
    }
}
