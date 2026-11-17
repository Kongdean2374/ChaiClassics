import Foundation

/// A standard seven-column, six-row gravity game. Only move histories are saved:
/// cells, turns and results are derived by replay, so a save cannot forge a win.
public struct ConnectFourBoard: Codable, Equatable, Sendable {
    public static let columns = 7
    public static let rows = 6
    public static let maximumAINodes = 20_000

    public let mode: DuelMode
    public let difficulty: DuelDifficulty
    public let humanPlayer: DuelPlayer
    public let seed: UInt64
    public private(set) var history: [Int]
    public var elapsedSeconds: Int
    private var completedRounds: [CompletedRound]

    private struct CompletedRound: Codable, Equatable, Sendable {
        let history: [Int]
        let perspective: DuelPlayer
    }

    public init(mode: DuelMode = .singlePlayer, difficulty: DuelDifficulty = .normal,
                humanPlayer: DuelPlayer = .first, seed: UInt64) {
        self.mode = mode; self.difficulty = difficulty; self.humanPlayer = humanPlayer
        self.seed = seed; history = []; elapsedSeconds = 0; completedRounds = []
    }

    public init(mode: DuelMode = .singlePlayer, difficulty: DuelDifficulty = .normal,
                humanPlayer: DuelPlayer = .first) {
        var random = SystemRandomNumberGenerator()
        self.init(mode: mode, difficulty: difficulty, humanPlayer: humanPlayer, seed: random.next())
    }

    public var cells: [DuelPlayer?] {
        (Self.replay(history)?.cells ?? Array(repeating: 0, count: 42)).map { DuelPlayer(rawValue: Int($0)) }
    }
    public var moves: Int { history.count }
    public var currentPlayer: DuelPlayer { history.count.isMultiple(of: 2) ? .first : .second }
    public var winner: DuelPlayer? {
        guard let position = Self.replay(history) else { return nil }
        return DuelPlayer(rawValue: Int(position.winner))
    }
    public var winningLine: [Int] { Self.replay(history)?.winningLine ?? [] }
    public var isDraw: Bool { history.count == 42 && winner == nil }
    public var isFinished: Bool { winner != nil || history.count >= 42 }
    public var isComputerTurn: Bool { mode == .singlePlayer && !isFinished && currentPlayer != humanPlayer }

    /// Single player records are from the human's perspective. Local records are
    /// from player one's perspective. Clearing records also clears their replay data.
    public var statistics: DuelStatistics {
        var result = DuelStatistics()
        for round in completedRounds {
            guard let position = Self.replay(round.history), position.finished else { continue }
            result.record(winner: DuelPlayer(rawValue: Int(position.winner)), humanPlayer: round.perspective)
        }
        return result
    }

    public var isValidSave: Bool {
        guard elapsedSeconds >= 0, elapsedSeconds <= 31_536_000,
              Self.replay(history) != nil else { return false }
        return completedRounds.allSatisfy { round in Self.replay(round.history)?.finished == true }
    }

    public func canDrop(in column: Int) -> Bool {
        guard let position = Self.replay(history), !position.finished,
              (0..<7).contains(column) else { return false }
        return position.heights[column] < 6
    }

    /// The explicit player rejects wrong-turn input as well as occupied/full and
    /// terminal input. A successful move is the sole way to append a round result.
    @discardableResult public mutating func drop(in column: Int, player: DuelPlayer) -> Bool {
        guard player == currentPlayer, isValidSave, canDrop(in: column) else { return false }
        history.append(column)
        if let position = Self.replay(history), position.finished {
            completedRounds.append(CompletedRound(history: history, perspective: mode == .singlePlayer ? humanPlayer : .first))
        }
        return true
    }

    public mutating func restart() { history = []; elapsedSeconds = 0 }
    public mutating func clearStatistics() { completedRounds = [] }

    /// Creates a fresh configured round while retaining the explicitly clearable records.
    public func newRound(mode: DuelMode, difficulty: DuelDifficulty, humanPlayer: DuelPlayer, seed: UInt64) -> Self {
        var next = Self(mode: mode, difficulty: difficulty, humanPlayer: humanPlayer, seed: seed)
        next.completedRounds = completedRounds
        return next
    }

    public struct AIAnalysis: Equatable, Sendable {
        public let column: Int?
        public let visitedNodes: Int
    }

    public func recommendedMove() -> Int? { analyzeMove().column }

