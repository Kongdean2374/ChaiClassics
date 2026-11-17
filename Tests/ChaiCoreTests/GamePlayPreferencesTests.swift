import XCTest
@testable import ChaiCore

final class GamePlayPreferencesTests: XCTestCase {
    private let levels = ["easy", "normal", "hard"]

    private func directory() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent("game-preferences-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: value) }
        return value
    }

    private func contents(_ directory: URL) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }

    private func preferences(_ sourceIndex: Int) -> GamePlayPreferences {
        let index = (sourceIndex % 10 + 10) % 10
        var value = GamePlayPreferences()
        value.haptics = index.isMultiple(of: 2)
        value.sudokuPencilByDefault = !index.isMultiple(of: 2)
        value.minesWidth = 5 + index; value.minesHeight = 6 + index; value.minesCount = 1 + index
        value.slidingSize = 3 + index % 3; value.slidingDifficulty = levels[index % 3]
        value.duelMode = index.isMultiple(of: 2) ? "singlePlayer" : "localTwoPlayer"
        value.duelDifficulty = levels[(index + 1) % 3]; value.humanPlayer = 1 + index % 2
        value.twentyFourDifficulty = levels[(index + 2) % 3]
        value.memoryMode = levels[index % 3]; value.memoryRevealSeconds = 0.5 + Double(index % 10) * 0.1
        value.mazeDifficulty = levels[(index + 1) % 3]; value.mazeSpeed = [0.8, 1.0, 1.2][index % 3]
        return value
    }

    private var invalidChanges: [(String, (inout GamePlayPreferences) -> Void)] {
        [
            ("narrow mines", { $0.minesWidth = 4 }), ("wide mines", { $0.minesWidth = 41 }),
            ("short mines", { $0.minesHeight = 4 }), ("tall mines", { $0.minesHeight = 41 }),
            ("mines width overflow", { $0.minesWidth = Int.max }), ("mines height overflow", { $0.minesHeight = Int.max }),
            ("zero mines", { $0.minesCount = 0 }), ("full mines", { $0.minesCount = 81 }),
            ("negative mines", { $0.minesCount = -1 }), ("mines overflow", { $0.minesCount = Int.max }),
            ("small sliding", { $0.slidingSize = 2 }), ("large sliding", { $0.slidingSize = 6 }),
            ("sliding size overflow", { $0.slidingSize = Int.max }),
            ("unknown sliding level", { $0.slidingDifficulty = "medium" }),
            ("unknown duel mode", { $0.duelMode = "network" }),
            ("unknown duel level", { $0.duelDifficulty = "Hard" }),
            ("missing human", { $0.humanPlayer = 0 }), ("third human", { $0.humanPlayer = 3 }),
            ("unknown 24 level", { $0.twentyFourDifficulty = "" }),
            ("unknown memory mode", { $0.memoryMode = "6x6" }),
            ("short memory reveal", { $0.memoryRevealSeconds = 0.5.nextDown }),
            ("long memory reveal", { $0.memoryRevealSeconds = 1.5.nextUp }),
            ("nan memory reveal", { $0.memoryRevealSeconds = .nan }),
            ("infinite memory reveal", { $0.memoryRevealSeconds = .infinity }),
            ("negative infinite memory reveal", { $0.memoryRevealSeconds = -.infinity }),
            ("unknown maze level", { $0.mazeDifficulty = "expert" }),
            ("unsupported maze speed", { $0.mazeSpeed = 0.9 }),
            ("rounded maze speed", { $0.mazeSpeed = 0.8.nextUp }),
            ("zero maze speed", { $0.mazeSpeed = 0 }),
            ("nan maze speed", { $0.mazeSpeed = .nan }), ("infinite maze speed", { $0.mazeSpeed = .infinity })
        ]
    }

    func testEveryStoredDefaultMapsToRealTypedGameConfiguration() throws {
        XCTAssertTrue(GamePlayPreferences().isValid)
        for (index, game) in GameID.allCases.enumerated() {
            let value = preferences(index)
            XCTAssertTrue(value.isValid, game.rawValue)
            XCTAssertEqual(try JSONDecoder().decode(GamePlayPreferences.self, from: JSONEncoder().encode(value)), value)
            let mineConfiguration = try MineConfiguration(width: value.minesWidth, height: value.minesHeight, mines: value.minesCount)
            XCTAssertTrue(MinesweeperBoard(configuration: mineConfiguration, seed: 20).isValidSave)
            XCTAssertTrue(try SlidingBoard(size: value.slidingSize,
                                          difficulty: XCTUnwrap(SlidingBoard.Difficulty(rawValue: value.slidingDifficulty)), seed: 21).isValidSave)
            let mode = try XCTUnwrap(DuelMode(rawValue: value.duelMode))
            let level = try XCTUnwrap(DuelDifficulty(rawValue: value.duelDifficulty))
            let player = try XCTUnwrap(DuelPlayer(rawValue: value.humanPlayer))
            XCTAssertTrue(TicTacToeBoard(mode: mode, difficulty: level, humanPlayer: player, seed: 22).isValidSave)
            XCTAssertTrue(ConnectFourBoard(mode: mode, difficulty: level, humanPlayer: player, seed: 23).isValidSave)
            XCTAssertTrue(TwentyFourBoard(difficulty: try XCTUnwrap(TwentyFourDifficulty(rawValue: value.twentyFourDifficulty)), seed: 24).isValidSave)
            XCTAssertTrue(MemoryBoard(mode: try XCTUnwrap(MemoryBoard.Mode(rawValue: value.memoryMode)), seed: 25).isValidSave)
            XCTAssertTrue(MazeBoard(difficulty: try XCTUnwrap(MazeBoard.Difficulty(rawValue: value.mazeDifficulty)), seed: 26).isValidSave)
        }
    }

    func testPlayableNumericBoundariesAndAllSupportedPresetValuesAreValid() {
        for (width, height, mines) in [(5, 5, 1), (5, 5, 24), (40, 40, 1), (40, 40, 1599)] {
            var value = GamePlayPreferences()
            value.minesWidth = width; value.minesHeight = height; value.minesCount = mines
            XCTAssertTrue(value.isValid)
        }
        for level in levels {
            var value = GamePlayPreferences()
            value.slidingDifficulty = level; value.duelDifficulty = level
            value.twentyFourDifficulty = level; value.memoryMode = level; value.mazeDifficulty = level
            XCTAssertTrue(value.isValid)
        }
        for size in 3...5 { var value = GamePlayPreferences(); value.slidingSize = size; XCTAssertTrue(value.isValid) }
        for player in 1...2 { var value = GamePlayPreferences(); value.humanPlayer = player; XCTAssertTrue(value.isValid) }
        for seconds in [0.5, 0.65, 1.0, 1.5] { var value = GamePlayPreferences(); value.memoryRevealSeconds = seconds; XCTAssertTrue(value.isValid) }
        for speed in [0.8, 1.0, 1.2] { var value = GamePlayPreferences(); value.mazeSpeed = speed; XCTAssertTrue(value.isValid) }
        for mode in ["singlePlayer", "localTwoPlayer"] { var value = GamePlayPreferences(); value.duelMode = mode; XCTAssertTrue(value.isValid) }
    }

    func testAllInvalidFieldsAreRejectedWithoutChangingAnotherValueCopy() {
        let original = GamePlayPreferences()
        for (name, change) in invalidChanges {
            var value = original
            change(&value)
            XCTAssertFalse(value.isValid, name)
            XCTAssertEqual(original, GamePlayPreferences(), name)
        }
    }

    func testInvalidGamePreferencesCannotRewriteMetadataBackupOrGameplayBytes() throws {
        let folder = try directory()
        let store = try GameDataTransferStore(directory: folder)
        try SaveStore(directory: folder).save(MemoryBoard(seed: 13), namespace: "memory")
        var metadata = GameSessionData()
        metadata.gamePreferences[.memory] = preferences(6)
        metadata.gamePreferences[.twentyFour] = preferences(5)
        try store.saveSessionData(metadata)
        let before = try contents(folder)
        for (name, change) in invalidChanges {
            var invalid = metadata, value = GamePlayPreferences()
            change(&value); invalid.gamePreferences[.memory] = value
            XCTAssertThrowsError(try store.saveSessionData(invalid), name)
            XCTAssertEqual(try contents(folder), before, name)
        }
        XCTAssertEqual(try store.loadSessionData(), metadata)
    }

    func testEightGamePreferencesAndFractionalActiveProgressRemainIndependentAfterReload() throws {
        let folder = try directory(), store = try GameDataTransferStore(directory: folder)
        var metadata = GameSessionData()
        for (index, game) in GameID.allCases.enumerated() { metadata.gamePreferences[game] = preferences(index) }
        metadata.sessions[.memory] = GameSessionState(gameID: .memory, startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                     phase: .paused, elapsedSeconds: 19, elapsedFraction: 0.625, moves: 7)
        try store.saveSessionData(metadata)
        let restarted = try GameDataTransferStore(directory: folder)
        XCTAssertEqual(try restarted.loadSessionData(), metadata)
        var changed = metadata.gamePreferences[.memory]!
        changed.haptics.toggle(); changed.memoryMode = "hard"; changed.memoryRevealSeconds = 1.5
        let result = try restarted.updateSessionData { $0.gamePreferences[.memory] = changed }
        XCTAssertEqual(result.gamePreferences[.memory], changed)
        XCTAssertEqual(result.sessions, metadata.sessions)
        for game in GameID.allCases where game != .memory { XCTAssertEqual(result.gamePreferences[game], metadata.gamePreferences[game]) }
        XCTAssertEqual(try GameDataTransferStore(directory: folder).loadSessionData(), result)
    }

    func testScopedPreferenceImportCannotOverwriteOtherSevenSettingsOrActiveSession() throws {
        let source = try directory(), target = try directory()
        try SaveStore(directory: source).save(MemoryBoard(seed: 33), namespace: "memory")
        let sourceStore = try GameDataTransferStore(directory: source), targetStore = try GameDataTransferStore(directory: target)
        var incoming = GameSessionData(), existing = GameSessionData()
        for (index, game) in GameID.allCases.enumerated() {
            incoming.gamePreferences[game] = preferences(index)
            existing.gamePreferences[game] = preferences(7 - index)
        }
        existing.sessions[.maze] = GameSessionState(gameID: .maze, phase: .paused, elapsedSeconds: 51, elapsedFraction: 0.25, moves: 23)
        try sourceStore.saveSessionData(incoming); try targetStore.saveSessionData(existing)
        let archive = try sourceStore.exportArchive(scope: .game(.memory), preferences: AppPreferences())
        let result = try targetStore.applyArchive(archive).metadata
        XCTAssertEqual(result.gamePreferences[.memory], incoming.gamePreferences[.memory])
        for game in GameID.allCases where game != .memory { XCTAssertEqual(result.gamePreferences[game], existing.gamePreferences[game]) }
        XCTAssertEqual(result.sessions[.maze], existing.sessions[.maze])
        XCTAssertTrue(result.isValid)
    }
}
