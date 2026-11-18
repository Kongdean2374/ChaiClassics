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
        // Prefer a new mosaic, but cap work across all attempts. An unfinished
        // uniqueness search is never accepted as a proof.
        var image: [Bool] = []
        for _ in 0..<6 {
            let candidate = (0..<(n * n)).map { _ in Int.random(in: 0..<100, using: &random) < 60 }
            if candidate.contains(true), candidate.contains(false),
               Self.solve(rows: Self.rows(candidate, n), columns: Self.columns(candidate, n),
                          limit: 2, nodeLimit: 64) == [candidate] {
                image = candidate
                break
            }
        }
        if image.isEmpty {
            let template = Self.fallbackRows[n]!.randomElement(using: &random)!
            image = Self.transformedTemplate(template, transform: Int.random(in: 0..<8, using: &random))
        }
        solution = image; marks = Array(repeating: 0, count: image.count)
    }

    // Prevalidated independent mosaics, encoded as row bitmasks.
    // All eight rotations/reflections preserve uniqueness and regenerate clues.
    static let fallbackRows: [Int: [[Int]]] = [
        5: [
            [0x13, 0x18, 0x1a, 0x10, 0x18],
            [0x0f, 0x13, 0x19, 0x10, 0x17],
            [0x18, 0x1d, 0x1a, 0x19, 0x1e],
            [0x15, 0x03, 0x17, 0x0b, 0x18],
            [0x07, 0x12, 0x0c, 0x1e, 0x0a],
            [0x17, 0x08, 0x0c, 0x09, 0x13],
        ],
        10: [
            [0x366, 0x16e, 0x37b, 0x172, 0x076, 0x2fe, 0x3f4, 0x3f7, 0x36f, 0x3f7],
            [0x2f5, 0x353, 0x2fc, 0x3d0, 0x236, 0x115, 0x175, 0x345, 0x36c, 0x294],
            [0x24c, 0x1be, 0x08b, 0x3db, 0x1e4, 0x33f, 0x112, 0x3a7, 0x1c9, 0x27d],
            [0x0b2, 0x183, 0x07f, 0x06f, 0x370, 0x0af, 0x1e4, 0x09d, 0x372, 0x2cc],
            [0x3bd, 0x27d, 0x24c, 0x3c0, 0x0fd, 0x156, 0x06c, 0x39f, 0x3f9, 0x37e],
            [0x1bb, 0x3a4, 0x1af, 0x166, 0x2df, 0x157, 0x2d7, 0x2ff, 0x2ec, 0x107],
        ],
        15: [
            [0x074d, 0x59be, 0x73fe, 0x2f33, 0x7b9f, 0x366e, 0x7bdf, 0x54ef, 0x6f9b, 0x2f73, 0x7ab5, 0x577d, 0x1ede, 0x6ee5, 0x5fd7],
            [0x5be7, 0x64f6, 0x7c93, 0x145b, 0x4b62, 0x7fcd, 0x357b, 0x6dd6, 0x5527, 0x7d7f, 0x3d15, 0x6ff7, 0x270f, 0x76aa, 0x7f83],
            [0x7bd7, 0x1942, 0x7ebe, 0x3bdb, 0x3eb3, 0x0be6, 0x077e, 0x1d8f, 0x165a, 0x2bb1, 0x66b0, 0x57f8, 0x75d5, 0x7d3f, 0x4bbf],
            [0x29f1, 0x46dc, 0x5fff, 0x4f7d, 0x7daf, 0x5e3c, 0x4d30, 0x55ff, 0x0cc3, 0x1eae, 0x5fef, 0x2c8d, 0x6974, 0x7ffb, 0x73fb],
            [0x37dd, 0x5669, 0x5e7e, 0x0f23, 0x0569, 0x38b8, 0x5636, 0x4e90, 0x2ed5, 0x6c1d, 0x63bd, 0x215b, 0x4df0, 0x2b65, 0x5b75],
            [0x75ff, 0x0baf, 0x1a96, 0x579b, 0x753a, 0x1fb8, 0x5ef4, 0x69ed, 0x63be, 0x0f67, 0x1e91, 0x7af7, 0x1d69, 0x5a37, 0x61f1],
        ]
    ]

    static func transformedTemplate(_ rows: [Int], transform: Int) -> [Bool] {
        let size = rows.count
        return (0..<(size * size)).map { index in
            let source = PuzzleSymmetry.sourceIndex(index, size: size, transform: transform)
            return rows[source / size] & (1 << (source % size)) != 0
        }
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
        solve(rows: rows, columns: columns, limit: limit, nodeLimit: 30_000)
    }

    private static func solve(rows: [[Int]], columns: [[Int]], limit: Int, nodeLimit: Int) -> [[Bool]] {
        let n = rows.count
        guard (1...15).contains(n), columns.count == n, (1...2).contains(limit) else { return [] }
        func patterns(_ clue: [Int]) -> [[Bool]] {
            if clue == [0] { return [Array(repeating: false, count: n)] }
            guard !clue.isEmpty, clue.allSatisfy({ (1...n).contains($0) }), clue.reduce(0,+) + clue.count - 1 <= n else { return [] }
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
            guard !exhausted, answers.count < limit else { return }
            guard nodes < nodeLimit else { exhausted = true; return }; nodes += 1
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
            for pattern in row[index] { var next = row; next[index] = [pattern]; search(next, column); if exhausted || answers.count >= limit { return } }
        }
        search(rows.map(patterns), columns.map(patterns)); return exhausted ? [] : answers
    }
}