    /// The hard search has a deterministic node budget, never an unbounded tree.
    /// Call from a background task in UI code. Normal and hard win or block in one.
    public func analyzeMove() -> AIAnalysis {
        guard var position = Self.replay(history), !position.finished else { return AIAnalysis(column: nil, visitedNodes: 0) }
        var random = SeededRandom(seed: seed ^ UInt64(history.count) &* 0x9e3779b97f4a7c15)
        let legal = position.legalColumns
        if difficulty == .easy { return AIAnalysis(column: legal.randomElement(using: &random), visitedNodes: 0) }
        let player = position.turn
        let wins = legal.filter { position.wins(in: $0, for: player) }
        if let column = wins.randomElement(using: &random) { return AIAnalysis(column: column, visitedNodes: 0) }
        let blocks = legal.filter { position.wins(in: $0, for: 3 - player) }
        if blocks.count == 1 { return AIAnalysis(column: blocks[0], visitedNodes: 0) }

        let depth = difficulty == .hard ? 6 : 3
        let budget = difficulty == .hard ? Self.maximumAINodes : 2_000
        var search = Search(budget: budget)
        var best = Int.min
        var choices: [Int] = []
        for column in legal {
            let row = position.make(column)
            let score = -search.negamax(&position, depth: depth - 1, alpha: -1_000_000, beta: 1_000_000)
            position.undo(column, row: row)
            if score > best { best = score; choices = [column] }
            else if score == best { choices.append(column) }
        }
        return AIAnalysis(column: choices.randomElement(using: &random), visitedNodes: search.nodes)
    }

    private static func replay(_ history: [Int]) -> Position? {
        guard history.count <= 42 else { return nil }
        var position = Position()
        for column in history {
            guard (0..<7).contains(column), !position.finished, position.heights[column] < 6 else { return nil }
            _ = position.make(column)
        }
        return position
    }

    private struct Position {
        var cells = [Int8](repeating: 0, count: 42)
        var heights = [Int](repeating: 0, count: 7)
        var count = 0
        var turn: Int8 = 1
        var winner: Int8 = 0
        var winningLine: [Int] = []
        var finished: Bool { winner != 0 || count == 42 }
        var legalColumns: [Int] { [3, 2, 4, 1, 5, 0, 6].filter { heights[$0] < 6 } }
        mutating func make(_ column: Int) -> Int {
            let row = 5 - heights[column]
            let index = row * 7 + column
            cells[index] = turn; heights[column] += 1; count += 1
            winningLine = line(at: index, player: turn)
            winner = winningLine.isEmpty ? 0 : turn
            turn = 3 - turn
            return row
        }
        mutating func undo(_ column: Int, row: Int) {
            cells[row * 7 + column] = 0; heights[column] -= 1; count -= 1
            turn = 3 - turn; winner = 0; winningLine = []
        }
        mutating func wins(in column: Int, for player: Int8) -> Bool {
            let index = (5 - heights[column]) * 7 + column
            cells[index] = player
            let result = !line(at: index, player: player).isEmpty
            cells[index] = 0
            return result
        }
        func line(at index: Int, player: Int8) -> [Int] {
            let row = index / 7, column = index % 7
            for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
                var indices = [index]
                for sign in [-1, 1] {
                    var r = row + dr * sign, c = column + dc * sign
                    while (0..<6).contains(r), (0..<7).contains(c), cells[r * 7 + c] == player {
                        indices.append(r * 7 + c); r += dr * sign; c += dc * sign
                    }
                }
                if indices.count >= 4 { return indices.sorted() }
            }
            return []
        }
        func evaluation() -> Int {
            var result = 0
            for row in 0..<6 {
                let owner = cells[row * 7 + 3]
                if owner != 0 { result += owner == turn ? 5 : -5 }
            }
            for row in 0..<6 {
                for col in 0..<7 {
                    for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
                        let endRow = row + 3 * dr, endCol = col + 3 * dc
                        guard (0..<6).contains(endRow), (0..<7).contains(endCol) else { continue }
                        var own = 0, opponent = 0
                        for step in 0..<4 {
                            let owner = cells[(row + step * dr) * 7 + col + step * dc]
                            if owner == turn { own += 1 }
                            else if owner != 0 { opponent += 1 }
                        }
                        let weights = [0, 1, 8, 55, 10_000]
                        if opponent == 0 { result += weights[own] }
                        if own == 0 { result -= weights[opponent] }
                    }
                }
            }
            return result
        }
    }

    private struct Search {
        let budget: Int
        var nodes = 0
        mutating func negamax(_ position: inout Position, depth: Int, alpha: Int, beta: Int) -> Int {
            if position.winner != 0 { return -100_000 - depth }
            if position.count == 42 { return 0 }
            guard nodes < budget else { return position.evaluation() }
            nodes += 1
            guard depth > 0 else { return position.evaluation() }
            var best = Int.min, lower = alpha
            for column in position.legalColumns {
                let row = position.make(column)
                let score = -negamax(&position, depth: depth - 1, alpha: -beta, beta: -lower)
                position.undo(column, row: row)
                best = max(best, score); lower = max(lower, score)
                if lower >= beta { break }
            }
            return best
        }
    }
}
