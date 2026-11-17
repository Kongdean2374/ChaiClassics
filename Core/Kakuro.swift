import Foundation

public struct KakuroRun: Codable, Equatable, Sendable {
    public let cells: [Int]
    public let total: Int
    public let horizontal: Bool
    public let clueIndex: Int
}

/// Cross sums: each run totals its clue using distinct digits 1...9. Fixed
/// starting digits are explicit ivory givens; player digits remain blue.
public struct KakuroBoard: Codable, Equatable, Sendable {
    public let size: Int
    public let seed: UInt64
    public let solution: [Int] // -1 black, otherwise 1...9
    public let givens: [Int]
    public private(set) var cells: [Int]
    public private(set) var moves = 0
    public var runs: [KakuroRun] { Self.runs(solution, size: size) }
    public var isComplete: Bool {
        runs.allSatisfy { run in let values = run.cells.map { cells[$0] }; return values.allSatisfy { (1...9).contains($0) } && Set(values).count == values.count && values.reduce(0,+) == run.total }
    }
    public var isValidSave: Bool {
        guard [4, 6, 8].contains(size), solution.count == size * size, givens.count == solution.count, cells.count == solution.count,
              (0...1_000_000).contains(moves) else { return false }
        guard solution.indices.allSatisfy({ i in
            solution[i] == -1 ? givens[i] == -1 && cells[i] == -1 : (1...9).contains(solution[i]) && (0...9).contains(cells[i]) && (givens[i] == 0 || givens[i] == solution[i] && cells[i] == givens[i])
        }) else { return false }
        let all = runs
        return !all.isEmpty && all.allSatisfy { (2...9).contains($0.cells.count) && Set($0.cells.map { solution[$0] }).count == $0.cells.count } &&
            solution.indices.filter { solution[$0] > 0 }.allSatisfy { cell in all.filter { $0.cells.contains(cell) }.count == 2 }
    }

    public init(size: Int, seed: UInt64) {
        self.size = [4, 6, 8].contains(size) ? size : 4; self.seed = seed
        var random = SeededRandom(seed: seed), digits = Array(1...9); digits.shuffle(using: &random)
        var answer = Array(repeating: -1, count: self.size * self.size)
        for r in 1..<self.size { for c in 1..<self.size { answer[r * self.size + c] = digits[(r + c) % 9] } }
        solution = answer
        var fixed = answer
        // Remove givens only after the independent solver proves uniqueness.
        // Starting with a complete valid cross avoids an exponential search on
        // a large empty board. A bounded inconclusive search keeps the given.
        var order = answer.indices.filter { answer[$0] > 0 }; order.shuffle(using: &random)
        for index in order {
            fixed[index] = 0
            if Self.solutions(cells: fixed, runs: Self.runs(answer, size: self.size), limit: 2).count != 1 { fixed[index] = answer[index] }
        }
        givens = fixed; cells = fixed
    }
    @discardableResult public mutating func enter(_ value: Int, at index: Int) -> Bool {
        guard isValidSave, !isComplete, cells.indices.contains(index), givens[index] == 0, (0...9).contains(value), cells[index] != value, moves < 1_000_000 else { return false }
        cells[index] = value; moves += 1; return true
    }
    private static func runs(_ answer: [Int], size: Int) -> [KakuroRun] {
        guard answer.count == size * size else { return [] }
        var result: [KakuroRun] = []
        for i in answer.indices where answer[i] == -1 {
            for horizontal in [true, false] {
                let delta = horizontal ? 1 : size
                var cursor = i + delta, cells: [Int] = []
                while cursor < answer.count, (!horizontal || cursor / size == i / size), answer[cursor] > 0 {
                    cells.append(cursor); cursor += delta
                }
                if !cells.isEmpty { result.append(KakuroRun(cells: cells, total: cells.map { answer[$0] }.reduce(0,+), horizontal: horizontal, clueIndex: i)) }
            }
        }
        return result
    }
    public static func solutions(cells: [Int], runs: [KakuroRun], limit: Int = 2) -> [[Int]] {
        guard (1...2).contains(limit), !runs.isEmpty, runs.allSatisfy({ (2...9).contains($0.cells.count) && $0.cells.allSatisfy(cells.indices.contains) }) else { return [] }
        var board = cells, answers: [[Int]] = [], nodes = 0, exhausted = false
        func legal(_ run: KakuroRun) -> Bool {
            let set = run.cells.map { board[$0] }, values = set.filter { $0 > 0 }, missing = set.filter { $0 == 0 }.count
            guard Set(values).count == values.count else { return false }
            let available = (1...9).filter { !values.contains($0) }, remaining = run.total - values.reduce(0,+)
            return missing == 0 ? remaining == 0 : available.prefix(missing).reduce(0,+) <= remaining && available.suffix(missing).reduce(0,+) >= remaining
        }
        func search() {
            guard answers.count < limit else { return }
            guard nodes < 256 else { exhausted = true; return }; nodes += 1
            guard runs.allSatisfy(legal) else { return }
            var chosen: Int?, options: [Int] = []
            for i in board.indices where board[i] == 0 {
                let affected = runs.filter { $0.cells.contains(i) }
                var possible: [Int] = []
                for value in 1...9 { board[i] = value; if affected.allSatisfy(legal) { possible.append(value) } }
                board[i] = 0
                if possible.isEmpty { return }
                if chosen == nil || possible.count < options.count { chosen = i; options = possible }
                if options.count == 1 { break }
            }
            guard let chosen else { answers.append(board); return }
            for value in options { board[chosen] = value; search(); if answers.count >= limit { break } }; board[chosen] = 0
        }
        search(); return exhausted ? [] : answers
    }
}
