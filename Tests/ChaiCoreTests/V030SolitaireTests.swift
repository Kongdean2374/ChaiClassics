import XCTest
@testable import ChaiCore

final class V030SolitaireTests: XCTestCase {
    private func arranged(_ variant: SolitaireVariant, columns: [[Int]], free: [Int?] = [nil,nil,nil,nil], waste: [Int] = []) throws -> SolitaireBoard {
        let count = variant == .spider ? 104 : 52
        let used = Set(columns.flatMap{$0}+free.compactMap{$0}+waste)
        let remaining = (0..<count).filter{!used.contains($0)}
        var actual = columns
        let columnCount = variant == .spider ? 10 : variant == .freecell ? 8 : 7
        actual += Array(repeating:[],count:max(0,columnCount-actual.count))
        var stock = remaining
        if variant == .freecell { actual[columnCount-1] += remaining; stock = [] }
        func cards(_ values: [Int]) -> [[String:Int]] { values.map{["id":$0]} }
        let exposed = Set(actual.flatMap{$0}+free.compactMap{$0}+waste)
        return try v030Fixture(SolitaireBoard(variant:variant,seed:1),[
            "stock":cards(stock),"waste":cards(waste),"columns":actual.map(cards),"freeCells":free.map{$0.map{["id":$0]} as Any? ?? NSNull()},"faceUp":Array(exposed)
        ])
    }
    func testAllDealsDeterministicConserveCardsAndRoundTrip() throws {
        for variant in SolitaireVariant.allCases { for seed in 0..<30 {
            let board = SolitaireBoard(variant:variant,seed:UInt64(seed)); XCTAssertTrue(board.isValidSave,"\(variant) \(seed)")
            XCTAssertEqual(board,SolitaireBoard(variant:variant,seed:UInt64(seed))); XCTAssertFalse(board.isComplete)
            XCTAssertEqual(try JSONDecoder().decode(SolitaireBoard.self,from:JSONEncoder().encode(board)),board)
        }}
    }
    func testKlondikeDrawThreeRecycleAndNoMutationOnIllegalMove() {
        var board = SolitaireBoard(variant:.klondike,seed:4,drawCount:3)
        let previous = board, expected = Array(board.stock.suffix(3).reversed())
        XCTAssertFalse(board.move(from:.column(0),index:99,to:.foundation(0))); XCTAssertEqual(board,previous)
        XCTAssertTrue(board.draw()); XCTAssertEqual(board.waste,expected); XCTAssertEqual(board.stock.count,21)
        while !board.stock.isEmpty { XCTAssertTrue(board.draw()) }
        XCTAssertTrue(board.recycle()); XCTAssertEqual(board.stock,previous.stock); XCTAssertTrue(board.waste.isEmpty); XCTAssertTrue(board.isValidSave)
    }
    func testKlondikeAlternatingSequencesKingOnlyAndFoundations() throws {
        var board = try arranged(.klondike,columns:[[0],[14],[2]])
        XCTAssertTrue(board.isValidSave); XCTAssertFalse(board.move(from:.column(1),index:0,to:.column(3)))
        XCTAssertTrue(board.move(from:.column(0),index:0,to:.foundation(0)))
        XCTAssertTrue(board.move(from:.column(1),index:0,to:.column(2)))
        XCTAssertTrue(board.move(from:.foundation(0),index:0,to:.column(2)))
        XCTAssertEqual(board.columns[2].map(\.id),[2,14,0]); XCTAssertTrue(board.isValidSave)
        var king = try arranged(.klondike,columns:[[12]])
        XCTAssertTrue(king.move(from:.column(0),index:0,to:.column(1)))
    }
    func testFreecellCapacityUsesEmptyCellsAndDestinationColumnCorrectly() throws {
        var board = try arranged(.freecell,columns:[[2,14],[16],[5],[7],[9],[11],[18]],free:[0,20,21,22])
        XCTAssertTrue(board.isValidSave); XCTAssertFalse(board.canMove(from:.column(0),index:0,to:.column(1)))
        XCTAssertTrue(board.move(from:.freeCell(0),index:0,to:.foundation(0)))
        XCTAssertTrue(board.canMove(from:.column(0),index:0,to:.column(1)))
        XCTAssertTrue(board.move(from:.column(0),index:0,to:.column(1))); XCTAssertTrue(board.isValidSave)
        XCTAssertFalse(board.draw()); XCTAssertFalse(board.recycle())
    }
    func testSpiderCollectsOnlyCompleteSuitedRunAndCannotMoveCompletedCardsBack() throws {
        var board = try arranged(.spider,columns:[Array(stride(from:12,through:1,by:-1)),[0]])
        XCTAssertTrue(board.isValidSave); XCTAssertTrue(board.move(from:.column(1),index:0,to:.column(0)))
        XCTAssertEqual(board.foundations[0].count,13); XCTAssertTrue(board.columns[0].isEmpty)
        XCTAssertFalse(board.move(from:.foundation(0),index:12,to:.column(0))); XCTAssertFalse(board.draw())
        XCTAssertTrue(board.isValidSave)
    }
    func testSpiderDealsTenCardsAndPreservesAll104Identities() {
        var board = SolitaireBoard(variant:.spider,seed:99,spiderSuits:4)
        let old = board.columns.map(\.count); XCTAssertTrue(board.draw())
        XCTAssertEqual(board.columns.map(\.count),old.map{$0+1}); XCTAssertEqual(board.stock.count,40); XCTAssertTrue(board.isValidSave)
    }
    func testPyramidCoverageAndSum13RemovalWithWaste() throws {
        var board = SolitaireBoard(variant:.pyramid,seed:42)
        XCTAssertFalse(board.isExposed(0)); for i in 21..<28 { XCTAssertTrue(board.isExposed(i)) }
        XCTAssertFalse(board.removePyramid(0)); XCTAssertFalse(board.removePyramid(-999))
        let bottom = Array(board.tableau[21..<28]).compactMap{$0}
        if let king = bottom.first(where:{$0.rank==13}), let index = board.tableau.firstIndex(where:{$0?.id==king.id}) {
            XCTAssertTrue(board.removePyramid(index)); XCTAssertNil(board.tableau[index]); XCTAssertTrue(board.isValidSave)
        }
        // Actual fixture keeps every original card identity while arranging a
        // bottom-row A and waste Q, which must remove together.
        var table = board.tableau; var stock = board.stock
        let all = table.compactMap{$0}+stock+board.waste+board.removed
        let ace = try XCTUnwrap(all.first(where:{$0.rank==1})), queen = try XCTUnwrap(all.first(where:{$0.rank==12}))
        let remaining = all.filter{$0 != ace && $0 != queen}
        table = Array(remaining.prefix(27)).map(Optional.some)+[ace]; stock = Array(remaining.dropFirst(27))
        func data(_ c: PlayingCard) -> [String:Int] { ["id":c.id] }
        board = try v030Fixture(board,["tableau":table.map{$0.map(data) as Any? ?? NSNull()},"stock":stock.map(data),"waste":[data(queen)],"removed":[],"faceUp":[ace.id,queen.id]])
        XCTAssertTrue(board.isValidSave); XCTAssertTrue(board.removePyramid(27,-1)); XCTAssertEqual(board.removed.count,2); XCTAssertTrue(board.isValidSave)
    }
    func testTriPeaksCoverageAndAdjacentRankIncludingWrap() throws {
        var board = SolitaireBoard(variant:.tripeaks,seed:12)
        for i in 18..<28 { XCTAssertTrue(board.isExposed(i)) }; for i in 0..<18 { XCTAssertFalse(board.isExposed(i)) }
        let old = board; XCTAssertFalse(board.removeTriPeak(0)); XCTAssertEqual(board,old)
        let all = board.stock+board.waste+board.tableau.compactMap{$0}, ace = try XCTUnwrap(all.first(where:{$0.rank==1})), king = try XCTUnwrap(all.first(where:{$0.rank==13}))
        let remaining = all.filter{$0 != ace && $0 != king}; var tableau = Array(remaining.prefix(27)); tableau.append(ace)
        func data(_ c: PlayingCard) -> [String:Int] { ["id":c.id] }
        board = try v030Fixture(board,["tableau":tableau.map(data),"stock":remaining.dropFirst(27).map(data),"waste":[data(king)],"faceUp":[ace.id,king.id]])
        XCTAssertTrue(board.removeTriPeak(27)); XCTAssertEqual(board.waste.last,ace); XCTAssertNil(board.tableau[27]); XCTAssertTrue(board.isValidSave)
    }
}
