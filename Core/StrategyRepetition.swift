/// Records the position occurrences and the last nonchecking move by each side.
/// Those are sufficient to test every move in the span of a repeated position.
struct StrategyRepetition: Codable, Equatable, Sendable {
    private var visits: [String: [Int]]
    private var lastQuietPly: [Int]

    init(key: String, ply: Int) {
        visits = [key: [ply]]
        lastQuietPly = [ply, ply]
    }

    mutating func record(key: String, ply: Int, mover: DuelPlayer, gaveCheck: Bool) {
        visits[key, default: []].append(ply)
        if !gaveCheck { lastQuietPly[mover.rawValue - 1] = ply }
    }

    func result(key: String, occurrences: Int) -> StrategyResult? {
        guard lastQuietPly.count == 2, let plies = visits[key], plies.count >= occurrences, let first = plies.first else { return nil }
        let firstChecking = lastQuietPly[0] <= first
        let secondChecking = lastQuietPly[1] <= first
        if firstChecking != secondChecking { return .won(firstChecking ? .second : .first) }
        return .draw
    }

    func isValid(through ply: Int, occurrences: Int) -> Bool {
        lastQuietPly.count == 2 && lastQuietPly.allSatisfy { (0...ply).contains($0) } &&
            visits.count <= 10_001 && visits.values.allSatisfy { plies in
                (1...occurrences).contains(plies.count) && plies.allSatisfy { (0...ply).contains($0) } &&
                    zip(plies, plies.dropFirst()).allSatisfy { $0 < $1 }
            }
    }
}
