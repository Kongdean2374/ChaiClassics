import XCTest
@testable import ChaiCore

final class MazeMotionTests: XCTestCase {
    private let frame = 1.0 / 120.0

    private func input(_ direction: MazeBoard.Direction) -> MazeMotion.Input {
        switch direction {
        case .up: return .init(x: 0, y: -1)
        case .right: return .init(x: 1, y: 0)
        case .down: return .init(x: 0, y: 1)
        case .left: return .init(x: -1, y: 0)
        }
    }

    private func horizontalBoard() throws -> MazeBoard {
        try XCTUnwrap((UInt64(0)..<100).lazy.map { MazeBoard(difficulty: .easy, seed: $0) }
            .first { $0.canMove(.right) })
    }

    private func arrive(_ direction: MazeBoard.Direction, motion: inout MazeMotion, board: inout MazeBoard,
                        file: StaticString = #filePath, line: UInt = #line) {
        let previous = board.position, count = board.moves
        for _ in 0..<120 {
            let update = motion.advance(delta: frame, input: input(direction), board: &board)
            XCTAssertEqual(motion.origin, board.position, file: file, line: line)
            XCTAssertTrue((0...1).contains(motion.progress), file: file, line: line)
            if update == .arrived(direction) {
                XCTAssertEqual(board.position, direction.neighbor(of: previous), file: file, line: line)
                XCTAssertEqual(board.moves, count + 1, file: file, line: line)
                return
            }
        }
        XCTFail("A legal corridor never reached its center", file: file, line: line)
    }

    private func route(_ board: MazeBoard) -> [MazeBoard.Direction] {
        var queue = [board.start], parents: [MazeBoard.Cell: (MazeBoard.Cell, MazeBoard.Direction)] = [:]
        var seen: Set<MazeBoard.Cell> = [board.start]
        var head = 0
        while head < queue.count {
            let cell = queue[head]; head += 1
            for direction in MazeBoard.Direction.allCases where !board.hasWall(direction, at: cell) {
                let next = direction.neighbor(of: cell)
                if seen.insert(next).inserted { parents[next] = (cell, direction); queue.append(next) }
            }
        }
        var cursor = board.goal, directions: [MazeBoard.Direction] = []
        while let (previous, direction) = parents[cursor] { directions.append(direction); cursor = previous }
        return Array(directions.reversed())
    }

