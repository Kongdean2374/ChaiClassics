import Foundation

/// A perfect maze: a connected tree of passages with one route between any two cells.
/// Layout generation is versioned so a saved seed always describes the same walls.
public struct MazeBoard: Codable, Equatable, Sendable {
    public enum Difficulty: String, Codable, CaseIterable, Sendable {
        case easy, normal, hard
        public var size: Int {
            switch self { case .easy: return 9; case .normal: return 15; case .hard: return 21 }
        }
    }

    public struct Cell: Codable, Equatable, Hashable, Sendable {
        public let row: Int
        public let column: Int
        public init(row: Int, column: Int) { self.row = row; self.column = column }
    }

    public enum Direction: String, Codable, CaseIterable, Sendable {
        case up, right, down, left
        public var opposite: Direction {
            switch self { case .up: return .down; case .right: return .left; case .down: return .up; case .left: return .right }
        }
        /// NESW wall bits; a set bit means a wall, not a passage.
        public var wallMask: UInt8 {
            switch self { case .up: return 1; case .right: return 2; case .down: return 4; case .left: return 8 }
        }
        public func neighbor(of cell: Cell) -> Cell {
            // Saturation also makes this public helper safe for untrusted coordinates.
            switch self {
            case .up: return Cell(row: cell.row == .min ? .min : cell.row - 1, column: cell.column)
            case .right: return Cell(row: cell.row, column: cell.column == .max ? .max : cell.column + 1)
            case .down: return Cell(row: cell.row == .max ? .max : cell.row + 1, column: cell.column)
            case .left: return Cell(row: cell.row, column: cell.column == .min ? .min : cell.column - 1)
            }
        }

        /// Classify one completed gesture. Its length never multiplies the move count.
        public static func fromSwipe(horizontal: Double, vertical: Double, minimumDistance: Double = 14) -> Direction? {
            guard horizontal.isFinite, vertical.isFinite, minimumDistance.isFinite, minimumDistance > 0,
                  max(abs(horizontal), abs(vertical)) >= minimumDistance else { return nil }
            return abs(horizontal) > abs(vertical) ? (horizontal > 0 ? .right : .left) : (vertical > 0 ? .down : .up)
        }
    }

    public let generationVersion: Int
    public let seed: UInt64
    public let difficulty: Difficulty
    public let walls: [UInt8]
    public private(set) var position: Cell
    /// Every accepted single-cell move, including backtracking. Never contains a hint.
    public private(set) var history: [Direction]
    public private(set) var isPaused: Bool
    public var elapsedSeconds: Int

    public var size: Int { difficulty.size }
    public var start: Cell { Cell(row: 0, column: 0) }
    public var goal: Cell { Cell(row: size - 1, column: size - 1) }
    public var moves: Int { history.count }
    public var isComplete: Bool { position == goal }
    private static let historyLimit = 1_000_000

    public init(difficulty: Difficulty, seed: UInt64 = UInt64.random(in: .min ... .max)) {
        generationVersion = 1
        self.seed = seed
        self.difficulty = difficulty
        walls = Self.generate(size: difficulty.size, seed: seed)
        position = Cell(row: 0, column: 0)
        history = []
        isPaused = false
        elapsedSeconds = 0
    }

    public func contains(_ cell: Cell) -> Bool {
        (0..<size).contains(cell.row) && (0..<size).contains(cell.column)
    }

    /// Invalid coordinates and missing wall data behave as closed walls.
    public func hasWall(_ direction: Direction, at cell: Cell) -> Bool {
        guard contains(cell), walls.count == size * size else { return true }
        let neighbor = direction.neighbor(of: cell)
        guard contains(neighbor) else { return true }
        return walls[cell.row * size + cell.column] & direction.wallMask != 0 ||
            walls[neighbor.row * size + neighbor.column] & direction.opposite.wallMask != 0
    }

    public func canMove(_ direction: Direction) -> Bool {
        !isPaused && !isComplete && history.count < Self.historyLimit &&
            contains(position) && !hasWall(direction, at: position)
    }

    @discardableResult
    public mutating func move(_ direction: Direction) -> Bool {
        guard canMove(direction) else { return false }
        position = direction.neighbor(of: position)
        history.append(direction)
        return true
    }

    public mutating func pause() { if !isComplete { isPaused = true } }
    public mutating func resume() { isPaused = false }
    public mutating func restart() {
        position = start
        history.removeAll(keepingCapacity: false)
        elapsedSeconds = 0
        isPaused = false
    }

    /// Validate the graph, the exact seeded layout, and a replay of all accepted input.
    /// A plausible position alone cannot authenticate a partially corrupted save.
    public var isValidSave: Bool {
        guard generationVersion == 1, elapsedSeconds >= 0,
              walls.count == size * size, walls.allSatisfy({ $0 < 16 }),
              contains(position), history.count <= Self.historyLimit,
              !(isPaused && isComplete) else { return false }
        var openings = 0
        for row in 0..<size {
            for column in 0..<size {
                let cell = Cell(row: row, column: column)
                let mask = walls[row * size + column]
                for direction in Direction.allCases {
                    let next = direction.neighbor(of: cell)
                    let closed = mask & direction.wallMask != 0
                    if contains(next) {
                        guard closed == (walls[next.row * size + next.column] & direction.opposite.wallMask != 0) else { return false }
                        if !closed { openings += 1 }
                    } else if !closed { return false }
                }
            }
        }
        guard openings == 2 * (size * size - 1),
              walls == Self.generate(size: size, seed: seed) else { return false }
        var cursor = start
        for direction in history {
            guard cursor != goal, !hasWall(direction, at: cursor) else { return false }
            cursor = direction.neighbor(of: cursor)
        }
        return cursor == position
    }

    /// Iterative depth-first carving avoids recursion limits and allocates O(cells).
    private static func generate(size: Int, seed: UInt64) -> [UInt8] {
        var rng = SeededRandom(seed: seed)
        var result = [UInt8](repeating: 15, count: size * size)
        var visited = [Bool](repeating: false, count: size * size)
        var stack = [0]
        visited[0] = true
        while let index = stack.last {
            let cell = Cell(row: index / size, column: index % size)
            let choices = Direction.allCases.filter { direction in
                let next = direction.neighbor(of: cell)
                return (0..<size).contains(next.row) && (0..<size).contains(next.column) && !visited[next.row * size + next.column]
            }
            guard !choices.isEmpty else { stack.removeLast(); continue }
            // Own the bounded sampling as well as the generator: Swift's randomElement
            // implementation is not part of the long-term saved-layout contract.
            let bound = UInt64(choices.count)
            let threshold = (UInt64(0) &- bound) % bound
            var sample = rng.next()
            while sample < threshold { sample = rng.next() }
            let direction = choices[Int(sample % bound)]
            let next = direction.neighbor(of: cell)
            let nextIndex = next.row * size + next.column
            result[index] &= ~direction.wallMask
            result[nextIndex] &= ~direction.opposite.wallMask
            visited[nextIndex] = true
            stack.append(nextIndex)
        }
        return result
    }
}
