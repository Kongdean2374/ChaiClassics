import Foundation

/// Freestyle Gomoku: black starts; five or more consecutive stones win.
public struct GomokuBoard: Codable, Equatable, Sendable {
    public static let size = 15
    public private(set) var cells = Array(repeating: 0, count: 225)
    public private(set) var currentPlayer = DuelPlayer.first
    public private(set) var history: [Int] = []
    public init() {}
    public var winner: DuelPlayer? {
        for i in cells.indices where cells[i] > 0 {
            for (dx,dy) in [(1,0),(0,1),(1,1),(1,-1)] {
                var count = 1, x = i%15+dx, y = i/15+dy
                while (0..<15).contains(x), (0..<15).contains(y), cells[y*15+x] == cells[i] { count += 1; x += dx; y += dy }
                if count >= 5 { return DuelPlayer(rawValue: cells[i]) }
            }
        }
        return nil
    }
    public var isFinished: Bool { winner != nil || !cells.contains(0) }
    public var isValidSave: Bool {
        guard cells.count == 225, history.count <= 225, Set(history).count == history.count, history.allSatisfy(cells.indices.contains),
              cells.allSatisfy({ (0...2).contains($0) }), cells.filter({$0>0}).count == history.count else { return false }
        guard history.enumerated().allSatisfy({ cells[$0.element] == $0.offset%2+1 }), currentPlayer.rawValue == history.count%2+1 else { return false }
        var replay = Self()
        for i in history { if !replay.place(i) { return false } }
        return replay.cells==cells
    }
    @discardableResult public mutating func place(_ index: Int) -> Bool {
        guard cells.count == 225, !isFinished, cells.indices.contains(index), cells[index] == 0 else { return false }
        cells[index] = currentPlayer.rawValue; history.append(index); currentPlayer = currentPlayer.opponent; return true
    }
    public func recommendedMove(difficulty: DuelDifficulty, seed: UInt64) -> Int? {
        guard !isFinished else { return nil }
        let legal = cells.indices.filter { cells[$0] == 0 }
        var random = SeededRandom(seed: seed &+ UInt64(history.count))
        if difficulty == .easy { return legal.randomElement(using: &random) }
        if history.isEmpty { return 112 }
        for player in [currentPlayer,currentPlayer.opponent] {
            for index in legal { var next = self; next.currentPlayer = player; _ = next.place(index); if next.winner == player { return index } }
        }
        func score(_ index: Int, _ player: DuelPlayer) -> Int {
            var score = 0
            for (dx,dy) in [(1,0),(0,1),(1,1),(1,-1)] {
                var count = 1, open = 0
                for direction in [-1,1] {
                    var x = index%15+dx*direction, y = index/15+dy*direction
                    while (0..<15).contains(x), (0..<15).contains(y), cells[y*15+x] == player.rawValue { count += 1; x += dx*direction; y += dy*direction }
                    if (0..<15).contains(x), (0..<15).contains(y), cells[y*15+x] == 0 { open += 1 }
                }
                if open > 0 { score += [0,2,12,100,2000,100_000][min(count,5)] * open }
            }
            return score
        }
        let candidates = legal.filter { i in history.contains { abs($0%15-i%15) <= 2 && abs($0/15-i/15) <= 2 } }
        return candidates.max { a,b in
            let defensive = difficulty == .hard ? 2 : 1
            return score(a,currentPlayer)*2+score(a,currentPlayer.opponent)*defensive < score(b,currentPlayer)*2+score(b,currentPlayer.opponent)*defensive
        }
    }
}
