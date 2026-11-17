import Foundation

/// All callers must finish synchronous legacy SaveStore writes before importing.
/// AppModel serializes those writes on its actor. Transfer/metadata operations
/// additionally share a directory lock across instances in this process.
public final class GameDataTransferStore {
    public static let maximumArchiveBytes = 16 * 1024 * 1024
    public static let metadataNamespace = "sessions-v1"
    public static let preferencesNamespace = "preferences-v1"
    static let journalName = "transfer-transaction-v1.json"
    private static let registryLock = NSLock()
    private static var directoryLocks: [String: NSRecursiveLock] = [:]

    public enum TransferError: Error, Equatable {
        case unsupportedVersion(Int), invalidArchive, oversized, unsupportedSaveVersion(Int)
        case corruptSave(GameID), invalidMetadata, unavailable, transactionFailed, recoveryRequired
    }
    private enum Mutation { case write(Data), remove }
    private struct Header: Decodable { let schemaVersion: Int }
    private struct ArchiveHeader: Decodable { let version: Int }
    private struct JournalEntry: Codable { let name: String; let original: Data? }
    private struct Journal: Codable { let version: Int; var committed: Bool; let originals: [JournalEntry] }
    private let directory: URL
    private let lock: NSRecursiveLock
    private let catalog: [SudokuPuzzle]
    /// Only the test target injects failures; production never executes a hook.
    var beforeTransactionWrite: ((String) throws -> Void)?

    public init(directory: URL) throws {
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        Self.registryLock.lock()
        let key = self.directory.path
        let sharedLock = Self.directoryLocks[key] ?? NSRecursiveLock()
        Self.directoryLocks[key] = sharedLock
        Self.registryLock.unlock()
        lock = sharedLock
        catalog = try SudokuPuzzle.bundled()
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        lock.lock(); defer { lock.unlock() }
        try recoverInterruptedTransaction()
    }

    public func loadSessionData() throws -> GameSessionData {
        lock.lock(); defer { lock.unlock() }
        try recoverInterruptedTransaction()
        let value: GameSessionData = try readEnvelope(GameSessionData.self, namespace: Self.metadataNamespace,
                                                      validate: { $0.isValid }) ?? GameSessionData()
        guard value.isValid else { throw TransferError.invalidMetadata }
        return value
    }

    public func saveSessionData(_ value: GameSessionData) throws {
        lock.lock(); defer { lock.unlock() }
        try recoverInterruptedTransaction()
        guard value.isValid else { throw TransferError.invalidMetadata }
        try protectFutureFiles(namespace: Self.metadataNamespace)
        try SaveStore(directory: directory).save(value, namespace: Self.metadataNamespace)
    }

    @discardableResult public func updateSessionData(_ change: (inout GameSessionData) throws -> Void) throws -> GameSessionData {
        lock.lock(); defer { lock.unlock() }
        var value = try loadSessionData(); try change(&value); try saveSessionData(value); return value
    }

