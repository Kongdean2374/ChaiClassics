import Foundation

public enum GameID: String, Codable, CaseIterable, Identifiable, Sendable {
    case sudoku, minesweeper
    public var id: String { rawValue }
}

public struct GameDescriptor: Identifiable, Sendable {
    public let id: GameID
    public let name: String
    public let symbol: String
    public let category: String
}

public enum GameRegistry {
    public static let columns = 3
    public static let games = [
        GameDescriptor(id: .sudoku, name: "數獨", symbol: "square.grid.3x3", category: "數字與邏輯"),
        GameDescriptor(id: .minesweeper, name: "踩地雷", symbol: "flag", category: "數字與邏輯")
    ]
}
