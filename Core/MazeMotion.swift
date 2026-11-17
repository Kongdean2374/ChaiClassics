import Foundation

/// Transient presentation state, deliberately excluded from MazeBoard's save format.
/// A segment always joins the saved cell to one legal orthogonal neighbor.
public struct MazeMotion: Equatable, Sendable {
    public struct Input: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public static let zero = Input(x: 0, y: 0)
        public static let deadZone = 0.08

        /// Screen coordinates: positive x is right and positive y is down.
        public init(x: Double, y: Double) {
            guard x.isFinite, y.isFinite else { self.x = 0; self.y = 0; return }
            let length = hypot(x, y)
            guard length.isFinite, length > Self.deadZone else { self.x = 0; self.y = 0; return }
            let scale = max(1, length)
            self.x = x / scale
            self.y = y / scale
        }

        public var isZero: Bool { x == 0 && y == 0 }

        fileprivate func component(along direction: MazeBoard.Direction) -> Double {
            switch direction { case .up: return -y; case .right: return x; case .down: return y; case .left: return -x }
        }

        fileprivate var directions: [MazeBoard.Direction] {
            let horizontal: MazeBoard.Direction = x >= 0 ? .right : .left
            let vertical: MazeBoard.Direction = y >= 0 ? .down : .up
            let ordered = abs(x) >= abs(y) ? [horizontal, vertical] : [vertical, horizontal]
            return ordered.filter { component(along: $0) > Self.deadZone }
        }
    }

    public enum Update: Equatable, Sendable {
        case idle
        case moving
        case blocked(MazeBoard.Direction)
        case arrived(MazeBoard.Direction)
    }

    public static let cellsPerSecond = 5.0
    /// Discard suspended-frame time instead of catching up with a jump or queued moves.
    public static let maximumFrameDelta = 1.0 / 30.0
    public private(set) var origin: MazeBoard.Cell
    public private(set) var target: MazeBoard.Cell?
    public private(set) var progress: Double = 0
    public private(set) var direction: MazeBoard.Direction?
    private var seed: UInt64
    private var difficulty: MazeBoard.Difficulty

    public init(board: MazeBoard) {
        origin = board.position
        seed = board.seed
        difficulty = board.difficulty
    }

    /// Fractional cell coordinates; drawing adds half a cell to reach its center.
    public var row: Double {
        Double(origin.row) + Double((target?.row ?? origin.row) - origin.row) * progress
    }
    public var column: Double {
        Double(origin.column) + Double((target?.column ?? origin.column) - origin.column) * progress
    }

    /// Pause, scene changes and failed persistence discard only the unsaved fraction.
    public mutating func settle(on board: MazeBoard) {
        origin = board.position
        seed = board.seed
        difficulty = board.difficulty
        clearSegment()
    }

    /// Reads only the current vector; there is no direction buffer or pending move queue.
    /// At most one center can be reached per call. Only that arrival calls board.move.
    @discardableResult
    public mutating func advance(delta: TimeInterval, input: Input, board: inout MazeBoard) -> Update {
        if origin != board.position || seed != board.seed || difficulty != board.difficulty {
            settle(on: board)
        }
        guard !board.isPaused, !board.isComplete else { settle(on: board); return .idle }
        guard delta.isFinite, delta > 0, !input.isZero else { return .idle }
        let elapsed = min(delta, Self.maximumFrameDelta)

        if direction == nil {
            let choices = input.directions
            guard let next = choices.first(where: { board.canMove($0) }) else {
                return choices.first.map(Update.blocked) ?? .idle
            }
            direction = next
            target = next.neighbor(of: origin)
        }
        guard let direction, let target,
              board.contains(target), !board.hasWall(direction, at: origin) else {
            settle(on: board)
            return .idle
        }

        // A perpendicular vector cannot turn or cut a corner between cell centers.
        // Its projection may be negative, so an opposite input reverses this frame.
        let velocity = input.component(along: direction)
        guard abs(velocity) > Input.deadZone else { return .idle }
        let nextProgress = progress + velocity * Self.cellsPerSecond * elapsed
        if nextProgress <= 0 {
            clearSegment()
            return .idle
        }
        if nextProgress >= 1 - 1e-12 {
            guard board.move(direction) else { settle(on: board); return .blocked(direction) }
            origin = board.position
            clearSegment()
            return .arrived(direction)
        }
        progress = nextProgress
        return .moving
    }

    private mutating func clearSegment() {
        target = nil
        direction = nil
        progress = 0
    }
}
