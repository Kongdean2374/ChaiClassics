import Foundation

public struct BlockPoint: Codable, Equatable, Hashable, Sendable { public let x: Int; public let y: Int; public init(_ x: Int,_ y: Int) { self.x = x; self.y = y } }

/// Seven-piece bag, fixed board, bounded lock delay, hold, ghost, soft/hard
/// drops and clockwise/counterclockwise rotation with wall/floor kicks.
public struct FallingBlocksBoard: Codable, Equatable, Sendable {
    public let seed: UInt64
    public private(set) var cells = Array(repeating:0,count:200)
    public private(set) var active = 0
    public private(set) var rotation = 0
    public private(set) var x = 3
    public private(set) var y = -1
    public private(set) var next: [Int] = []
    public private(set) var held: Int?
    public private(set) var holdUsed = false
    public private(set) var bagNumber = 0
    public private(set) var lines = 0
    public private(set) var score = 0
    public private(set) var piecesPlaced = 0
    public private(set) var hasLost = false
    private var lockTicks = 0
    private var lockResets = 0
    public var level: Int { lines/10+1 }
    public init(seed: UInt64) { self.seed = seed; refill(); active = next.removeFirst(); refill() }
    public static func shape(_ kind: Int, rotation: Int) -> [BlockPoint] {
        let bases = [[BlockPoint(0,1),.init(1,1),.init(2,1),.init(3,1)], [.init(1,0),.init(2,0),.init(1,1),.init(2,1)],
                     [.init(1,0),.init(0,1),.init(1,1),.init(2,1)], [.init(1,0),.init(2,0),.init(0,1),.init(1,1)],
                     [.init(0,0),.init(1,0),.init(1,1),.init(2,1)], [.init(0,0),.init(0,1),.init(1,1),.init(2,1)],
                     [.init(2,0),.init(0,1),.init(1,1),.init(2,1)]]
        guard bases.indices.contains(kind), (0...3).contains(rotation) else { return [] }
        if kind==1 { return bases[kind] }
        var points = bases[kind]
        for _ in 0..<rotation { points = points.map { .init((kind==0 ? 3 : 2)-$0.y,$0.x) } }; return points
    }
    public var activeCells: [BlockPoint] { Self.shape(active,rotation:rotation).map{.init($0.x+x,$0.y+y)} }
    public var ghostY: Int { var row = y; while fits(x:x,y:row+1,rotation:rotation) { row += 1 }; return row }
    public var isValidSave: Bool {
        cells.count==200 && cells.allSatisfy{(0...7).contains($0)} && (0...6).contains(active) && (0...3).contains(rotation) &&
        (-3...9).contains(x) && (-4...19).contains(y) && (1...14).contains(next.count) && next.allSatisfy{(0...6).contains($0)} &&
        (held == nil || (0...6).contains(held!)) && (0...10_000_000).contains(score) && (0...1_000_000).contains(lines) &&
        (0...1_000_000).contains(piecesPlaced) && (0...1_000_000).contains(bagNumber) && (hasLost || fits(x:x,y:y,rotation:rotation))
    }
    private func fits(x: Int,y: Int,rotation: Int) -> Bool {
        guard cells.count==200 else { return false }
        return Self.shape(active,rotation:rotation).allSatisfy { p in
            let nx = x+p.x, ny = y+p.y
            return (0..<10).contains(nx) && ny>=(-4) && ny<20 && (ny<0 || cells[ny*10+nx]==0)
        }
    }
    @discardableResult public mutating func move(_ dx: Int) -> Bool {
        guard !hasLost, abs(dx)==1, fits(x:x+dx,y:y,rotation:rotation) else { return false }
        x += dx; resetLock(); return true
    }
    @discardableResult public mutating func rotate(clockwise: Bool = true) -> Bool {
        guard !hasLost, active != 1 else { return false }
        let target = (rotation+(clockwise ? 1 : 3))%4
        for kick in [BlockPoint(0,0),.init(-1,0),.init(1,0),.init(-2,0),.init(2,0),.init(0,-1),.init(-1,-1),.init(1,-1),.init(0,-2)] {
            if fits(x:x+kick.x,y:y+kick.y,rotation:target) { x += kick.x; y += kick.y; rotation = target; resetLock(); return true }
        }; return false
    }
    @discardableResult public mutating func step(soft: Bool = false) -> Bool {
        guard isValidSave, !hasLost else { return false }
        if fits(x:x,y:y+1,rotation:rotation) { y += 1; lockTicks = 0; if soft { score = min(10_000_000,score+1) } }
        else { lockTicks += 1; if lockTicks>=2 || soft { lock() } }; return true
    }
    @discardableResult public mutating func hardDrop() -> Bool {
        guard !hasLost else { return false }; let target = ghostY; score = min(10_000_000,score+(target-y)*2); y = target; lock(); return true
    }
    @discardableResult public mutating func hold() -> Bool {
        guard !hasLost, !holdUsed else { return false }
        let previous = active
        if let held { active = held } else { active = next.removeFirst(); refill() }
        held = previous; holdUsed = true; x = 3; y = -1; rotation = 0; lockTicks = 0; lockResets = 0
        hasLost = !fits(x:x,y:y,rotation:rotation); return true
    }
    private mutating func resetLock() { if lockResets<15 { lockTicks = 0; lockResets += 1 } }
    private mutating func refill() {
        if next.count<7 { var random = SeededRandom(seed:seed &+ UInt64(bagNumber) &* 0x9e3779b9); next += Array(0...6).shuffled(using:&random); bagNumber += 1 }
    }
    private mutating func lock() {
        let points = activeCells
        if points.contains(where:{$0.y<0}) { hasLost = true; return }
        for p in points { cells[p.y*10+p.x] = active+1 }
        var kept: [[Int]] = []
        for row in 0..<20 { let values = Array(cells[(row*10)..<(row*10+10)]); if values.contains(0) { kept.append(values) } }
        let cleared = 20-kept.count
        cells = Array(repeating:0,count:cleared*10)+kept.flatMap{$0}; score = min(10_000_000,score+[0,100,300,500,800][min(cleared,4)]*level); lines += cleared; piecesPlaced += 1
        active = next.removeFirst(); refill(); x = 3; y = -1; rotation = 0; holdUsed = false; lockTicks = 0; lockResets = 0
        hasLost = !fits(x:x,y:y,rotation:rotation)
    }
}
