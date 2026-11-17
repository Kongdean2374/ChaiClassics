import Foundation

public enum GameOutcome: String, Codable, CaseIterable, Sendable {
    case won, lost, completed, draw, abandoned
}

public enum GameSessionPhase: String, Codable, Sendable {
    case playing, paused, result, reviewing, menu
}

public enum GameSessionAction: String, Codable, Sendable { case restart, leave, clear }

public struct GameSessionToken: Codable, Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let action: GameSessionAction
    public init(sessionID: UUID, action: GameSessionAction, id: UUID = UUID()) {
        self.id = id; self.sessionID = sessionID; self.action = action
    }
}

/// A single outstanding destructive dialog. A late response from an earlier
/// dialog cannot resolve the next one, even when buttons are tapped rapidly.
public struct GameActionGate: Equatable, Sendable {
    public private(set) var id: UUID?
    public init() {}
    public mutating func begin() -> UUID? {
        guard id == nil else { return nil }
        let token = UUID(); id = token; return token
    }
    @discardableResult public mutating func resolve(_ token: UUID) -> Bool {
        guard id == token else { return false }
        id = nil; return true
    }
    public mutating func invalidate() { id = nil }
}

public struct GamePlayRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let gameID: GameID
    public let startedAt: Date
    public let finishedAt: Date
    public let difficulty: String
    public let mode: String
    public let elapsedSeconds: Int
    public let moves: Int
    public let result: GameOutcome

    public init(id: UUID = UUID(), sessionID: UUID, gameID: GameID, startedAt: Date,
                finishedAt: Date, difficulty: String = "", mode: String = "",
                elapsedSeconds: Int, moves: Int, result: GameOutcome) {
        self.id = id; self.sessionID = sessionID; self.gameID = gameID
        self.startedAt = startedAt; self.finishedAt = finishedAt
        self.difficulty = difficulty; self.mode = mode
        self.elapsedSeconds = elapsedSeconds; self.moves = moves; self.result = result
    }

    public var isValid: Bool {
        validSessionDate(startedAt) && validSessionDate(finishedAt) && finishedAt >= startedAt &&
        validSessionLabel(difficulty) && validSessionLabel(mode) &&
        (0...315_360_000).contains(elapsedSeconds) && (0...1_000_000_000).contains(moves)
    }
}

public struct GameStatistics: Codable, Equatable, Sendable {
    public private(set) var won = 0
    public private(set) var lost = 0
    public private(set) var completed = 0
    public private(set) var draw = 0
    public private(set) var abandoned = 0
    public private(set) var elapsedSeconds = 0
    public private(set) var moves = 0
    public private(set) var bestTime: Int?
    public var total: Int { won + lost + completed + draw + abandoned }
    public init() {}

    public var isValid: Bool {
        let limit = GameSessionData.maximumRecords
        guard [won, lost, completed, draw, abandoned].allSatisfy({ (0...limit).contains($0) }),
              (0...(limit * 315_360_000)).contains(elapsedSeconds),
              (0...(limit * 1_000_000_000)).contains(moves),
              bestTime == nil || (0...315_360_000).contains(bestTime!) else { return false }
        return total <= limit && ((won + completed == 0) == (bestTime == nil))
    }

    fileprivate mutating func include(_ record: GamePlayRecord) {
        switch record.result {
        case .won: won += 1
        case .lost: lost += 1
        case .completed: completed += 1
        case .draw: draw += 1
        case .abandoned: abandoned += 1
        }
        elapsedSeconds += record.elapsedSeconds; moves += record.moves
        if record.result == .won || record.result == .completed {
            bestTime = min(bestTime ?? record.elapsedSeconds, record.elapsedSeconds)
        }
    }
}

public struct GameSessionConfirmation: Equatable, Sendable {
    public let accepted: Bool
    public let record: GamePlayRecord?
}

