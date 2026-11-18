import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum SolitaireDragSource: Equatable, Sendable {
    case pile(CardPlace, index: Int)
    case tableau(Int)
}

public enum SolitaireDropTarget: Hashable, Sendable {
    case pile(CardPlace)
    case tableau(Int)
}

/// Layout and hit testing share the same unscaled rectangles. The board view
/// converts finger positions to these coordinates, even after a pinch or pan.
public struct SolitaireTableLayout {
    public static let cardSize = CGSize(width: 56, height: 76)
    public static let peakSize = CGSize(width: 52, height: 72)
    public static let faceUpStep: CGFloat = 28
    public static let faceDownStep: CGFloat = 15

    public struct Slot: Identifiable {
        public let id: CardPlace
        public let frame: CGRect
    }

    public let size: CGSize
    public let stock: CGRect
    public let slots: [Slot]
    public let columns: [[CGRect]]
    public let columnTargets: [CGRect]
    public let peaks: [CGRect]

    public init(board: SolitaireBoard) {
        let cardSize = Self.cardSize
        func topFrame(_ index: Int) -> CGRect {
            CGRect(origin: CGPoint(x: CGFloat(4 + index * 64), y: 6), size: cardSize)
        }
        stock = topFrame(0)
        let places: [(CardPlace, Int)]
        switch board.variant {
        case .klondike:
            places = [(.waste, 1)] + (0..<4).map { (.foundation($0), $0 + 3) }
        case .freecell:
            places = (0..<4).map { (.freeCell($0), $0) } + (0..<4).map { (.foundation($0), $0 + 4) }
        case .spider:
            places = []
        case .pyramid, .tripeaks:
            places = [(.waste, 1)]
        }
        slots = places.map { Slot(id: $0.0, frame: topFrame($0.1)) }

        columns = board.columns.enumerated().map { index, cards in
            var y: CGFloat = 116
            return cards.map { card in
                let frame = CGRect(origin: CGPoint(x: CGFloat(4 + index * 64), y: y), size: cardSize)
                y += board.faceUp.contains(card.id) ? Self.faceUpStep : Self.faceDownStep
                return frame
            }
        }
        columnTargets = columns.enumerated().map { index, cards in
            let height = (cards.last?.maxY ?? (116 + cardSize.height)) - 116
            return CGRect(x: CGFloat(index * 64), y: 116, width: 64, height: height + 12)
        }
        if board.variant == .pyramid || board.variant == .tripeaks {
            let pyramid = board.variant == .pyramid
            peaks = board.tableau.indices.map { index in
                let point = Self.peakOrigin(index, pyramid: pyramid)
                return CGRect(origin: point, size: Self.peakSize)
            }
            size = CGSize(width: pyramid ? 420 : 600, height: (peaks.last?.maxY ?? 116) + 8)
        } else {
            peaks = []
            size = CGSize(width: CGFloat(board.columns.count * 64), height: (columnTargets.map(\.maxY).max() ?? 208) + 4)
        }
    }

    public func source(at point: CGPoint, in board: SolitaireBoard) -> (SolitaireDragSource, CGRect)? {
        if let slot = slots.first(where: { $0.frame.contains(point) }) {
            return (.pile(slot.id, index: board.cards(at: slot.id).count - 1), slot.frame)
        }
        if let index = peakIndex(at: point, in: board) { return (.tableau(index), peaks[index]) }
        guard let column = columnTargets.firstIndex(where: { $0.contains(point) }),
              let index = columns[column].lastIndex(where: { $0.contains(point) }) else { return nil }
        return (.pile(.column(column), index: index), columns[column][index])
    }

    public func target(at point: CGPoint, in board: SolitaireBoard) -> SolitaireDropTarget? {
        if let slot = slots.first(where: { $0.frame.insetBy(dx: -3, dy: -3).contains(point) }) { return .pile(slot.id) }
        if let index = peakIndex(at: point, in: board) { return .tableau(index) }
        return columnTargets.firstIndex(where: { $0.contains(point) }).map { .pile(.column($0)) }
    }

    private func peakIndex(at point: CGPoint, in board: SolitaireBoard) -> Int? {
        peaks.indices.last { board.tableau[$0] != nil && peaks[$0].contains(point) }
    }

    private static func peakOrigin(_ index: Int, pyramid: Bool) -> CGPoint {
        if pyramid {
            var row = 0
            while (row + 1) * (row + 2) / 2 <= index { row += 1 }
            let column = index - row * (row + 1) / 2
            let x = (6 - row) * 29 + column * 58 + 8
            let y = 116 + row * 44
            return CGPoint(x: CGFloat(x), y: CGFloat(y))
        }
        if index < 3 { return CGPoint(x: CGFloat(index * 174 + 64), y: 116) }
        if index < 9 {
            let offset = index - 3
            let x = (offset / 2) * 174 + (offset % 2) * 58 + 35
            return CGPoint(x: CGFloat(x), y: 157)
        }
        if index < 18 {
            let offset = index - 9
            let x = (offset / 3) * 174 + (offset % 3) * 58 + 6
            return CGPoint(x: CGFloat(x), y: 198)
        }
        return CGPoint(x: CGFloat((index - 18) * 58 + 6), y: 239)
    }
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

    /// Double-tapping may send a single exposed card to the first legal
    /// foundation. Never move cards already in a foundation or auto-play a run.
    public func foundationTarget(in board: SolitaireBoard) -> SolitaireDropTarget? {
        guard board.variant == .klondike || board.variant == .freecell, cards.count == 1 else { return nil }
        if case .pile(.foundation, _) = source { return nil }
        return board.foundations.indices.map { SolitaireDropTarget.pile(.foundation($0)) }
            .first { canDrop(on: $0, in: board) }
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
