import XCTest
@testable import ChaiCore

final class V030PuzzleTests: XCTestCase {
    func testNonogramCluesAmbiguityAndImpossibleClues() {
        XCTAssertEqual(NonogramBoard.clues([true,true,false,true]),[2,1])
        XCTAssertEqual(NonogramBoard.clues([false,false]),[0])
        XCTAssertEqual(NonogramBoard.solutions(rows:[[1],[1]],columns:[[1],[1]]).count,2)
        XCTAssertTrue(NonogramBoard.solutions(rows:[[3],[1]],columns:[[1],[1]]).isEmpty)
        XCTAssertEqual(NonogramBoard.solutions(rows:[[2],[0]],columns:[[1],[1]]),[[true,true,false,false]])
    }
    func testNonogramGeneratedBoardsAreUniqueDeterministicAndPlayable() throws {
        for size in [5,10,15] { for seed in [0, 1, 7, 42] {
            var board = NonogramBoard(size:size,seed:UInt64(seed))
            XCTAssertTrue(board.isValidSave); XCTAssertFalse(board.isComplete)
            XCTAssertEqual(board,NonogramBoard(size:size,seed:UInt64(seed)))
            XCTAssertEqual(NonogramBoard.solutions(rows:board.rowClues,columns:board.columnClues),[board.solution])
            XCTAssertFalse(board.mark(-1,crossed:false)); XCTAssertFalse(board.mark(size*size,crossed:false))
            let first = try XCTUnwrap(board.solution.firstIndex(of:true)); XCTAssertTrue(board.mark(first,crossed:true)); XCTAssertEqual(board.marks[first],-1)
            XCTAssertTrue(board.mark(first,crossed:true)); XCTAssertEqual(board.marks[first],0)
            for i in board.solution.indices where board.solution[i] { XCTAssertTrue(board.mark(i,crossed:false)) }
            XCTAssertTrue(board.isComplete); XCTAssertFalse(board.mark(first,crossed:false))
            XCTAssertEqual(try JSONDecoder().decode(NonogramBoard.self,from:JSONEncoder().encode(board)),board)
        }}
    }
    func testNonogramFallbackFamiliesRemainUniqueAfterReorientation() {
        for (size, templates) in NonogramBoard.fallbackRows {
            var signatures = Set<[Bool]>()
            for (index, template) in templates.enumerated() {
                let picture = NonogramBoard.transformedTemplate(template, transform: index + 2)
                let rows = (0..<size).map { row in
                    NonogramBoard.clues(Array(picture[(row * size)..<((row + 1) * size)]))
                }
                let columns = (0..<size).map { column in
                    NonogramBoard.clues((0..<size).map { picture[$0 * size + column] })
                }
                XCTAssertTrue((rows + columns).contains { $0.count >= 2 })
                XCTAssertEqual(NonogramBoard.solutions(rows: rows, columns: columns), [picture])
                signatures.insert(picture)
            }
            XCTAssertEqual(signatures.count, templates.count)
        }
    }
    func testKakuroGeneratedCrossesHaveUniqueDistinctDigitSolutions() throws {
        for size in [4,6,8] {
            var shapes = Set<[Bool]>()
            for seed in [0, 1, 7, 42] {
                var board = KakuroBoard(size:size,seed:UInt64(seed))
                XCTAssertTrue(board.isValidSave); XCTAssertFalse(board.isComplete)
                shapes.insert(board.solution.map { $0 < 0 })
                XCTAssertEqual(board,KakuroBoard(size:size,seed:UInt64(seed)))
                XCTAssertEqual(KakuroBoard.solutions(cells:board.givens,runs:board.runs),[board.solution])
                XCTAssertFalse(board.enter(1,at:0)); XCTAssertFalse(board.enter(10,at:size+1))
                for i in board.cells.indices where board.givens[i]==0 { XCTAssertTrue(board.enter(board.solution[i],at:i)) }
                XCTAssertTrue(board.isComplete); XCTAssertTrue(board.isValidSave)
                XCTAssertEqual(try JSONDecoder().decode(KakuroBoard.self,from:JSONEncoder().encode(board)),board)
            }
            XCTAssertGreaterThan(shapes.count, 1, "Seeded boards should vary in shape at size \(size).")
        }
    }
    func testKakuroRejectsRepeatedDigitsEvenWhenTheirSumMatches() {
        let board = KakuroBoard(size:4,seed:42)
        var cells = board.solution
        let run = board.runs[0]; cells[run.cells[0]] = 4; cells[run.cells[1]] = 4
        XCTAssertTrue(KakuroBoard.solutions(cells:cells,runs:board.runs).isEmpty)
    }
    func testKlotskiGenerationLegalMovesAndRoundTrip() throws {
        for seed in 0..<100 {
            var board = KlotskiBoard(seed:UInt64(seed),shuffle:250)
            XCTAssertTrue(board.isValidSave,"seed \(seed)"); XCTAssertFalse(board.isComplete,"seed \(seed)")
            XCTAssertEqual(board,KlotskiBoard(seed:UInt64(seed),shuffle:250))
            XCTAssertFalse(board.move(99,dx:1,dy:0)); XCTAssertFalse(board.move(0,dx:1,dy:1))
            var random = SeededRandom(seed:UInt64(seed))
            for _ in 0..<20 {
                let options = board.pieces.flatMap { p in [(1,0),(-1,0),(0,1),(0,-1)].filter { board.canMove(p.id,dx:$0.0,dy:$0.1) }.map{(p.id,$0.0,$0.1)} }
                if let m = options.randomElement(using:&random), !board.isComplete { XCTAssertTrue(board.move(m.0,dx:m.1,dy:m.2)); XCTAssertTrue(board.isValidSave) }
            }
            XCTAssertEqual(try JSONDecoder().decode(KlotskiBoard.self,from:JSONEncoder().encode(board)),board)
        }
    }
}
