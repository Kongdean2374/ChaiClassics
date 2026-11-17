import Foundation

/// Shared settings for the two offline alternating-turn games.
public enum DuelMode: String, Codable, CaseIterable, Sendable {
    case singlePlayer, localTwoPlayer
}

public enum DuelDifficulty: String, Codable, CaseIterable, Sendable {
    case easy, normal, hard
}

public enum DuelPlayer: Int, Codable, CaseIterable, Sendable {
    case first = 1, second = 2
    public var opponent: DuelPlayer { self == .first ? .second : .first }
}

/// Wins and losses use the human player's perspective in solo games and player one's in local games.
public struct DuelStatistics: Codable, Equatable, Sendable {
    public private(set) var wins = 0
    public private(set) var draws = 0
    public private(set) var losses = 0
    public init() {}
    public var isValid: Bool { wins >= 0 && draws >= 0 && losses >= 0 }
    public mutating func record(winner: DuelPlayer?, humanPlayer: DuelPlayer) {
        if winner == nil { draws = draws == Int.max ? draws : draws + 1 }
        else if winner == humanPlayer { wins = wins == Int.max ? wins : wins + 1 }
        else { losses = losses == Int.max ? losses : losses + 1 }
    }
    public mutating func clear() { self = DuelStatistics() }
}
