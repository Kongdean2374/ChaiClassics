import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import ChaiCore

final class V030InteractionTests: XCTestCase {
    private func arranged(_ variant: SolitaireVariant, columns: [[Int]]) throws -> SolitaireBoard {
        let count = variant == .spider ? 104 : 52
        var columns = columns
        columns += Array(repeating:[],count:(variant == .spider ? 10 : variant == .freecell ? 8 : 7)-columns.count)
        let used = Set(columns.flatMap{$0}), remaining = (0..<count).filter{!used.contains($0)}
        var stock = remaining
        if variant == .freecell { columns[7] += remaining;stock = [] }
        func cards(_ ids:[Int]) -> [[String:Int]] { ids.map{["id":$0]} }
        return try v030Fixture(SolitaireBoard(variant:variant,seed:1),[
            "columns":columns.map(cards),"stock":cards(stock),"faceUp":columns.flatMap{$0}])
    }

    func testSolitaireLiftsOnlyTheTopCardWhenFingerStartsOnItsVisibleFace() throws {
        var board = try arranged(.klondike, columns: [[2, 14, 0], [16]])
        let table = SolitaireTableLayout(board: board)
        let top = table.columns[0][2]
        let picked = try XCTUnwrap(table.source(at: CGPoint(x: top.midX, y: top.minY + 3), in: board))
        let single = try XCTUnwrap(SolitaireDragIntent(board: board, source: picked.0))
        XCTAssertEqual(single.cards.map(\.id), [0])
        XCTAssertEqual(picked.1, top)

        let first = table.columns[0][0]
        let earlier = try XCTUnwrap(table.source(at: CGPoint(x: first.midX, y: first.minY + 3), in: board))
        XCTAssertEqual(SolitaireDragIntent(board: board, source: earlier.0)?.cards.map(\.id), [2, 14, 0])

        let wrongDrop = table.columns[1][0]
        let target = try XCTUnwrap(table.target(at: CGPoint(x: wrongDrop.midX, y: wrongDrop.midY), in: board))
        let before = board
        XCTAssertFalse(single.apply(on: target, to: &board))
        XCTAssertEqual(board, before)

        let foundation = try XCTUnwrap(table.slots.last)
        let rightmost = try XCTUnwrap(table.target(at: CGPoint(x: foundation.frame.midX, y: foundation.frame.midY), in: board))
        XCTAssertEqual(rightmost, .pile(.foundation(3)))
        XCTAssertTrue(single.apply(on: rightmost, to: &board))
        XCTAssertEqual(board.foundations[3].map(\.id), [0])
        XCTAssertEqual(board.columns[0].map(\.id), [2, 14])
    }

