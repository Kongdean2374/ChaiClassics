import Foundation

public enum BanqiAction: Codable, Equatable, Sendable { case reveal(Int), move(Int,Int) }

/// Taiwanese dark chess: 4×8 board; the first reveal assigns sides. A general
/// cannot capture a soldier, a soldier can capture a general, cannon captures
/// require exactly one screen and may target only a revealed piece.
public struct BanqiBoard: Codable, Equatable, Sendable {
    public let seed: UInt64
    public private(set) var pieces: [Int]
    public private(set) var revealed = Array(repeating:false,count:32)
    public private(set) var currentPlayer = DuelPlayer.first
    public private(set) var firstPlayerColor: Int?
    public private(set) var moves = 0
    public private(set) var quietMoves = 0
    public init(seed: UInt64) {
        self.seed = seed; var random = SeededRandom(seed:seed)
        let side = [1,2,2,3,3,4,4,5,5,6,6,7,7,7,7,7]
        pieces = side+side.map(-); pieces.shuffle(using:&random)
    }
    public var color: Int? { firstPlayerColor.map { currentPlayer == .first ? $0 : -$0 } }
    public var isValidSave: Bool {
        guard pieces.count==32, revealed.count==32, pieces.allSatisfy({(-7...7).contains($0)}), firstPlayerColor == nil || [1,-1].contains(firstPlayerColor!),
              (0...1_000_000).contains(moves), (0...1_000_000).contains(quietMoves), pieces.indices.allSatisfy({pieces[$0] != 0 || revealed[$0]}) else { return false }
        let maxCounts = [0,1,2,2,2,2,2,5]
        return (1...7).allSatisfy { k in pieces.filter{$0==k}.count<=maxCounts[k] && pieces.filter{$0 == -k}.count<=maxCounts[k] } &&
            (firstPlayerColor != nil || !revealed.contains(true) && moves==0)
    }
    private func canCapture(_ attacker: Int,_ target: Int) -> Bool {
        guard attacker*target<0 else { return false }
        let a = abs(attacker), b = abs(target)
        if a==6 { return true }; if a==1 && b==7 { return false }; if a==7 { return b==7 || b==1 }
        return a<=b
    }
    public func legalActions() -> [BanqiAction] {
        guard pieces.count==32, revealed.count==32 else { return [] }
        var actions = pieces.indices.filter{!revealed[$0]}.map(BanqiAction.reveal)
        guard let color else { return actions }
        for from in pieces.indices where revealed[from] && pieces[from]*color>0 {
            for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
                var x = from%4+dx, y = from/4+dy, screens = 0
                while (0..<4).contains(x), (0..<8).contains(y) {
                    let to = y*4+x
                    if abs(pieces[from]) != 6 {
                        if pieces[to]==0 || revealed[to] && canCapture(pieces[from],pieces[to]) { actions.append(.move(from,to)) }; break
                    }
                    if screens==0, abs(x-from%4)+abs(y-from/4)==1, pieces[to]==0 { actions.append(.move(from,to)) }
                    if pieces[to] != 0 {
                        screens += 1
                        if screens==2 { if revealed[to], canCapture(pieces[from],pieces[to]) { actions.append(.move(from,to)) }; break }
                    }
                    x += dx; y += dy
                }
            }
        }
        return actions
    }
    public var result: StrategyResult {
        guard let assigned = firstPlayerColor else { return .playing }
        if !pieces.contains(where:{$0*assigned>0}) { return .won(.second) }
        if !pieces.contains(where:{$0*assigned<0}) { return .won(.first) }
        if legalActions().isEmpty { return .won(currentPlayer.opponent) }
        if quietMoves>=80 { return .draw }; return .playing
    }
    @discardableResult public mutating func play(_ action: BanqiAction) -> Bool {
        guard isValidSave, result == .playing, legalActions().contains(action) else { return false }
        switch action {
        case .reveal(let i): revealed[i] = true; if firstPlayerColor == nil { firstPlayerColor = pieces[i]>0 ? 1 : -1 }; quietMoves = 0
        case .move(let from,let to): quietMoves = pieces[to]==0 ? quietMoves+1 : 0; pieces[to] = pieces[from]; pieces[from] = 0; revealed[to] = true
        }
        currentPlayer = currentPlayer.opponent; moves += 1; return true
    }
    public func recommendedAction(difficulty: DuelDifficulty, randomSeed: UInt64) -> BanqiAction? {
        let actions = legalActions(); guard result == .playing else { return nil }
        var random = SeededRandom(seed:randomSeed &+ UInt64(moves))
        if difficulty == .easy { return actions.randomElement(using:&random) }
        // Never inspect the identity of an unrevealed piece when choosing AI.
        let values = [0,1000,600,500,450,400,350,150]
        let captures = actions.compactMap { action -> (BanqiAction,Int)? in
            if case .move(_,let to) = action, revealed[to], pieces[to] != 0 { return (action,values[abs(pieces[to])]) }; return nil
        }
        if let best = captures.max(by:{$0.1<$1.1}) { return best.0 }
        let flips = actions.filter { if case .reveal = $0 { return true }; return false }
        if let flip = flips.randomElement(using:&random) { return flip }
        return actions.randomElement(using:&random)
    }
}