/// A value-state machine. A callback must carry its original session/token so a
/// delayed tap, timer or confirmation cannot finish or replace the next round.
public struct GameSessionState: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let gameID: GameID
    public let startedAt: Date
    public let difficulty: String
    public let mode: String
    public private(set) var phase: GameSessionPhase
    public private(set) var elapsedSeconds: Int
    public private(set) var elapsedFraction: Double
    public private(set) var moves: Int
    public private(set) var recordID: UUID?
    public private(set) var outcome: GameOutcome?
    public private(set) var pendingToken: GameSessionToken?
    private var phaseBeforeConfirmation: GameSessionPhase?

    public init(gameID: GameID, id: UUID = UUID(), startedAt: Date = Date(),
                difficulty: String = "", mode: String = "", phase: GameSessionPhase = .playing,
                elapsedSeconds: Int = 0, elapsedFraction: Double = 0, moves: Int = 0) {
        self.gameID = gameID; self.id = id; self.startedAt = startedAt
        self.difficulty = difficulty; self.mode = mode; self.phase = phase
        self.elapsedSeconds = elapsedSeconds; self.elapsedFraction = elapsedFraction; self.moves = moves
    }

    public var isValid: Bool {
        guard validSessionDate(startedAt), validSessionLabel(difficulty), validSessionLabel(mode),
              (0...315_360_000).contains(elapsedSeconds), elapsedFraction.isFinite,
              (0..<1).contains(elapsedFraction), (0...1_000_000_000).contains(moves) else { return false }
        if let pendingToken {
            guard pendingToken.sessionID == id, let previous = phaseBeforeConfirmation else { return false }
            if recordID == nil {
                guard phase == .paused, previous == .playing || previous == .paused else { return false }
            } else {
                guard previous == phase, phase == .result || phase == .reviewing else { return false }
            }
        } else if phaseBeforeConfirmation != nil { return false }
        if recordID == nil && (phase == .result || phase == .reviewing) { return false }
        if recordID != nil && (phase == .playing || phase == .paused) { return false }
        if (recordID == nil) != (outcome == nil) { return false }
        return true
    }

    @discardableResult public mutating func pause(expectedSessionID: UUID? = nil) -> Bool {
        guard expectedSessionID == nil || expectedSessionID == id, phase == .playing, pendingToken == nil else { return false }
        phase = .paused; return true
    }
    @discardableResult public mutating func resume(expectedSessionID: UUID? = nil) -> Bool {
        guard expectedSessionID == nil || expectedSessionID == id, phase == .paused,
              pendingToken == nil, recordID == nil else { return false }
        phase = .playing; return true
    }

    @discardableResult public mutating func advance(by interval: TimeInterval, expectedSessionID: UUID) -> Int {
        guard id == expectedSessionID, phase == .playing, pendingToken == nil, interval.isFinite,
              interval > 0, interval <= 86_400, isValid else { return 0 }
        let total = elapsedFraction + interval
        let seconds = Int(total.rounded(.down))
        guard seconds <= 315_360_000 - elapsedSeconds else { return 0 }
        elapsedSeconds += seconds; elapsedFraction = total - Double(seconds)
        return seconds
    }

    @discardableResult public mutating func recordMove(by count: Int = 1, expectedSessionID: UUID) -> Bool {
        guard isValid, id == expectedSessionID, phase == .playing, pendingToken == nil,
              count > 0, count <= 1_000_000_000 - moves else { return false }
        moves += count; return true
    }

    @discardableResult public mutating func syncMoves(_ count: Int, expectedSessionID: UUID) -> Bool {
        guard id == expectedSessionID, phase == .playing, pendingToken == nil,
              (0...1_000_000_000).contains(count), isValid else { return false }
        moves = count; return true
    }

    public mutating func beginConfirmation(_ action: GameSessionAction) -> GameSessionToken? {
        guard pendingToken == nil, phase != .menu, isValid else { return nil }
        let token = GameSessionToken(sessionID: id, action: action)
        pendingToken = token; phaseBeforeConfirmation = phase
        if phase == .playing { phase = .paused }
        return token
    }

    @discardableResult public mutating func cancelConfirmation(_ token: GameSessionToken) -> Bool {
        guard pendingToken == token, token.sessionID == id, let previous = phaseBeforeConfirmation else { return false }
        phase = previous; pendingToken = nil; phaseBeforeConfirmation = nil; return true
    }

    public mutating func confirm(_ token: GameSessionToken, elapsedSeconds: Int, moves: Int,
                                 at date: Date = Date()) -> GameSessionConfirmation {
        guard pendingToken == token, token.sessionID == id else { return GameSessionConfirmation(accepted: false, record: nil) }
        let previous = self
        pendingToken = nil; phaseBeforeConfirmation = nil
        let record = recordID == nil ? finish(result: .abandoned, elapsedSeconds: elapsedSeconds, moves: moves,
                                              at: date, expectedSessionID: token.sessionID) : nil
        guard recordID != nil else { self = previous; return GameSessionConfirmation(accepted: false, record: nil) }
        phase = .menu
        return GameSessionConfirmation(accepted: true, record: record)
    }

    public mutating func finish(result: GameOutcome, elapsedSeconds: Int, moves: Int,
                                at date: Date = Date(), expectedSessionID: UUID? = nil) -> GamePlayRecord? {
        guard expectedSessionID == nil || expectedSessionID == id, recordID == nil,
              pendingToken == nil, phase == .playing || phase == .paused else { return nil }
        let record = GamePlayRecord(sessionID: id, gameID: gameID, startedAt: startedAt, finishedAt: date,
                                    difficulty: difficulty, mode: mode, elapsedSeconds: elapsedSeconds, moves: moves, result: result)
        guard record.isValid else { return nil }
        recordID = record.id; outcome = result
        self.elapsedSeconds = elapsedSeconds; self.moves = moves; elapsedFraction = 0; phase = .result
        return record
    }

    @discardableResult public mutating func review() -> Bool {
        guard phase == .result, recordID != nil, pendingToken == nil else { return false }
        phase = .reviewing; return true
    }

    @discardableResult public mutating func showResult() -> Bool {
        guard phase == .reviewing, recordID != nil, pendingToken == nil else { return false }
        phase = .result; return true
    }

    @discardableResult public mutating func close() -> Bool {
        guard recordID != nil, phase == .result || phase == .reviewing else { return false }
        phase = .menu; pendingToken = nil; phaseBeforeConfirmation = nil; return true
    }

    @discardableResult public mutating func reopenResult() -> Bool {
        guard phase == .menu, recordID != nil, pendingToken == nil else { return false }
        phase = .result; return true
    }
}

