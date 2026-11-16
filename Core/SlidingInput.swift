import Foundation

/// Maps a tile's physical swipe to one legal move into the neighboring blank.
/// Has no stored state and leaves the released board/save format unchanged.
public enum SlidingInput {
    public enum Direction { case left, right, up, down }
    public static func direction(tile: Int, board: SlidingBoard) -> Direction? {
        guard board.canMove(tile) else { return nil }
        if board.blank / board.size < tile / board.size { return .up }
        if board.blank / board.size > tile / board.size { return .down }
        return board.blank < tile ? .left : .right
    }
    public static func accepts(tile: Int, board: SlidingBoard, horizontal: Double, vertical: Double, minimumDistance: Double) -> Bool {
        guard horizontal.isFinite, vertical.isFinite, minimumDistance.isFinite, minimumDistance > 0,
              let direction = direction(tile: tile, board: board) else { return false }
        let along: Double, across: Double
        switch direction {
        case .left: along = -horizontal; across = vertical
        case .right: along = horizontal; across = vertical
        case .up: along = -vertical; across = horizontal
        case .down: along = vertical; across = horizontal
        }
        return along >= minimumDistance && along >= abs(across) * 1.3
    }
}
