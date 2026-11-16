import Foundation

public enum SessionState: String, Equatable, Sendable { case notStarted, inProgress, completed, failed }

public struct GameSummary: Equatable, Sendable {
    public enum Detail: Equatable, Sendable {
        case none
        case sudoku(SudokuDifficulty, Int, Int, Int)
        case mines(MineConfiguration, Int, Int)
        case sliding(Int, SlidingBoard.Difficulty, Int, Int)
    }
    public let state: SessionState
    public let detail: Detail
    public static func sudoku(_ progress: SudokuProgress, catalog: [SudokuPuzzle]) -> Self {
        guard let id = progress.currentID, let puzzle = catalog.first(where: { $0.id == id }), let board = progress.boards[id] else {
            return Self(state: .notStarted, detail: .none)
        }
        let filled = puzzle.givens.indices.filter { puzzle.givens[$0] == 0 && board.cells[$0] != 0 }.count
        let total = puzzle.givens.filter { $0 == 0 }.count
        return Self(state: board.isComplete(puzzle: puzzle) ? .completed : .inProgress,
                    detail: .sudoku(puzzle.difficulty, puzzle.number, filled, total))
    }
    public static func mines(_ board: MinesweeperBoard?) -> Self {
        guard let board else { return Self(state: .notStarted, detail: .none) }
        let state: SessionState
        switch board.status {
        case .ready: state = board.flags.isEmpty ? .notStarted : .inProgress
        case .playing: state = .inProgress
        case .won: state = .completed
        case .lost: state = .failed
        }
        return Self(state: state, detail: .mines(board.configuration, board.flags.count, board.elapsedSeconds))
    }
    public static func sliding(_ board: SlidingBoard?) -> Self {
        guard let board else { return Self(state: .notStarted, detail: .none) }
        return Self(state: board.isComplete ? .completed : board.moves == 0 ? .notStarted : .inProgress,
                    detail: .sliding(board.size, board.difficulty, board.moves, board.elapsedSeconds))
    }
}

public extension MineConfiguration {
    var mineDensity: Double { Double(mineCount) / Double(width * height) }
    /// A density estimate, not a promise of a no-guess layout or a solve time.
    var difficultyKey: String {
        if mineDensity <= 0.13 { return "difficulty.easy" }
        if mineDensity <= 0.18 { return "difficulty.medium" }
        return "difficulty.hard"
    }
}
