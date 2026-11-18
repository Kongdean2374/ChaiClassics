/// Transient input for number → operator → number. It is deliberately separate from the
/// saved puzzle: reopening a board never preselects an operator or reuses stale card IDs.
public struct TwentyFourInput: Equatable, Sendable {
    public enum Stage: String, Equatable, Sendable {
        case first, operation, second, ready
    }
    public private(set) var firstID: Int?
    public private(set) var operation: TwentyFourOperator?
    public private(set) var secondID: Int?

    public init() {}
    public var stage: Stage {
        if firstID == nil { return .first }
        if operation == nil { return .operation }
        return secondID == nil ? .second : .ready
    }
    public var isEmpty: Bool { firstID == nil }

    @discardableResult public mutating func selectCard(_ id: Int, in board: TwentyFourBoard) -> Bool {
        guard board.isValidSave, !board.isEnded, board.cards.contains(where: { $0.id == id }) else { return false }
        if firstID == id { clear() }
        else if firstID == nil || operation == nil { firstID = id; secondID = nil }
        else if secondID == id { secondID = nil }
        else { secondID = id }
        return true
    }
    @discardableResult public mutating func selectOperator(_ next: TwentyFourOperator) -> Bool {
        guard firstID != nil else { return false }
        operation = next
        return true
    }
    @discardableResult public mutating func swap() -> Bool {
        guard let first = firstID, let second = secondID else { return false }
        firstID = second; secondID = first
        return true
    }
    public mutating func clear() { firstID = nil; operation = nil; secondID = nil }
    @discardableResult public mutating func stepBack() -> Bool {
        if secondID != nil { secondID = nil }
        else if operation != nil { operation = nil }
        else if firstID != nil { firstID = nil }
        else { return false }
        return true
    }
    public mutating func reconcile(with board: TwentyFourBoard) {
        guard board.isValidSave, !board.isEnded,
              firstID.map({ id in board.cards.contains { $0.id == id } }) ?? true else { clear(); return }
        if let secondID, !board.cards.contains(where: { $0.id == secondID }) { self.secondID = nil }
    }
    public func canApply(to board: TwentyFourBoard) -> Bool {
        resolvedMove(in: board) != nil
    }
    public func resolvedMove(in board: TwentyFourBoard) -> TwentyFourMove? {
        guard let firstID, let operation, let secondID,
              board.canCombine(firstID: firstID, secondID: secondID, operation: operation) else { return nil }
        return TwentyFourMove(firstID: firstID, secondID: secondID, operation: operation)
    }
    public func result(in board: TwentyFourBoard) -> Rational? {
        guard canApply(to: board), let first = board.cards.first(where: { $0.id == firstID }),
              let second = board.cards.first(where: { $0.id == secondID }), let operation else { return nil }
        return first.value.applying(operation, to: second.value)
    }
}
