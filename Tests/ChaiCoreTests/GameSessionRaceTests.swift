import XCTest
@testable import ChaiCore

final class GameSessionRaceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let actions: [GameSessionAction] = [.restart, .leave, .clear]

    private func state(_ game: GameID, paused: Bool = false) -> GameSessionState {
        GameSessionState(gameID: game, startedAt: start, difficulty: "normal", mode: game.rawValue,
                         phase: paused ? .paused : .playing, elapsedSeconds: 8, elapsedFraction: 0.625, moves: 3)
    }

    private func replacingPreviousPhase(_ state: GameSessionState, with phase: String) throws -> GameSessionState {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object["phaseBeforeConfirmation"] = phase
        return try JSONDecoder().decode(GameSessionState.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testEveryGameActionAndPriorPhaseHonorFirstOppositeConfirmationResponse() throws {
        for game in GameID.allCases {
            for action in actions {
                for paused in [false, true] {
                    for cancelFirst in [false, true] {
                        var session = state(game, paused: paused)
                        let before = session
                        let token = try XCTUnwrap(session.beginConfirmation(action))
                        let opposite: GameSessionAction = action == .leave ? .clear : .leave
                        let forged = GameSessionToken(sessionID: session.id, action: opposite, id: token.id)
                        XCTAssertFalse(session.cancelConfirmation(forged))
                        XCTAssertFalse(session.confirm(forged, elapsedSeconds: 8, moves: 3, at: start.addingTimeInterval(10)).accepted)
                        XCTAssertNil(session.beginConfirmation(opposite))
                        XCTAssertFalse(session.resume())
                        XCTAssertEqual(session.advance(by: 20, expectedSessionID: session.id), 0)
                        XCTAssertFalse(session.recordMove(expectedSessionID: session.id))
                        XCTAssertFalse(session.syncMoves(99, expectedSessionID: session.id))
                        if cancelFirst {
                            XCTAssertTrue(session.cancelConfirmation(token))
                            XCTAssertEqual(session, before, "Cancel must restore \(game)/\(action) exactly, including fraction and prior pause")
                            XCTAssertFalse(session.confirm(token, elapsedSeconds: 8, moves: 3, at: start.addingTimeInterval(10)).accepted)
                            XCTAssertFalse(session.cancelConfirmation(token))
                        } else {
                            let confirmation = session.confirm(token, elapsedSeconds: 8, moves: 3, at: start.addingTimeInterval(10))
                            XCTAssertTrue(confirmation.accepted)
                            XCTAssertEqual(confirmation.record?.result, .abandoned)
                            XCTAssertEqual(confirmation.record?.sessionID, before.id)
                            XCTAssertEqual(session.phase, .menu)
                            let resolved = session
                            XCTAssertFalse(session.cancelConfirmation(token))
                            XCTAssertFalse(session.confirm(token, elapsedSeconds: 999, moves: 999).accepted)
                            XCTAssertEqual(session, resolved)
                        }
                        XCTAssertTrue(session.isValid)
                    }
                }
            }
        }
    }

    func testAllTerminalOutcomesFreezeClockAndMovesThroughRepeatedReviewCloseAndReopen() throws {
        for game in GameID.allCases {
            for outcome in GameOutcome.allCases {
                var session = state(game), metadata = GameSessionData()
                let record = try XCTUnwrap(session.finish(result: outcome, elapsedSeconds: 12, moves: 9,
                                                          at: start.addingTimeInterval(20), expectedSessionID: session.id))
                XCTAssertTrue(try metadata.append(record))
                for _ in 0..<8 {
                    XCTAssertTrue(session.review())
                    XCTAssertFalse(session.review())
                    XCTAssertFalse(session.resume())
                    XCTAssertFalse(session.pause())
                    XCTAssertFalse(session.recordMove(expectedSessionID: session.id))
                    XCTAssertFalse(session.syncMoves(0, expectedSessionID: session.id))
                    XCTAssertEqual(session.advance(by: 100, expectedSessionID: session.id), 0)
                    XCTAssertNil(session.finish(result: .abandoned, elapsedSeconds: 100, moves: 100))
                    XCTAssertTrue(session.showResult())
                    XCTAssertFalse(session.showResult())
                    XCTAssertFalse(try metadata.append(record))
                }
                XCTAssertTrue(session.close())
                XCTAssertFalse(session.resume())
                XCTAssertFalse(session.recordMove(expectedSessionID: session.id))
                XCTAssertEqual(session.advance(by: 100, expectedSessionID: session.id), 0)
                session = try JSONDecoder().decode(GameSessionState.self, from: JSONEncoder().encode(session))
                XCTAssertTrue(session.reopenResult())
                XCTAssertEqual(session.elapsedSeconds, 12)
                XCTAssertEqual(session.moves, 9)
                XCTAssertEqual(session.recordID, record.id)
                metadata.sessions[game] = session
                XCTAssertTrue(metadata.isValid)
                XCTAssertEqual(metadata.statistics[game]?.total, 1)
                XCTAssertEqual(metadata.statistics[game]?.moves, 9)
                XCTAssertEqual(metadata.statistics[game]?.elapsedSeconds, 12)
            }
        }
    }

    func testOldSessionCallbacksCannotModifyReplacementOrResurrectClearedStatistics() throws {
        for game in GameID.allCases {
            for action in actions {
                var old = state(game), metadata = GameSessionData()
                let staleToken = try XCTUnwrap(old.beginConfirmation(action))
                let record = try XCTUnwrap(old.confirm(staleToken, elapsedSeconds: 8, moves: 3, at: start.addingTimeInterval(10)).record)
                try metadata.append(record); metadata.sessions[game] = old
                metadata.clearRecords(for: game)
                var current = state(game)
                metadata.sessions[game] = current
                let currentToken = try XCTUnwrap(current.beginConfirmation(action))
                let expected = current
                XCTAssertFalse(current.cancelConfirmation(staleToken))
                XCTAssertFalse(current.confirm(staleToken, elapsedSeconds: 20, moves: 20).accepted)
                XCTAssertFalse(current.pause(expectedSessionID: old.id))
                XCTAssertFalse(current.resume(expectedSessionID: old.id))
                XCTAssertFalse(current.recordMove(expectedSessionID: old.id))
                XCTAssertFalse(current.syncMoves(99, expectedSessionID: old.id))
                XCTAssertEqual(current.advance(by: 30, expectedSessionID: old.id), 0)
                XCTAssertNil(current.finish(result: .won, elapsedSeconds: 20, moves: 20, expectedSessionID: old.id))
                XCTAssertEqual(current, expected)
                XCTAssertTrue(current.cancelConfirmation(currentToken))
                metadata.sessions[game] = current
                XCTAssertTrue(metadata.records.isEmpty)
                XCTAssertTrue(metadata.statistics.isEmpty)
                XCTAssertTrue(metadata.isValid)
            }
        }
    }

    func testRepeatedPausedConfirmationReloadsPreserveEveryFractionOfActiveTime() throws {
        for game in GameID.allCases {
            var session = GameSessionState(gameID: game, startedAt: start)
            let id = session.id
            for _ in 0..<64 {
                session.advance(by: 0.125, expectedSessionID: id)
                XCTAssertTrue(session.pause(expectedSessionID: id))
                let pending = try XCTUnwrap(session.beginConfirmation(.leave))
                session = try JSONDecoder().decode(GameSessionState.self, from: JSONEncoder().encode(session))
                XCTAssertEqual(session.advance(by: 86_400, expectedSessionID: id), 0)
                XCTAssertTrue(session.cancelConfirmation(pending))
                XCTAssertEqual(session.phase, .paused, "Cancel must not silently resume a previously paused game")
                XCTAssertTrue(session.resume(expectedSessionID: id))
                session.advance(by: 0.375, expectedSessionID: id)
            }
            XCTAssertEqual(session.elapsedSeconds, 32)
            XCTAssertEqual(session.elapsedFraction, 0, accuracy: 0.000_000_001)
            XCTAssertTrue(session.isValid)
        }
    }

    func testConcurrentActiveMovesAreNotLostAndStatisticsAppearOnlyAfterOneFinish() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("session-move-race-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try GameDataTransferStore(directory: folder), second = try GameDataTransferStore(directory: folder)
        var initial = GameSessionData()
        for game in GameID.allCases { initial.sessions[game] = GameSessionState(gameID: game, startedAt: start) }
        try first.saveSessionData(initial)
        let lock = NSLock(); var failures = 0
        DispatchQueue.concurrentPerform(iterations: GameID.allCases.count * 8) { index in
            let game = GameID.allCases[index % GameID.allCases.count]
            do {
                _ = try (index.isMultiple(of: 2) ? first : second).updateSessionData { metadata in
                    var session = try XCTUnwrap(metadata.sessions[game])
                    XCTAssertTrue(session.recordMove(expectedSessionID: session.id))
                    metadata.sessions[game] = session
                }
            } catch { lock.lock(); failures += 1; lock.unlock() }
        }
        XCTAssertEqual(failures, 0)
        let active = try first.loadSessionData()
        XCTAssertTrue(active.records.isEmpty)
        XCTAssertTrue(active.statistics.isEmpty)
        for game in GameID.allCases { XCTAssertEqual(active.sessions[game]?.moves, 8) }
        let finished = try first.updateSessionData { metadata in
            for game in GameID.allCases {
                var session = try XCTUnwrap(metadata.sessions[game])
                let record = try XCTUnwrap(session.finish(result: .completed, elapsedSeconds: 4, moves: session.moves,
                                                          at: start.addingTimeInterval(10), expectedSessionID: session.id))
                try metadata.append(record); metadata.sessions[game] = session
            }
        }
        let repeated = try second.updateSessionData { metadata in
            for record in finished.records { XCTAssertFalse(try metadata.append(record)) }
            for game in GameID.allCases {
                XCTAssertNil(metadata.sessions[game]?.finish(result: .completed, elapsedSeconds: 999, moves: 999))
            }
        }
        XCTAssertEqual(repeated, finished)
        XCTAssertEqual(repeated.records.count, GameID.allCases.count)
        for game in GameID.allCases {
            XCTAssertEqual(repeated.statistics[game]?.total, 1)
            XCTAssertEqual(repeated.statistics[game]?.moves, 8)
        }
    }

    func testCorruptConfirmationPreviousPhaseCannotResumeFinishedOrInventActiveResult() throws {
        for game in GameID.allCases {
            for paused in [false, true] {
                var active = state(game, paused: paused)
                XCTAssertNotNil(active.beginConfirmation(.restart))
                for impossible in ["result", "reviewing", "menu"] {
                    XCTAssertFalse(try replacingPreviousPhase(active, with: impossible).isValid)
                }
                var finished = state(game)
                XCTAssertNotNil(finished.finish(result: .completed, elapsedSeconds: 8, moves: 3, at: start.addingTimeInterval(10)))
                if paused { XCTAssertTrue(finished.review()) }
                XCTAssertNotNil(finished.beginConfirmation(.clear))
                for impossible in ["playing", "paused", "menu", paused ? "result" : "reviewing"] {
                    XCTAssertFalse(try replacingPreviousPhase(finished, with: impossible).isValid)
                }
            }
        }
    }

    func testClearedRecordTombstoneCannotMaskAConflictingRecordForSameSession() throws {
        var finished = state(.memory)
        let cleared = try XCTUnwrap(finished.finish(result: .completed, elapsedSeconds: 8, moves: 3, at: start.addingTimeInterval(10)))
        let conflicting = GamePlayRecord(sessionID: finished.id, gameID: .memory, startedAt: start,
                                         finishedAt: start.addingTimeInterval(11), elapsedSeconds: 9, moves: 4, result: .won)
        for record in [cleared, conflicting] {
            var metadata = GameSessionData()
            try metadata.append(record); metadata.sessions[.memory] = finished
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? [String: Any])
            object["clearedRecordIDs"] = [cleared.id.uuidString]
            let corrupt = try JSONDecoder().decode(GameSessionData.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertFalse(corrupt.isValid, "A cleared result may neither remain in history nor hide a second identity for the same session")
        }
    }
}
