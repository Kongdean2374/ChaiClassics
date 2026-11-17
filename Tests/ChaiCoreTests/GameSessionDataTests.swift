import XCTest
@testable import ChaiCore

final class GameSessionDataTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private func state(_ game: GameID = .sliding) -> GameSessionState {
        GameSessionState(gameID: game, startedAt: start, difficulty: "easy", mode: "3x3")
    }

    func testFractionalClockPausesResumesAndRejectsStaleCallbacks() {
        var session = state()
        let id = session.id
        XCTAssertEqual(session.advance(by: 0.6, expectedSessionID: id), 0)
        XCTAssertTrue(session.pause(expectedSessionID: id))
        XCTAssertEqual(session.advance(by: 10, expectedSessionID: id), 0)
        XCTAssertTrue(session.resume(expectedSessionID: id))
        XCTAssertEqual(session.advance(by: 0.6, expectedSessionID: id), 1)
        XCTAssertEqual(session.elapsedFraction, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(session.advance(by: 100, expectedSessionID: UUID()), 0)
        XCTAssertEqual(session.advance(by: .infinity, expectedSessionID: id), 0)
        XCTAssertEqual(session.advance(by: -.infinity, expectedSessionID: id), 0)
        XCTAssertEqual(session.advance(by: -1, expectedSessionID: id), 0)
        XCTAssertEqual(session.elapsedSeconds, 1)
        XCTAssertTrue(session.isValid)
    }

    func testRapidConfirmCancelAndRepeatedFinishCommitOnce() throws {
        var session = state()
        let token = try XCTUnwrap(session.beginConfirmation(.restart))
        XCTAssertEqual(session.phase, .paused)
        XCTAssertNil(session.beginConfirmation(.leave))
        XCTAssertFalse(session.resume())
        XCTAssertTrue(session.cancelConfirmation(token))
        XCTAssertEqual(session.phase, .playing)
        XCTAssertFalse(session.cancelConfirmation(token))
        XCTAssertFalse(session.confirm(token, elapsedSeconds: 5, moves: 1, at: start.addingTimeInterval(10)).accepted)
        let next = try XCTUnwrap(session.beginConfirmation(.restart))
        let resolution = session.confirm(next, elapsedSeconds: 5, moves: 1, at: start.addingTimeInterval(10))
        XCTAssertTrue(resolution.accepted)
        XCTAssertEqual(resolution.record?.result, .abandoned)
        XCTAssertEqual(session.phase, .menu)
        XCTAssertFalse(session.confirm(next, elapsedSeconds: 5, moves: 1).accepted)
        XCTAssertNil(session.finish(result: .won, elapsedSeconds: 5, moves: 1))
        XCTAssertTrue(session.isValid)
    }

    func testStaleSessionConfirmationCannotAffectReplacementRound() throws {
        var first = state()
        let token = try XCTUnwrap(first.beginConfirmation(.leave))
        var replacement = state()
        XCTAssertFalse(replacement.confirm(token, elapsedSeconds: 1, moves: 0).accepted)
        XCTAssertNil(replacement.finish(result: .won, elapsedSeconds: 1, moves: 0,
                                         at: start.addingTimeInterval(1), expectedSessionID: first.id))
        XCTAssertEqual(replacement.phase, .playing)
    }

    func testMoveCountersRejectStalePausedNegativeOverflowAndSupportBoardUndoSync() {
        var session = state()
        XCTAssertTrue(session.recordMove(expectedSessionID: session.id))
        XCTAssertTrue(session.recordMove(by: 2, expectedSessionID: session.id))
        XCTAssertEqual(session.moves, 3)
        XCTAssertFalse(session.recordMove(by: -1, expectedSessionID: session.id))
        XCTAssertFalse(session.recordMove(by: Int.max, expectedSessionID: session.id))
        XCTAssertFalse(session.syncMoves(100, expectedSessionID: UUID()))
        XCTAssertTrue(session.syncMoves(2, expectedSessionID: session.id))
        XCTAssertEqual(session.moves, 2)
        XCTAssertTrue(session.pause())
        XCTAssertFalse(session.recordMove(expectedSessionID: session.id))
        XCTAssertFalse(session.syncMoves(3, expectedSessionID: session.id))
    }

    func testCompletedResultReviewAndRestartDoNotRecordAbandonment() throws {
        var session = state()
        let record = try XCTUnwrap(session.finish(result: .completed, elapsedSeconds: 3, moves: 2, at: start.addingTimeInterval(5)))
        XCTAssertTrue(session.review())
        XCTAssertTrue(session.showResult())
        XCTAssertEqual(session.phase, .result)
        XCTAssertTrue(session.review())
        let token = try XCTUnwrap(session.beginConfirmation(.restart))
        let resolution = session.confirm(token, elapsedSeconds: 99, moves: 99)
        XCTAssertTrue(resolution.accepted)
        XCTAssertNil(resolution.record)
        XCTAssertEqual(session.recordID, record.id)
        XCTAssertEqual(session.phase, .menu)
    }

    func testClosingAResultRetainsCommittedMovesAndDedupFlag() throws {
        var session = state()
        let record = try XCTUnwrap(session.finish(result: .completed, elapsedSeconds: 3, moves: 12, at: start.addingTimeInterval(5)))
        XCTAssertEqual(session.moves, 12)
        XCTAssertTrue(session.close())
        XCTAssertEqual(session.phase, .menu)
        XCTAssertEqual(session.recordID, record.id)
        XCTAssertFalse(session.resume())
        XCTAssertFalse(session.close())
        XCTAssertTrue(session.reopenResult())
        XCTAssertEqual(session.phase, .result)
        XCTAssertEqual(session.recordID, record.id)
        XCTAssertFalse(session.reopenResult())
        XCTAssertTrue(session.isValid)
    }

    func testActionGateFirstResponseWinsAndInvalidatesStaleDialogs() throws {
        var gate = GameActionGate()
        let first = try XCTUnwrap(gate.begin())
        XCTAssertNil(gate.begin())
        XCTAssertFalse(gate.resolve(UUID()))
        XCTAssertTrue(gate.resolve(first))
        XCTAssertFalse(gate.resolve(first))
        let second = try XCTUnwrap(gate.begin())
        XCTAssertFalse(gate.resolve(first))
        XCTAssertEqual(gate.id, second)
        gate.invalidate()
        XCTAssertFalse(gate.resolve(second))
        XCTAssertNotNil(gate.begin())
    }

    func testMetadataDeduplicatesRecordsAndDerivesRealStatistics() throws {
        var data = GameSessionData()
        var session = state()
        let record = try XCTUnwrap(session.finish(result: .won, elapsedSeconds: 12, moves: 7, at: start.addingTimeInterval(20)))
        XCTAssertTrue(try data.append(record))
        XCTAssertFalse(try data.append(record))
        data.sessions[.sliding] = session
        XCTAssertEqual(data.statistics[.sliding]?.won, 1)
        XCTAssertEqual(data.statistics[.sliding]?.total, 1)
        XCTAssertEqual(data.statistics[.sliding]?.bestTime, 12)
        XCTAssertEqual(data.statistics[.sliding]?.moves, 7)
        XCTAssertTrue(data.isValid)
        let forged = GamePlayRecord(sessionID: record.sessionID, gameID: .sliding, startedAt: start,
                                    finishedAt: start.addingTimeInterval(30), elapsedSeconds: 30, moves: 9, result: .won)
        XCTAssertThrowsError(try data.append(forged))
    }

    func testClearRecordsRetainsActiveProgressAndFinishedDedupAfterRestart() throws {
        var data = GameSessionData()
        var finished = state()
        let record = try XCTUnwrap(finished.finish(result: .won, elapsedSeconds: 4, moves: 2, at: start.addingTimeInterval(10)))
        try data.append(record); data.sessions[.sliding] = finished
        let active = state(.memory); data.sessions[.memory] = active
        data.clearRecords(for: .sliding)
        XCTAssertEqual(data.sessions[.memory], active)
        XCTAssertEqual(data.sessions[.sliding], finished)
        XCTAssertTrue(data.records.isEmpty)
        XCTAssertTrue(data.statistics.isEmpty)
        XCTAssertTrue(data.isValid)
        var restarted = try JSONDecoder().decode(GameSessionData.self, from: JSONEncoder().encode(data))
        XCTAssertFalse(try restarted.append(record))
        XCTAssertNil(restarted.sessions[.sliding]?.finish(result: .won, elapsedSeconds: 4, moves: 2))
        XCTAssertTrue(restarted.sessions[.sliding]?.close() == true)
        XCTAssertTrue(restarted.sessions[.sliding]?.reopenResult() == true)
        XCTAssertTrue(restarted.isValid)
        restarted.sessions[.sliding] = state()
        XCTAssertTrue(restarted.clearedRecordIDs.isEmpty)
        XCTAssertTrue(restarted.isValid)
    }

    func testInvalidHistoryAndPreferencesAreRejectedWithoutChangingRecords() throws {
        var data = GameSessionData()
        let invalid = GamePlayRecord(sessionID: UUID(), gameID: .maze, startedAt: start,
                                     finishedAt: start.addingTimeInterval(-1), elapsedSeconds: -1, moves: 0, result: .completed)
        XCTAssertThrowsError(try data.append(invalid))
        XCTAssertTrue(data.records.isEmpty)
        var preferences = GamePlayPreferences(); preferences.minesCount = Int.max
        data.gamePreferences[.minesweeper] = preferences
        XCTAssertFalse(data.isValid)
    }

    func testEmptyMetadataDoesNotInventLegacyHistory() throws {
        let data = GameSessionData()
        XCTAssertTrue(data.records.isEmpty); XCTAssertTrue(data.statistics.isEmpty)
        XCTAssertTrue(data.sessions.isEmpty); XCTAssertTrue(data.isValid)
    }

    func testAdoptingLegacyFinishedGamesCreatesNoHistoryOrStatistics() throws {
        var data = GameSessionData()
        let state = GameSessionState(gameID: .memory, startedAt: start, phase: .paused,
                                     elapsedSeconds: 91, moves: 35)
        XCTAssertTrue(data.adoptUntrackedFinishedSession(state, outcome: .completed, elapsedSeconds: 91, moves: 35))
        XCTAssertTrue(data.records.isEmpty); XCTAssertTrue(data.statistics.isEmpty)
        XCTAssertEqual(data.sessions[.memory]?.phase, .result)
        XCTAssertEqual(data.sessions[.memory]?.outcome, .completed)
        XCTAssertEqual(data.sessions[.memory]?.elapsedSeconds, 91)
        XCTAssertEqual(data.sessions[.memory]?.moves, 35)
        XCTAssertEqual(data.clearedRecordIDs.count, 1)
        var restarted = try JSONDecoder().decode(GameSessionData.self, from: JSONEncoder().encode(data))
        XCTAssertTrue(restarted.isValid)
        XCTAssertTrue(restarted.sessions[.memory]?.close() == true)
        XCTAssertTrue(restarted.sessions[.memory]?.reopenResult() == true)
        XCTAssertNil(restarted.sessions[.memory]?.finish(result: .completed, elapsedSeconds: 91, moves: 35))
        XCTAssertTrue(restarted.records.isEmpty); XCTAssertTrue(restarted.statistics.isEmpty)
    }

    func testSudokuSwitchingPuzzlesPreservesIndependentIdentityTimeMovesAndFraction() throws {
        let firstID = "sudoku.easy.0001", secondID = "sudoku.easy.0002"
        var first = GameSessionState(gameID: .sudoku, startedAt: start, difficulty: "easy", mode: firstID)
        _ = first.advance(by: 15.25, expectedSessionID: first.id)
        XCTAssertTrue(first.recordMove(by: 3, expectedSessionID: first.id))
        var data = GameSessionData(); data.sessions[.sudoku] = first
        XCTAssertTrue(data.parkSudokuSession())
        XCTAssertNil(data.sessions[.sudoku]); XCTAssertEqual(data.sudokuSessions[firstID]?.phase, .paused)
        var second = GameSessionState(gameID: .sudoku, startedAt: start, difficulty: "easy", mode: secondID)
        _ = second.advance(by: 7.5, expectedSessionID: second.id)
        data.sessions[.sudoku] = second
        XCTAssertTrue(data.parkSudokuSession())
        var restarted = try JSONDecoder().decode(GameSessionData.self, from: JSONEncoder().encode(data))
        XCTAssertTrue(restarted.restoreSudokuSession(puzzleID: firstID))
        XCTAssertEqual(restarted.sessions[.sudoku]?.id, first.id)
        XCTAssertEqual(restarted.sessions[.sudoku]?.elapsedSeconds, 15)
        XCTAssertEqual(restarted.sessions[.sudoku]?.elapsedFraction, 0.25)
        XCTAssertEqual(restarted.sessions[.sudoku]?.moves, 3)
        XCTAssertEqual(restarted.sudokuSessions[secondID]?.id, second.id)
        XCTAssertEqual(restarted.sudokuSessions[secondID]?.elapsedSeconds, 7)
        XCTAssertFalse(restarted.restoreSudokuSession(puzzleID: secondID))
        XCTAssertTrue(restarted.records.isEmpty); XCTAssertTrue(restarted.statistics.isEmpty)
        XCTAssertTrue(restarted.isValid)
    }

    func testSudokuParkingCancelsConfirmationPausesAndRetainsClearedResultMarker() throws {
        let id = "sudoku.easy.0001"
        var active = GameSessionState(gameID: .sudoku, startedAt: start, difficulty: "easy", mode: id)
        let token = try XCTUnwrap(active.beginConfirmation(.restart))
        var data = GameSessionData(); data.sessions[.sudoku] = active
        XCTAssertTrue(data.parkSudokuSession())
        XCTAssertNil(data.sudokuSessions[id]?.pendingToken)
        XCTAssertEqual(data.sudokuSessions[id]?.phase, .paused)
        XCTAssertFalse(data.sudokuSessions[id]?.confirm(token, elapsedSeconds: 1, moves: 1).accepted == true)
        XCTAssertTrue(data.restoreSudokuSession(puzzleID: id))
        var finished = try XCTUnwrap(data.sessions[.sudoku])
        let record = try XCTUnwrap(finished.finish(result: .completed, elapsedSeconds: 1, moves: 1, at: start.addingTimeInterval(5)))
        try data.append(record); data.sessions[.sudoku] = finished
        XCTAssertTrue(data.parkSudokuSession())
        data.clearRecords(for: .sudoku)
        XCTAssertTrue(data.isValid); XCTAssertEqual(data.clearedRecordIDs, [record.id])
        XCTAssertTrue(data.restoreSudokuSession(puzzleID: id))
        XCTAssertFalse(try data.append(record))
        XCTAssertEqual(data.sessions[.sudoku]?.recordID, record.id)
        XCTAssertTrue(data.isValid)
    }

    func testAllOutcomesAndBestTimeStatisticsRemainIndependentPerGame() throws {
        var data = GameSessionData()
        for (index, outcome) in GameOutcome.allCases.enumerated() {
            try data.append(GamePlayRecord(sessionID: UUID(), gameID: .maze, startedAt: start,
                                           finishedAt: start.addingTimeInterval(100), elapsedSeconds: index + 1, moves: index, result: outcome))
        }
        XCTAssertEqual(data.statistics[.maze]?.total, 5)
        XCTAssertEqual(data.statistics[.maze]?.won, 1)
        XCTAssertEqual(data.statistics[.maze]?.lost, 1)
        XCTAssertEqual(data.statistics[.maze]?.completed, 1)
        XCTAssertEqual(data.statistics[.maze]?.draw, 1)
        XCTAssertEqual(data.statistics[.maze]?.abandoned, 1)
        XCTAssertEqual(data.statistics[.maze]?.bestTime, 1)
        XCTAssertNil(data.statistics[.memory])
    }

    func testUndatedLegacyDuelTotalsRoundTripAndClearKeepsMigrationMarker() throws {
        var old = DuelStatistics()
        old.record(winner: .first, humanPlayer: .first)
        old.record(winner: nil, humanPlayer: .first)
        old.record(winner: .second, humanPlayer: .first)
        var data = GameSessionData()
        data.legacyDuelStatistics[.ticTacToe] = old
        data.legacyDuelStatistics[.connectFour] = old
        let restarted = try JSONDecoder().decode(GameSessionData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(restarted.legacyDuelStatistics[.ticTacToe], old)
        XCTAssertTrue(restarted.records.isEmpty); XCTAssertTrue(restarted.statistics.isEmpty)
        XCTAssertTrue(restarted.isValid)
        data.clearRecords(for: .ticTacToe)
        XCTAssertEqual(data.legacyDuelStatistics[.ticTacToe], DuelStatistics())
        XCTAssertEqual(data.legacyDuelStatistics[.connectFour], old)
        // Startup imports only a missing key. A deliberate clear must survive
        // restart even when the released board still contains its old totals.
        if data.legacyDuelStatistics[.ticTacToe] == nil { data.legacyDuelStatistics[.ticTacToe] = old }
        XCTAssertEqual(data.legacyDuelStatistics[.ticTacToe]?.wins, 0)
        data.clearRecords()
        XCTAssertEqual(Set(data.legacyDuelStatistics.keys), [.ticTacToe, .connectFour])
        XCTAssertTrue(data.legacyDuelStatistics.values.allSatisfy { $0 == DuelStatistics() })
        XCTAssertTrue(data.records.isEmpty); XCTAssertTrue(data.isValid)
    }

    func testLegacyDuelTotalsScopeReplaceRemoveAndBoundsAreStrict() throws {
        var old = DuelStatistics(); old.record(winner: .first, humanPlayer: .first)
        var data = GameSessionData(); data.legacyDuelStatistics = [.ticTacToe: old, .connectFour: old]
        let scoped = data.scoped(to: .ticTacToe)
        XCTAssertEqual(Set(scoped.legacyDuelStatistics.keys), [.ticTacToe])
        data.remove(.ticTacToe)
        XCTAssertNil(data.legacyDuelStatistics[.ticTacToe])
        XCTAssertEqual(data.legacyDuelStatistics[.connectFour], old)
        try data.replace(.ticTacToe, with: scoped)
        XCTAssertEqual(data.legacyDuelStatistics[.ticTacToe], old)
        data.legacyDuelStatistics[.memory] = old
        XCTAssertFalse(data.isValid)
        data.legacyDuelStatistics[.memory] = nil
        data.legacyDuelStatistics[.ticTacToe] = try JSONDecoder().decode(DuelStatistics.self, from:
            Data(#"{"wins":1000000001,"draws":0,"losses":0}"#.utf8))
        XCTAssertFalse(data.isValid)
    }
}
