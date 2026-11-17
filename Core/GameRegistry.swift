import Foundation

public enum GameID: String, Codable, CaseIterable, Identifiable, Sendable {
    case sudoku, minesweeper, sliding
    case ticTacToe = "tictactoe"
    case connectFour = "connectfour"
    case twentyFour = "twentyfour"
    case memory, maze
    public var id: String { rawValue }
}

/// Only playable games have a save identity. Catalog folders and previews use
/// `CatalogItemID`, so adding a future entry cannot change saved-game decoding.
public struct GameDescriptor: Identifiable, Sendable {
    public let id: GameID
    /// A localization key; resolve it using the application's selected language.
    public let name: String
    public let symbol: String
    public let category: String
}

public enum GameRegistry {
    public static let columns = 3
    public static let games: [GameDescriptor] = GameCatalog.playableGames.compactMap { item in
        guard let game = item.gameID else { return nil }
        return GameDescriptor(id: game, name: item.titleKey, symbol: item.symbol, category: item.group.rawValue)
    }
}
