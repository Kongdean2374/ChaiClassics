import XCTest
@testable import ChaiCore

/// Real 0.1.0 envelopes remain in place while all five 0.2.0 namespaces are added.
final class V020UpgradeTests: XCTestCase {
    private let legacyNamespaces = ["sudoku", "minesweeper", "sliding"]

    private func preparedStore() throws -> (URL, SaveStore, [String: Data]) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("v020-upgrade-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var originals: [String: Data] = [:]
        for namespace in legacyNamespaces {
            let fixture = try XCTUnwrap(Bundle.module.url(forResource: "v010-" + namespace,
                                                          withExtension: "json", subdirectory: "Fixtures"))
            let data = try Data(contentsOf: fixture)
            try data.write(to: directory.appendingPathComponent(namespace + ".json"))
            originals[namespace] = data
        }
        return (directory, try SaveStore(directory: directory), originals)
    }

    private func assertLegacyBytes(_ originals: [String: Data], directory: URL,
                                   file: StaticString = #filePath, line: UInt = #line) throws {
        for namespace in legacyNamespaces {
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(namespace + ".json")), originals[namespace],
                           "Upgrade must not rewrite \(namespace)", file: file, line: line)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(namespace + ".json.backup").path),
                           "Reading a legacy save must not rotate it", file: file, line: line)
        }
    }

    func testAllRealV010ProgressFieldsSurviveV020Loading() throws {
        let (directory, store, originals) = try preparedStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = try SudokuPuzzle.bundled()
        let sudoku = try XCTUnwrap(store.load(SudokuProgress.self, namespace: "sudoku"))
        let id = "sudoku.easy.0001"
        XCTAssertEqual(sudoku.currentID, id)
        XCTAssertEqual(sudoku.completed, [id])
        XCTAssertEqual(Set(sudoku.boards.keys), [id])
        let puzzle = try XCTUnwrap(catalog.first { $0.id == id })
        let sudokuBoard = try XCTUnwrap(sudoku.boards[id])
        XCTAssertTrue(sudokuBoard.isValidSave(for: puzzle))
        XCTAssertEqual(sudokuBoard.puzzleID, id)
        XCTAssertEqual(sudokuBoard.mode, .pencil)
        XCTAssertEqual(sudokuBoard.selected, 1)
        XCTAssertEqual(sudokuBoard.cells, [
            2,0,4,0,0,0,0,5,0, 0,1,5,0,0,2,7,0,8, 8,0,9,5,0,0,3,0,2,
            7,0,6,2,5,0,0,0,3, 0,0,0,6,9,0,0,0,0, 0,0,0,8,0,3,9,6,7,
            0,0,1,3,2,0,8,0,0, 5,2,0,7,0,4,6,1,0, 0,0,0,0,0,0,0,3,5
        ])
        XCTAssertEqual(sudokuBoard.notes.count, 81)
        XCTAssertEqual(sudokuBoard.notes[1], [2, 7])
        XCTAssertTrue(sudokuBoard.notes.enumerated().allSatisfy { $0.offset == 1 || $0.element.isEmpty })
        XCTAssertTrue(sudoku.isUnlocked(catalog[1], catalog: catalog))

        let mines = try XCTUnwrap(store.load(MinesweeperBoard.self, namespace: "minesweeper"))
        XCTAssertTrue(mines.isValidSave)
        XCTAssertEqual(mines.configuration, MineConfiguration.easy)
        XCTAssertEqual(mines.seed, 23)
        XCTAssertEqual(mines.mines, [30,31,32,39,41,48,49,50,70,71])
        XCTAssertEqual(mines.revealed, [
            0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,
            33,34,35,36,37,38,42,43,44,45,46,47,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,
            67,68,69,72,73,74,75,76,77,78
        ])
        XCTAssertEqual(mines.flags, [30])
        XCTAssertEqual(mines.status, .playing)
        XCTAssertEqual(mines.mode, .flag)
        XCTAssertEqual(mines.elapsedSeconds, 37)

        let sliding = try XCTUnwrap(store.load(SlidingBoard.self, namespace: "sliding"))
        XCTAssertTrue(sliding.isValidSave)
        XCTAssertEqual(sliding.size, 3)
        XCTAssertEqual(sliding.difficulty, .normal)
        XCTAssertEqual(sliding.initialTiles, [1,2,3,4,5,6,0,7,8])
        XCTAssertEqual(sliding.tiles, [1,2,3,4,5,6,7,0,8])
        XCTAssertEqual(sliding.moves, 35)
        XCTAssertEqual(sliding.elapsedSeconds, 91)
        try assertLegacyBytes(originals, directory: directory)
    }

    func testAddingFiveInProgressGamesReloadsEightNamespacesWithoutRewritingLegacyBytes() throws {
        let (directory, store, originals) = try preparedStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sudoku = try XCTUnwrap(store.load(SudokuProgress.self, namespace: "sudoku"))
        let mines = try XCTUnwrap(store.load(MinesweeperBoard.self, namespace: "minesweeper"))
        let sliding = try XCTUnwrap(store.load(SlidingBoard.self, namespace: "sliding"))

        var ticTacToe = TicTacToeBoard(mode: .localTwoPlayer, difficulty: .easy, seed: 20)
        XCTAssertTrue(ticTacToe.play(at: 0, by: .first))
        XCTAssertTrue(ticTacToe.play(at: 4, by: .second))
        ticTacToe.elapsedSeconds = 21
        XCTAssertTrue(ticTacToe.isValidSave)
        try store.save(ticTacToe, namespace: GameID.ticTacToe.rawValue)

        var connectFour = ConnectFourBoard(mode: .localTwoPlayer, difficulty: .easy, seed: 22)
        XCTAssertTrue(connectFour.drop(in: 3, player: .first))
        XCTAssertTrue(connectFour.drop(in: 2, player: .second))
        XCTAssertTrue(connectFour.drop(in: 3, player: .first))
        connectFour.elapsedSeconds = 32
        XCTAssertTrue(connectFour.isValidSave)
        try store.save(connectFour, namespace: GameID.connectFour.rawValue)

        var twentyFour = TwentyFourBoard(difficulty: .easy, seed: 24)
        XCTAssertTrue(twentyFour.combine(firstID: 0, secondID: 1, operation: .add))
        twentyFour.elapsedSeconds = 43
        XCTAssertTrue(twentyFour.isValidSave)
        try store.save(twentyFour, namespace: GameID.twentyFour.rawValue)

        var memory = MemoryBoard(mode: .easy, seed: 26)
        for index in memory.cards.indices where memory.cards[index] == 0 { XCTAssertTrue(memory.select(index)) }
        let unmatched = try XCTUnwrap(memory.cards.indices.first { !memory.matched[$0] })
        XCTAssertTrue(memory.select(unmatched))
        memory.elapsedSeconds = 54
        XCTAssertTrue(memory.isValidSave)
        try store.save(memory, namespace: GameID.memory.rawValue)

        var maze = MazeBoard(difficulty: .easy, seed: 28)
        let direction = try XCTUnwrap(MazeBoard.Direction.allCases.first { maze.canMove($0) })
        XCTAssertTrue(maze.move(direction))
        maze.elapsedSeconds = 65
        maze.pause()
        XCTAssertTrue(maze.isValidSave)
        try store.save(maze, namespace: GameID.maze.rawValue)

        try assertLegacyBytes(originals, directory: directory)
        let restarted = try SaveStore(directory: directory)
        XCTAssertEqual(try restarted.load(SudokuProgress.self, namespace: "sudoku"), sudoku)
        XCTAssertEqual(try restarted.load(MinesweeperBoard.self, namespace: "minesweeper"), mines)
        XCTAssertEqual(try restarted.load(SlidingBoard.self, namespace: "sliding"), sliding)
        XCTAssertEqual(try restarted.load(TicTacToeBoard.self, namespace: "tictactoe"), ticTacToe)
        XCTAssertEqual(try restarted.load(ConnectFourBoard.self, namespace: "connectfour"), connectFour)
        XCTAssertEqual(try restarted.load(TwentyFourBoard.self, namespace: "twentyfour"), twentyFour)
        XCTAssertEqual(try restarted.load(MemoryBoard.self, namespace: "memory"), memory)
        XCTAssertEqual(try restarted.load(MazeBoard.self, namespace: "maze"), maze)
        let savedFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }
        XCTAssertEqual(Set(savedFiles), Set(GameID.allCases.map(\.rawValue)))
        try assertLegacyBytes(originals, directory: directory)
    }

    func testCorruptAndFutureNewSavesNeverDeleteOrRewriteOtherNamespaces() throws {
        let (directory, store, originals) = try preparedStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let maze = MazeBoard(difficulty: .easy, seed: 40)
        try store.save(maze, namespace: "maze")
        let mazeData = try Data(contentsOf: directory.appendingPathComponent("maze.json"))
        let memoryURL = directory.appendingPathComponent("memory.json")
        try Data("{broken".utf8).write(to: memoryURL)
        XCTAssertThrowsError(try store.load(MemoryBoard.self, namespace: "memory"))
        try assertLegacyBytes(originals, directory: directory)
        XCTAssertEqual(try store.load(MazeBoard.self, namespace: "maze"), maze)

        let future = Data("{\"schemaVersion\":99,\"payload\":{}}".utf8)
        try future.write(to: memoryURL)
        XCTAssertThrowsError(try store.load(MemoryBoard.self, namespace: "memory")) { error in
            guard case SaveStore.StoreError.unsupportedVersion(99) = error else { return XCTFail("Expected future schema protection") }
        }
        XCTAssertThrowsError(try store.save(MemoryBoard(seed: 41), namespace: "memory"))
        XCTAssertEqual(try Data(contentsOf: memoryURL), future)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("maze.json")), mazeData)
        XCTAssertNotNil(try store.load(SudokuProgress.self, namespace: "sudoku"))
        XCTAssertNotNil(try store.load(MinesweeperBoard.self, namespace: "minesweeper"))
        XCTAssertNotNil(try store.load(SlidingBoard.self, namespace: "sliding"))
        try assertLegacyBytes(originals, directory: directory)
    }

    func testPersistentGameIDsContainExactlyEightPlayableGamesAndPreserveV010RawValues() throws {
        let expected = Set(["sudoku", "minesweeper", "sliding", "tictactoe", "connectfour", "twentyfour", "memory", "maze"])
        XCTAssertEqual(GameID.allCases.count, 8)
        XCTAssertEqual(Set(GameID.allCases.map(\.rawValue)), expected)
        XCTAssertEqual(Set(GameCatalog.playableGames.compactMap(\.gameID)), Set(GameID.allCases))
        for namespace in expected {
            XCTAssertEqual(try JSONDecoder().decode(GameID.self, from: JSONEncoder().encode(namespace)).rawValue, namespace)
        }
        let previewsAndFolders = GameCatalog.items.filter { $0.gameID == nil }
        XCTAssertEqual(previewsAndFolders.count, 19)
        for item in previewsAndFolders {
            XCTAssertNil(GameID(rawValue: item.id.rawValue))
            XCTAssertThrowsError(try JSONDecoder().decode(GameID.self, from: JSONEncoder().encode(item.id.rawValue)))
        }
    }
}