public struct GameSessionData: Codable, Equatable, Sendable {
    public static let maximumRecords = 20_000
    public static let maximumSudokuSessions = 150
    private static let sudokuIDs = Set((try? SudokuPuzzle.bundled())?.map(\.id) ?? [])
    public enum ValidationError: Error { case invalid, historyLimit, duplicateRecord }
    public private(set) var records: [GamePlayRecord] = []
    public private(set) var statistics: [GameID: GameStatistics] = [:]
    public private(set) var clearedRecordIDs: Set<UUID> = []
    public var sessions: [GameID: GameSessionState] = [:] {
        didSet { trimClearedMarkers() }
    }
    public var sudokuSessions: [String: GameSessionState] = [:] {
        didSet { trimClearedMarkers() }
    }
    public var gamePreferences: [GameID: GamePlayPreferences] = [:]
    /// Undated totals copied once from released duel boards. A present zero
    /// value is an intentional migration/clear marker, never a missing value.
    public var legacyDuelStatistics: [GameID: DuelStatistics] = [:]
    public init() {}

    @discardableResult public mutating func append(_ record: GamePlayRecord) throws -> Bool {
        guard record.isValid, statistics.values.allSatisfy(\.isValid) else { throw ValidationError.invalid }
        if clearedRecordIDs.contains(record.id) { return false }
        if allStates.contains(where: { $0.id == record.sessionID && $0.recordID != nil && clearedRecordIDs.contains($0.recordID!) }) {
            throw ValidationError.duplicateRecord
        }
        if let existing = records.first(where: { $0.id == record.id || $0.sessionID == record.sessionID }) {
            guard existing == record else { throw ValidationError.duplicateRecord }
            return false
        }
        guard records.count < Self.maximumRecords else { throw ValidationError.historyLimit }
        records.append(record)
        var totals = statistics[record.gameID] ?? GameStatistics(); totals.include(record); statistics[record.gameID] = totals
        return true
    }

    public var isValid: Bool {
        let states = allStates
        guard records.count <= Self.maximumRecords, records.allSatisfy(\.isValid),
              Set(records.map(\.id)).count == records.count, Set(records.map(\.sessionID)).count == records.count,
              sessions.count <= GameID.allCases.count, gamePreferences.count <= GameID.allCases.count,
              legacyDuelStatistics.allSatisfy({ game, totals in
                  (game == .ticTacToe || game == .connectFour) && totals.isValid &&
                  totals.wins <= 1_000_000_000 && totals.draws <= 1_000_000_000 && totals.losses <= 1_000_000_000
              }),
              sudokuSessions.count <= Self.maximumSudokuSessions,
              Set(states.map(\.id)).count == states.count,
              gamePreferences.values.allSatisfy(\.isValid), clearedRecordIDs.count <= GameID.allCases.count + Self.maximumSudokuSessions,
              clearedRecordIDs.isDisjoint(with: Set(records.map(\.id))),
              clearedRecordIDs.isSubset(of: Set(states.compactMap(\.recordID))),
              sessions[.sudoku].map({ sudokuSessions[$0.mode] == nil }) ?? true,
              sudokuSessions.allSatisfy({ id, state in
                  Self.sudokuIDs.contains(id) && state.gameID == .sudoku && state.mode == id &&
                  state.phase != .playing && state.phase != .reviewing && state.pendingToken == nil
              }) else { return false }
        var expected: [GameID: GameStatistics] = [:]
        for record in records {
            var totals = expected[record.gameID] ?? GameStatistics(); totals.include(record); expected[record.gameID] = totals
        }
        guard statistics == expected else { return false }
        guard sessions.allSatisfy({ $0.key == $0.value.gameID }) else { return false }
        return states.allSatisfy { session in
            guard session.isValid else { return false }
            guard let recordID = session.recordID else { return !records.contains(where: { $0.sessionID == session.id }) }
            if clearedRecordIDs.contains(recordID) { return !records.contains { $0.sessionID == session.id } }
            return records.contains {
                $0.id == recordID && $0.sessionID == session.id && $0.gameID == session.gameID &&
                $0.elapsedSeconds == session.elapsedSeconds && $0.moves == session.moves &&
                $0.result == session.outcome &&
                $0.difficulty == session.difficulty && $0.mode == session.mode
            }
        }
    }

