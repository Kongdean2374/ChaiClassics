import Foundation

/// Navigation identities are deliberately separate from persistent `GameID`s.
/// This includes 25 logical games and the folders that organize their cards.
public enum CatalogItemID: String, CaseIterable, Identifiable, Sendable {
    case sudoku, minesweeper, sliding
    case ticTacToe = "tictactoe"
    case connectFour = "connectfour"
    case twentyFour = "twentyfour"
    case memory, maze, nonogram, kakuro, klotski, gomoku, reversi
    case boardGames = "boardgames"
    case xiangqi, banqi, chess, shogi
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
    /// Navigation membership is independent of both genre and save identity.
    public let parentID: CatalogItemID?
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
        case .folder:
            return GameCatalog.children(of: id).contains { $0.gameID != nil }
                ? "catalog.status.folderAvailable" : "catalog.status.folder"
        }
    }

    fileprivate init(_ id: CatalogItemID, _ kind: CatalogItemKind, _ group: CatalogGroup,
                     _ symbol: String, _ accent: CatalogAccent, parent: CatalogItemID? = nil) {
        self.id = id
        self.kind = kind
        self.group = group
        parentID = parent
        titleKey = kind == .folder ? "catalog." + id.rawValue + ".title" : "game." + id.rawValue
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
        .init(.boardGames, .folder, .strategy, "checkerboard.rectangle", .blue),
        .init(.ticTacToe, .playable(.ticTacToe), .strategy, "xmark.circle", .rose, parent: .boardGames),
        .init(.connectFour, .playable(.connectFour), .strategy, "circle.grid.3x3.fill", .blue, parent: .boardGames),
        .init(.twentyFour, .playable(.twentyFour), .logic, "plus.forwardslash.minus", .coral),
        .init(.memory, .playable(.memory), .puzzles, "square.on.square", .teal),
        .init(.maze, .playable(.maze), .puzzles, "point.topleft.down.curvedto.point.bottomright.up", .indigo),
        .init(.nonogram, .comingSoon, .logic, "square.grid.3x3.fill", .violet),
        .init(.kakuro, .comingSoon, .logic, "sum", .coral),
        .init(.klotski, .comingSoon, .puzzles, "rectangle.split.2x2", .amber),
        .init(.gomoku, .comingSoon, .strategy, "circle.grid.cross", .blue, parent: .boardGames),
        .init(.reversi, .comingSoon, .strategy, "circle.lefthalf.filled", .slate, parent: .boardGames),
        .init(.xiangqi, .comingSoon, .strategy, "circle.grid.3x3", .coral, parent: .boardGames),
        .init(.banqi, .comingSoon, .strategy, "rectangle.split.2x2", .amber, parent: .boardGames),
        .init(.chess, .comingSoon, .strategy, "checkerboard.rectangle", .slate, parent: .boardGames),
        .init(.shogi, .comingSoon, .strategy, "pentagon", .indigo, parent: .boardGames),
        .init(.solitaire, .folder, .solitaire, "suit.spade.fill", .jade),
        .init(.klondike, .comingSoon, .solitaire, "suit.spade.fill", .jade, parent: .solitaire),
        .init(.spider, .comingSoon, .solitaire, "suit.club.fill", .violet, parent: .solitaire),
        .init(.freecell, .comingSoon, .solitaire, "rectangle.on.rectangle", .blue, parent: .solitaire),
        .init(.pyramid, .comingSoon, .solitaire, "triangle", .amber, parent: .solitaire),
        .init(.tripeaks, .comingSoon, .solitaire, "mountain.2", .teal, parent: .solitaire),
        .init(.snake, .comingSoon, .arcade, "point.3.connected.trianglepath.dotted", .jade),
        .init(.fallingBlocks, .comingSoon, .arcade, "square.stack.3d.up", .rose),
        .init(.brickBreaker, .comingSoon, .arcade, "rectangle.split.3x1", .coral)
    ]

    /// 25 logical games, including both folders' children, never the folders.
    public static let games = items.filter { $0.kind != .folder }
    public static let playableGames = games.filter { $0.gameID != nil }
    public static let comingSoonGames = games.filter { $0.kind == .comingSoon }
    /// Six playable games, six individual previews, and two folders.
    public static let homeItems = items.filter { $0.parentID == nil }

    public static func item(_ id: CatalogItemID) -> CatalogItem? {
        items.first { $0.id == id }
    }

    public static func item(for game: GameID) -> CatalogItem? {
        playableGames.first { $0.gameID == game }
    }

    public static func children(of folder: CatalogItemID) -> [CatalogItem] {
        guard let entry = item(folder), entry.kind == .folder else { return [] }
        return items.filter { $0.parentID == entry.id }
    }
}
