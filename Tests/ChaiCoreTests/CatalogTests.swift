import XCTest
@testable import ChaiCore

final class CatalogTests: XCTestCase {
    func testCompleteLogicalCatalogAndUniqueIdentities() {
        let expected: Set<CatalogItemID> = [
            .sudoku, .minesweeper, .sliding, .ticTacToe, .connectFour, .twentyFour, .memory, .maze,
            .nonogram, .kakuro, .klotski, .gomoku, .reversi, .xiangqi, .banqi, .chess, .shogi,
            .klondike, .spider, .freecell, .pyramid, .tripeaks,
            .snake, .fallingBlocks, .brickBreaker
        ]
        XCTAssertEqual(GameCatalog.games.count, 25)
        XCTAssertEqual(Set(GameCatalog.games.map(\.id)), expected)
        XCTAssertEqual(GameCatalog.items.count, 27)
        XCTAssertEqual(Set(GameCatalog.items.map(\.id)).count, 27)
        XCTAssertEqual(Set(CatalogItemID.allCases), Set(GameCatalog.items.map(\.id)))
        XCTAssertEqual(GameCatalog.playableGames.count, 8)
        XCTAssertEqual(GameCatalog.comingSoonGames.count, 17)
    }

    func testHomeAndSolitaireFolderCoverEveryEntryExactlyOnce() throws {
        XCTAssertEqual(GameRegistry.columns, 3)
        XCTAssertEqual(GameCatalog.homeItems.count, 14)
        XCTAssertEqual(GameCatalog.homeItems.filter { $0.gameID != nil }.count, 6)
        XCTAssertEqual(GameCatalog.homeItems.filter { $0.kind == .comingSoon }.count, 6)
        XCTAssertEqual(GameCatalog.homeItems.filter { $0.kind == .folder }.map(\.id), [.boardGames, .solitaire])
        let children = GameCatalog.children(of: .solitaire)
        XCTAssertEqual(children.map(\.id), [.klondike, .spider, .freecell, .pyramid, .tripeaks])
        XCTAssertTrue(children.allSatisfy { $0.kind == .comingSoon && $0.group == .solitaire })
        XCTAssertEqual(try XCTUnwrap(GameCatalog.item(.solitaire)).kind, .folder)
        XCTAssertFalse(GameCatalog.games.contains { $0.id == .solitaire })

        let boardGames = GameCatalog.children(of: .boardGames)
        XCTAssertEqual(boardGames.map(\.id), [.ticTacToe, .connectFour, .gomoku, .reversi, .xiangqi, .banqi, .chess, .shogi])
        XCTAssertEqual(boardGames.compactMap(\.gameID), [.ticTacToe, .connectFour])
        XCTAssertEqual(boardGames.filter { $0.kind == .comingSoon }.count, 6)
        XCTAssertTrue(boardGames.allSatisfy { $0.parentID == .boardGames && $0.group == .strategy })
        XCTAssertEqual(try XCTUnwrap(GameCatalog.item(.boardGames)).kind, .folder)
        XCTAssertEqual(GameCatalog.item(.boardGames)?.availabilityKey, "catalog.status.folderAvailable")
        XCTAssertEqual(GameCatalog.item(.solitaire)?.availabilityKey, "catalog.status.folder")
        XCTAssertFalse(GameCatalog.games.contains { $0.id == .boardGames })

        let homeIDs = Set(GameCatalog.homeItems.map(\.id))
        let childIDs = Set((children + boardGames).map(\.id))
        XCTAssertEqual(childIDs.count, 13)
        XCTAssertTrue(Set(children.map(\.id)).isDisjoint(with: Set(boardGames.map(\.id))))
        XCTAssertTrue(homeIDs.isDisjoint(with: childIDs))
        XCTAssertEqual(homeIDs.union(childIDs), Set(GameCatalog.items.map(\.id)))
        XCTAssertTrue(GameCatalog.homeItems.allSatisfy { $0.parentID == nil })
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
        XCTAssertEqual(previews.count, 19)
        for item in previews {
            XCTAssertNil(item.gameID)
            XCTAssertNil(GameID(rawValue: item.id.rawValue))
            let data = try JSONEncoder().encode(item.id.rawValue)
            XCTAssertThrowsError(try JSONDecoder().decode(GameID.self, from: data))
            let folderKey = item.id == .boardGames ? "catalog.status.folderAvailable" : "catalog.status.folder"
            XCTAssertEqual(item.availabilityKey, item.kind == .folder ? folderKey : "catalog.status.comingSoon")
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
        XCTAssertEqual(Set(GameCatalog.items.map(\.titleKey)).count, 27)
        XCTAssertEqual(Set(GameCatalog.items.map(\.descriptionKey)).count, 27)
        for item in GameCatalog.items {
            XCTAssertFalse(item.symbol.isEmpty)
            XCTAssertEqual(item.titleKey, item.kind == .folder ? "catalog." + item.id.rawValue + ".title" : "game." + item.id.rawValue)
            XCTAssertEqual(item.descriptionKey, "catalog.description." + item.id.rawValue)
            XCTAssertEqual(GameCatalog.item(item.id), item)
            if let parent = item.parentID {
                XCTAssertEqual(GameCatalog.item(parent)?.kind, .folder)
                XCTAssertTrue(GameCatalog.children(of: parent).contains(item))
            }
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