    @discardableResult public func appendRecord(_ record: GamePlayRecord) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        var value = try loadSessionData()
        let inserted = try value.append(record)
        if inserted { try saveSessionData(value) }
        return inserted
    }

    public func loadImportedPreferences() throws -> AppPreferences? {
        lock.lock(); defer { lock.unlock() }
        try recoverInterruptedTransaction()
        return try readEnvelope(AppPreferences.self, namespace: Self.preferencesNamespace)
    }

    public func saveImportedPreferences(_ preferences: AppPreferences) throws {
        lock.lock(); defer { lock.unlock() }
        try recoverInterruptedTransaction()
        try protectFutureFiles(namespace: Self.preferencesNamespace)
        try SaveStore(directory: directory).save(preferences, namespace: Self.preferencesNamespace)
    }

    public func exportArchive(scope: GameDataScope = .all, preferences: AppPreferences,
                              at date: Date = Date()) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        try recoverInterruptedTransaction()
        let entries = try scope.gameIDs.map { game in GameArchiveEntry(gameID: game, payload: try readGame(game)) }
        let allMetadata = try loadSessionData()
        let metadata: GameSessionData
        let exportedPreferences: AppPreferences?
        switch scope {
        case .all: metadata = allMetadata; exportedPreferences = preferences
        case .game(let game): metadata = allMetadata.scoped(to: game); exportedPreferences = nil
        }
        let archive = GameDataArchive(scope: scope, preferences: exportedPreferences, games: entries, metadata: metadata, createdAt: date)
        guard archive.isValid(catalog: catalog) else { throw TransferError.invalidArchive }
        let data = try JSONEncoder().encode(archive)
        guard data.count <= Self.maximumArchiveBytes else { throw TransferError.oversized }
        return data
    }

    public func validateArchive(_ data: Data) throws -> GameDataArchive {
        guard data.count <= Self.maximumArchiveBytes else { throw TransferError.oversized }
        guard !data.isEmpty else { throw TransferError.invalidArchive }
        let header: ArchiveHeader
        do { header = try JSONDecoder().decode(ArchiveHeader.self, from: data) }
        catch { throw TransferError.invalidArchive }
        guard header.version == GameDataArchive.currentVersion else { throw TransferError.unsupportedVersion(header.version) }
        let archive: GameDataArchive
        do { archive = try JSONDecoder().decode(GameDataArchive.self, from: data) }
        catch { throw TransferError.invalidArchive }
        guard archive.isValid(catalog: catalog) else { throw TransferError.invalidArchive }
        return archive
    }

    @discardableResult public func applyArchive(_ data: Data) throws -> GameDataImportResult {
        // Validate the complete typed archive before opening the write transaction.
        let archive = try validateArchive(data)
        lock.lock(); defer { lock.unlock() }
        try recoverInterruptedTransaction()
        var metadata: GameSessionData
        switch archive.scope {
        case .all:
            if Set(archive.games.map(\.gameID)) == GameID.legacyGames {
                // A released 0.2.2 backup predates the new namespaces. Restore
                // exactly its eight games without clearing newer game data.
                metadata = try loadSessionData()
                for entry in archive.games { try metadata.replace(entry.gameID, with: archive.metadata) }
            } else { metadata = archive.metadata }
        case .game(let game):
            metadata = try loadSessionData()
            try metadata.replace(game, with: archive.metadata)
        }
        guard metadata.isValid else { throw TransferError.invalidMetadata }
        var mutations: [String: Mutation] = [:]
        for entry in archive.games {
            try addReplacement(try entry.payload?.envelopeData(), namespace: entry.gameID.rawValue, to: &mutations)
        }
        try addReplacement(JSONEncoder().encode(GameDataEnvelope(payload: metadata)), namespace: Self.metadataNamespace, to: &mutations)
        if let preferences = archive.preferences {
            try addReplacement(JSONEncoder().encode(GameDataEnvelope(payload: preferences)), namespace: Self.preferencesNamespace, to: &mutations)
        }
        try transact(mutations)
        return GameDataImportResult(scope: archive.scope, preferences: archive.preferences, metadata: metadata)
    }

    @discardableResult public func removeGame(_ game: GameID, includingHistory: Bool = true,
                                             includingPreferences: Bool = true) throws -> GameSessionData {
        lock.lock(); defer { lock.unlock() }
        try recoverInterruptedTransaction()
        var metadata = try loadSessionData()
        if includingHistory { metadata.clearRecords(for: game) }
        metadata.sessions[game] = nil
        if game == .sudoku { metadata.sudokuSessions = [:] }
        if includingPreferences { metadata.gamePreferences[game] = nil }
        var mutations: [String: Mutation] = [:]
        try addReplacement(nil, namespace: game.rawValue, to: &mutations)
        try addReplacement(JSONEncoder().encode(GameDataEnvelope(payload: metadata)), namespace: Self.metadataNamespace, to: &mutations)
        try transact(mutations)
        return metadata
    }

    /// Replaces progress and that game's metadata in one journal transaction.
    /// Deleting progress also removes its active session, while supplied history
    /// and preferences survive. The other seven metadata slices stay untouched.
    @discardableResult public func replaceGame(_ game: GameID, payload: GameSavePayload?,
                                              metadata: GameSessionData) throws -> GameDataImportResult {
        guard metadata.isValid else { throw TransferError.invalidMetadata }
        var scoped = metadata.scoped(to: game)
        if payload == nil {
            scoped.sessions[game] = nil
            if game == .sudoku { scoped.sudokuSessions = [:] }
        }
        if let payload, case .sudoku(let progress) = payload {
            if progress.currentID == nil || progress.boards[progress.currentID!] == nil { scoped.sessions[game] = nil }
            scoped.sudokuSessions = scoped.sudokuSessions.filter { progress.boards[$0.key] != nil }
        }
        let archive = GameDataArchive(scope: .game(game), preferences: nil,
                                      games: [GameArchiveEntry(gameID: game, payload: payload)], metadata: scoped)
        return try applyArchive(JSONEncoder().encode(archive))
    }

    private var allowedNames: Set<String> {
        let namespaces = GameID.allCases.map(\.rawValue) + [Self.metadataNamespace, Self.preferencesNamespace]
        return Set(namespaces.flatMap { [$0 + ".json", $0 + ".json.backup", $0 + ".json.corrupt"] })
    }
    private func file(_ name: String) throws -> URL {
        guard allowedNames.contains(name) || name == Self.journalName else { throw TransferError.recoveryRequired }
        let url = directory.appendingPathComponent(name)
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true {
            throw TransferError.unavailable
        }
        return url
    }

    private func read(_ name: String, limit: Int = GameDataTransferStore.maximumArchiveBytes) throws -> Data? {
        let url = try file(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= limit else { throw TransferError.oversized }
        let data = try Data(contentsOf: url)
        guard data.count <= limit else { throw TransferError.oversized }
        return data
    }

    private func checkHeader(_ data: Data) throws {
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.schemaVersion == 1 else { throw TransferError.unsupportedSaveVersion(header.schemaVersion) }
    }

    private func protectFutureFiles(namespace: String) throws {
        for name in [namespace + ".json", namespace + ".json.backup"] {
            if let data = try read(name), let header = try? JSONDecoder().decode(Header.self, from: data), header.schemaVersion > 1 {
                throw TransferError.unsupportedSaveVersion(header.schemaVersion)
            }
        }
    }

    private func readEnvelope<T: Codable>(_ type: T.Type, namespace: String, validate: (T) -> Bool = { _ in true }) throws -> T? {
        var found = false
        for name in [namespace + ".json", namespace + ".json.backup"] {
            guard let data = try read(name) else { continue }
            found = true
            do {
                try checkHeader(data)
                let value = try JSONDecoder().decode(GameDataEnvelope<T>.self, from: data).payload
                if validate(value) {
                    if name.hasSuffix(".backup") {
                        let primary = namespace + ".json"
                        if let damaged = try read(primary) { try writeAtomically(damaged, to: file(primary + ".corrupt")) }
                        try writeAtomically(data, to: file(primary))
                    }
                    return value
                }
            }
            catch let error as TransferError {
                if case .unsupportedSaveVersion = error { throw error }
            }
            catch { continue }
        }
        if found { throw TransferError.invalidMetadata }
        return nil
    }

    private func readGame(_ game: GameID) throws -> GameSavePayload? {
        var found = false
        for name in [game.rawValue + ".json", game.rawValue + ".json.backup"] {
            guard let data = try read(name) else { continue }
            found = true
            do {
                try checkHeader(data)
                let payload = try GameSavePayload.decodeEnvelope(data, game: game)
                if payload.isValid(catalog: catalog) { return payload }
            } catch let error as TransferError {
                if case .unsupportedSaveVersion = error { throw error }
            } catch { continue }
        }
        if found { throw TransferError.corruptSave(game) }
        return nil
    }

    private func addReplacement(_ data: Data?, namespace: String, to mutations: inout [String: Mutation]) throws {
        try protectFutureFiles(namespace: namespace)
        let primary = namespace + ".json", backup = primary + ".backup"
        if let data {
            if let previous = try read(primary) { mutations[backup] = .write(previous) }
            mutations[primary] = .write(data)
        } else {
            mutations[primary] = .remove; mutations[backup] = .remove
            mutations[primary + ".corrupt"] = .remove
        }
    }

    private func writeJournal(_ journal: Journal) throws {
        let url = try file(Self.journalName)
        try JSONEncoder().encode(journal).write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.synchronize()
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.synchronize()
    }

    private func transact(_ mutations: [String: Mutation]) throws {
        let names = mutations.keys.sorted()
        var originals: [JournalEntry] = [], total = 0
        for name in names {
            guard allowedNames.contains(name) else { throw TransferError.invalidArchive }
            let data = try read(name)
            total += data?.count ?? 0
            guard total <= Self.maximumArchiveBytes * 4 else { throw TransferError.oversized }
            originals.append(JournalEntry(name: name, original: data))
        }
        var journal = Journal(version: 1, committed: false, originals: originals)
        try writeJournal(journal)
        do {
            for name in names {
                try beforeTransactionWrite?(name)
                let url = try file(name)
                switch mutations[name]! {
                case .write(let data): try writeAtomically(data, to: url)
                case .remove:
                    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                }
            }
            journal.committed = true
            try writeJournal(journal)
        } catch {
            do { try restore(journal) }
            catch { throw TransferError.recoveryRequired }
            throw TransferError.transactionFailed
        }
        // A committed marker means recovery must retain the new complete state.
        // Cleanup failure does not turn an already committed import into failure.
        try? FileManager.default.removeItem(at: file(Self.journalName))
    }

    private func restore(_ journal: Journal) throws {
        for entry in journal.originals {
            let url = try file(entry.name)
            if let original = entry.original { try writeAtomically(original, to: url) }
            else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        try FileManager.default.removeItem(at: file(Self.journalName))
    }

    private func recoverInterruptedTransaction() throws {
        guard let data = try read(Self.journalName, limit: Self.maximumArchiveBytes * 6) else { return }
        let journal: Journal
        do { journal = try JSONDecoder().decode(Journal.self, from: data) }
        catch { throw TransferError.recoveryRequired }
        guard journal.version == 1, journal.originals.count <= allowedNames.count,
              Set(journal.originals.map(\.name)).count == journal.originals.count,
              journal.originals.reduce(0, { $0 + ($1.original?.count ?? 0) }) <= Self.maximumArchiveBytes * 4,
              journal.originals.allSatisfy({ allowedNames.contains($0.name) && ($0.original?.count ?? 0) <= Self.maximumArchiveBytes }) else {
            throw TransferError.recoveryRequired
        }
        do {
            if journal.committed { try FileManager.default.removeItem(at: file(Self.journalName)) }
            else { try restore(journal) }
        } catch { throw TransferError.recoveryRequired }
    }
}
