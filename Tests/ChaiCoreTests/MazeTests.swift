import XCTest
@testable import ChaiCore

final class MazeTests: XCTestCase {
    private struct Analysis {
        let path: [MazeBoard.Direction]
        let reachable: Int
        let passages: Int
        let wallsValid: Bool
    }

    /// Independent breadth-first graph audit, deliberately reading raw wall masks.
    private func analyze(_ board: MazeBoard) -> Analysis {
        var valid = board.walls.count == board.size * board.size
        var passages = 0
        var parents: [MazeBoard.Cell: (MazeBoard.Cell, MazeBoard.Direction)] = [:]
        var queue = [board.start]
        var seen: Set<MazeBoard.Cell> = [board.start]
        var head = 0
        for row in 0..<board.size {
            for column in 0..<board.size {
                let cell = MazeBoard.Cell(row: row, column: column)
                let mask = board.walls[row * board.size + column]
                valid = valid && mask < 16
                for direction in MazeBoard.Direction.allCases {
                    let neighbor = direction.neighbor(of: cell)
                    let closed = mask & direction.wallMask != 0
                    if !board.contains(neighbor) { valid = valid && closed; continue }
                    let reciprocal = board.walls[neighbor.row * board.size + neighbor.column] & direction.opposite.wallMask != 0
                    valid = valid && (closed == reciprocal)
                    if !closed { passages += 1 }
                }
            }
        }
        while head < queue.count {
            let cell = queue[head]; head += 1
            for direction in MazeBoard.Direction.allCases {
                let neighbor = direction.neighbor(of: cell)
                guard board.contains(neighbor), board.walls[cell.row * board.size + cell.column] & direction.wallMask == 0,
                      !seen.contains(neighbor) else { continue }
                seen.insert(neighbor)
                parents[neighbor] = (cell, direction)
                queue.append(neighbor)
            }
        }
        var path: [MazeBoard.Direction] = []
        var cursor = board.goal
        while let (previous, direction) = parents[cursor] {
            path.append(direction); cursor = previous
        }
        return Analysis(path: Array(path.reversed()), reachable: seen.count, passages: passages / 2, wallsValid: valid)
    }

    func testMoreThanOneThousandSeedsAtEverySizeArePerfectAndPlayable() {
        for difficulty in MazeBoard.Difficulty.allCases {
            for seed in UInt64(0)..<1_025 {
                var board = MazeBoard(difficulty: difficulty, seed: seed)
                let audit = analyze(board)
                XCTAssertTrue(audit.wallsValid, "\(difficulty) seed \(seed)")
                XCTAssertEqual(audit.reachable, board.size * board.size)
                XCTAssertEqual(audit.passages, board.size * board.size - 1)
                XCTAssertFalse(audit.path.isEmpty)
                XCTAssertFalse(board.isComplete)
                XCTAssertEqual(board.moves, 0)
                // Each wall direction must reject input without changing any saved state.
                for direction in MazeBoard.Direction.allCases where board.hasWall(direction, at: board.position) {
                    let before = board
                    XCTAssertFalse(board.move(direction))
                    XCTAssertEqual(before, board)
                }
                var legal = true
                for direction in audit.path {
                    let previous = board.position
                    let count = board.moves
                    legal = legal && board.canMove(direction) && board.move(direction)
                    legal = legal && abs(board.position.row - previous.row) + abs(board.position.column - previous.column) == 1
                    legal = legal && board.moves == count + 1
                }
                XCTAssertTrue(legal)
                XCTAssertEqual(board.position, board.goal)
                XCTAssertTrue(board.isComplete)
                XCTAssertEqual(board.moves, audit.path.count)
                XCTAssertTrue(board.isValidSave)
                let terminal = board
                for direction in MazeBoard.Direction.allCases { XCTAssertFalse(board.move(direction)) }
                XCTAssertEqual(board, terminal)
            }
        }
    }

    func testSeedReplayDistinctSizesAndNewLayouts() {
        XCTAssertEqual(MazeBoard.Difficulty.allCases.map(\.size), [9, 15, 21])
        XCTAssertEqual(Array(MazeBoard(difficulty: .easy, seed: 42).walls.prefix(18)), [11, 9, 3, 13, 5, 3, 9, 5, 3, 10, 10, 12, 5, 3, 8, 6, 11, 10])
        for level in MazeBoard.Difficulty.allCases {
            XCTAssertEqual(MazeBoard(difficulty: level, seed: 42), MazeBoard(difficulty: level, seed: 42))
            let layouts = (0..<32).map { MazeBoard(difficulty: level, seed: UInt64($0)).walls }
            XCTAssertEqual(Set(layouts).count, 32)
        }
        XCTAssertNotEqual(MazeBoard(difficulty: .easy).seed, MazeBoard(difficulty: .easy).seed)
    }

