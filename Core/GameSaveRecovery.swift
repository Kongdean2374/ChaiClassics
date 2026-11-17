import Foundation

/// Explicit user-requested recovery preserves unreadable bytes and affects one game only.
/// SaveStore's released envelopes and atomic write/backup behavior remain unchanged.
public struct GameSaveRecovery {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }

    @discardableResult public func quarantine(_ game: GameID) throws -> URL {
        let names = [game.rawValue + ".json", game.rawValue + ".json.backup", game.rawValue + ".json.corrupt"]
        let originals = names.map { directory.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        for source in originals where !source.lastPathComponent.hasSuffix(".corrupt") {
            let data = try Data(contentsOf: source)
            if let header = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let version = header["schemaVersion"] as? Int, version > 1 {
                throw SaveStore.StoreError.unsupportedVersion(version)
            }
        }
        let archive = directory.appendingPathComponent("Recovered-" + game.rawValue + "-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        // Copy every affected file before removing any primary or backup.
        for source in originals {
            try FileManager.default.copyItem(at: source, to: archive.appendingPathComponent(source.lastPathComponent))
        }
        for source in originals { try FileManager.default.removeItem(at: source) }
        return archive
    }
}
