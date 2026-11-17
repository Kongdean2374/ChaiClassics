import Foundation

public enum ExpandedGameState: Codable, Equatable, Sendable {
    case nonogram(NonogramBoard), kakuro(KakuroBoard), klotski(KlotskiBoard)
    case gomoku(GomokuBoard), reversi(ReversiBoard), chess(ChessBoard), xiangqi(XiangqiBoard), banqi(BanqiBoard), shogi(ShogiBoard)
    case solitaire(SolitaireBoard), snake(SnakeBoard), fallingBlocks(FallingBlocksBoard), brickBreaker(BrickBreakerBoard)

    public var gameID: GameID {
        switch self {
        case .nonogram:return .nonogram
        case .kakuro:return .kakuro
        case .klotski:return .klotski
        case .gomoku:return .gomoku
        case .reversi:return .reversi
        case .chess:return .chess
        case .xiangqi:return .xiangqi
        case .banqi:return .banqi
        case .shogi:return .shogi
        case .solitaire(let board):return GameID(rawValue:board.variant.rawValue)!
        case .snake:return .snake
        case .fallingBlocks:return .fallingBlocks
        case .brickBreaker:return .brickBreaker
        }
    }
    public var isValid: Bool {
        switch self {
        case .nonogram(let b):return b.isValidSave
        case .kakuro(let b):return b.isValidSave
        case .klotski(let b):return b.isValidSave
        case .gomoku(let b):return b.isValidSave
        case .reversi(let b):return b.isValidSave
        case .chess(let b):return b.isValidSave
        case .xiangqi(let b):return b.isValidSave
        case .banqi(let b):return b.isValidSave
        case .shogi(let b):return b.isValidSave
        case .solitaire(let b):return b.isValidSave
        case .snake(let b):return b.isValidSave
        case .fallingBlocks(let b):return b.isValidSave
        case .brickBreaker(let b):return b.isValidSave
        }
    }
    public var moves: Int {
        switch self {
        case .nonogram(let b):return b.moves
        case .kakuro(let b):return b.moves
        case .klotski(let b):return b.moves
        case .gomoku(let b):return b.history.count
        case .reversi(let b):return b.moves
        case .chess(let b):return b.moves
        case .xiangqi(let b):return b.moves
        case .banqi(let b):return b.moves
        case .shogi(let b):return b.moves
        case .solitaire(let b):return b.moves
        case .snake(let b):return b.ticks
        case .fallingBlocks(let b):return b.piecesPlaced
        case .brickBreaker(let b):return b.score/10
        }
    }
    public var currentPlayer: DuelPlayer? {
        switch self {
        case .gomoku(let b):return b.currentPlayer
        case .reversi(let b):return b.currentPlayer
        case .chess(let b):return b.currentPlayer
        case .xiangqi(let b):return b.currentPlayer
        case .banqi(let b):return b.currentPlayer
        case .shogi(let b):return b.currentPlayer
        default:return nil
        }
    }
    public var strategyResult: StrategyResult? {
        switch self {
        case .gomoku(let b):return !b.isFinished ? .playing : b.winner.map(StrategyResult.won) ?? .draw
        case .reversi(let b):return !b.isFinished ? .playing : b.winner.map(StrategyResult.won) ?? .draw
        case .chess(let b):return b.result
        case .xiangqi(let b):return b.result
        case .banqi(let b):return b.result
        case .shogi(let b):return b.result
        default:return nil
        }
    }
}

public struct ExpandedGamePreferences: Codable, Equatable, Sendable {
    public var drawCount = 1
    public var spiderSuits = 1
    public var showLegalMoves = true
    public var showGhost = true
    public init() {}
    public var isValid: Bool { [1,3].contains(drawCount) && [1,2,4].contains(spiderSuits) }
}

/// Each new game uses its own existing SaveStore envelope/namespace. The typed
/// union is also carried by the existing rollback-protected data archive.
public struct ExpandedGameSave: Codable, Equatable, Sendable {
    public let gameID: GameID
    public let seed: UInt64
    public let difficulty: DuelDifficulty
    public let mode: DuelMode
    public let humanPlayer: DuelPlayer
    public var elapsedSeconds = 0
    public var state: ExpandedGameState
    public init?(game: GameID, seed: UInt64, difficulty: DuelDifficulty = .normal, mode: DuelMode = .singlePlayer,
                 humanPlayer: DuelPlayer = .first, options: ExpandedGamePreferences = .init()) {
        guard game.isExpanded, options.isValid else { return nil }
        gameID = game; self.seed = seed; self.difficulty = difficulty; self.mode = mode; self.humanPlayer = humanPlayer
        let level = difficulty == .easy ? 0 : difficulty == .normal ? 1 : 2
        switch game {
        case .nonogram:state = .nonogram(.init(size:[5,10,15][level],seed:seed))
        case .kakuro:state = .kakuro(.init(size:[4,6,8][level],seed:seed))
        case .klotski:state = .klotski(.init(seed:seed,shuffle:[50,150,400][level]))
        case .gomoku:state = .gomoku(.init())
        case .reversi:state = .reversi(.init())
        case .chess:state = .chess(.init())
        case .xiangqi:state = .xiangqi(.init())
        case .banqi:state = .banqi(.init(seed:seed))
        case .shogi:state = .shogi(.init())
        case .klondike,.spider,.freecell,.pyramid,.tripeaks:state = .solitaire(.init(variant:SolitaireVariant(rawValue:game.rawValue)!,seed:seed,drawCount:options.drawCount,spiderSuits:options.spiderSuits))
        case .snake:state = .snake(.init(size:[16,20,24][level],seed:seed))
        case .fallingBlocks:state = .fallingBlocks(.init(seed:seed))
        case .brickBreaker:state = .brickBreaker(.init(seed:seed,hard:difficulty == .hard))
        default:return nil
        }
    }
    public var isValidSave: Bool { gameID.isExpanded && state.gameID==gameID && state.isValid && (0...315_360_000).contains(elapsedSeconds) }
    public var isComputerTurn: Bool { gameID.isStrategy && mode == .singlePlayer && state.currentPlayer != humanPlayer && outcome == nil }
    public var outcome: GameOutcome? {
        if let result = state.strategyResult {
            switch result { case .playing:return nil; case .draw:return .draw; case .won(let player):return player == (mode == .singlePlayer ? humanPlayer : .first) ? .won : .lost }
        }
        switch state {
        case .nonogram(let b):return b.isComplete ? .completed : nil
        case .kakuro(let b):return b.isComplete ? .completed : nil
        case .klotski(let b):return b.isComplete ? .completed : nil
        case .solitaire(let b):return b.isComplete ? .won : !b.hasAvailableMove ? .lost : nil
        case .snake(let b):return b.isComplete ? .completed : b.hasLost ? .lost : nil
        case .fallingBlocks(let b):return b.hasLost ? .lost : nil
        case .brickBreaker(let b):return b.isComplete ? .completed : b.hasLost ? .lost : nil
        default:return nil
        }
    }
    public var snapshot: GameRunSnapshot {
        GameRunSnapshot(game:gameID,exists:true,ended:outcome != nil,outcome:outcome,elapsedSeconds:elapsedSeconds,moves:state.moves,
                        difficulty:difficulty.rawValue,mode:gameID.isStrategy ? mode.rawValue : gameID.rawValue)
    }
}