    func testBacktrackingPauseRestoreAndRestartPreserveTheSameMaze() throws {
        for difficulty in MazeBoard.Difficulty.allCases {
            var board = MazeBoard(difficulty: difficulty, seed: 817)
            let original = board
            let first = try XCTUnwrap(analyze(board).path.first)
            XCTAssertTrue(board.move(first))
            XCTAssertTrue(board.move(first.opposite))
            XCTAssertEqual(board.position, board.start)
            XCTAssertEqual(board.moves, 2)
            board.elapsedSeconds = 37
            board.pause()
            let paused = board
            XCTAssertTrue(board.isPaused)
            for direction in MazeBoard.Direction.allCases { XCTAssertFalse(board.move(direction)) }
            XCTAssertEqual(board, paused)
            XCTAssertTrue(board.isValidSave)
            let data = try JSONEncoder().encode(board)
            board = try JSONDecoder().decode(MazeBoard.self, from: data)
            XCTAssertEqual(board, paused)
            board.resume()
            XCTAssertTrue(board.move(first))
            XCTAssertEqual(board.elapsedSeconds, 37)
            board.restart()
            XCTAssertEqual(board, original)
            XCTAssertTrue(board.isValidSave)
        }
    }

    func testEveryDirectionalWallRejectsWithoutIncrementingMoves() {
        for difficulty in MazeBoard.Difficulty.allCases {
            var board = MazeBoard(difficulty: difficulty, seed: 19)
            let path = analyze(board).path
            for direction in path {
                for wall in MazeBoard.Direction.allCases where board.hasWall(wall, at: board.position) {
                    let before = board
                    XCTAssertFalse(board.canMove(wall))
                    XCTAssertFalse(board.move(wall))
                    XCTAssertEqual(before, board)
                }
                XCTAssertTrue(board.move(direction))
            }
        }
    }

