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
                       "v020-catalog", "v020-tictactoe", "v020-connectfour", "v020-twentyfour", "v020-memory", "v020-maze", "v020-layout"]
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
                do { try seedNearWin(fixture, directory: configuration.directory) }
                catch { fatalError("Invalid simulator UI fixture: \(fixture): \(error)") }
            }
        }
    }

    /// These are legal game operations in a separate test save directory. No
    /// production game or release UI exposes a solution or deterministic deck.
    private static func seedNearWin(_ game: String, directory: URL) throws {
        let store = try SaveStore(directory: directory)
        switch game {
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
