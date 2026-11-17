import XCTest
@testable import ChaiCore

func v030Fixture<T: Codable>(_ value: T, _ changes: [String:Any]) throws -> T {
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as? [String:Any])
    for (key,data) in changes { object[key] = data }
    return try JSONDecoder().decode(T.self,from:JSONSerialization.data(withJSONObject:object))
}

final class V030StrategyTests: XCTestCase {
    func testGomokuAllDirectionsAndTerminalInput() {
        for stride in [1,15,16,14] {
            var board = GomokuBoard(); let start = stride==14 ? 4 : 0
            for i in 0..<4 { XCTAssertTrue(board.place(start+i*stride)); XCTAssertTrue(board.place(200+i)) }
            XCTAssertTrue(board.place(start+4*stride)); XCTAssertEqual(board.winner,.first)
            XCTAssertTrue(board.isFinished); XCTAssertFalse(board.place(100)); XCTAssertTrue(board.isValidSave)
        }
    }
    func testGomokuAIWinsOrBlocksAndNeverPlacesOnAnOccupiedCell() {
        var board = GomokuBoard()
        for i in 0..<4 { XCTAssertTrue(board.place(i)); XCTAssertTrue(board.place(30+i)) }
        XCTAssertEqual(board.recommendedMove(difficulty:.hard,seed:0),4)
        var threat = GomokuBoard()
        for pair in [(100,0),(120,1),(140,2),(160,3)] { _ = threat.place(pair.0); _ = threat.place(pair.1) }
        XCTAssertEqual(threat.recommendedMove(difficulty:.normal,seed:0),4)
        XCTAssertFalse(threat.place(100)); XCTAssertFalse(threat.place(-1))
    }
    func testReversiOpeningFlipsAndFullRandomGamesIncludingAutomaticPass() throws {
        var opening = ReversiBoard(); XCTAssertEqual(opening.legalMoves(for:.first),[19,26,37,44])
        XCTAssertFalse(opening.place(0)); XCTAssertTrue(opening.place(19)); XCTAssertEqual(opening.cells[27],1); XCTAssertEqual(opening.count(.first),4)
        var observedPass = false
        for seed in 0..<40 {
            var board = ReversiBoard(), random = SeededRandom(seed:UInt64(seed))
            while !board.isFinished {
                let move = try XCTUnwrap(board.legalMoves(for:board.currentPlayer).randomElement(using:&random))
                XCTAssertTrue(board.place(move)); XCTAssertTrue(board.isValidSave); observedPass = observedPass || board.lastPassedPlayer != nil
            }
            XCTAssertFalse(board.place(0)); XCTAssertEqual(board.count(.first)+board.count(.second),board.moves+4)
            XCTAssertEqual(try JSONDecoder().decode(ReversiBoard.self,from:JSONEncoder().encode(board)),board)
        }
        XCTAssertTrue(observedPass)
    }
    func testChessOpeningPerftAndFoolsMate() throws {
        let board = ChessBoard(); XCTAssertTrue(board.isValidSave); XCTAssertEqual(board.legalMoves().count,20)
        var nodes = 0
        for move in board.legalMoves() { var child = board; XCTAssertTrue(child.play(move)); nodes += child.legalMoves().count }
        XCTAssertEqual(nodes,400)
        let kiwi = try XCTUnwrap(ChessBoard(fen:"r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"))
        XCTAssertEqual(kiwi.legalMoves().count,48)
        var mate = board
        for m in [ChessMove(from:53,to:45),.init(from:12,to:28),.init(from:54,to:38),.init(from:3,to:39)] { XCTAssertTrue(mate.play(m)) }
        XCTAssertEqual(mate.result,.won(.second)); XCTAssertFalse(mate.play(.init(from:52,to:44)))
    }
    func testChessCastlingThroughCheckEnPassantAndPromotionChoices() throws {
        var castle = try XCTUnwrap(ChessBoard(fen:"r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
        XCTAssertTrue(castle.legalMoves().contains(.init(from:60,to:62))); XCTAssertTrue(castle.play(.init(from:60,to:62)))
        XCTAssertEqual(castle.cells[61],4); XCTAssertEqual(castle.cells[63],0); XCTAssertEqual(castle.castling.prefix(2),[false,false])
        let checked = try XCTUnwrap(ChessBoard(fen:"4kr2/8/8/8/8/8/8/4K2R w K - 0 1"))
        XCTAssertFalse(checked.legalMoves().contains(.init(from:60,to:62)))
        var ep = try XCTUnwrap(ChessBoard(fen:"7k/8/8/3pP3/8/8/8/7K w - d6 0 1"))
        XCTAssertTrue(ep.play(.init(from:28,to:19))); XCTAssertEqual(ep.cells[27],0); XCTAssertEqual(ep.cells[19],1)
        let pinnedEP = try XCTUnwrap(ChessBoard(fen:"k3r3/8/8/3pP3/8/8/8/4K3 w - d6 0 1"))
        XCTAssertFalse(pinnedEP.legalMoves().contains(.init(from:28,to:19)))
        let promotion = try XCTUnwrap(ChessBoard(fen:"7k/P7/8/8/8/8/8/7K w - - 0 1"))
        XCTAssertEqual(promotion.legalMoves().filter{$0.from==8 && $0.to==0}.count,4)
        for piece in [2,3,4,5] { var next = promotion; XCTAssertTrue(next.play(.init(from:8,to:0,promotion:piece))); XCTAssertEqual(next.cells[0],piece) }
    }
    func testChessStalemateRepetitionInsufficientMaterialAndSave() throws {
        let stale = try XCTUnwrap(ChessBoard(fen:"7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")); XCTAssertEqual(stale.result,.draw); XCTAssertFalse(stale.isInCheck(.second))
        let insufficient = try XCTUnwrap(ChessBoard(fen:"7k/8/8/8/8/8/8/KB6 w - - 0 1")); XCTAssertEqual(insufficient.result,.draw)
        var repeatBoard = ChessBoard()
        for _ in 0..<2 { for m in [ChessMove(from:62,to:45),.init(from:6,to:21),.init(from:45,to:62),.init(from:21,to:6)] { XCTAssertTrue(repeatBoard.play(m)) } }
        XCTAssertEqual(repeatBoard.result,.draw); XCTAssertEqual(try JSONDecoder().decode(ChessBoard.self,from:JSONEncoder().encode(repeatBoard)),repeatBoard)
    }
    func testXiangqiOpeningHorseLegCannonScreenAndGeneralSafety() throws {
        let board = XiangqiBoard(); XCTAssertTrue(board.isValidSave); XCTAssertEqual(board.legalMoves().count,44)
        XCTAssertTrue(board.legalMoves().contains(.init(from:82,to:63))); XCTAssertFalse(board.legalMoves().contains(.init(from:82,to:75)))
        XCTAssertTrue(board.legalMoves().contains(.init(from:64,to:1))); XCTAssertFalse(board.legalMoves().contains(.init(from:64,to:19)))
        var exposed = board.cells
        for i in stride(from:13,through:76,by:9) { exposed[i] = 0 }
        let facing = try v030Fixture(board,["cells":exposed]); XCTAssertTrue(facing.isInCheck(.first)); XCTAssertTrue(facing.isInCheck(.second))
        for move in facing.legalMoves() { var next = facing; XCTAssertTrue(next.play(move)); XCTAssertFalse(next.isInCheck(.first)) }
    }
    func testShogiOpeningNifuAndPromotion() throws {
        let board = ShogiBoard(); XCTAssertTrue(board.isValidSave); XCTAssertEqual(board.legalMoves().count,30)
        var cells = board.cells, hands = board.hands
        cells[18] = 0; hands[0][1] = 1
        var hand = try v030Fixture(board,["cells":cells,"hands":hands]); XCTAssertTrue(hand.isValidSave)
        XCTAssertFalse(hand.legalMoves().contains{$0.drop==1})
        cells[54] = 0; hands[1][1] = 1
        hand = try v030Fixture(board,["cells":cells,"hands":hands]); XCTAssertTrue(hand.isValidSave)
        XCTAssertTrue(hand.legalMoves().contains(.init(to:27,drop:1))); XCTAssertFalse(hand.legalMoves().contains(.init(to:0,drop:1)))
        XCTAssertTrue(hand.play(.init(to:27,drop:1))); XCTAssertEqual(hand.hands[0][1],0); XCTAssertEqual(hand.cells[27],1)
        cells = board.cells; cells[54] = 0; cells[9] = 1
        let promote = try v030Fixture(board,["cells":cells]); XCTAssertTrue(promote.isValidSave)
        XCTAssertTrue(promote.legalMoves().contains(.init(from:9,to:0,promote:true))); XCTAssertFalse(promote.legalMoves().contains(.init(from:9,to:0)))
    }
    func testBanqiRevealsAssignSidesAndAINeverPeeks() throws {
        var board = BanqiBoard(seed:12); XCTAssertEqual(board.legalActions().count,32); XCTAssertTrue(board.isValidSave)
        let first = board.pieces[0]; XCTAssertTrue(board.play(.reveal(0))); XCTAssertEqual(board.firstPlayerColor,first>0 ? 1 : -1)
        XCTAssertFalse(board.play(.reveal(0))); XCTAssertEqual(board.currentPlayer,.second)
        let different = try XCTUnwrap((2..<32).first(where:{board.pieces[$0] != board.pieces[1]}))
        var swapped = board.pieces; swapped.swapAt(1,different); XCTAssertNotEqual(swapped,board.pieces)
        let other = try v030Fixture(board,["pieces":swapped]); XCTAssertTrue(other.isValidSave)
        XCTAssertEqual(board.recommendedAction(difficulty:.hard,randomSeed:77),other.recommendedAction(difficulty:.hard,randomSeed:77))
        XCTAssertEqual(try JSONDecoder().decode(BanqiBoard.self,from:JSONEncoder().encode(board)),board)
    }
    func testStrategyAIsAlwaysReturnLegalMovesAndRespectCancellationBounds() throws {
        for difficulty in DuelDifficulty.allCases {
            let chess = ChessBoard(); XCTAssertTrue(chess.legalMoves().contains(try XCTUnwrap(chess.recommendedMove(difficulty:difficulty,seed:1))))
            let xiangqi = XiangqiBoard(); XCTAssertTrue(xiangqi.legalMoves().contains(try XCTUnwrap(xiangqi.recommendedMove(difficulty:difficulty,seed:1))))
            let shogi = ShogiBoard(); XCTAssertTrue(shogi.legalMoves().contains(try XCTUnwrap(shogi.recommendedMove(difficulty:difficulty,seed:1))))
            let reversi = ReversiBoard(); XCTAssertTrue(reversi.legalMoves(for:.first).contains(try XCTUnwrap(reversi.recommendedMove(difficulty:difficulty,seed:1))))
        }
    }
    func testBanqiHardAIAvoidsAVisibleLosingExchangeAndCannonNeedsOneScreen() throws {
        var cells = Array(repeating:0,count:32)
        cells[0] = 5; cells[1] = -7; cells[5] = -2; cells[8] = 1
        let board = try v030Fixture(BanqiBoard(seed:0),["pieces":cells,"revealed":Array(repeating:true,count:32),"firstPlayerColor":1,"moves":40])
        XCTAssertTrue(board.isValidSave)
        // The rook may take the soldier, but an adjacent guard recaptures it.
        XCTAssertTrue(board.legalActions().contains(.move(8,9)))
        XCTAssertEqual(board.recommendedAction(difficulty:.normal,randomSeed:7),.move(0,1))
        XCTAssertNotEqual(board.recommendedAction(difficulty:.hard,randomSeed:7),.move(0,1))
        cells = Array(repeating:0,count:32); cells[0] = 6; cells[3] = -1; cells[4] = 1
        var cannon = try v030Fixture(board,["pieces":cells])
        XCTAssertFalse(cannon.legalActions().contains(.move(0,3)))
        cells[1] = 7; cannon = try v030Fixture(board,["pieces":cells])
        XCTAssertTrue(cannon.legalActions().contains(.move(0,3)))
        XCTAssertEqual(cannon.recommendedAction(difficulty:.hard,randomSeed:7),.move(0,3))
        cells = Array(repeating:0,count:32); cells[0] = 5; cells[1] = -4; cells[4] = 1
        let rook = try v030Fixture(board,["pieces":cells])
        XCTAssertTrue(rook.legalActions().contains(.move(0,1)),"A rook outranks a horse even though its artwork ID is larger.")
        cells[0] = 4; cells[1] = -5
        let horse = try v030Fixture(board,["pieces":cells])
        XCTAssertFalse(horse.legalActions().contains(.move(0,1)))
    }
}
