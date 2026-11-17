import Foundation

public enum ExpandedStrategyAction: Codable, Equatable, Sendable {
    case place(Int), banqi(BanqiAction), chess(ChessMove), xiangqi(ChessMove), shogi(ShogiMove)
    public var from: Int? {
        switch self { case .chess(let m),.xiangqi(let m):return m.from; case .shogi(let m):return m.from; case .banqi(.move(let from,_)):return from; default:return nil }
    }
    public var to: Int {
        switch self { case .place(let i),.banqi(.reveal(let i)):return i; case .banqi(.move(_,let i)):return i; case .chess(let m),.xiangqi(let m):return m.to; case .shogi(let m):return m.to }
    }
    public var promotion: Int? {
        switch self { case .chess(let m):return m.promotion; case .shogi(let m):return m.promote ? 1 : nil; default:return nil }
    }
}

public extension ExpandedGameState {
    var strategyCells: [Int] {
        switch self { case .gomoku(let b):return b.cells; case .reversi(let b):return b.cells; case .chess(let b):return b.cells; case .xiangqi(let b):return b.cells; case .banqi(let b):return b.pieces; case .shogi(let b):return b.cells; default:return [] }
    }
    var legalStrategyActions: [ExpandedStrategyAction] {
        switch self {
        case .gomoku(let b):return b.isFinished ? [] : b.cells.indices.filter{b.cells[$0]==0}.map(ExpandedStrategyAction.place)
        case .reversi(let b):return b.isFinished ? [] : b.legalMoves(for:b.currentPlayer).map(ExpandedStrategyAction.place)
        case .chess(let b):return b.result == .playing ? b.legalMoves().map(ExpandedStrategyAction.chess) : []
        case .xiangqi(let b):return b.result == .playing ? b.legalMoves().map(ExpandedStrategyAction.xiangqi) : []
        case .shogi(let b):return b.result == .playing ? b.legalMoves().map(ExpandedStrategyAction.shogi) : []
        case .banqi(let b):return b.result == .playing ? b.legalActions().map(ExpandedStrategyAction.banqi) : []
        default:return []
        }
    }
    mutating func playStrategy(_ action: ExpandedStrategyAction) -> Bool {
        switch (self,action) {
        case (.gomoku(var b),.place(let i)):guard b.place(i) else { return false }; self = .gomoku(b)
        case (.reversi(var b),.place(let i)):guard b.place(i) else { return false }; self = .reversi(b)
        case (.chess(var b),.chess(let m)):guard b.play(m) else { return false }; self = .chess(b)
        case (.xiangqi(var b),.xiangqi(let m)):guard b.play(m) else { return false }; self = .xiangqi(b)
        case (.shogi(var b),.shogi(let m)):guard b.play(m) else { return false }; self = .shogi(b)
        case (.banqi(var b),.banqi(let m)):guard b.play(m) else { return false }; self = .banqi(b)
        default:return false
        }; return true
    }
    func recommendedStrategyAction(difficulty: DuelDifficulty, seed: UInt64) -> ExpandedStrategyAction? {
        switch self {
        case .gomoku(let b):return b.recommendedMove(difficulty:difficulty,seed:seed).map(ExpandedStrategyAction.place)
        case .reversi(let b):return b.recommendedMove(difficulty:difficulty,seed:seed).map(ExpandedStrategyAction.place)
        case .chess(let b):return b.recommendedMove(difficulty:difficulty,seed:seed).map(ExpandedStrategyAction.chess)
        case .xiangqi(let b):return b.recommendedMove(difficulty:difficulty,seed:seed).map(ExpandedStrategyAction.xiangqi)
        case .shogi(let b):return b.recommendedMove(difficulty:difficulty,seed:seed).map(ExpandedStrategyAction.shogi)
        case .banqi(let b):return b.recommendedAction(difficulty:difficulty,randomSeed:seed).map(ExpandedStrategyAction.banqi)
        default:return nil
        }
    }
}
