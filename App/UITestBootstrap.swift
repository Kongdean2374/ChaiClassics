#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Simulator-only test data uses a different directory and preferences suite.
/// This code is compiled out of Release; it cannot reset production saves.
enum UITestBootstrap {
    struct Configuration { let directory: URL; let defaults: UserDefaults; let suite: String }
    static func configuration() -> Configuration? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--ui-testing") else { return nil }
        let allowed = ["base", "sudoku", "mines", "legacy", "large", "settings", "legal", "sliding"]
        let index = args.firstIndex(of: "--ui-profile")
        let requested = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "base"
        let profile = allowed.contains(requested) ? requested : "base"
        let suite = "cc.chaihome.chaiclassics.uitests." + profile
        guard let defaults = UserDefaults(suiteName: suite), let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { fatalError("Test sandbox unavailable") }
        return Configuration(directory: support.appendingPathComponent("ChaiClassicsUITests/" + profile), defaults: defaults, suite: suite)
    }
    static func prepare(_ configuration: Configuration) {
        if ProcessInfo.processInfo.arguments.contains("--ui-reset") {
            try? FileManager.default.removeItem(at: configuration.directory)
            configuration.defaults.removePersistentDomain(forName: configuration.suite)
        }
        try? FileManager.default.createDirectory(at: configuration.directory, withIntermediateDirectories: true)
        for namespace in ["sudoku", "minesweeper", "sliding"] {
            let file = configuration.directory.appendingPathComponent(namespace + ".json")
            if !FileManager.default.fileExists(atPath: file.path), let encoded = ProcessInfo.processInfo.environment["CHAI_UI_SEED_" + namespace.uppercased()], let data = Data(base64Encoded: encoded) {
                try? data.write(to: file, options: .atomic)
            }
        }
    }
}
#endif