    func testSolitaireDoubleTapOnlyCollectsOneCardWhenFoundationAllowsIt() throws {
        for variant in [SolitaireVariant.klondike, .freecell] {
            var board = try arranged(variant, columns: [[0], [1], [15]])
            let ace = try XCTUnwrap(SolitaireDragIntent(board: board, source: .pile(.column(0), index: 0)))
            let earlyTwo = try XCTUnwrap(SolitaireDragIntent(board: board, source: .pile(.column(1), index: 0)))
            XCTAssertNil(earlyTwo.foundationTarget(in: board))
            let target = try XCTUnwrap(ace.foundationTarget(in: board))
            XCTAssertTrue(ace.apply(on: target, to: &board))
            let two = try XCTUnwrap(SolitaireDragIntent(board: board, source: .pile(.column(1), index: 0)))
            XCTAssertEqual(two.foundationTarget(in: board), target)
            XCTAssertTrue(two.apply(on: target, to: &board))
            XCTAssertEqual(board.foundations[0].map(\.id), [0, 1])
            let wrongSuit = try XCTUnwrap(SolitaireDragIntent(board: board, source: .pile(.column(2), index: 0)))
            XCTAssertNil(wrongSuit.foundationTarget(in: board))
            let collected = try XCTUnwrap(SolitaireDragIntent(board: board, source: .pile(.foundation(0), index: 1)))
            XCTAssertNil(collected.foundationTarget(in: board))
        }
    }
    func testCardDragMovesWholeSequenceOnceAndInvalidDropIsAtomic() throws {
        var board = try arranged(.klondike,columns:[[2,14,0],[16]])
        let before = board
        let intent = try XCTUnwrap(SolitaireDragIntent(board:board,source:.pile(.column(0),index:0)))
        XCTAssertEqual(intent.cards.map(\.id),[2,14,0])
        XCTAssertFalse(intent.canDrop(on:.pile(.foundation(0)),in:board))
        XCTAssertFalse(intent.apply(on:.pile(.column(0)),to:&board))
        XCTAssertEqual(board,before)
        XCTAssertTrue(intent.apply(on:.pile(.column(1)),to:&board))
        XCTAssertEqual(board.columns[1].map(\.id),[16,2,14,0]);XCTAssertEqual(board.moves,1)
        let moved = board;XCTAssertFalse(intent.apply(on:.pile(.column(2)),to:&board));XCTAssertEqual(board,moved)
        XCTAssertTrue(board.isValidSave)
    }
    func testHiddenAndBrokenSequencesCannotStartDragging() throws {
        let broken = try arranged(.klondike,columns:[[15,14],[3]])
        XCTAssertNil(SolitaireDragIntent(board:broken,source:.pile(.column(0),index:0)))
        let hidden = try v030Fixture(try arranged(.klondike,columns:[[2,14,0],[16]]),["faceUp":[14,0,16]])
        XCTAssertNil(SolitaireDragIntent(board:hidden,source:.pile(.column(0),index:0)))
        XCTAssertNil(SolitaireDragIntent(board:hidden,source:.pile(.column(Int.max),index:Int.min)))
    }
    func testDrawAndUndoInvalidateAnOldDragWithoutChangingItsSourceCards() throws {
        var board = try arranged(.klondike,columns:[[0]])
        let intent = try XCTUnwrap(SolitaireDragIntent(board:board,source:.pile(.column(0),index:0)))
        XCTAssertTrue(board.draw());XCTAssertFalse(intent.canDrop(on:.pile(.foundation(0)),in:board))
        XCTAssertTrue(board.undo());XCTAssertFalse(intent.canDrop(on:.pile(.foundation(0)),in:board))
        XCTAssertEqual(board.columns[0].map(\.id),[0])
    }
    func testFreecellDragToCellAndSpiderSequenceUseTheirRealRules() throws {
        var free = try arranged(.freecell,columns:[[0]])
        let freeDrag = try XCTUnwrap(SolitaireDragIntent(board:free,source:.pile(.column(0),index:0)))
        XCTAssertTrue(freeDrag.apply(on:.pile(.freeCell(0)),to:&free));XCTAssertEqual(free.freeCells[0]?.id,0)
        var spider = try arranged(.spider,columns:[[1,0],[2]])
        let spiderDrag = try XCTUnwrap(SolitaireDragIntent(board:spider,source:.pile(.column(0),index:0)))
        XCTAssertTrue(spiderDrag.apply(on:.pile(.column(1)),to:&spider));XCTAssertEqual(spider.columns[1].map(\.id),[2,1,0])
        XCTAssertTrue(free.isValidSave);XCTAssertTrue(spider.isValidSave)
    }
    private func peaks(_ variant:SolitaireVariant) throws -> SolitaireBoard {
        let waste = variant == .pyramid ? 11 : 12
        let remaining = (0..<52).filter{$0 != 0 && $0 != waste}
        func cards(_ ids:[Int]) -> [[String:Int]] { ids.map{["id":$0]} }
        let table = Array(remaining.prefix(27))+[0]
        return try v030Fixture(SolitaireBoard(variant:variant,seed:1),[
            "tableau":cards(table),"stock":cards(Array(remaining.dropFirst(27))),
            "waste":cards([waste]),"faceUp":table+[waste]])
    }
    func testPyramidDragPairsWithWasteWithoutRemovingCoveredCards() throws {
        var board = try peaks(.pyramid)
        XCTAssertNil(SolitaireDragIntent(board:board,source:.tableau(0)))
        let intent = try XCTUnwrap(SolitaireDragIntent(board:board,source:.tableau(27)))
        XCTAssertTrue(intent.apply(on:.pile(.waste),to:&board))
        XCTAssertNil(board.tableau[27]);XCTAssertEqual(Set(board.removed.map(\.id)),Set([0,11]))
        XCTAssertTrue(board.isValidSave);XCTAssertFalse(intent.apply(on:.pile(.waste),to:&board))
    }
    func testTripeaksDragAceOntoKingUsesWrapRule() throws {
        var board = try peaks(.tripeaks)
        let intent = try XCTUnwrap(SolitaireDragIntent(board:board,source:.tableau(27)))
        XCTAssertFalse(intent.canDrop(on:.tableau(26),in:board))
        XCTAssertTrue(intent.apply(on:.pile(.waste),to:&board));XCTAssertEqual(board.waste.last?.id,0)
        XCTAssertTrue(board.isValidSave)
    }
    func testSnakeSwipeCommitsOneDominantDirectionPerGestureAndRejectsReversal() throws {
        var swipe = SnakeSwipe()
        XCTAssertNil(swipe.direction(x: 4, y: 5))
        XCTAssertNil(swipe.direction(x: .nan, y: 50))
        XCTAssertNil(swipe.direction(x: 50, y: .infinity))
        XCTAssertEqual(swipe.direction(x: 25, y: 10), .right)
        XCTAssertNil(swipe.direction(x: 4, y: -40), "A curved swipe cannot queue a second turn.")

        var board = SnakeBoard(size: 16, seed: 3)
        swipe.finish()
        XCTAssertFalse(board.turn(try XCTUnwrap(swipe.direction(x: -25, y: 9))))
        XCTAssertNil(swipe.direction(x: -25, y: 60), "A rejected reversal still consumes that swipe.")
        XCTAssertTrue(board.queued.isEmpty)

        swipe.finish()
        XCTAssertTrue(board.turn(try XCTUnwrap(swipe.direction(x: 8, y: -30))))
        XCTAssertTrue(board.step())
        XCTAssertEqual(board.direction, .up)

        swipe.finish()
        XCTAssertTrue(board.turn(try XCTUnwrap(swipe.direction(x: -35, y: 0))))
        // A continuous left-then-down path, including a direction change
        // across many touch samples, still queues only the original left turn.
        for y in 1...120 {
            XCTAssertNil(swipe.direction(x: -35, y: Double(y)))
        }
        XCTAssertEqual(board.queued, [.left])

        swipe.finish()
        XCTAssertTrue(board.turn(try XCTUnwrap(swipe.direction(x: 8, y: 30))))
        XCTAssertEqual(board.queued, [.left, .down])
        XCTAssertTrue(board.step())
        XCTAssertEqual(board.direction, .left)
        XCTAssertTrue(board.step())
        XCTAssertEqual(board.direction, .down)
        XCTAssertFalse(board.hasLost)
    }
    func testHeldInputIsDisplayRateIndependentAndOldFingerCannotReleaseNewDirection() {
        func count(_ frames:Int) -> Int {
            var input = ArcadeInputRepeat();XCTAssertTrue(input.press(.left));var count = 1
            for _ in 0..<frames { if input.advance(1/Double(frames)) != nil { count += 1 } }
            return count
        }
        XCTAssertEqual(count(60),count(120))
        var input = ArcadeInputRepeat();XCTAssertTrue(input.press(.left));XCTAssertFalse(input.press(.left))
        XCTAssertTrue(input.press(.right));input.release(.left);XCTAssertEqual(input.held,.right)
        XCTAssertNil(input.advance(30));XCTAssertNil(input.advance(.nan))
        input.cancel();XCTAssertNil(input.advance(0.1));XCTAssertNil(input.held)
    }
    func testBlockDragMapsColumnsAndCannotOperateTheNextPiece() {
        var drag = FallingBlockDrag(piece:4)
        XCTAssertEqual(drag.change(x:65,y:5,unit:20,currentPiece:4).dx,3)
        XCTAssertEqual(drag.change(x:42,y:8,unit:20,currentPiece:4).dx,-1)
        XCTAssertEqual(drag.change(x:80,y:10,unit:20,currentPiece:5).dx,0)
        var drop = FallingBlockDrag(piece:4)
        XCTAssertEqual(drop.change(x:0,y:65,unit:20,currentPiece:4).down,3)
        XCTAssertTrue(drop.hardDrop(y:90,predictedY:180,unit:20,currentPiece:4))
        XCTAssertFalse(drop.hardDrop(y:90,predictedY:180,unit:20,currentPiece:5))
        XCTAssertFalse(drop.hardDrop(y:90,predictedY:100,unit:20,currentPiece:4))
        XCTAssertEqual(drop.change(x:.infinity,y:10,unit:20,currentPiece:4).down,0)
    }
    func testMalformedLockCountersAndExtremeMoveInputsAreRejectedWithoutTrapping() throws {
        var blocks = FallingBlocksBoard(seed:7);let original = blocks
        XCTAssertFalse(blocks.move(Int.min));XCTAssertEqual(blocks,original)
        for patch in [["lockTicks":Int.max],["lockResets":Int.max],["lockTicks":-1]] {
            XCTAssertFalse(try v030Fixture(blocks,patch).isValidSave)
        }
        var klotski = KlotskiBoard(seed:1);let originalKlotski = klotski
        XCTAssertFalse(klotski.move(0,dx:Int.min,dy:0));XCTAssertEqual(klotski,originalKlotski)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(klotski)) as? [String:Any])
        var pieces = try XCTUnwrap(raw["pieces"] as? [[String:Any]])
        pieces[0]["x"] = Int.max
        XCTAssertFalse(try v030Fixture(klotski,["pieces":pieces]).isValidSave)
    }
}
