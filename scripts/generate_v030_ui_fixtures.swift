// Run against the actual ChaiCore build, never against App UI or production storage.
import Foundation
import ChaiCore

struct FixturePlan: Codable { let game: String; let actions: [String]; let outcome: String }
func changed<T: Codable>(_ value: T,_ fields: [String:Any]) throws -> T {
    var object = try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as! [String:Any]
    for (key,data) in fields { object[key] = data }
    return try JSONDecoder().decode(T.self,from:JSONSerialization.data(withJSONObject:object))
}
func cards(_ ids: [Int]) -> [[String:Int]] { ids.map{["id":$0]} }
let output = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let store = try SaveStore(directory:output)
for game in GameID.allCases where game.isExpanded {
    var save = ExpandedGameSave(game:game,seed:42,difficulty:.easy,mode:.localTwoPlayer)!
    var actions: [String] = [], expected = "won"
    switch save.state {
    case .nonogram(let board):
        let target = board.solution.firstIndex(of:true)!
        var marks = board.solution.map{$0 ? 1 : -1}; marks[target] = 0
        save.state = .nonogram(try changed(board,["marks":marks,"moves":20])); actions = ["nonogram.cell.\(target)"]; expected = "completed"
    case .kakuro(let board):
        let target = board.givens.firstIndex(of:0)!
        var cells = board.solution; cells[target] = 0
        save.state = .kakuro(try changed(board,["cells":cells,"moves":20])); actions = ["kakuro.cell.\(target)","kakuro.digit.\(board.solution[target])"]; expected = "completed"
    case .klotski(let board):
        let pieces = [KlotskiPieceFixture(0,2,2,1,2),.init(1,2,1,1,1),.init(2,1,2,0,1),.init(3,1,2,3,1),.init(4,1,2,0,3),.init(5,1,2,3,3),.init(6,1,1,0,0),.init(7,1,1,3,0),.init(8,1,1,1,0),.init(9,1,1,2,0)]
        save.state = .klotski(try changed(board,["pieces":pieces.map(\.dictionary),"moves":20])); actions = ["klotski.piece.0","klotski.move.2"]; expected = "completed"
    case .gomoku(var board):
        for i in [0,15,1,16,2,17,3,18] { precondition(board.place(i)) }; save.state = .gomoku(board); actions = ["gomoku.cell.4"]
    case .reversi(let board):
        var cells = Array(repeating:1,count:64); cells[0] = 0; cells[1] = 2
        save.state = .reversi(try changed(board,["cells":cells,"moves":59])); actions = ["reversi.cell.0"]
    case .chess:
        save.state = .chess(ChessBoard(fen:"7k/6pp/5KQ1/8/8/8/8/8 w - - 0 1")!); actions = ["chess.cell.22","chess.cell.14"]
    case .xiangqi(let board):
        var cells = Array(repeating:0,count:90); cells[4] = -1; cells[3] = -4; cells[5] = -4; cells[85] = 1; cells[49] = 7; cells[12] = 5; cells[15] = 5
        save.state = .xiangqi(try changed(board,["cells":cells])); actions = ["xiangqi.cell.12","xiangqi.cell.13"]
    case .banqi(let board):
        var cells = Array(repeating:0,count:32); cells[0] = 7; cells[1] = -1
        save.state = .banqi(try changed(board,["pieces":cells,"revealed":Array(repeating:true,count:32),"firstPlayerColor":1,"moves":60])); actions = ["banqi.cell.0","banqi.cell.1"]
    case .shogi(let board):
        var cells = Array(repeating:0,count:81); cells[4] = -8; cells[3] = -3; cells[5] = -3; cells[76] = 8; cells[12] = 7; cells[15] = 7
        let hands = [[0,18,4,2,4,4,2,0],Array(repeating:0,count:8)]
        save.state = .shogi(try changed(board,["cells":cells,"hands":hands])); actions = ["shogi.cell.12","shogi.cell.13","shogi.promotion.1"]
    case .solitaire(let board):
        let variant = board.variant
        var columns = Array(repeating:[Int](),count:variant == .spider ? 10 : variant == .freecell ? 8 : variant == .klondike ? 7 : 0)
        var foundation = Array(repeating:[Int](),count:variant == .spider ? 8 : 4)
        var waste: [Int] = [], removed: [Int] = [], tableau: [Any] = []
        if variant == .klondike || variant == .freecell {
            foundation = (0..<4).map { Array(($0*13)..<($0*13+($0==0 ? 12 : 13))) }; columns[0] = [12]
            actions = [game.rawValue+".card.12",game.rawValue+".pile.foundation.0"]
        } else if variant == .spider {
            foundation = (0..<8).map { k in k==0 ? [] : Array(stride(from:k*13+12,through:k*13,by:-1)) }
            columns[0] = Array(stride(from:12,through:1,by:-1)); columns[1] = [0]
            actions = ["spider.card.0","spider.card.1"]
        } else if variant == .pyramid {
            tableau = Array(repeating:NSNull() as Any,count:28); tableau[27] = ["id":12]
            removed = (0..<52).filter{$0 != 12}; actions = ["pyramid.tableau.27"]
        } else {
            tableau = Array(repeating:NSNull() as Any,count:28); tableau[27] = ["id":0]
            waste = Array(1..<52).filter{$0 != 12}+[12]; actions = ["tripeaks.tableau.27"]
        }
        save.state = .solitaire(try changed(board,["stock":[],"waste":cards(waste),"columns":columns.map(cards),"foundations":foundation.map(cards),"tableau":tableau,"removed":cards(removed),"faceUp":Array(0..<(variant == .spider ? 104 : 52))]))
    case .snake(let board):
        let path = (0..<16).flatMap { row in (0..<16).map { column in row*16+(row%2==0 ? column : 15-column) } }
        save.state = .snake(try changed(board,["body":Array(path.dropLast().reversed()),"food":path.last!,"direction":3,"ticks":400])); expected = "completed"
    case .fallingBlocks(let board):
        var cells = Array(repeating:0,count:200); for row in 0..<20 { cells[row*10+3] = 7 }
        save.state = .fallingBlocks(try changed(board,["cells":cells,"active":1,"rotation":0,"x":3,"y":15,"next":[2,0,1,3,4,5,6]])); actions = ["fallingblocks.hardDrop"]; expected = "lost"
    case .brickBreaker(let board):
        var bricks = Array(repeating:0,count:40); bricks[0] = 1
        save.state = .brickBreaker(try changed(board,["bricks":bricks,"ballX":0.075,"ballY":0.15,"velocityX":0.0,"velocityY":(-0.43)])); actions = ["brickbreaker.launch"]; expected = "completed"
    }
    save.elapsedSeconds = 12
    precondition(save.isValidSave && save.outcome==nil,"Invalid pre-game fixture: \(game)")
    var completed = save
    switch completed.state {
    case .nonogram(var b):precondition(b.mark(Int(actions[0].split(separator:".").last!)!,crossed:false)); completed.state = .nonogram(b)
    case .kakuro(var b):precondition(b.enter(Int(actions[1].split(separator:".").last!)!,at:Int(actions[0].split(separator:".").last!)!)); completed.state = .kakuro(b)
    case .klotski(var b):precondition(b.move(0,dx:0,dy:1)); completed.state = .klotski(b)
    case .solitaire(var b):
        switch b.variant {
        case .klondike,.freecell:precondition(b.move(from:.column(0),index:0,to:.foundation(0)))
        case .spider:precondition(b.move(from:.column(1),index:0,to:.column(0)))
        case .pyramid:precondition(b.removePyramid(27))
        case .tripeaks:precondition(b.removeTriPeak(27))
        }; completed.state = .solitaire(b)
    case .snake(var b):precondition(b.step()); completed.state = .snake(b)
    case .fallingBlocks(var b):precondition(b.hardDrop()); completed.state = .fallingBlocks(b)
    case .brickBreaker(var b):precondition(b.launch()); for _ in 0..<100 where !b.isComplete { _ = b.advance(1.0/120) }; completed.state = .brickBreaker(b)
    default:
        let target = game == .gomoku ? 4 : game == .reversi ? 0 : game == .chess ? 14 : game == .xiangqi || game == .shogi ? 13 : 1
        let action = completed.state.legalStrategyActions.first { $0.to==target && (game != .shogi || $0.promotion==1) }!
        precondition(completed.state.playStrategy(action))
    }
    precondition(completed.isValidSave && completed.outcome?.rawValue==expected,"Fixture does not reach real result: \(game)")
    try store.save(save,namespace:game.rawValue)
    let file = output.appendingPathComponent(game.rawValue+".json")
    var envelope = try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [String:Any]
    envelope["testPlan"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(FixturePlan(game:game.rawValue,actions:actions,outcome:expected)))
    try JSONSerialization.data(withJSONObject:envelope,options:[.sortedKeys]).write(to:output.appendingPathComponent("v030-"+game.rawValue+".json"))
    try FileManager.default.removeItem(at:file)
    print("Validated near-end fixture: \(game.rawValue)")
}
struct KlotskiPieceFixture {
    let id:Int,width:Int,height:Int,x:Int,y:Int
    init(_ id:Int,_ width:Int,_ height:Int,_ x:Int,_ y:Int) { self.id=id;self.width=width;self.height=height;self.x=x;self.y=y }
    var dictionary: [String:Int] { ["id":id,"width":width,"height":height,"x":x,"y":y] }
}
