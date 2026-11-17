import Foundation

/// A memory turn is either waiting for a card, showing one card, or waiting for
/// an unmatched pair to close. Matching pairs are committed synchronously.
public struct MemoryBoard: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case easy, normal, hard
        public var columns: Int { self == .hard ? 6 : 4 }
        public var rows: Int {
            switch self { case .easy: return 4; case .normal: return 5; case .hard: return 6 }
        }
        public var cardCount: Int { columns * rows }
        public var pairCount: Int { cardCount / 2 }
    }

    public enum Phase: Equatable, Sendable { case ready, oneCard, mismatch, complete }

    /// These SF Symbols are bundled by the operating system and work offline.
    public static let symbols = [
        "sun.max.fill", "moon.fill", "star.fill", "heart.fill", "leaf.fill", "flame.fill",
        "bolt.fill", "drop.fill", "cloud.fill", "snowflake", "fish.fill", "bird.fill",
        "tortoise.fill", "hare.fill", "pawprint.fill", "bell.fill", "gift.fill", "cup.and.saucer.fill"
    ]

    public let mode: Mode
    public let seed: UInt64
    /// Each value identifies one of `symbols`, appearing exactly twice.
    public private(set) var cards: [Int]
    public private(set) var matched: [Bool]
    public private(set) var selectedIndices: [Int] = []
    public private(set) var moves = 0
    public var elapsedSeconds = 0

    public init(mode: Mode = .easy, seed: UInt64 = UInt64.random(in: .min ... .max)) {
        self.mode = mode
        self.seed = seed
        var random = SeededRandom(seed: seed)
        cards = (0..<mode.pairCount).flatMap { [$0, $0] }.shuffled(using: &random)
        matched = Array(repeating: false, count: mode.cardCount)
    }

    public var matchedPairCount: Int { matched.filter { $0 }.count / 2 }
    public var isComplete: Bool { matched.count == mode.cardCount && matched.allSatisfy { $0 } }
    public var phase: Phase {
        if isComplete { return .complete }
        switch selectedIndices.count { case 1: return .oneCard; case 2: return .mismatch; default: return .ready }
    }

    public func isFaceUp(_ index: Int) -> Bool {
        guard matched.indices.contains(index) else { return false }
        return matched[index] || selectedIndices.contains(index)
    }

    public func canSelect(_ index: Int) -> Bool {
        isValidSave && cards.indices.contains(index) && !isComplete && selectedIndices.count < 2 && !isFaceUp(index)
    }

    /// Returns false for repeat taps, a third card, out-of-range taps, or a
    /// completed/invalid board. No asynchronous work ever mutates this state.
    @discardableResult public mutating func select(_ index: Int) -> Bool {
        guard canSelect(index) else { return false }
        selectedIndices.append(index)
        if selectedIndices.count == 2 {
            moves += 1
            let first = selectedIndices[0], second = selectedIndices[1]
            if cards[first] == cards[second] {
                matched[first] = true
                matched[second] = true
                selectedIndices.removeAll()
            }
        }
        return true
    }

    /// The view calls this after its readable mismatch delay. A caller can
    /// supply the expected turn so a canceled/stale task cannot close a new one.
    @discardableResult public mutating func resolveMismatch(expectedMoves: Int? = nil,
                                                           expectedSelection: [Int]? = nil) -> Bool {
        guard isValidSave, phase == .mismatch,
              expectedMoves == nil || expectedMoves == moves,
              expectedSelection == nil || expectedSelection == selectedIndices else { return false }
        selectedIndices.removeAll()
        return true
    }

    /// Pausing, leaving, backgrounding and re-entering close transient cards.
    /// Permanent matches, completed-turn count and active elapsed time survive.
    public mutating func settleUnmatchedCards() { selectedIndices.removeAll() }

    public mutating func restart() {
        matched = Array(repeating: false, count: mode.cardCount)
        selectedIndices.removeAll()
        moves = 0
        elapsedSeconds = 0
    }

    public var isValidSave: Bool {
        guard cards.count == mode.cardCount, matched.count == mode.cardCount,
              selectedIndices.count <= 2, Set(selectedIndices).count == selectedIndices.count,
              // Finite bounds also prevent overflowing subsequent UI timer/turn ticks.
              (0...315_360_000).contains(elapsedSeconds), (0...1_000_000_000).contains(moves) else { return false }
        var counts = Array(repeating: 0, count: mode.pairCount)
        var matchedCounts = Array(repeating: 0, count: mode.pairCount)
        for index in cards.indices {
            let symbol = cards[index]
            guard counts.indices.contains(symbol) else { return false }
            counts[symbol] += 1
            if matched[index] { matchedCounts[symbol] += 1 }
        }
        guard counts.allSatisfy({ $0 == 2 }), matchedCounts.allSatisfy({ $0 == 0 || $0 == 2 }),
              selectedIndices.allSatisfy({ cards.indices.contains($0) && !matched[$0] }),
              moves >= matchedPairCount + (selectedIndices.count == 2 ? 1 : 0) else { return false }
        if selectedIndices.count == 2, cards[selectedIndices[0]] == cards[selectedIndices[1]] { return false }
        return true
    }
}
