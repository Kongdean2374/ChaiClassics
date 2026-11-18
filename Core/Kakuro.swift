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
        let side = self.size - 1
        let layout = Self.layouts[side]!.randomElement(using: &random)!
        let transform = Int.random(in: 0..<8, using: &random)
        let rowOffsets = Array(0..<9).shuffled(using: &random)
        let columnOffsets = Array(0..<9).shuffled(using: &random)
        var answer = Array(repeating: -1, count: self.size * self.size)
        for i in 0..<(side * side) {
            let source = PuzzleSymmetry.sourceIndex(i, size: side, transform: transform)
            guard layout[source / side] & (1 << (source % side)) != 0 else { continue }
            let row = i / side, column = i % side
            answer[(row + 1) * self.size + column + 1] = digits[(rowOffsets[row] + columnOffsets[column]) % 9]
        }
        solution = answer
        let clues = Self.runs(answer, size: self.size)
        var fixed = answer
        // Remove givens only after the independent solver proves uniqueness.
        // Starting with a complete valid cross avoids an exponential search on
        // a large empty board. A bounded inconclusive search keeps the given.
        var order = answer.indices.filter { answer[$0] > 0 }; order.shuffle(using: &random)
        var budget = 1_800
        for index in order where budget > 0 {
            fixed[index] = 0
            var used = 0
            let results = Self.solve(cells: fixed, runs: clues, limit: 2, nodeLimit: min(128, budget), nodes: &used)
            budget -= used
            if results.count != 1 { fixed[index] = answer[index] }
        }
        givens = fixed; cells = fixed
    }
    // Inner rows as bitmasks. Each playable cell belongs to two runs of at
    // least two cells, with the clue border kept outside all transformations.
    private static let layouts: [Int: [[Int]]] = [
        3: [[0b111, 0b111, 0b111], [0b111, 0b111, 0b011], [0b110, 0b111, 0b011]],
        5: [
            [0b11100, 0b11111, 0b11011, 0b11111, 0b00111],
            [0b11100, 0b11100, 0b11111, 0b00111, 0b00111],
            [0b01111, 0b01111, 0b11011, 0b11110, 0b11110]
        ],
        7: [
            [0b1111000, 0b1111000, 0b1111111, 0b1110111, 0b1111111, 0b0001111, 0b0001111],
            [0b1111110, 0b1111110, 0b1111111, 0b1110111, 0b1111111, 0b0111111, 0b0111111],
            [0b1111100, 0b1111100, 0b1111111, 0b1100011, 0b1111111, 0b0011111, 0b0011111]
        ]
    ]
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
        var nodes = 0
        return solve(cells: cells, runs: runs, limit: limit, nodeLimit: 256, nodes: &nodes)
    }

    private static let digitMasks: [[Int]] = {
        var masks = Array(repeating: [Int](), count: 10 * 46)
        for mask in 0..<512 {
            let sum = (1...9).reduce(0) { $0 + (mask & (1 << ($1 - 1)) != 0 ? $1 : 0) }
            masks[mask.nonzeroBitCount * 46 + sum].append(mask)
        }
        return masks
    }()

    private static func solve(cells: [Int], runs: [KakuroRun], limit: Int, nodeLimit: Int, nodes: inout Int) -> [[Int]] {
        guard (1...2).contains(limit), !runs.isEmpty, runs.allSatisfy({ run in
            (2...9).contains(run.cells.count) && (1...45).contains(run.total) &&
                run.cells.allSatisfy { cells.indices.contains($0) && (0...9).contains(cells[$0]) }
        }) else { return [] }
        var affected = Array(repeating: [Int](), count: cells.count)
        for (i, run) in runs.enumerated() { for cell in run.cells { affected[cell].append(i) } }
        guard cells.indices.allSatisfy({ cells[$0] != 0 || !affected[$0].isEmpty }) else { return [] }
        var board = cells, answers: [[Int]] = [], exhausted = false
        func legal(_ run: KakuroRun) -> Bool {
            var used = 0, missing = 0, remaining = run.total
            for cell in run.cells {
                let digit = board[cell]
                if digit == 0 { missing += 1; continue }
                let bit = 1 << (digit - 1)
                guard used & bit == 0 else { return false }
                used |= bit
                remaining -= digit
            }
            guard (0...45).contains(remaining) else { return false }
            return digitMasks[missing * 46 + remaining].contains { $0 & used == 0 }
        }
        func search() {
            guard !exhausted, answers.count < limit else { return }
            guard nodes < nodeLimit else { exhausted = true; return }; nodes += 1
            guard runs.allSatisfy(legal) else { return }
            var chosen: Int?, options: [Int] = []
            for i in board.indices where board[i] == 0 {
                var possible: [Int] = []
                for value in 1...9 {
                    board[i] = value
                    if affected[i].allSatisfy({ legal(runs[$0]) }) { possible.append(value) }
                }
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
