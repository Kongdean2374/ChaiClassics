#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftUI
import ChaiCore

/// Simulator-only test data uses a different directory and preferences suite.
/// This code is compiled out of Release; it cannot reset production saves.
enum UITestBootstrap {
    struct Configuration { let directory: URL; let defaults: UserDefaults; let suite: String }
    // Test flags may suppress a celebration, never override the real OS to enable one.
    static var forceReducedMotion: Bool { testFlag("--ui-reduce-motion") }
    static var forceLowPower: Bool { testFlag("--ui-low-power") }
    /// Constrains the real SwiftUI layout inside the simulator window. A 320 pt
    /// capture is a viewport test, not a claim of running an unsupported device.
    static var viewportWidth: CGFloat? {
        guard let value = argument("--uitest-viewport-width"), ["320", "375", "390", "430"].contains(value),
              let width = Double(value) else { return nil }
        return CGFloat(width)
    }
    static var dynamicTypeSize: DynamicTypeSize? {
        switch argument("--ui-content-size") {
        case "accessibility3": return .accessibility3
        case "accessibility5": return .accessibility5
        case "xxxLarge": return .xxxLarge
        default: return nil
        }
    }
    private static func argument(_ flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--ui-testing"), let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    private static func testFlag(_ name: String) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing") && arguments.contains(name)
    }
    static func configuration() -> Configuration? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--ui-testing") else { return nil }
        let allowed = ["base", "sudoku", "mines", "legacy", "large", "settings", "legal", "sliding",
                       "visual-normal", "visual-reduced", "visual-lowpower", "visual-gallery",
                       "v020-catalog", "v020-tictactoe", "v020-connectfour", "v020-twentyfour", "v020-memory", "v020-maze", "v020-layout",
                       "v021-tictactoe", "v021-connectfour", "v021-memory", "v021-twentyfour", "v021-maze",
                       "v022-session-sudoku", "v022-session-minesweeper", "v022-session-sliding", "v022-session-tictactoe",
                       "v022-session-connectfour", "v022-session-twentyfour", "v022-session-memory", "v022-session-maze", "v022-history"]
            + GameID.allCases.filter(\.isExpanded).map { "v030-"+$0.rawValue }
        let index = args.firstIndex(of: "--ui-profile")
        let requested = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "base"
        let profile = allowed.contains(requested) ? requested : "base"
        let suite = "cc.chaihome.chaiclassics.uitests." + profile
        guard let defaults = UserDefaults(suiteName: suite), let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { fatalError("Test sandbox unavailable") }
        return Configuration(directory: support.appendingPathComponent("ChaiClassicsUITests/" + profile), defaults: defaults, suite: suite)
    }
    static func prepare(_ configuration: Configuration) {
        let resetting = ProcessInfo.processInfo.arguments.contains("--ui-reset")
        if resetting {
            try? FileManager.default.removeItem(at: configuration.directory)
            configuration.defaults.removePersistentDomain(forName: configuration.suite)
        }
        try? FileManager.default.createDirectory(at: configuration.directory, withIntermediateDirectories: true)
        for namespace in GameID.allCases.map(\.rawValue) {
            let file = configuration.directory.appendingPathComponent(namespace + ".json")
            if !FileManager.default.fileExists(atPath: file.path), let encoded = ProcessInfo.processInfo.environment["CHAI_UI_SEED_" + namespace.uppercased()], let data = Data(base64Encoded: encoded) {
                try? data.write(to: file, options: .atomic)
            }
        }
        if resetting {
            let preferences = PreferencesStore(defaults: configuration.defaults)
            var value = preferences.load()
            if let raw = argument("--ui-language"), let language = AppLanguage(rawValue: raw) { value.language = language }
            if let raw = argument("--ui-appearance"), let appearance = AppAppearance(rawValue: raw) { value.appearance = appearance }
            preferences.save(value)
            if let fixture = argument("--ui-near-win") {
                do { try seedScenario(fixture, directory: configuration.directory) }
                catch { fatalError("Invalid simulator UI fixture: \(fixture): \(error)") }
            }
        }
    }

    /// These are legal game operations in a separate test save directory. No
    /// production game or release UI exposes a solution or deterministic deck.
    private static func seedScenario(_ game: String, directory: URL) throws {
        let store = try SaveStore(directory: directory)
        switch game {
        case "sudoku":
            let puzzles = try SudokuPuzzle.bundled()
            guard let puzzle = puzzles.first(where: { $0.difficulty == .easy && $0.number == 1 }),
                  let sentinel = puzzles.first(where: { $0.difficulty == .medium && $0.number == 1 }) else {
                preconditionFailure("Missing released Sudoku catalog fixtures")
            }
            let solution = [
                2, 3, 4, 9, 7, 8, 1, 5, 6,
                6, 1, 5, 4, 3, 2, 7, 9, 8,
                8, 7, 9, 5, 1, 6, 3, 4, 2,
                7, 9, 6, 2, 5, 1, 4, 8, 3,
                3, 4, 8, 6, 9, 7, 5, 2, 1,
                1, 5, 2, 8, 4, 3, 9, 6, 7,
                9, 6, 1, 3, 2, 5, 8, 7, 4,
                5, 2, 3, 7, 8, 4, 6, 1, 9,
                4, 8, 7, 1, 6, 9, 2, 3, 5
            ]
            precondition(SudokuRules.isComplete(solution, givens: puzzle.givens) && puzzle.givens[1] == 0)
            var board = SudokuBoard(puzzle: puzzle)
            for index in puzzle.givens.indices where puzzle.givens[index] == 0 && index != 1 {
                board.selected = index; board.enter(solution[index], puzzle: puzzle)
            }
            board.selected = 1
            var progress = SudokuProgress()
            progress.record(SudokuBoard(puzzle: sentinel), puzzle: sentinel)
            progress.record(board, puzzle: puzzle)
            precondition(board.isValidSave(for: puzzle) && !board.isComplete(puzzle: puzzle) && progress.completed.isEmpty)
            try store.save(progress, namespace: GameID.sudoku.rawValue)
        case "minesweeper":
            var board = MinesweeperBoard(configuration: .easy, seed: 42)
            // Flag cell0 before the first reveal: reveal1's safety exclusion
            // makes it safe, while the flag keeps flood-fill from opening it.
            board.toggleFlag(0); board.reveal(1)
            precondition(!board.mines.contains(0))
            for index in 0..<board.cellCount where index != 0 && !board.mines.contains(index) { board.reveal(index) }
            board.toggleFlag(0); board.elapsedSeconds = 12
            precondition(board.isValidSave && !board.isFinished && board.revealed.count == 70)
            try store.save(board, namespace: GameID.minesweeper.rawValue)
        case "tictactoe":
            var board = TicTacToeBoard(mode: .localTwoPlayer, difficulty: .normal, humanPlayer: .first, seed: 24)
            for index in [0, 3, 1, 4] { precondition(board.play(at: index, by: board.currentPlayer)) }
            board.elapsedSeconds = 12
            precondition(board.isValidSave && !board.isFinished)
            try store.save(board, namespace: GameID.ticTacToe.rawValue)
        case "connectfour":
            var board = ConnectFourBoard(mode: .localTwoPlayer, difficulty: .normal, humanPlayer: .first, seed: 24)
            for column in [0, 6, 1, 6, 2, 5] { precondition(board.drop(in: column, player: board.currentPlayer)) }
            board.elapsedSeconds = 12
            precondition(board.isValidSave && !board.isFinished)
            try store.save(board, namespace: GameID.connectFour.rawValue)
        case "twentyfour-fresh", "twentyfour-zero":
            var board = try TwentyFourBoard(numbers: [1, 2, 3, 4], seed: 24)
            if game == "twentyfour-zero" {
                precondition(board.combine(firstID: 0, secondID: 1, operation: .add))
                precondition(board.combine(firstID: 2, secondID: 4, operation: .subtract))
            }
            board.elapsedSeconds = 12
            precondition(board.isValidSave && !board.isComplete)
            try store.save(board, namespace: GameID.twentyFour.rawValue)
        case "twentyfour":
            var board = try TwentyFourBoard(numbers: [1, 2, 3, 4], seed: 24)
            precondition(board.combine(firstID: 0, secondID: 1, operation: .add))
            precondition(board.combine(firstID: 2, secondID: 4, operation: .add))
            board.elapsedSeconds = 12
            precondition(board.isValidSave && !board.isComplete)
            try store.save(board, namespace: GameID.twentyFour.rawValue)
        case "memory":
            var board = MemoryBoard(mode: .easy, seed: 24)
            for symbol in 0..<(board.mode.pairCount - 1) {
                for index in board.cards.indices.filter({ board.cards[$0] == symbol }) {
                    precondition(board.select(index))
                }
            }
            board.elapsedSeconds = 12
            precondition(board.isValidSave && board.matchedPairCount == 7)
            try store.save(board, namespace: GameID.memory.rawValue)
        case "memory-fresh":
            let board = MemoryBoard(mode: .easy, seed: 24)
            precondition(board.isValidSave && board.matchedPairCount == 0)
            try store.save(board, namespace: GameID.memory.rawValue)
        case "maze-joystick":
            let board = MazeBoard(difficulty: .easy, seed: 42)
            precondition(board.isValidSave && board.moves == 0)
            try store.save(board, namespace: GameID.maze.rawValue)
        case "maze":
            var board = MazeBoard(difficulty: .easy, seed: 42)
            var queue = [board.start]
            var seen: Set<MazeBoard.Cell> = [board.start]
            var parent: [MazeBoard.Cell: (MazeBoard.Cell, MazeBoard.Direction)] = [:]
            var cursor = 0
            while cursor < queue.count {
                let cell = queue[cursor]; cursor += 1
                for direction in MazeBoard.Direction.allCases where !board.hasWall(direction, at: cell) {
                    let next = direction.neighbor(of: cell)
                    if seen.insert(next).inserted {
                        parent[next] = (cell, direction)
                        queue.append(next)
                    }
                }
            }
            var path: [MazeBoard.Direction] = []
            var cell = board.goal
            while cell != board.start {
                guard let step = parent[cell] else { preconditionFailure("Maze fixture is disconnected") }
                path.append(step.1); cell = step.0
            }
            path.reverse()
            // Stable generation-v1 seed 42 has 44 moves and ends right, down.
            precondition(path.count == 44 && Array(path.suffix(2)) == [.right, .down])
            for direction in path.dropLast(2) { precondition(board.move(direction)) }
            board.elapsedSeconds = 12
            precondition(board.isValidSave && !board.isComplete)
            try store.save(board, namespace: GameID.maze.rawValue)
        default: preconditionFailure("Unknown simulator UI fixture")
        }
    }
}
#endif
