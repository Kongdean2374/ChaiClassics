import Foundation

public enum SolitaireDragSource: Equatable, Sendable {
    case pile(CardPlace, index: Int)
    case tableau(Int)
}

public enum SolitaireDropTarget: Hashable, Sendable {
    case pile(CardPlace)
    case tableau(Int)
}

/// A transient drag, never part of the Codable save. Cancelling or hovering
/// cannot mutate cards. A changed deal, draw, undo or earlier drop invalidates it.
public struct SolitaireDragIntent: Equatable, Sendable {
    private let snapshot: SolitaireBoard
    public let source: SolitaireDragSource
    public let cards: [PlayingCard]
    public func effectiveSuit(_ card: PlayingCard) -> Int { snapshot.effectiveSuit(card) }

    public init?(board: SolitaireBoard, source: SolitaireDragSource) {
        guard board.isValidSave, !board.isComplete else { return nil }
        let cards: [PlayingCard]
        switch source {
        case .pile(let place, let index):
            if board.variant == .pyramid, place == .waste {
                guard index == board.waste.count - 1, let card = board.waste.last else { return nil }
                cards = [card]
            } else {
                guard let moving = board.movableCards(from: place, index: index) else { return nil }
                cards = moving
            }
        case .tableau(let index):
            guard board.variant == .pyramid || board.variant == .tripeaks,
                  board.isExposed(index), let card = board.tableau[index] else { return nil }
            cards = [card]
        }
        snapshot = board; self.source = source; self.cards = cards
    }

    public func canDrop(on target: SolitaireDropTarget, in board: SolitaireBoard) -> Bool {
        guard board == snapshot else { return false }
        switch (source, target) {
        case (.pile(let from, let index), .pile(let to)) where board.variant != .pyramid:
            return board.canMove(from: from, index: index, to: to)
        case (.tableau(let index), .pile(.waste)) where board.variant == .tripeaks:
            return board.canRemoveTriPeak(index)
        default:
            guard board.variant == .pyramid, let from = pyramidIndex(source), let to = pyramidIndex(target) else { return false }
            return board.canRemovePyramid(from, to)
        }
    }

    @discardableResult public func apply(on target: SolitaireDropTarget, to board: inout SolitaireBoard) -> Bool {
        guard canDrop(on: target, in: board) else { return false }
        switch (source, target) {
        case (.pile(let from, let index), .pile(let to)) where board.variant != .pyramid:
            return board.move(from: from, index: index, to: to)
        case (.tableau(let index), .pile(.waste)) where board.variant == .tripeaks:
            return board.removeTriPeak(index)
        default:
            guard let from = pyramidIndex(source), let to = pyramidIndex(target) else { return false }
            return board.removePyramid(from, to)
        }
    }

    private func pyramidIndex(_ source: SolitaireDragSource) -> Int? {
        switch source { case .tableau(let index): return index; case .pile(.waste, _): return -1; default: return nil }
    }
    private func pyramidIndex(_ target: SolitaireDropTarget) -> Int? {
        switch target { case .tableau(let index): return index; case .pile(.waste): return -1; default: return nil }
    }
}
