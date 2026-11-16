import Foundation

public struct SlidingBoard: Codable, Equatable, Sendable {
    public enum Difficulty: String, Codable, CaseIterable, Sendable {
        case easy, normal, hard
        public var title: String { switch self { case .easy: return "簡單"; case .normal: return "普通"; case .hard: return "困難" } }
        public var multiplier: Int { switch self { case .easy: return 12; case .normal: return 60; case .hard: return 200 } }
    }
    public enum BoardError: Error { case invalidSize }
    public let size: Int
    public let difficulty: Difficulty
    public let initialTiles: [Int]
    public private(set) var tiles: [Int]
    public private(set) var moves = 0
    public var elapsedSeconds = 0
    public var blank: Int { tiles.firstIndex(of: 0)! }
    public var isComplete: Bool { tiles == Self.goal(size) }
    public init(size: Int, difficulty: Difficulty, seed: UInt64 = UInt64.random(in: .min ... .max)) throws {
        guard (3...5).contains(size) else { throw BoardError.invalidSize }
        self.size = size; self.difficulty = difficulty
        var rng = SeededRandom(seed: seed)
        var grid = Self.goal(size), zero = size * size - 1, previous = -1
        let steps = size * difficulty.multiplier
        for _ in 0..<steps {
            let choices = Self.neighbors(zero, size: size).filter { $0 != previous }
            let index = choices.randomElement(using: &rng)!
            grid.swapAt(zero, index); previous = zero; zero = index
        }
        // A shuffled board must not start solved. The chain remains entirely legal.
        if grid == Self.goal(size) { grid.swapAt(zero, Self.neighbors(zero, size: size)[0]) }
        initialTiles = grid; tiles = grid
    }
    private static func goal(_ size: Int) -> [Int] { Array(1..<(size * size)) + [0] }
    private static func neighbors(_ i: Int, size: Int) -> [Int] {
        (0..<(size*size)).filter { abs($0 / size - i / size) + abs($0 % size - i % size) == 1 }
    }
    public func canMove(_ i: Int) -> Bool { tiles.indices.contains(i) && Self.neighbors(blank, size: size).contains(i) && !isComplete }
    public mutating func move(_ i: Int) {
        guard canMove(i) else { return }
        tiles.swapAt(i, blank); moves += 1
    }
    public mutating func restart() { tiles = initialTiles; moves = 0; elapsedSeconds = 0 }
    public static func isSolvable(_ tiles: [Int], size: Int) -> Bool {
        guard (3...5).contains(size), tiles.count == size*size, Set(tiles) == Set(0..<(size*size)) else { return false }
        let values = tiles.filter { $0 != 0 }
        var inversions = 0
        for i in values.indices { for j in values.indices where j > i && values[i] > values[j] { inversions += 1 } }
        if size % 2 == 1 { return inversions % 2 == 0 }
        let blankFromBottom = size - tiles.firstIndex(of: 0)! / size
        return (inversions + blankFromBottom) % 2 == 1
    }
    public var isValidSave: Bool {
        Self.isSolvable(tiles, size: size) && Self.isSolvable(initialTiles, size: size) && moves >= 0 && elapsedSeconds >= 0
    }
}
