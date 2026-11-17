import XCTest
@testable import ChaiCore

final class CatalogTests: XCTestCase {
    func testCompleteLogicalCatalogAndUniqueIdentities() {
        let expected: Set<CatalogItemID> = [
            .sudoku, .minesweeper, .sliding, .ticTacToe, .connectFour, .twentyFour, .memory, .maze,
            .nonogram, .kakuro, .klotski, .gomoku, .reversi,
            .klondike, .spider, .freecell, .pyramid, .tripeaks,
            .snake, .fallingBlocks, .brickBreaker
        ]
        XCTAssertEqual(GameCatalog.games.count, 21)
        XCTAssertEqual(Set(GameCatalog.games.map(\.id)), expected)
        XCTAssertEqual(GameCatalog.items.count, 22)
        XCTAssertEqual(Set(GameCatalog.items.map(\.id)).count, 22)
        XCTAssertEqual(Set(CatalogItemID.allCases), Set(GameCatalog.items.map(\.id)))
        XCTAssertEqual(GameCatalog.playableGames.count, 8)
        XCTAssertEqual(GameCatalog.comingSoonGames.count, 13)
    }

    func testHomeAndSolitaireFolderCoverEveryEntryExactlyOnce() throws {
        XCTAssertEqual(GameRegistry.columns, 3)
        XCTAssertEqual(GameCatalog.homeItems.count, 17)
        XCTAssertEqual(GameCatalog.homeItems.filter { $0.gameID != nil }.count, 8)
        XCTAssertEqual(GameCatalog.homeItems.filter { $0.kind == .comingSoon }.count, 8)
        XCTAssertEqual(GameCatalog.homeItems.filter { $0.kind == .folder }.map(\.id), [.solitaire])
        let children = GameCatalog.children(of: .solitaire)
        XCTAssertEqual(children.map(\.id), [.klondike, .spider, .freecell, .pyramid, .tripeaks])
        XCTAssertTrue(children.allSatisfy { $0.kind == .comingSoon && $0.group == .solitaire })
        XCTAssertEqual(try XCTUnwrap(GameCatalog.item(.solitaire)).kind, .folder)
        XCTAssertFalse(GameCatalog.games.contains { $0.id == .solitaire })

        let homeIDs = Set(GameCatalog.homeItems.map(\.id))
        let childIDs = Set(children.map(\.id))
        XCTAssertTrue(homeIDs.isDisjoint(with: childIDs))
        XCTAssertEqual(homeIDs.union(childIDs), Set(GameCatalog.items.map(\.id)))
        for item in GameCatalog.games {
            XCTAssertTrue(GameCatalog.children(of: item.id).isEmpty)
        }
    }

    func testPlayableRoutesAreOneToOneWithSaveIdentities() throws {
        let expected = ["sudoku", "minesweeper", "sliding", "tictactoe", "connectfour", "twentyfour", "memory", "maze"]
        XCTAssertEqual(GameID.allCases.map(\.rawValue), expected)
        XCTAssertEqual(GameRegistry.games.map(\.id), GameID.allCases)
        XCTAssertEqual(GameCatalog.playableGames.compactMap(\.gameID), GameID.allCases)
        for game in GameID.allCases {
            let item = try XCTUnwrap(GameCatalog.item(for: game))
            XCTAssertEqual(item.id.rawValue, game.rawValue)
            XCTAssertEqual(item.kind, .playable(game))
            XCTAssertEqual(item.titleKey, "game." + game.rawValue)
            XCTAssertEqual(item.availabilityKey, "catalog.status.playable")
        }
    }

    func testPlaceholdersAndFolderNeverBecomeSaveIDs() throws {
        let previews = GameCatalog.comingSoonGames + GameCatalog.items.filter { $0.kind == .folder }
        XCTAssertEqual(previews.count, 14)
        for item in previews {
            XCTAssertNil(item.gameID)
            XCTAssertNil(GameID(rawValue: item.id.rawValue))
            let data = try JSONEncoder().encode(item.id.rawValue)
            XCTAssertThrowsError(try JSONDecoder().decode(GameID.self, from: data))
            XCTAssertEqual(item.availabilityKey, item.kind == .folder ? "catalog.status.folder" : "catalog.status.comingSoon")
        }
    }

    func testLegacyRawValuesRemainByteCompatibleAndAllGamesRoundTrip() throws {
        for (game, legacy) in [(GameID.sudoku, "sudoku"), (.minesweeper, "minesweeper"), (.sliding, "sliding")] {
            let bytes = Data(("\"" + legacy + "\"").utf8)
            XCTAssertEqual(try JSONDecoder().decode(GameID.self, from: bytes), game)
            XCTAssertEqual(try JSONEncoder().encode(game), bytes)
        }
        for game in GameID.allCases {
            XCTAssertEqual(try JSONDecoder().decode(GameID.self, from: JSONEncoder().encode(game)), game)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(GameID.self, from: Data("\"unknown-future-game\"".utf8)))
    }

    func testMetadataHasDistinctLocalizationKeysAndArtwork() {
        XCTAssertEqual(Set(GameCatalog.items.map(\.titleKey)).count, 22)
        XCTAssertEqual(Set(GameCatalog.items.map(\.descriptionKey)).count, 22)
        for item in GameCatalog.items {
            XCTAssertFalse(item.symbol.isEmpty)
            XCTAssertTrue(item.titleKey.hasPrefix("game.") || item.titleKey == "catalog.solitaire.title")
            XCTAssertEqual(item.descriptionKey, "catalog.description." + item.id.rawValue)
            XCTAssertEqual(GameCatalog.item(item.id), item)
        }
        // The original three games retain their artwork identifiers and accents.
        XCTAssertEqual(GameCatalog.item(.sudoku)?.symbol, "square.grid.3x3")
        XCTAssertEqual(GameCatalog.item(.sudoku)?.accent, .violet)
        XCTAssertEqual(GameCatalog.item(.minesweeper)?.symbol, "flag")
        XCTAssertEqual(GameCatalog.item(.minesweeper)?.accent, .jade)
        XCTAssertEqual(GameCatalog.item(.sliding)?.symbol, "square.grid.2x2")
        XCTAssertEqual(GameCatalog.item(.sliding)?.accent, .amber)
    }
}
