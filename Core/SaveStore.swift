import Foundation

/// Each game owns an envelope. Writes and backup rotation are serialized and atomic.
/// Unknown future schemas are never overwritten; callers must surface the error.
public final class SaveStore {
    public enum StoreError: Error { case unsupportedVersion(Int), corrupt, invalidNamespace }
    private struct Envelope<T: Codable>: Codable {
        var schemaVersion: Int
        var payload: T
    }
    private let directory: URL
    private let lock = NSRecursiveLock()
    public private(set) var recoveredBackup = false

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(_ namespace: String) throws -> URL {
        guard !namespace.isEmpty, namespace.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }),
              !namespace.contains("..") else { throw StoreError.invalidNamespace }
        return directory.appendingPathComponent(namespace).appendingPathExtension("json")
    }

    public func load<T: Codable>(_ type: T.Type, namespace: String, version: Int = 1,
                                 migrate: ((Int, Data) throws -> T)? = nil) throws -> T? {
        lock.lock(); defer { lock.unlock() }
        recoveredBackup = false
        let primary = try url(namespace)
        let backup = primary.appendingPathExtension("backup")
        func decode(_ file: URL) throws -> T {
            let data = try Data(contentsOf: file)
            let header = try JSONDecoder().decode(Header.self, from: data)
            if header.schemaVersion > version { throw StoreError.unsupportedVersion(header.schemaVersion) }
            if header.schemaVersion < version {
                guard let migrate else { throw StoreError.unsupportedVersion(header.schemaVersion) }
                return try migrate(header.schemaVersion, data)
            }
            return try JSONDecoder().decode(Envelope<T>.self, from: data).payload
        }
        guard FileManager.default.fileExists(atPath: primary.path) else {
            if FileManager.default.fileExists(atPath: backup.path) {
                let result = try decode(backup)
                recoveredBackup = true
                try Data(contentsOf: backup).write(to: primary, options: .atomic)
                return result
            }
            return nil
        }
        do { return try decode(primary) }
        catch let error as StoreError { // Future versions must not fall back to older saves.
            if case .unsupportedVersion = error { throw error }
            throw error
        }
        catch {
            guard FileManager.default.fileExists(atPath: backup.path) else { throw StoreError.corrupt }
            let result = try decode(backup)
            // Keep evidence; restore a known-good primary before allowing another write.
            try Data(contentsOf: primary).write(to: primary.appendingPathExtension("corrupt"), options: .atomic)
            try Data(contentsOf: backup).write(to: primary, options: .atomic)
            recoveredBackup = true
            return result
        }
    }

    private struct Header: Decodable { let schemaVersion: Int }

    public func save<T: Codable>(_ value: T, namespace: String, version: Int = 1) throws {
        lock.lock(); defer { lock.unlock() }
        let primary = try url(namespace)
        let data = try JSONEncoder().encode(Envelope(schemaVersion: version, payload: value))
        if FileManager.default.fileExists(atPath: primary.path) {
            let previous = try Data(contentsOf: primary)
            let header = try JSONDecoder().decode(Header.self, from: previous)
            guard header.schemaVersion <= version else { throw StoreError.unsupportedVersion(header.schemaVersion) }
            try previous.write(to: primary.appendingPathExtension("backup"), options: .atomic)
        }
        try data.write(to: primary, options: .atomic)
    }
    // All saves finish synchronously before returning; no delayed queue to flush.
    public func flush() { lock.lock(); lock.unlock() }
}
