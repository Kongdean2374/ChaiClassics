import Foundation

public struct KlotskiPiece: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let width: Int
    public let height: Int
    public var x: Int
    public var y: Int
}

/// The classic 4×5 sliding-block escape. New positions are reversible legal
/// walks from a solved board, therefore every generated position is solvable.
public struct KlotskiBoard: Codable, Equatable, Sendable {
    public let seed: UInt64
    public private(set) var pieces: [KlotskiPiece]
    public private(set) var moves = 0
    public var isComplete: Bool { pieces.first(where: { $0.id == 0 }).map { $0.x == 1 && $0.y == 3 } == true }
    public var isValidSave: Bool {
        guard pieces.count == 10, Set(pieces.map(\.id)) == Set(0..<10), (0...1_000_000).contains(moves) else { return false }
        var used: Set<Int> = []
        for p in pieces {
            let expected = p.id == 0 ? (2,2) : p.id == 1 ? (2,1) : p.id < 6 ? (1,2) : (1,1)
            guard p.width == expected.0, p.height == expected.1, p.x >= 0, p.y >= 0, p.x + p.width <= 4, p.y + p.height <= 5 else { return false }
            for y in p.y..<(p.y+p.height) { for x in p.x..<(p.x+p.width) { guard used.insert(y*4+x).inserted else { return false } } }
        }
        return used.count == 18
    }
    public init(seed: UInt64, shuffle: Int = 120) {
        self.seed = seed
        pieces = [.init(id: 0,width: 2,height: 2,x: 1,y: 3), .init(id: 1,width: 2,height: 1,x: 1,y: 2),
                  .init(id: 2,width: 1,height: 2,x: 0,y: 0), .init(id: 3,width: 1,height: 2,x: 3,y: 0),
                  .init(id: 4,width: 1,height: 2,x: 0,y: 2), .init(id: 5,width: 1,height: 2,x: 3,y: 2),
                  .init(id: 6,width: 1,height: 1,x: 1,y: 0), .init(id: 7,width: 1,height: 1,x: 2,y: 0),
                  .init(id: 8,width: 1,height: 1,x: 1,y: 1), .init(id: 9,width: 1,height: 1,x: 2,y: 1)]
        // A known legal ten-move walk opens the goal's upper edge. This avoids
        // spending a random walk inside the solved board's small corner pocket.
        for (id,dx,dy) in [(4,0,1),(2,0,1),(6,-1,0),(8,0,-1),(5,0,1),(3,0,1),(7,1,0),(9,0,-1),(1,0,-1),(0,0,-1)] {
            shift(id,dx:dx,dy:dy)
        }
        var random = SeededRandom(seed: seed), previous: (Int, Int, Int)?
        for _ in 0..<max(20,min(shuffle,2000)) {
            let legal = pieces.flatMap { p in [(1,0),(-1,0),(0,1),(0,-1)].compactMap { dx,dy -> (Int,Int,Int)? in
                guard canMove(p.id, dx: dx, dy: dy), !(previous.map { $0.0 == p.id && $0.1 == -dx && $0.2 == -dy } ?? false) else { return nil }
                if p.id==0 && p.x+dx==1 && p.y+dy==3 { return nil }
                return (p.id,dx,dy)
            }}
            if let choice = legal.randomElement(using: &random) { shift(choice.0,dx:choice.1,dy:choice.2); previous = choice }
        }
        moves = 0
    }
    public func canMove(_ id: Int, dx: Int, dy: Int) -> Bool {
        guard abs(dx)+abs(dy) == 1, let p = pieces.first(where: {$0.id == id}),
              p.x+dx >= 0, p.y+dy >= 0, p.x+dx+p.width <= 4, p.y+dy+p.height <= 5 else { return false }
        let x = p.x+dx, y = p.y+dy
        return pieces.filter { $0.id != id }.allSatisfy { other in x+p.width <= other.x || other.x+other.width <= x || y+p.height <= other.y || other.y+other.height <= y }
    }
    @discardableResult public mutating func move(_ id: Int, dx: Int, dy: Int) -> Bool {
        guard isValidSave, !isComplete, moves < 1_000_000, canMove(id,dx:dx,dy:dy) else { return false }
        shift(id,dx:dx,dy:dy); moves += 1; return true
    }
    private mutating func shift(_ id: Int, dx: Int, dy: Int) {
        if let i = pieces.firstIndex(where: {$0.id == id}) { pieces[i].x += dx; pieces[i].y += dy }
    }
}
