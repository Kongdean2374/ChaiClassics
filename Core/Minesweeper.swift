import Foundation

public struct MineConfiguration: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let mineCount: Int
    public static let easy = try! MineConfiguration(width: 9, height: 9, mines: 10)
    public static let medium = try! MineConfiguration(width: 16, height: 16, mines: 40)
    public static let hard = try! MineConfiguration(width: 30, height: 16, mines: 99)
    public enum ConfigurationError: Error { case outOfRange }
    public init(width: Int, height: Int, mines: Int) throws {
        guard (5...40).contains(width), (5...40).contains(height), (1..<(width * height)).contains(mines) else { throw ConfigurationError.outOfRange }
        self.width = width; self.height = height; mineCount = mines
    }
    public var isValid: Bool { (try? Self(width: width, height: height, mines: mineCount)) != nil }
}

public struct MinesweeperBoard: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case ready, playing, won, lost }
    public enum Mode: String, Codable, Sendable { case reveal, flag }
    public let configuration: MineConfiguration
    public let seed: UInt64
    public private(set) var mines: Set<Int> = []
    public private(set) var revealed: Set<Int> = []
    public private(set) var flags: Set<Int> = []
    public private(set) var status: Status = .ready
    public var mode: Mode = .reveal
    public var elapsedSeconds = 0
    public private(set) var exploded: Int?
    public init(configuration: MineConfiguration, seed: UInt64 = UInt64.random(in: .min ... .max)) {
        self.configuration = configuration; self.seed = seed
    }
    public var cellCount: Int { configuration.width * configuration.height }
    public func neighbors(_ i: Int) -> [Int] {
        guard (0..<cellCount).contains(i) else { return [] }
        let w = configuration.width, h = configuration.height, r = i / w, c = i % w
        return (-1...1).flatMap { dr in (-1...1).compactMap { dc -> Int? in
            let rr = r + dr, cc = c + dc
            guard (dr != 0 || dc != 0), (0..<h).contains(rr), (0..<w).contains(cc) else { return nil }
            return rr * w + cc
        } }
    }
    public func adjacentMines(_ i: Int) -> Int { neighbors(i).filter { mines.contains($0) }.count }
    public var isFinished: Bool { status == .won || status == .lost }
    public mutating func toggleFlag(_ i: Int) {
        guard !isFinished, (0..<cellCount).contains(i), !revealed.contains(i) else { return }
        if !flags.insert(i).inserted { flags.remove(i) }
    }
    public mutating func tap(_ i: Int) {
        if mode == .flag { toggleFlag(i) } else { reveal(i) }
    }
    public mutating func reveal(_ i: Int) {
        guard !isFinished, (0..<cellCount).contains(i), !revealed.contains(i), !flags.contains(i) else { return }
        if status == .ready {
            let preferred = Set(neighbors(i) + [i])
            let excluded = cellCount - preferred.count >= configuration.mineCount ? preferred : [i]
            var rng = SeededRandom(seed: seed)
            let candidates = (0..<cellCount).filter { !excluded.contains($0) }.shuffled(using: &rng)
            mines = Set(candidates.prefix(configuration.mineCount)); status = .playing
        }
        if mines.contains(i) { exploded = i; revealed.insert(i); status = .lost; return }
        var queue = [i]
        while let index = queue.popLast() {
            guard !revealed.contains(index), !flags.contains(index), !mines.contains(index) else { continue }
            revealed.insert(index)
            if adjacentMines(index) == 0 { queue += neighbors(index).filter { !revealed.contains($0) } }
        }
        if revealed.count == cellCount - mines.count { status = .won }
    }
    public var isValidSave: Bool {
        guard configuration.isValid, elapsedSeconds >= 0 else { return false }
        let domain = Set(0..<cellCount)
        guard mines.isSubset(of: domain), revealed.isSubset(of: domain), flags.isSubset(of: domain), flags.isDisjoint(with: revealed) else { return false }
        switch status {
        case .ready: return mines.isEmpty && revealed.isEmpty && exploded == nil
        case .playing: return mines.count == configuration.mineCount && revealed.isDisjoint(with: mines) && revealed.count < cellCount - mines.count && exploded == nil
        case .won: return mines.count == configuration.mineCount && revealed.isDisjoint(with: mines) && revealed.count == cellCount - mines.count && exploded == nil
        case .lost: return mines.count == configuration.mineCount && exploded.map { mines.contains($0) && revealed.contains($0) } == true
        }
    }
}
