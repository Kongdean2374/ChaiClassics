import Foundation

public struct ChessMove: Codable, Equatable, Hashable, Sendable {
    public let from: Int
    public let to: Int
    /// 2 knight, 3 bishop, 4 rook, 5 queen; nil outside promotion.
    public let promotion: Int?
    public init(from: Int, to: Int, promotion: Int? = nil) { self.from = from; self.to = to; self.promotion = promotion }
}

public enum StrategyResult: Codable, Equatable, Sendable { case playing, won(DuelPlayer), draw }

/// Orthodox chess. Signed pieces: pawn=1, knight=2, bishop=3, rook=4,
/// queen=5, king=6. Positive white starts at the bottom of the display.
public struct ChessBoard: Codable, Equatable, Sendable {
    public private(set) var cells: [Int]
    public private(set) var currentPlayer = DuelPlayer.first
    public private(set) var castling = [true,true,true,true] // WK WQ BK BQ
    public private(set) var enPassant: Int?
    public private(set) var halfMoves = 0
    public private(set) var moves = 0
    private var positions: [String: Int] = [:]
    public init() {
        cells = [-4,-2,-3,-5,-6,-3,-2,-4] + Array(repeating:-1,count:8) + Array(repeating:0,count:32) + Array(repeating:1,count:8) + [4,2,3,5,6,3,2,4]
        positions[positionKey] = 1
    }
    public init?(fen: String) {
        let fields = fen.split(separator:" "); guard fields.count >= 4 else { return nil }
        let mapping: [Character:Int] = ["p":1,"n":2,"b":3,"r":4,"q":5,"k":6]
        var values: [Int] = []
        for row in fields[0].split(separator:"/") {
            var line: [Int] = []
            for char in row {
                if let digit = char.wholeNumberValue, (1...8).contains(digit) { line += Array(repeating:0,count:digit) }
                else if let value = mapping[Character(char.lowercased())] { line.append(char.isUppercase ? value : -value) }
                else { return nil }
            }
            guard line.count == 8 else { return nil }; values += line
        }
        cells = values; guard fields[1] == "w" || fields[1] == "b" else { return nil }
        currentPlayer = fields[1] == "w" ? .first : .second
        castling = ["K","Q","k","q"].map { fields[2].contains($0) }
        if fields[3] != "-" {
            let chars = Array(fields[3]); guard chars.count == 2, let file = chars[0].asciiValue, (97...104).contains(file), let rank = chars[1].wholeNumberValue, (1...8).contains(rank) else { return nil }
            enPassant = (8-rank)*8+Int(file-97)
        }
        halfMoves = fields.count>4 ? Int(fields[4]) ?? -1 : 0
        guard isValidSave else { return nil }; positions[positionKey] = 1
    }
    public var sign: Int { currentPlayer == .first ? 1 : -1 }
    public var isValidSave: Bool {
        guard cells.count == 64, cells.allSatisfy({ (-6...6).contains($0) }), cells.filter({$0==6}).count == 1, cells.filter({$0 == -6}).count == 1,
              castling.count == 4, (0...1_000_000).contains(moves), (0...1_000_000).contains(halfMoves), positions.count <= 10_000,
              positions.values.allSatisfy({ (1...1_000_000).contains($0) }), enPassant == nil || [2,5].contains(enPassant!/8) && cells.indices.contains(enPassant!) && cells[enPassant!] == 0 else { return false }
        guard !(0..<8).contains(where:{ abs(cells[$0]) == 1 || abs(cells[56+$0]) == 1 }) else { return false }
        let white = cells.firstIndex(of:6)!, black = cells.firstIndex(of:-6)!
        return abs(white%8-black%8)>1 || abs(white/8-black/8)>1
    }
    public func isInCheck(_ player: DuelPlayer) -> Bool {
        guard let king = cells.firstIndex(of: player == .first ? 6 : -6) else { return true }
        return attacked(king, by:player.opponent)
    }
    public func attacked(_ square: Int, by player: DuelPlayer) -> Bool {
        guard cells.count == 64, cells.indices.contains(square) else { return false }
        let side = player == .first ? 1 : -1
        for from in cells.indices where cells[from]*side>0 {
            let dx = square%8-from%8, dy = square/8-from/8
            switch abs(cells[from]) {
            case 1: if abs(dx)==1 && dy == -side { return true }
            case 2: if abs(dx)*abs(dy)==2 { return true }
            case 6: if max(abs(dx),abs(dy))==1 { return true }
            case 3,4,5:
                let diagonal = abs(dx)==abs(dy) && dx != 0, straight = (dx==0 || dy==0) && dx != dy
                let kind = abs(cells[from])
                if (diagonal && kind != 4) || (straight && kind != 3) {
                    let step = (dy == 0 ? 0 : dy>0 ? 8 : -8)+(dx == 0 ? 0 : dx>0 ? 1 : -1)
                    var i = from+step
                    while i != square && cells[i]==0 { i += step }
                    if i==square { return true }
                }
            default: break
            }
        }
        return false
    }
    private func pseudoMoves(from: Int) -> [ChessMove] {
        let piece = cells[from], side = sign, x = from%8, y = from/8
        guard piece*side>0 else { return [] }
        var destinations: [Int] = []
        func append(_ dx: Int, _ dy: Int, sliding: Bool) {
            var nx = x+dx, ny = y+dy
            while (0..<8).contains(nx), (0..<8).contains(ny) {
                let i = ny*8+nx
                if cells[i]*side>0 || abs(cells[i])==6 { break }
                destinations.append(i)
                if cells[i] != 0 || !sliding { break }; nx += dx; ny += dy
            }
        }
        switch abs(piece) {
        case 1:
            let ny = y-side
            if (0..<8).contains(ny) {
                if cells[ny*8+x]==0 {
                    destinations.append(ny*8+x)
                    if y == (side==1 ? 6 : 1), cells[(y-2*side)*8+x]==0 { destinations.append((y-2*side)*8+x) }
                }
                for nx in [x-1,x+1] where (0..<8).contains(nx) {
                    let target = ny*8+nx
                    if cells[target]*side<0 && abs(cells[target]) != 6 || enPassant==target && cells[y*8+nx] == -side { destinations.append(target) }
                }
            }
        case 2: for (dx,dy) in [(1,2),(2,1),(-1,2),(-2,1),(1,-2),(2,-1),(-1,-2),(-2,-1)] { append(dx,dy,sliding:false) }
        case 3,4,5:
            for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                if abs(piece)==3 && (dx==0 || dy==0) || abs(piece)==4 && dx != 0 && dy != 0 { continue }; append(dx,dy,sliding:true)
            }}
        case 6:
            for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 { append(dx,dy,sliding:false) }}
            let base = side==1 ? 56 : 0, offset = side==1 ? 0 : 2
            if from==base+4 && !isInCheck(currentPlayer) {
                if castling[offset], cells[base+7]==4*side, cells[base+5]==0, cells[base+6]==0,
                   !attacked(base+5,by:currentPlayer.opponent), !attacked(base+6,by:currentPlayer.opponent) { destinations.append(base+6) }
                if castling[offset+1], cells[base]==4*side, (1...3).allSatisfy({cells[base+$0]==0}),
                   !attacked(base+3,by:currentPlayer.opponent), !attacked(base+2,by:currentPlayer.opponent) { destinations.append(base+2) }
            }
        default: break
        }
        return destinations.flatMap { target -> [ChessMove] in
            if abs(piece)==1 && (target/8==0 || target/8==7) { return [5,4,3,2].map { ChessMove(from:from,to:target,promotion:$0) } }
            return [ChessMove(from:from,to:target)]
        }
    }
    public func legalMoves() -> [ChessMove] {
        guard cells.count == 64, castling.count == 4 else { return [] }
        return cells.indices.flatMap { pseudoMoves(from:$0) }.filter { move in var next = self; next.apply(move); return !next.isInCheck(currentPlayer) }
    }
    private mutating func apply(_ move: ChessMove) {
        let piece = cells[move.from], captured = cells[move.to], side = piece>0 ? 1 : -1
        if abs(piece)==1, move.to==enPassant, captured==0 { cells[move.to+8*side] = 0 }
        cells[move.to] = (move.promotion ?? abs(piece))*side; cells[move.from] = 0
        if abs(piece)==6 {
            let offset = side==1 ? 0 : 2; castling[offset] = false; castling[offset+1] = false
            if abs(move.to-move.from)==2 {
                let rook = move.to>move.from ? move.from+3 : move.from-4, to = move.to>move.from ? move.from+1 : move.from-1
                cells[to] = cells[rook]; cells[rook] = 0
            }
        }
        for (index,square) in [63,56,7,0].enumerated() where move.from==square || move.to==square { castling[index] = false }
        enPassant = abs(piece)==1 && abs(move.to-move.from)==16 ? (move.from+move.to)/2 : nil
        halfMoves = abs(piece)==1 || captured != 0 ? 0 : halfMoves+1; moves += 1; currentPlayer = currentPlayer.opponent
    }
    private var positionKey: String {
        let effectiveEP = enPassant.flatMap { square -> Int? in
            // Count an en-passant field only when an actual legal capture exists.
            let fromRow = square/8+sign
            return [square%8-1,square%8+1].contains { x in
                guard (0..<8).contains(x), (0..<8).contains(fromRow), cells[fromRow*8+x]==sign else { return false }
                var next = self; next.apply(ChessMove(from:fromRow*8+x,to:square)); return !next.isInCheck(currentPlayer)
            } ? square : nil
        }
        return cells.map(String.init).joined(separator:",")+"/\(currentPlayer.rawValue)/\(castling)/\(effectiveEP ?? -1)"
    }
    public var result: StrategyResult {
        let legal = legalMoves()
        if legal.isEmpty { return isInCheck(currentPlayer) ? .won(currentPlayer.opponent) : .draw }
        let remaining = cells.enumerated().filter { $0.element != 0 && abs($0.element) != 6 }
        let minorOnly = remaining.allSatisfy { [2,3].contains(abs($0.element)) }
        let bishopsOnlySameColor = remaining.allSatisfy { abs($0.element)==3 } && Set(remaining.map { ($0.offset/8+$0.offset%8)%2 }).count <= 1
        if halfMoves>=100 || positions[positionKey,default:0]>=3 || minorOnly && (remaining.count<=1 || bishopsOnlySameColor) { return .draw }
        return .playing
    }
    @discardableResult public mutating func play(_ move: ChessMove) -> Bool {
        guard isValidSave, result == .playing, legalMoves().contains(move) else { return false }
        apply(move); positions[positionKey,default:0] += 1; return true
    }
    public func recommendedMove(difficulty: DuelDifficulty, seed: UInt64) -> ChessMove? {
        let legal = legalMoves(); guard result == .playing else { return nil }
        var random = SeededRandom(seed:seed &+ UInt64(moves)); if difficulty == .easy { return legal.randomElement(using:&random) }
        let perspective = sign, values = [0,100,320,330,500,900,20_000]
        func evaluation(_ board: Self) -> Int {
            board.cells.enumerated().reduce(0) { total,p in total+(p.element>0 ? 1 : -1)*perspective*(values[abs(p.element)]+(p.element==0 ? 0 : 14-abs(p.offset%8*2-7)-abs(p.offset/8*2-7))) }
        }
        var nodes = 0
        func search(_ board: Self, _ depth: Int, _ alpha: Int, _ beta: Int) -> Int {
            nodes += 1; guard nodes<12_000, !Task.isCancelled else { return evaluation(board) }
            let options = board.legalMoves()
            if options.isEmpty { return board.isInCheck(board.currentPlayer) ? (board.sign==perspective ? -100_000-depth : 100_000+depth) : 0 }
            if depth==0 { return evaluation(board) }
            var a = alpha, b = beta, best = board.sign==perspective ? Int.min : Int.max
            for move in options.sorted(by:{abs(board.cells[$0.to])>abs(board.cells[$1.to])}) {
                var next = board; next.apply(move); let score = search(next,depth-1,a,b)
                if board.sign==perspective { best = max(best,score); a = max(a,best) } else { best = min(best,score); b = min(b,best) }
                if a>=b { break }
            }; return best
        }
        var best = Int.min, chosen = legal.first
        for move in legal.shuffled(using:&random) { var next = self; next.apply(move); let score = search(next,difficulty == .hard ? 2 : 0,Int.min+1,Int.max-1); if score>best { best = score; chosen = move } }
        return chosen
    }
}
