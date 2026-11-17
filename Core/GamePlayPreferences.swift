import Foundation

/// Independent defaults for each game; no gameplay payload or released preference key changes.
public struct GamePlayPreferences: Codable, Equatable, Sendable {
    public var haptics = true
    public var sudokuPencilByDefault = false
    public var minesWidth = 9
    public var minesHeight = 9
    public var minesCount = 10
    public var slidingSize = 3
    public var slidingDifficulty = "normal"
    public var duelMode = "singlePlayer"
    public var duelDifficulty = "normal"
    public var humanPlayer = 1
    public var twentyFourDifficulty = "easy"
    public var memoryMode = "easy"
    public var memoryRevealSeconds = 0.65
    public var mazeDifficulty = "normal"
    public var mazeSpeed = 1.0

    public init() {}

    public var isValid: Bool {
        let levels = ["easy", "normal", "hard"]
        return (try? MineConfiguration(width: minesWidth, height: minesHeight, mines: minesCount)) != nil &&
            (3...5).contains(slidingSize) && levels.contains(slidingDifficulty) &&
            ["singlePlayer", "localTwoPlayer"].contains(duelMode) && levels.contains(duelDifficulty) &&
            [1, 2].contains(humanPlayer) && levels.contains(twentyFourDifficulty) && levels.contains(memoryMode) &&
            memoryRevealSeconds.isFinite && (0.5...1.5).contains(memoryRevealSeconds) &&
            levels.contains(mazeDifficulty) && [0.8, 1.0, 1.2].contains(mazeSpeed)
    }
}

public struct GameRunSnapshot: Equatable, Sendable {
    public let game: GameID
    public let exists: Bool
    public let ended: Bool
    public let outcome: GameOutcome?
    public let elapsedSeconds: Int
    public let moves: Int
    public let difficulty: String
    public let mode: String

    public init(game: GameID, exists: Bool, ended: Bool, outcome: GameOutcome?, elapsedSeconds: Int, moves: Int,
                difficulty: String, mode: String) {
        self.game = game; self.exists = exists; self.ended = ended; self.outcome = outcome
        self.elapsedSeconds = elapsedSeconds; self.moves = moves; self.difficulty = difficulty; self.mode = mode
    }
}