    func testFractionalMovementDoesNotCommitOrChangeSavedBoard() throws {
        var board = try horizontalBoard()
        let saved = board
        var motion = MazeMotion(board: board)
        XCTAssertEqual(motion.advance(delta: frame, input: input(.right), board: &board), .moving)
        XCTAssertEqual(board, saved)
        XCTAssertEqual(motion.row, 0)
        XCTAssertEqual(motion.column, 5.0 / 120, accuracy: 1e-12)
        XCTAssertEqual(motion.target, MazeBoard.Cell(row: 0, column: 1))
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(board), try encoder.encode(saved))
    }

    func testLeftRightReversalChangesVelocityOnTheVeryNextFrame() throws {
        var board = try horizontalBoard()
        var motion = MazeMotion(board: board)
        for _ in 0..<10 { motion.advance(delta: frame, input: input(.right), board: &board) }
        let forward = motion.column
        motion.advance(delta: frame, input: input(.left), board: &board)
        XCTAssertLessThan(motion.column, forward)
        XCTAssertEqual(motion.column, forward - 5.0 / 120, accuracy: 1e-12)
        let backward = motion.column
        motion.advance(delta: frame, input: input(.right), board: &board)
        XCTAssertGreaterThan(motion.column, backward)
        XCTAssertEqual(motion.column, forward, accuracy: 1e-12)
        XCTAssertEqual(board.moves, 0)
        XCTAssertEqual(board.position, board.start)
    }

    func testReturningToOriginCreatesNoMoveAndCannotContinueThroughBoundary() throws {
        var board = try horizontalBoard()
        var motion = MazeMotion(board: board)
        for _ in 0..<5 { motion.advance(delta: frame, input: input(.right), board: &board) }
        for _ in 0..<12 { motion.advance(delta: frame, input: input(.left), board: &board) }
        XCTAssertEqual(motion.column, 0)
        XCTAssertEqual(motion.progress, 0)
        XCTAssertNil(motion.target)
        XCTAssertEqual(board.moves, 0)
        XCTAssertEqual(board.position, board.start)
        arrive(.right, motion: &motion, board: &board)
        XCTAssertEqual(board.history, [.right])
    }

    func testOnlyCenterArrivalCommitsOneMoveAndNoInputIsQueuedAfterIt() throws {
        var board = try horizontalBoard()
        var motion = MazeMotion(board: board)
        arrive(.right, motion: &motion, board: &board)
        XCTAssertEqual(motion.progress, 0)
        XCTAssertNil(motion.direction)
        let saved = board
        for _ in 0..<240 { motion.advance(delta: frame, input: .zero, board: &board) }
        XCTAssertEqual(board, saved)
        XCTAssertEqual(motion.column, Double(saved.position.column))
        XCTAssertTrue(board.isValidSave)
    }

    func testReleasingInputStopsBetweenCentersUntilNewInputArrives() throws {
        var board = try horizontalBoard()
        var motion = MazeMotion(board: board)
        for _ in 0..<8 { motion.advance(delta: frame, input: input(.right), board: &board) }
        let stopped = motion
        for _ in 0..<240 { motion.advance(delta: frame, input: .zero, board: &board) }
        XCTAssertEqual(motion, stopped)
        XCTAssertEqual(board.moves, 0)
        motion.advance(delta: frame, input: input(.left), board: &board)
        XCTAssertLessThan(motion.column, stopped.column)
    }

    func testDiagonalInputStaysOnAnOpenAxisAndNeverCutsACorner() {
        var board = MazeBoard(difficulty: .easy, seed: 42)
        XCTAssertTrue(board.hasWall(.right, at: board.start))
        XCTAssertTrue(board.canMove(.down))
        var motion = MazeMotion(board: board)
        let diagonal = MazeMotion.Input(x: 1, y: 1)
        for _ in 0..<10 { motion.advance(delta: frame, input: diagonal, board: &board) }
        XCTAssertEqual(motion.column, 0)
        XCTAssertGreaterThan(motion.row, 0)
        XCTAssertLessThan(motion.row, 1)
        let beforePerpendicular = motion
        for _ in 0..<40 { motion.advance(delta: frame, input: input(.right), board: &board) }
        XCTAssertEqual(motion, beforePerpendicular)
        XCTAssertEqual(board.position, board.start)
        XCTAssertEqual(board.moves, 0)
    }

    func testClosedWallsRejectEveryFrameWithoutChangingPositionOrHistory() {
        var board = MazeBoard(difficulty: .hard, seed: 42)
        let original = board
        for direction in MazeBoard.Direction.allCases where board.hasWall(direction, at: board.position) {
            var motion = MazeMotion(board: board)
            for _ in 0..<120 {
                XCTAssertEqual(motion.advance(delta: frame, input: input(direction), board: &board), .blocked(direction))
                XCTAssertEqual(motion.progress, 0)
                XCTAssertNil(motion.target)
            }
        }
        XCTAssertEqual(board, original)
    }

    func testLongFramesAreClampedAndCannotJumpAcrossCells() throws {
        var board = try horizontalBoard()
        var motion = MazeMotion(board: board)
        motion.advance(delta: 3_600, input: input(.right), board: &board)
        XCTAssertEqual(motion.column, 5.0 / 30, accuracy: 1e-12)
        XCTAssertEqual(board.moves, 0)
        for _ in 0..<100 {
            let previous = board.position, count = board.moves
            motion.advance(delta: 3_600, input: input(.right), board: &board)
            XCTAssertLessThanOrEqual(board.moves - count, 1)
            XCTAssertLessThanOrEqual(abs(board.position.row - previous.row) + abs(board.position.column - previous.column), 1)
        }
        XCTAssertTrue(board.isValidSave)
    }

    func testInvalidTimeAndInvalidVectorsCannotMoveThePlayer() throws {
        var board = try horizontalBoard()
        var motion = MazeMotion(board: board)
        for delta in [0.0, -1, .nan, .infinity, -.infinity] {
            XCTAssertEqual(motion.advance(delta: delta, input: input(.right), board: &board), .idle)
        }
        for vector in [MazeMotion.Input(x: .nan, y: 0), .init(x: 0, y: .infinity), .init(x: 0.02, y: 0.02)] {
            XCTAssertEqual(vector, .zero)
            motion.advance(delta: frame, input: vector, board: &board)
        }
        XCTAssertEqual(motion.progress, 0)
        XCTAssertEqual(board.moves, 0)
        let diagonal = MazeMotion.Input(x: 100, y: 100)
        XCTAssertEqual(hypot(diagonal.x, diagonal.y), 1, accuracy: 1e-12)
    }

    func testPauseAndResumeSettleAtLastSavedCellAndDiscardOldInput() throws {
        var board = try horizontalBoard()
        var motion = MazeMotion(board: board)
        arrive(.right, motion: &motion, board: &board)
        for _ in 0..<7 { motion.advance(delta: frame, input: input(.left), board: &board) }
        XCTAssertGreaterThan(motion.progress, 0)
        let savedPosition = board.position, savedMoves = board.moves
        board.pause()
        motion.advance(delta: frame, input: input(.left), board: &board)
        XCTAssertEqual(motion.column, Double(savedPosition.column))
        XCTAssertEqual(motion.progress, 0)
        XCTAssertNil(motion.target)
        board.resume()
        motion.advance(delta: frame, input: .zero, board: &board)
        XCTAssertEqual(board.position, savedPosition)
        XCTAssertEqual(board.moves, savedMoves)
        XCTAssertTrue(board.isValidSave)
    }

    func testRelaunchRestartAndDifferentSeedDiscardUnsavedFractions() throws {
        var board = try horizontalBoard()
        var motion = MazeMotion(board: board)
        arrive(.right, motion: &motion, board: &board)
        motion.advance(delta: frame, input: input(.left), board: &board)
        board.elapsedSeconds = 37
        let restored = try JSONDecoder().decode(MazeBoard.self, from: JSONEncoder().encode(board))
        let freshMotion = MazeMotion(board: restored)
        XCTAssertEqual(freshMotion.column, Double(board.position.column))
        XCTAssertEqual(freshMotion.progress, 0)
        XCTAssertEqual(restored.history, [.right])
        XCTAssertEqual(restored.elapsedSeconds, 37)
        board.restart()
        motion.settle(on: board)
        XCTAssertEqual(motion.row, 0)
        XCTAssertEqual(motion.column, 0)
        XCTAssertEqual(board.moves, 0)
        motion.advance(delta: frame, input: input(.right), board: &board)
        board = MazeBoard(difficulty: .normal, seed: 999)
        motion.advance(delta: frame, input: .zero, board: &board)
        XCTAssertEqual(motion.origin, board.start)
        XCTAssertNil(motion.target)
        XCTAssertEqual(motion.progress, 0)
    }

    func testAnalogRoutesAtAllSizesReachTheRealGoalAndStopWithoutExtraMoves() {
        for difficulty in MazeBoard.Difficulty.allCases {
            for seed in UInt64(0)..<8 {
                var board = MazeBoard(difficulty: difficulty, seed: seed)
                var motion = MazeMotion(board: board)
                let directions = route(board)
                XCTAssertFalse(directions.isEmpty)
                for direction in directions { arrive(direction, motion: &motion, board: &board) }
                XCTAssertTrue(board.isComplete)
                XCTAssertEqual(board.history, directions)
                XCTAssertEqual(motion.row, Double(board.goal.row))
                XCTAssertEqual(motion.column, Double(board.goal.column))
                let completed = board
                for direction in MazeBoard.Direction.allCases {
                    for _ in 0..<30 { motion.advance(delta: frame, input: input(direction), board: &board) }
                }
                XCTAssertEqual(board, completed)
                XCTAssertTrue(board.isValidSave)
            }
        }
    }
}
