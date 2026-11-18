import Foundation

public struct ShogiMove: Codable, Equatable, Hashable, Sendable {
    /// nil for a drop; drop uses unpromoted kind 1...7.
    public let from: Int?
    public let to: Int
    public let promote: Bool
    public let drop: Int?
    public init(from: Int? = nil, to: Int, promote: Bool = false, drop: Int? = nil) { self.from = from; self.to = to; self.promote = promote; self.drop = drop }
}

/// Standard 9×9 shogi: captured pieces return to hand, promotion zones,
/// mandatory promotion, nifu and pawn-drop mate prohibition are enforced.
public struct ShogiBoard: Codable, Equatable, Sendable {
    public private(set) var cells: [Int]
    public private(set) var hands = [Array(repeating:0,count:8),Array(repeating:0,count:8)]
    public private(set) var currentPlayer = DuelPlayer.first
    public private(set) var moves = 0
    private var positions: [String:Int] = [:]
    private var consecutiveChecks = [0,0]
    private var repetition: StrategyRepetition?
    public private(set) var declaredWinner: DuelPlayer?
    public init() {
        let back: [Int] = [2,3,4,5,8,5,4,3,2]
        cells = back.map { -$0 }
        cells += Array(repeating:0,count:9)
        cells += Array(repeating:-1,count:9)
        cells += Array(repeating:0,count:27)
        cells += Array(repeating:1,count:9)
        cells += Array(repeating:0,count:9)
        cells += back
        cells[10] = -7; cells[16] = -6; cells[64] = 6; cells[70] = 7
        repetition = StrategyRepetition(key: key, ply: moves)
    }
    public var sign: Int { currentPlayer == .first ? 1 : -1 }
    public static func unpromoted(_ kind: Int) -> Int { kind>=9 && kind<=12 ? kind-8 : kind==13 ? 6 : kind==14 ? 7 : kind }
    private static func promoted(_ kind: Int) -> Int? { (1...4).contains(kind) ? kind+8 : kind==6 ? 13 : kind==7 ? 14 : nil }
    private var key: String { cells.map(String.init).joined(separator:",")+"/\(hands)/\(currentPlayer.rawValue)" }
    public var isValidSave: Bool {
        guard cells.count==81, cells.allSatisfy({(-14...14).contains($0)}), cells.filter({$0==8}).count==1, cells.filter({$0 == -8}).count==1,
              hands.count==2, hands.allSatisfy({$0.count==8 && $0[0]==0 && $0.allSatisfy{(0...18).contains($0)}}),
              (0...1_000_000).contains(moves), positions.count<=10_000, consecutiveChecks.count==2,
              repetition?.isValid(through: moves, occurrences: 4) ?? true else { return false }
        let totals = [0,18,4,4,4,4,2,2,2]
        for kind in 1...8 {
            let onBoard = cells.filter { Self.unpromoted(abs($0)) == kind }.count
            let inHand = kind < 8 ? hands[0][kind] + hands[1][kind] : 0
            if onBoard + inHand != totals[kind] { return false }
        }
        return true
    }
    private func destinations(_ from: Int) -> [Int] {
        let piece = cells[from], side = piece>0 ? 1 : -1, kind = abs(piece), x = from%9, y = from/9
        guard kind>0 else { return [] }; var targets: [Int] = []
        func add(_ dx: Int,_ dy: Int,_ sliding: Bool = false) {
            var nx = x+dx, ny = y+dy
            while (0..<9).contains(nx), (0..<9).contains(ny) {
                if cells[ny*9+nx]*side>0 { break }; targets.append(ny*9+nx)
                if cells[ny*9+nx] != 0 || !sliding { break }; nx += dx; ny += dy
            }
        }
        switch kind {
        case 1: add(0,-side)
        case 2: add(0,-side,true)
        case 3: add(-1,-2*side); add(1,-2*side)
        case 4: for dx in -1...1 { add(dx,-side) }; add(-1,side); add(1,side)
        case 5,9,10,11,12: for dx in -1...1 { add(dx,-side) }; add(-1,0); add(1,0); add(0,side)
        case 6,13:
            for dx in [-1,1] { for dy in [-1,1] { add(dx,dy,true) }}
            if kind==13 { add(-1,0); add(1,0); add(0,-1); add(0,1) }
        case 7,14:
            add(-1,0,true); add(1,0,true); add(0,-1,true); add(0,1,true)
            if kind==14 { for dx in [-1,1] { for dy in [-1,1] { add(dx,dy) }} }
        case 8: for dx in -1...1 { for dy in -1...1 where dx != 0 || dy != 0 { add(dx,dy) }}
        default: break
        }
        return targets
    }
    public func isInCheck(_ player: DuelPlayer) -> Bool {
        let side = player == .first ? 1 : -1
        guard let king = cells.firstIndex(of:8*side) else { return true }
        return cells.indices.contains { cells[$0]*side<0 && destinations($0).contains(king) }
    }
    public func legalMoves() -> [ShogiMove] { legalMoves(enforcePawnMate:true) }
    private func legalMoves(enforcePawnMate: Bool) -> [ShogiMove] {
        guard cells.count==81, hands.count==2, hands.allSatisfy({$0.count==8}) else { return [] }
        func zone(_ row: Int) -> Bool { sign==1 ? row<=2 : row>=6 }
        var options: [ShogiMove] = []
        for from in cells.indices where cells[from]*sign>0 {
            let kind = abs(cells[from])
            for to in destinations(from) where abs(cells[to]) != 8 {
                let last = sign==1 ? to/9 : 8-to/9
                let mandatory = (kind==1 || kind==2) && last==0 || kind==3 && last<=1
                if !mandatory { options.append(.init(from:from,to:to)) }
                if Self.promoted(kind) != nil && (zone(from/9) || zone(to/9)) { options.append(.init(from:from,to:to,promote:true)) }
            }
        }
        for kind in 1...7 where hands[currentPlayer.rawValue-1][kind]>0 {
            for to in cells.indices where cells[to]==0 {
                let last = sign==1 ? to/9 : 8-to/9
                if (kind==1 || kind==2) && last==0 || kind==3 && last<=1 { continue }
                if kind==1 && (0..<9).contains(where:{ cells[$0*9+to%9]==sign }) { continue }
                options.append(.init(to:to,drop:kind))
            }
        }
        return options.filter { move in
            var next = self; next.apply(move)
            if next.isInCheck(currentPlayer) { return false }
            if enforcePawnMate, move.drop==1, next.isInCheck(next.currentPlayer), next.legalMoves(enforcePawnMate:false).isEmpty { return false }
            return true
        }
    }
    private mutating func apply(_ move: ShogiMove) {
        let player = currentPlayer.rawValue-1
        if let drop = move.drop { hands[player][drop] -= 1; cells[move.to] = drop*sign }
        else if let from = move.from {
            let captured = Self.unpromoted(abs(cells[move.to]))
            if (1...7).contains(captured) { hands[player][captured] += 1 }
            cells[move.to] = (move.promote ? Self.promoted(abs(cells[from])) ?? abs(cells[from]) : abs(cells[from]))*sign; cells[from] = 0
        }
        currentPlayer = currentPlayer.opponent; moves += 1
    }
    public var result: StrategyResult {
        if let declaredWinner { return .won(declaredWinner) }
        if legalMoves().isEmpty { return .won(currentPlayer.opponent) }
        return repetitionResult ?? .playing
    }
    private var repetitionResult: StrategyResult? {
        if let repetition { return repetition.result(key: key, occurrences: 4) }
        if positions[key,default:0]>=4 {
            if consecutiveChecks[0]>=4 { return .won(.second) }; if consecutiveChecks[1]>=4 { return .won(.first) }; return .draw
        }
        return nil
    }
    /// The 27-point entering-king declaration rule. Only pieces in the enemy
    /// camp and in hand count; the king is excluded and may not be in check.
    public var canDeclareEnteringKing: Bool {
        guard declaredWinner==nil, let king = cells.firstIndex(of:8*sign), !isInCheck(currentPlayer) else { return false }
        func inCamp(_ i: Int) -> Bool { sign==1 ? i/9<=2 : i/9>=6 }
        guard inCamp(king) else { return false }
        let camp = cells.indices.filter { cells[$0]*sign>0 && abs(cells[$0]) != 8 && inCamp($0) }
        guard camp.count>=10 else { return false }
        func points(_ kind: Int) -> Int { [6,7].contains(Self.unpromoted(kind)) ? 5 : 1 }
        let boardPoints = camp.reduce(0) { $0+points(abs(cells[$1])) }
        let handPoints = (1...7).reduce(0) { $0+hands[currentPlayer.rawValue-1][$1]*points($1) }
        return boardPoints+handPoints >= (currentPlayer == .first ? 28 : 27)
    }
    @discardableResult public mutating func declareEnteringKing() -> Bool {
        guard isValidSave, result == .playing, canDeclareEnteringKing else { return false }; declaredWinner = currentPlayer; return true
    }
    @discardableResult public mutating func play(_ move: ShogiMove) -> Bool {
        guard isValidSave, declaredWinner == nil, repetitionResult == nil, legalMoves().contains(move) else { return false }
        var trace = repetition ?? StrategyRepetition(key: key, ply: moves)
        let player = currentPlayer
        apply(move)
        trace.record(key: key, ply: moves, mover: player, gaveCheck: isInCheck(currentPlayer))
        repetition = trace
        return true
    }
    public func recommendedMove(difficulty: DuelDifficulty, seed: UInt64) -> ShogiMove? {
        let options = legalMoves(); guard result == .playing else { return nil }
        var random = SeededRandom(seed:seed &+ UInt64(moves)); if difficulty == .easy { return options.randomElement(using:&random) }
        let perspective = sign, values = [0,100,300,320,450,550,800,1000,20_000,560,560,560,560,1000,1200]
        func score(_ board: Self) -> Int {
            let material = board.cells.reduce(0) { $0+($1>0 ? 1 : -1)*perspective*values[abs($1)] }
            let hand = (1...7).reduce(0) { $0+(board.hands[0][$1]-board.hands[1][$1])*perspective*values[$1] }
            return material+hand
        }
        // Bound the reply search. Every candidate is legal; hard play considers
        // the opponent's strongest capture instead of seeing hidden information.
        var best = Int.min, chosen = options.first
        for move in options.shuffled(using:&random) {
            if Task.isCancelled { break }
            var next = self; next.apply(move); var value = score(next)
            if next.isInCheck(next.currentPlayer) { value += 40 }
            if difficulty == .hard {
                let replies = next.legalMoves().sorted { abs(next.cells[$0.to])>abs(next.cells[$1.to]) }.prefix(24)
                if replies.isEmpty { return move }
                value = replies.map { reply -> Int in var after = next; after.apply(reply); return score(after) }.min() ?? value
            }
            if value>best { best = value; chosen = move }
        }
        return chosen
    }
}
