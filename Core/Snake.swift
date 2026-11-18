import Foundation

public enum ArcadeDirection: Int, Codable, CaseIterable, Sendable {
    case up, right, down, left
    public var dx: Int { self == .right ? 1 : self == .left ? -1 : 0 }
    public var dy: Int { self == .down ? 1 : self == .up ? -1 : 0 }
    public var opposite: Self { Self(rawValue:(rawValue+2)%4)! }
}
public struct SnakeBoard: Codable, Equatable, Sendable {
    public let size: Int
    public let seed: UInt64
    public private(set) var body: [Int]
    public private(set) var direction = ArcadeDirection.right
    public private(set) var queued: [ArcadeDirection] = []
    public private(set) var food: Int?
    public private(set) var ticks = 0
    public private(set) var hasLost = false
    public var score: Int { body.count-3 }
    public var isComplete: Bool { body.count==size*size }
    public func stepInterval(difficulty: DuelDifficulty) -> TimeInterval {
        let opening: Double
        switch difficulty {
        case .easy: opening = 0.32
        case .normal: opening = 0.26
        case .hard: opening = 0.20
        }
        return max(opening / 2, opening - 0.01 * Double(max(0, score)))
    }
    public init(size: Int = 20, seed: UInt64) {
        self.size = [16,20,24].contains(size) ? size : 20; self.seed = seed
        let head = self.size/2*self.size+self.size/2; body = [head,head-1,head-2]; placeFood()
    }
    public var isValidSave: Bool {
        guard [16,20,24].contains(size), (3...(size*size)).contains(body.count), Set(body).count==body.count,
              body.allSatisfy({(0..<(size*size)).contains($0)}), (0...100_000_000).contains(ticks), ticks>=score, queued.count<=2,
              food == nil ? isComplete : (0..<(size*size)).contains(food!) && !body.contains(food!) else { return false }
        for index in 1..<body.count {
            let a = body[index-1], b = body[index]
            let distance = abs(a%size-b%size) + abs(a/size-b/size)
            if distance != 1 { return false }
        }
        return true
    }
    @discardableResult public mutating func turn(_ next: ArcadeDirection) -> Bool {
        let previous = queued.last ?? direction
        guard !hasLost, !isComplete, queued.count<2, next != previous, next != previous.opposite else { return false }
        queued.append(next); return true
    }
    @discardableResult public mutating func step() -> Bool {
        guard isValidSave, !hasLost, !isComplete, ticks<100_000_000 else { return false }
        if !queued.isEmpty { direction = queued.removeFirst() }
        let x = body[0]%size+direction.dx, y = body[0]/size+direction.dy; ticks += 1
        guard (0..<size).contains(x), (0..<size).contains(y) else { hasLost = true; return true }
        let next = y*size+x, eating = food==next
        let occupied = eating ? body : Array(body.dropLast()) // Vacating tail is legal.
        guard !occupied.contains(next) else { hasLost = true; return true }
        body.insert(next,at:0)
        if eating { placeFood() } else { body.removeLast() }; return true
    }
    private mutating func placeFood() {
        let available = (0..<(size*size)).filter { !body.contains($0) }
        var random = SeededRandom(seed:seed &+ UInt64(ticks) &* 0x9e3779b9); food = available.randomElement(using:&random)
    }
}
