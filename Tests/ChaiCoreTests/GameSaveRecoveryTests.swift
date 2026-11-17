import XCTest
@testable import ChaiCore

final class GameSaveRecoveryTests: XCTestCase {
    func testExplicitRecoveryArchivesOnlyTheSelectedNamespace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Data("damaged memory envelope".utf8)
        let other = Data("preserved legacy Sudoku bytes".utf8)
        for suffix in [".json", ".json.backup", ".json.corrupt"] {
            try original.write(to: directory.appendingPathComponent("memory" + suffix))
        }
        try other.write(to: directory.appendingPathComponent("sudoku.json"))
        let archive = try GameSaveRecovery(directory: directory).quarantine(.memory)
        for suffix in [".json", ".json.backup", ".json.corrupt"] {
            XCTAssertEqual(try Data(contentsOf: archive.appendingPathComponent("memory" + suffix)), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("memory" + suffix).path))
        }
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("sudoku.json")), other)
        let store = try SaveStore(directory: directory)
        let fresh = MemoryBoard(seed: 20)
        try store.save(fresh, namespace: "memory")
        XCTAssertEqual(try store.load(MemoryBoard.self, namespace: "memory"), fresh)
    }

    func testFuturePrimaryAndBackupAreNeverQuarantined() throws {
        for futureSuffix in [".json", ".json.backup"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let future = Data(#"{"schemaVersion":2,"payload":{"unknown":true}}"#.utf8)
            try future.write(to: directory.appendingPathComponent("maze" + futureSuffix))
            XCTAssertThrowsError(try GameSaveRecovery(directory: directory).quarantine(.maze)) {
                guard let error = $0 as? SaveStore.StoreError,
                      case .unsupportedVersion(2) = error else { return XCTFail("Future schema must stay protected") }
            }
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("maze" + futureSuffix)), future)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
        }
    }
}
