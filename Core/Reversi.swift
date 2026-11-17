import Foundation

public struct ReversiBoard: Codable, Equatable, Sendable {
    public private(set) var cells: [Int]
    public private(set) var currentPlayer = DuelPlayer.first
    public private(set) var moves = 0
    public private(set) var lastPassedPlayer: DuelPlayer?
    public init() {
        cells = Array(repeating: 0, count: 64)
        cells[27] = 2; cells[28] = 1; cells[35] = 1; cells[36] = 2
    }
    public func captures(at index: Int, player: DuelPlayer) -> [Int] {
        guard cells.count == 64, cells.indices.contains(index), cells[index] == 0 else { return [] }
        var captured: [Int] = []
        for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
            var x = index%8+dx, y = index/8+dy, line: [Int] = []
            while (0..<8).contains(x), (0..<8).contains(y), cells[y*8+x] == player.opponent.rawValue { line.append(y*8+x); x += dx; y += dy }
            if !line.isEmpty, (0..<8).contains(x), (0..<8).contains(y), cells[y*8+x] == player.rawValue { captured += line }
        }}
        return captured
    }
    public func legalMoves(for player: DuelPlayer) -> [Int] { cells.indices.filter { !captures(at:$0,player:player).isEmpty } }
    public var isFinished: Bool { legalMoves(for:.first).isEmpty && legalMoves(for:.second).isEmpty }
    public func count(_ player: DuelPlayer) -> Int { cells.filter { $0 == player.rawValue }.count }
    public var winner: DuelPlayer? { guard isFinished, count(.first) != count(.second) else { return nil }; return count(.first)>count(.second) ? .first : .second }
    public var isValidSave: Bool {
        cells.count == 64 && cells.allSatisfy { (0...2).contains($0) } && (0...60).contains(moves) && cells.filter { $0>0 }.count == moves+4 &&
        (isFinished || !legalMoves(for:currentPlayer).isEmpty)
    }
    @discardableResult public mutating func place(_ index: Int) -> Bool {
        guard !isFinished else { return false }; let captured = captures(at:index,player:currentPlayer)
        guard !captured.isEmpty else { return false }
        for i in captured + [index] { cells[i] = currentPlayer.rawValue }
        moves += 1; currentPlayer = currentPlayer.opponent; lastPassedPlayer = nil
        if legalMoves(for:currentPlayer).isEmpty && !isFinished { lastPassedPlayer = currentPlayer; currentPlayer = currentPlayer.opponent }
        return true
    }
    public func recommendedMove(difficulty: DuelDifficulty, seed: UInt64) -> Int? {
        let legal = legalMoves(for:currentPlayer); var random = SeededRandom(seed: seed &+ UInt64(moves))
        if difficulty == .easy { return legal.randomElement(using:&random) }
        let perspective = currentPlayer
        func evaluate(_ board: Self) -> Int {
            if board.isFinished { return board.winner == perspective ? 100_000 : board.winner == nil ? 0 : -100_000 }
            let corners = [0,7,56,63].reduce(0) { $0 + (board.cells[$1] == perspective.rawValue ? 800 : board.cells[$1] == perspective.opponent.rawValue ? -800 : 0) }
            let danger = [1,8,9,6,14,15,48,49,57,54,55,62].reduce(0) { $0 + (board.cells[$1] == perspective.rawValue ? -35 : board.cells[$1] == perspective.opponent.rawValue ? 35 : 0) }
            return corners+danger+(board.legalMoves(for:perspective).count-board.legalMoves(for:perspective.opponent).count)*12+board.count(perspective)-board.count(perspective.opponent)
        }
        func minimax(_ board: Self, depth: Int) -> Int {
            guard depth>0, !board.isFinished else { return evaluate(board) }
            let values = board.legalMoves(for:board.currentPlayer).map { i -> Int in var next = board; _ = next.place(i); return minimax(next,depth:depth-1) }
            return board.currentPlayer == perspective ? values.max() ?? evaluate(board) : values.min() ?? evaluate(board)
        }
        return legal.max { a,b in
            var left = self, right = self; _ = left.place(a); _ = right.place(b)
            return minimax(left,depth:difficulty == .hard ? 2 : 0) < minimax(right,depth:difficulty == .hard ? 2 : 0)
        }
    }
}