    public func scoped(to game: GameID) -> Self {
        var result = Self()
        for record in records where record.gameID == game { _ = try? result.append(record) }
        result.sessions[game] = sessions[game]; result.gamePreferences[game] = gamePreferences[game]
        result.legacyDuelStatistics[game] = legacyDuelStatistics[game]
        if game == .sudoku { result.sudokuSessions = sudokuSessions }
        result.clearedRecordIDs = clearedRecordIDs.intersection(Set(result.allStates.compactMap(\.recordID)))
        return result
    }

    public mutating func remove(_ game: GameID) {
        records.removeAll { $0.gameID == game }; statistics[game] = nil
        legacyDuelStatistics[game] = nil
        sessions[game] = nil; gamePreferences[game] = nil
        if game == .sudoku { sudokuSessions = [:] }
        trimClearedMarkers()
    }

    public mutating func clearRecords(for game: GameID? = nil) {
        let removed = records.filter { game == nil || $0.gameID == game }
        records.removeAll { game == nil || $0.gameID == game }
        clearedRecordIDs.formUnion(removed.map(\.id))
        trimClearedMarkers()
        statistics = [:]
        for existing in Array(legacyDuelStatistics.keys) where game == nil || existing == game {
            legacyDuelStatistics[existing] = DuelStatistics()
        }
        for record in records {
            var totals = statistics[record.gameID] ?? GameStatistics(); totals.include(record); statistics[record.gameID] = totals
        }
    }

    public mutating func replace(_ game: GameID, with imported: Self) throws {
        var next = self; next.remove(game)
        for record in imported.records where record.gameID == game { try next.append(record) }
        next.sessions[game] = imported.sessions[game]; next.gamePreferences[game] = imported.gamePreferences[game]
        next.legacyDuelStatistics[game] = imported.legacyDuelStatistics[game]
        if game == .sudoku { next.sudokuSessions = imported.sudokuSessions }
        next.clearedRecordIDs.formUnion(imported.clearedRecordIDs.intersection(Set(next.allStates.compactMap(\.recordID))))
        guard next.isValid else { throw ValidationError.invalid }
        self = next
    }

    /// An old completed save can be viewed without inventing when it was played
    /// or adding a new win to the 0.2.2 history. Only its immutable result identity
    /// is adopted, using the same bounded marker mechanism as cleared history.
    @discardableResult public mutating func adoptUntrackedFinishedSession(_ state: GameSessionState,
        outcome: GameOutcome, elapsedSeconds: Int, moves: Int) -> Bool {
        var finished = state
        guard let record = finished.finish(result: outcome, elapsedSeconds: elapsedSeconds, moves: moves,
                                            at: max(Date(), state.startedAt)) else { return false }
        var next = self
        next.sessions[state.gameID] = finished; next.clearedRecordIDs.insert(record.id)
        guard next.isValid else { return false }
        self = next; return true
    }

    @discardableResult public mutating func parkSudokuSession() -> Bool {
        guard isValid, var state = sessions[.sudoku], Self.sudokuIDs.contains(state.mode),
              sudokuSessions[state.mode] == nil else { return false }
        if let token = state.pendingToken { _ = state.cancelConfirmation(token) }
        if state.phase == .playing { _ = state.pause() }
        if state.phase == .reviewing { _ = state.showResult() }
        sudokuSessions[state.mode] = state; sessions[.sudoku] = nil
        return true
    }

    @discardableResult public mutating func restoreSudokuSession(puzzleID: String) -> Bool {
        guard isValid, sessions[.sudoku] == nil, let state = sudokuSessions[puzzleID] else { return false }
        sessions[.sudoku] = state; sudokuSessions[puzzleID] = nil
        return true
    }

    private var allStates: [GameSessionState] { Array(sessions.values) + Array(sudokuSessions.values) }
    private mutating func trimClearedMarkers() {
        clearedRecordIDs.formIntersection(Set(allStates.compactMap(\.recordID)))
    }
}

private func validSessionLabel(_ value: String) -> Bool {
    value.utf8.count <= 128 && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
}
private func validSessionDate(_ date: Date) -> Bool {
    date.timeIntervalSince1970.isFinite && (0...253_402_300_799).contains(date.timeIntervalSince1970)
}
