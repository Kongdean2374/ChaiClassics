import Foundation

/// Transient presentation state. The board is saved before a disc starts moving;
/// abandoning an animation can therefore never discard an accepted game move.
public struct ConnectFourPresentation: Equatable, Sendable {
    public struct Drop: Equatable, Sendable, Identifiable {
        public let id: UInt64
        public let column: Int
        public let row: Int
        public let player: DuelPlayer
        public let history: [Int]
    }

    public private(set) var drop: Drop?
    private var generation: UInt64 = 0
    public init() {}
    public var isDropping: Bool { drop != nil }

    /// A visual drop must represent exactly one legal, already accepted move.
    /// While it is present a second input cannot begin another animation.
    @discardableResult public mutating func begin(before: ConnectFourBoard, after: ConnectFourBoard) -> Drop? {
        guard drop == nil, before.isValidSave, after.isValidSave,
              before.mode == after.mode, before.difficulty == after.difficulty,
              before.humanPlayer == after.humanPlayer, before.seed == after.seed,
              after.history.count == before.history.count + 1,
              after.history.dropLast().elementsEqual(before.history),
              let column = after.history.last, before.canDrop(in: column) else { return nil }
        let cells = before.cells
        guard let row = (0..<ConnectFourBoard.rows).last(where: { cells[$0 * ConnectFourBoard.columns + column] == nil }),
              after.cells[row * ConnectFourBoard.columns + column] == before.currentPlayer else { return nil }
        generation &+= 1
        let next = Drop(id: generation, column: column, row: row, player: before.currentPlayer, history: after.history)
        drop = next
        return next
    }

    /// Animation callbacks from an older round, pause or navigation are ignored.
    @discardableResult public mutating func settle(id: UInt64) -> Bool {
        guard drop?.id == id else { return false }
        drop = nil
        return true
    }

    public mutating func cancel() {
        generation &+= 1
        drop = nil
    }
}
