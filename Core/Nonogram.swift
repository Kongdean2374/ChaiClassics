import Foundation

public struct NonogramBoard: Codable, Equatable, Sendable {
    public let size: Int
    public let seed: UInt64
    public let solution: [Bool]
    /// 0: undecided, 1: filled, -1: crossed out. No incorrect-cell feedback.
    public private(set) var marks: [Int]
    public private(set) var moves = 0
    public var rowClues: [[Int]] { (0..<size).map { Self.clues(Array(solution[($0 * size)..<(($0 + 1) * size)])) } }
    public var columnClues: [[Int]] { (0..<size).map { column in Self.clues((0..<size).map { solution[$0 * size + column] }) } }
    public var isComplete: Bool { zip(marks, solution).allSatisfy { ($0 == 1) == $1 } }
    public var isValidSave: Bool {
        [5, 10, 15].contains(size) && solution.count == size * size && marks.count == solution.count &&
        marks.allSatisfy { (-1...1).contains($0) } && solution.contains(true) && solution.contains(false) && (0...1_000_000).contains(moves)
    }

    public init(size: Int, seed: UInt64) {
        self.size = [5, 10, 15].contains(size) ? size : 5; self.seed = seed
        let n = self.size
        var random = SeededRandom(seed: seed)
        // Regenerate ambiguous pictures. The fallback is a transformed staircase,
        // whose extreme full/empty lines propagate to a unique solution.
        var image: [Bool] = []
        for _ in 0..<32 {
            let candidate = (0..<(n * n)).map { _ in Int.random(in: 0..<100, using: &random) < 60 }
            if candidate.contains(false), Self.solutions(rows: Self.rows(candidate, n), columns: Self.columns(candidate, n), limit: 2).count == 1 {
                image = candidate; break
            }
        }
        if image.isEmpty {
            let mirrored = random.next() & 1 == 1, inverted = random.next() & 1 == 1
            image = (0..<(n * n)).map { index in
                let r = index / n, c = mirrored ? n - 1 - index % n : index % n
                return inverted ? c > r : c <= r
            }
        }
        solution = image; marks = Array(repeating: 0, count: image.count)
    }

    @discardableResult public mutating func mark(_ index: Int, crossed: Bool) -> Bool {
        guard isValidSave, !isComplete, marks.indices.contains(index), moves < 1_000_000 else { return false }
        let value = crossed ? -1 : 1; marks[index] = marks[index] == value ? 0 : value; moves += 1; return true
    }

    public static func clues(_ line: [Bool]) -> [Int] {
        var result: [Int] = [], count = 0
        for value in line + [false] { if value { count += 1 } else if count > 0 { result.append(count); count = 0 } }
        return result.isEmpty ? [0] : result
    }
    private static func rows(_ cells: [Bool], _ size: Int) -> [[Int]] { (0..<size).map { clues(Array(cells[($0 * size)..<(($0 + 1) * size)])) } }
    private static func columns(_ cells: [Bool], _ size: Int) -> [[Int]] { (0..<size).map { c in clues((0..<size).map { cells[$0 * size + c] }) } }

    /// Independent clue solver. Enumerate line patterns, propagate both axes,
    /// then branch on the smallest remaining line; stop after `limit` answers.
    public static func solutions(rows: [[Int]], columns: [[Int]], limit: Int = 2) -> [[Bool]] {
        let n = rows.count
        guard (1...15).contains(n), columns.count == n, (1...2).contains(limit) else { return [] }
        func patterns(_ clue: [Int]) -> [[Bool]] {
            if clue == [0] { return [Array(repeating: false, count: n)] }
            guard !clue.isEmpty, clue.allSatisfy({ $0 > 0 }), clue.reduce(0,+) + clue.count - 1 <= n else { return [] }
            var output: [[Bool]] = []
            func add(_ block: Int, _ start: Int, _ line: [Bool]) {
                if block == clue.count { output.append(line); return }
                let reserve = clue[block...].reduce(0,+) + clue.count - block - 1
                guard start <= n - reserve else { return }
                for position in start...(n - reserve) {
                    var next = line
                    for i in position..<(position + clue[block]) { next[i] = true }
                    add(block + 1, position + clue[block] + 1, next)
                }
            }
            add(0, 0, Array(repeating: false, count: n)); return output
        }
        var answers: [[Bool]] = [], nodes = 0, exhausted = false
        func search(_ rowInput: [[[Bool]]], _ columnInput: [[[Bool]]]) {
            guard answers.count < limit else { return }
            guard nodes < 30_000 else { exhausted = true; return }; nodes += 1
            var row = rowInput, column = columnInput, changed = true
            while changed {
                changed = false
                for axis in 0..<2 {
                    for i in 0..<n {
                        let candidates = axis == 0 ? row[i] : column[i]
                        guard !candidates.isEmpty else { return }
                        for j in 0..<n where candidates.allSatisfy({ $0[j] == candidates[0][j] }) {
                            let before = axis == 0 ? column[j].count : row[j].count
                            if axis == 0 { column[j].removeAll { $0[i] != candidates[0][j] } }
                            else { row[j].removeAll { $0[i] != candidates[0][j] } }
                            if (axis == 0 ? column[j].count : row[j].count) != before { changed = true }
                        }
                    }
                }
            }
            guard !row.contains(where: \.isEmpty), !column.contains(where: \.isEmpty) else { return }
            if row.allSatisfy({ $0.count == 1 }) { answers.append(row.flatMap { $0[0] }); return }
            guard let index = row.indices.filter({ row[$0].count > 1 }).min(by: { row[$0].count < row[$1].count }) else { return }
            for pattern in row[index] { var next = row; next[index] = [pattern]; search(next, column); if answers.count >= limit { return } }
        }
        search(rows.map(patterns), columns.map(patterns)); return exhausted ? [] : answers
    }
}
