import Foundation

/// Navigation identities are deliberately separate from persistent `GameID`s.
/// This includes all 21 logical games and the one folder that groups solitaire.
public enum CatalogItemID: String, CaseIterable, Identifiable, Sendable {
    case sudoku, minesweeper, sliding
    case ticTacToe = "tictactoe"
    case connectFour = "connectfour"
    case twentyFour = "twentyfour"
    case memory, maze, nonogram, kakuro, klotski, gomoku, reversi
    case solitaire, klondike, spider, freecell, pyramid, tripeaks
    case snake
    case fallingBlocks = "fallingblocks"
    case brickBreaker = "brickbreaker"
    public var id: String { rawValue }
}

public enum CatalogItemKind: Equatable, Sendable {
    case playable(GameID)
    case comingSoon
    case folder
}

public enum CatalogGroup: String, CaseIterable, Sendable {
    case logic, strategy, puzzles, solitaire, arcade
}

/// Semantic accents are resolved into light/dark colors by the UI layer.
public enum CatalogAccent: String, Sendable {
    case violet, jade, amber, rose, blue, coral, teal, indigo, slate
}

public struct CatalogItem: Identifiable, Equatable, Sendable {
    public let id: CatalogItemID
    public let kind: CatalogItemKind
    public let group: CatalogGroup
    public let titleKey: String
    public let descriptionKey: String
    public let symbol: String
    public let accent: CatalogAccent

    public var gameID: GameID? {
        if case let .playable(game) = kind { return game }
        return nil
    }

    public var availabilityKey: String {
        switch kind {
        case .playable: return "catalog.status.playable"
        case .comingSoon: return "catalog.status.comingSoon"
        case .folder: return "catalog.status.folder"
        }
    }

    fileprivate init(_ id: CatalogItemID, _ kind: CatalogItemKind, _ group: CatalogGroup,
                     _ symbol: String, _ accent: CatalogAccent) {
        self.id = id
        self.kind = kind
        self.group = group
        titleKey = id == .solitaire ? "catalog.solitaire.title" : "game." + id.rawValue
        descriptionKey = "catalog.description." + id.rawValue
        self.symbol = symbol
        self.accent = accent
    }
}

/// The complete, offline catalog is the only source for card metadata and
/// availability. Activate a future game here after connecting its real menu.
public enum GameCatalog {
    public static let items: [CatalogItem] = [
        .init(.sudoku, .playable(.sudoku), .logic, "square.grid.3x3", .violet),
        .init(.minesweeper, .playable(.minesweeper), .logic, "flag", .jade),
        .init(.sliding, .playable(.sliding), .puzzles, "square.grid.2x2", .amber),
        .init(.ticTacToe, .playable(.ticTacToe), .strategy, "xmark.circle", .rose),
        .init(.connectFour, .playable(.connectFour), .strategy, "circle.grid.3x3.fill", .blue),
        .init(.twentyFour, .playable(.twentyFour), .logic, "plus.forwardslash.minus", .coral),
        .init(.memory, .playable(.memory), .puzzles, "square.on.square", .teal),
        .init(.maze, .playable(.maze), .puzzles, "point.topleft.down.curvedto.point.bottomright.up", .indigo),
        .init(.nonogram, .comingSoon, .logic, "square.grid.3x3.fill", .violet),
        .init(.kakuro, .comingSoon, .logic, "sum", .coral),
        .init(.klotski, .comingSoon, .puzzles, "rectangle.split.2x2", .amber),
        .init(.gomoku, .comingSoon, .strategy, "circle.grid.cross", .blue),
        .init(.reversi, .comingSoon, .strategy, "circle.lefthalf.filled", .slate),
        .init(.solitaire, .folder, .solitaire, "suit.spade.fill", .jade),
        .init(.klondike, .comingSoon, .solitaire, "suit.spade.fill", .jade),
        .init(.spider, .comingSoon, .solitaire, "suit.club.fill", .violet),
        .init(.freecell, .comingSoon, .solitaire, "rectangle.on.rectangle", .blue),
        .init(.pyramid, .comingSoon, .solitaire, "triangle", .amber),
        .init(.tripeaks, .comingSoon, .solitaire, "mountain.2", .teal),
        .init(.snake, .comingSoon, .arcade, "point.3.connected.trianglepath.dotted", .jade),
        .init(.fallingBlocks, .comingSoon, .arcade, "square.stack.3d.up", .rose),
        .init(.brickBreaker, .comingSoon, .arcade, "rectangle.split.3x1", .coral)
    ]

    /// 21 logical games, including the five solitaire variants, never the folder.
    public static let games = items.filter { $0.kind != .folder }
    public static let playableGames = games.filter { $0.gameID != nil }
    public static let comingSoonGames = games.filter { $0.kind == .comingSoon }
    /// Eight playable games, eight individual previews, and the solitaire folder.
    public static let homeItems = items.filter { $0.group != .solitaire || $0.kind == .folder }

    public static func item(_ id: CatalogItemID) -> CatalogItem? {
        items.first { $0.id == id }
    }

    public static func item(for game: GameID) -> CatalogItem? {
        playableGames.first { $0.gameID == game }
    }

    public static func children(of folder: CatalogItemID) -> [CatalogItem] {
        guard let entry = item(folder), entry.kind == .folder else { return [] }
        return games.filter { $0.group == entry.group }
    }
}
