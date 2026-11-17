import Foundation

/// Red is positive and moves first. Piece kinds: general, advisor, elephant,
/// horse, chariot, cannon, soldier. Coordinates are intersections on a 9×10 board.
public struct XiangqiBoard: Codable, Equatable, Sendable {
    public private(set) var cells: [Int]
    public private(set) var currentPlayer = DuelPlayer.first
    public private(set) var moves = 0
    private var positions: [String:Int] = [:]
    private var consecutiveChecks = [0,0]
    public init() {
        cells = Array(repeating:0,count:90)
        let back = [5,4,3,2,1,2,3,4,5]
        for i in 0..<9 { cells[i] = -back[i]; cells[81+i] = back[i] }
        cells[19] = -6; cells[25] = -6; cells[64] = 6; cells[70] = 6
        for x in stride(from:0,through:8,by:2) { cells[27+x] = -7; cells[54+x] = 7 }
        positions[key] = 1
    }
    public var sign: Int { currentPlayer == .first ? 1 : -1 }
    private var key: String { cells.map(String.init).joined(separator:",")+"/\(currentPlayer.rawValue)" }
    public var isValidSave: Bool {
        cells.count==90 && cells.allSatisfy { (-7...7).contains($0) } && cells.filter{$0==1}.count==1 && cells.filter{$0 == -1}.count==1 &&
        (0...1_000_000).contains(moves) && positions.count<=10_000 && consecutiveChecks.count==2 && consecutiveChecks.allSatisfy { (0...1_000_000).contains($0) }
    }
    private func destinations(_ from: Int) -> [Int] {
        let piece = cells[from], side = piece>0 ? 1 : -1, x = from%9, y = from/9
        guard piece != 0 else { return [] }
        func palace(_ x: Int,_ y: Int) -> Bool { (3...5).contains(x) && (side==1 ? (7...9).contains(y) : (0...2).contains(y)) }
        var targets: [Int] = []
        func add(_ nx: Int,_ ny: Int) { if (0..<9).contains(nx), (0..<10).contains(ny), cells[ny*9+nx]*side<=0 { targets.append(ny*9+nx) } }
        switch abs(piece) {
        case 1:
            for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)] where palace(x+dx,y+dy) { add(x+dx,y+dy) }
            for dy in [-1,1] {
                var row = y+dy
                while (0..<10).contains(row), cells[row*9+x]==0 { row += dy }
                if (0..<10).contains(row), cells[row*9+x] == -side { targets.append(row*9+x) }
            }
        case 2:
            for dx in [-1,1] { for dy in [-1,1] where palace(x+dx,y+dy) { add(x+dx,y+dy) }}
        case 3:
            for dx in [-2,2] { for dy in [-2,2] {
                let nx = x+dx, ny = y+dy
                if (0..<9).contains(nx), (side==1 ? (5...9).contains(ny) : (0...4).contains(ny)), cells[(y+dy/2)*9+x+dx/2]==0 { add(nx,ny) }
            }}
        case 4:
            for (dx,dy) in [(1,2),(-1,2),(1,-2),(-1,-2),(2,1),(2,-1),(-2,1),(-2,-1)] {
                let nx = x+dx, ny = y+dy
                if (0..<9).contains(nx), (0..<10).contains(ny), cells[(y+(abs(dy)==2 ? dy/2 : 0))*9+x+(abs(dx)==2 ? dx/2 : 0)]==0 { add(nx,ny) }
            }
        case 5,6:
            for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
                var nx = x+dx, ny = y+dy, screen = false
                while (0..<9).contains(nx), (0..<10).contains(ny) {
                    let target = cells[ny*9+nx]
                    if abs(piece)==5 {
                        if target*side<=0 { targets.append(ny*9+nx) }; if target != 0 { break }
                    } else if !screen {
                        if target==0 { targets.append(ny*9+nx) } else { screen = true }
                    } else if target != 0 { if target*side<0 { targets.append(ny*9+nx) }; break }
                    nx += dx; ny += dy
                }
            }
        case 7:
            add(x,y-side)
            if side==1 ? y<=4 : y>=5 { add(x-1,y); add(x+1,y) }
        default: break
        }
        return targets
    }
    public func isInCheck(_ player: DuelPlayer) -> Bool {
        let side = player == .first ? 1 : -1
        guard let king = cells.firstIndex(of:side) else { return true }
        return cells.indices.contains { cells[$0]*side<0 && destinations($0).contains(king) }
    }
    public func legalMoves() -> [ChessMove] {
        guard cells.count==90 else { return [] }
        return cells.indices.filter{cells[$0]*sign>0}.flatMap { from in destinations(from).filter { abs(cells[$0]) != 1 }.compactMap { to in
            let move = ChessMove(from:from,to:to); var next = self; next.apply(move)
            return next.isInCheck(currentPlayer) ? nil : move
        }}
    }
    private mutating func apply(_ move: ChessMove) { cells[move.to] = cells[move.from]; cells[move.from] = 0; currentPlayer = currentPlayer.opponent; moves += 1 }
    public var result: StrategyResult {
        if legalMoves().isEmpty { return .won(currentPlayer.opponent) }
        if positions[key,default:0]>=3 {
            if consecutiveChecks[0]>=3 { return .won(.second) }; if consecutiveChecks[1]>=3 { return .won(.first) }
            return .draw
        }
        return .playing
    }
    @discardableResult public mutating func play(_ move: ChessMove) -> Bool {
        guard isValidSave, result == .playing, legalMoves().contains(move) else { return false }
        let player = currentPlayer; apply(move); positions[key,default:0] += 1
        consecutiveChecks[player.rawValue-1] = isInCheck(currentPlayer) ? consecutiveChecks[player.rawValue-1]+1 : 0; return true
    }
    public func recommendedMove(difficulty: DuelDifficulty, seed: UInt64) -> ChessMove? {
        let options = legalMoves(); guard result == .playing else { return nil }
        var random = SeededRandom(seed:seed &+ UInt64(moves)); if difficulty == .easy { return options.randomElement(using:&random) }
        let perspective = sign, values = [0,20_000,200,200,450,900,500,100]
        func score(_ board: Self) -> Int { board.cells.enumerated().reduce(0) { $0+($1.element>0 ? 1 : -1)*perspective*(values[abs($1.element)]+(abs($1.element)==7 ? ($1.element>0 ? 9-$1.offset/9 : $1.offset/9)*12 : 0)) } }
        var best = Int.min, selected = options.first
        for move in options.shuffled(using:&random) {
            var next = self; next.apply(move); var value = score(next)
            if next.legalMoves().isEmpty { return move }
            if difficulty == .hard {
                value = next.legalMoves().map { reply -> Int in var after = next; after.apply(reply); return score(after) }.min() ?? value
            }
            if value>best { best = value; selected = move }
        }
        return selected
    }
}