    func testRealStoreRoundTripAndOtherNamespacesRemainIntact() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaveStore(directory: directory)
        try store.save(["old": 17], namespace: "sudoku")
        for difficulty in MazeBoard.Difficulty.allCases {
            var board = MazeBoard(difficulty: difficulty, seed: 710)
            for direction in analyze(board).path.prefix(7) { board.move(direction) }
            board.elapsedSeconds = 72
            board.pause()
            try store.save(board, namespace: "maze")
            let reloaded = try XCTUnwrap(SaveStore(directory: directory).load(MazeBoard.self, namespace: "maze"))
            XCTAssertTrue(reloaded.isValidSave)
            XCTAssertEqual(reloaded, board)
        }
        XCTAssertEqual(try store.load([String: Int].self, namespace: "sudoku"), ["old": 17])
    }

    private func changed(_ board: MazeBoard, _ edit: (inout [String: Any]) -> Void) throws -> MazeBoard {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(board)) as? [String: Any])
        edit(&json)
        return try JSONDecoder().decode(MazeBoard.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testCorruptionCannotInventWallsPositionHistoryOrCompletion() throws {
        let original = MazeBoard(difficulty: .easy, seed: 44)
        let validPath = analyze(original).path
        let invalid: [(inout [String: Any]) -> Void] = [
            { $0["generationVersion"] = 2 },
            { $0["seed"] = 99 },
            { $0["difficulty"] = "hard" },
            { $0["elapsedSeconds"] = -1 },
            { $0["walls"] = [] },
            { $0["walls"] = [Int](repeating: 0, count: 81) },
            { $0["walls"] = [Int](repeating: 15, count: 81) },
            { $0["walls"] = [Int](repeating: 16, count: 81) },
            { $0["position"] = ["row": -1, "column": 0] },
            { $0["position"] = ["row": Int.max, "column": Int.min] },
            { $0["position"] = ["row": 8, "column": 8] },
            { $0["history"] = ["up"] },
            { $0["history"] = [validPath[0].rawValue] },
            { json in
                var walls = original.walls.map(Int.init)
                walls[0] &= ~1 // exterior opening
                json["walls"] = walls
            },
            { json in
                var walls = original.walls.map(Int.init)
                walls[0] ^= 2 // asymmetric internal wall
                json["walls"] = walls
            },
            { json in
                var walls = original.walls.map(Int.init)
                walls[0] ^= 2; walls[1] ^= 8 // reciprocal graph modification
                json["walls"] = walls
            }
        ]
        for mutate in invalid {
            let corrupted = try changed(original, mutate)
            XCTAssertFalse(corrupted.isValidSave)
            // Public collision helpers must remain safe even before a load is rejected.
            _ = corrupted.canMove(.left)
            XCTAssertTrue(corrupted.hasWall(.left, at: .init(row: Int.max, column: Int.min)))
        }
        var won = original
        for direction in validPath { won.move(direction) }
        XCTAssertTrue(won.isValidSave)
        XCTAssertFalse(try changed(won) { $0["isPaused"] = true }.isValidSave)
        XCTAssertFalse(try changed(won) { $0["history"] = (validPath + [.up]).map(\.rawValue) }.isValidSave)
        XCTAssertFalse(try changed(original) { $0["history"] = Array(repeating: "up", count: 1_000_001) }.isValidSave)
        XCTAssertThrowsError(try changed(original) { $0["difficulty"] = "future" })
        XCTAssertThrowsError(try changed(original) { $0["history"] = ["teleport"] })
        XCTAssertThrowsError(try changed(original) { $0["walls"] = [-1] })
    }

    func testCoordinateAndClosedBoundaryHelpersAreSafe() {
        let board = MazeBoard(difficulty: .easy, seed: 0)
        for cell in [MazeBoard.Cell(row: -1, column: 0), .init(row: 0, column: -1), .init(row: 9, column: 0), .init(row: Int.max, column: Int.min)] {
            XCTAssertFalse(board.contains(cell))
            for direction in MazeBoard.Direction.allCases { XCTAssertTrue(board.hasWall(direction, at: cell)) }
        }
        XCTAssertEqual(MazeBoard.Direction.up.neighbor(of: .init(row: Int.min, column: 0)).row, Int.min)
        XCTAssertEqual(MazeBoard.Direction.down.neighbor(of: .init(row: Int.max, column: 0)).row, Int.max)
        XCTAssertTrue(board.hasWall(.up, at: board.start))
        XCTAssertTrue(board.hasWall(.left, at: board.start))
        XCTAssertTrue(board.hasWall(.down, at: board.goal))
        XCTAssertTrue(board.hasWall(.right, at: board.goal))
    }

    func testSwipeThresholdDirectionAndSingleStepRegardlessOfDistance() throws {
        XCTAssertNil(MazeBoard.Direction.fromSwipe(horizontal: 13, vertical: 0))
        XCTAssertNil(MazeBoard.Direction.fromSwipe(horizontal: .nan, vertical: 50))
        XCTAssertNil(MazeBoard.Direction.fromSwipe(horizontal: .infinity, vertical: 0))
        XCTAssertNil(MazeBoard.Direction.fromSwipe(horizontal: 20, vertical: 0, minimumDistance: 0))
        XCTAssertEqual(MazeBoard.Direction.fromSwipe(horizontal: 20, vertical: 3), .right)
        XCTAssertEqual(MazeBoard.Direction.fromSwipe(horizontal: -20, vertical: 3), .left)
        XCTAssertEqual(MazeBoard.Direction.fromSwipe(horizontal: 3, vertical: -20), .up)
        XCTAssertEqual(MazeBoard.Direction.fromSwipe(horizontal: 3, vertical: 20), .down)
        var board = MazeBoard(difficulty: .easy, seed: 42)
        let direction = try XCTUnwrap(analyze(board).path.first)
        let x: Double = direction == .left ? -10_000 : direction == .right ? 10_000 : 0
        let y: Double = direction == .up ? -10_000 : direction == .down ? 10_000 : 0
        let input = try XCTUnwrap(MazeBoard.Direction.fromSwipe(horizontal: x, vertical: y))
        XCTAssertTrue(board.move(input))
        XCTAssertEqual(board.moves, 1)
        XCTAssertEqual(abs(board.position.row - board.start.row) + abs(board.position.column - board.start.column), 1)
    }

    func testHardGenerationAndSaveValidationHaveBoundedCost() {
        let start = Date()
        for seed in UInt64(0)..<250 {
            XCTAssertTrue(MazeBoard(difficulty: .hard, seed: seed).isValidSave)
        }
        // A generous regression bound for unoptimized CI runners, not a timing benchmark.
        XCTAssertLessThan(Date().timeIntervalSince(start), 8)
    }
}
