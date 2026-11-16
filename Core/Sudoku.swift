import Foundation

public enum SudokuDifficulty: String, Codable, CaseIterable, Sendable {
    case easy, medium, hard
    public var title: String { switch self { case .easy: return "簡單"; case .medium: return "中等"; case .hard: return "困難" } }
}

public struct SudokuPuzzle: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let difficulty: SudokuDifficulty
    public let number: Int
    public let givens: [Int]
    public init(id: String, difficulty: SudokuDifficulty, number: Int, givens: [Int]) {
        self.id = id; self.difficulty = difficulty; self.number = number; self.givens = givens
    }
    public static func bundled() throws -> [SudokuPuzzle] {
        guard let url = Bundle.module.url(forResource: "sudoku-v1", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode([SudokuPuzzle].self, from: Data(contentsOf: url))
    }
}

public enum SudokuRules {
    public static func validGivens(_ cells: [Int]) -> Bool {
        guard cells.count == 81, cells.allSatisfy({ (0...9).contains($0) }) else { return false }
        return units.allSatisfy { unit in
            let digits = unit.map { cells[$0] }.filter { $0 != 0 }
            return Set(digits).count == digits.count
        }
    }
    public static let units: [[Int]] = {
        var result = (0..<9).map { r in (0..<9).map { r * 9 + $0 } }
        result += (0..<9).map { c in (0..<9).map { $0 * 9 + c } }
        result += (0..<9).map { b in (0..<9).map { (b / 3 * 3 + $0 / 3) * 9 + b % 3 * 3 + $0 % 3 } }
        return result
    }()
    public static func isComplete(_ cells: [Int], givens: [Int]) -> Bool {
        guard validGivens(cells), givens.count == 81, !cells.contains(0) else { return false }
        return zip(cells, givens).allSatisfy { $1 == 0 || $0 == $1 }
    }
}

public struct SudokuBoard: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable { case answer, pencil }
    public let puzzleID: String
    public private(set) var cells: [Int]
    public private(set) var notes: [Set<Int>]
    public var mode: Mode = .answer
    public var selected: Int?
    public init(puzzle: SudokuPuzzle) {
        puzzleID = puzzle.id; cells = puzzle.givens; notes = Array(repeating: [], count: 81)
    }
    public func isValidSave(for puzzle: SudokuPuzzle) -> Bool {
        puzzleID == puzzle.id && cells.count == 81 && notes.count == 81 &&
        cells.allSatisfy { (0...9).contains($0) } && notes.allSatisfy { $0.isSubset(of: Set(1...9)) } &&
        zip(cells, puzzle.givens).allSatisfy { $1 == 0 || $0 == $1 } &&
        (selected == nil || (0..<81).contains(selected!))
    }
    public mutating func enter(_ digit: Int, puzzle: SudokuPuzzle) {
        guard (1...9).contains(digit), let i = selected, (0..<81).contains(i), puzzle.givens[i] == 0 else { return }
        if mode == .answer { cells[i] = digit; notes[i] = [] }
        else {
            guard cells[i] == 0 else { return }
            if !notes[i].insert(digit).inserted { notes[i].remove(digit) }
        }
    }
    public mutating func erase(puzzle: SudokuPuzzle) {
        guard let i = selected, (0..<81).contains(i), puzzle.givens[i] == 0 else { return }
        cells[i] = 0; notes[i] = []
    }
    public func isComplete(puzzle: SudokuPuzzle) -> Bool { SudokuRules.isComplete(cells, givens: puzzle.givens) }
}

public struct SudokuProgress: Codable, Equatable, Sendable {
    public var boards: [String: SudokuBoard] = [:]
    public var completed: Set<String> = []
    public var currentID: String?
    public init() {}
    public func isUnlocked(_ puzzle: SudokuPuzzle, catalog: [SudokuPuzzle]) -> Bool {
        if puzzle.number == 1 { return true }
        return catalog.contains { $0.difficulty == puzzle.difficulty && $0.number == puzzle.number - 1 && completed.contains($0.id) }
    }
    public mutating func record(_ board: SudokuBoard, puzzle: SudokuPuzzle) {
        boards[puzzle.id] = board; currentID = puzzle.id
        if board.isComplete(puzzle: puzzle) { completed.insert(puzzle.id) }
    }
}
