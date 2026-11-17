import SwiftUI
import ChaiCore

struct ExpandedStrategyView: View {
    let game: GameID
    @EnvironmentObject private var model: AppModel
    @Environment(\.gameReducedMotion) private var reduceMotion
    @State private var selected: Int?
    @State private var drop: Int?
    @State private var promotions: [ExpandedStrategyAction] = []
    @State private var choosingPromotion = false
    private var save: ExpandedGameSave? { model.expandedGames[game] }
    private var active: Bool { model.sessionIsPlaying(game) }
    private var humanTurn: Bool { active && save?.isComputerTurn == false && save?.outcome == nil }
    private var columns: Int { game == .gomoku ? 15 : [.chess,.reversi].contains(game) ? 8 : game == .banqi ? 4 : 9 }
    private var rows: Int { game == .xiangqi ? 10 : game == .banqi ? 8 : columns }
    private var unit: Int { game == .gomoku ? 34 : game == .banqi ? 58 : 42 }
    private var taskKey: String { "\(active)/\(save?.seed ?? 0)/\(save?.state.moves ?? -1)/\(save?.isComputerTurn ?? false)" }
    private var actions: [ExpandedStrategyAction] { save?.state.legalStrategyActions ?? [] }
    private var targets: Set<Int> {
        Set(actions.filter { action in
            if game == .gomoku || game == .reversi { return action.from == nil }
            if case .shogi(let move) = action, let drop { return move.drop == drop }
            if let selected { return action.from == selected }
            return false
        }.map(\.to))
    }
    private var turnText: String {
        let text = model.t("expanded.playerTurn",save?.state.currentPlayer?.rawValue ?? 1)
        if case .banqi(let board) = save?.state, let color = board.color {
            return text + (color>0 ? " · 🔴" : " · ⚫️")
        }
        return text
    }
    var body: some View {
        ScrollView {
            VStack(spacing:16) {
                HStack {
                    GameArtwork(game:game,size:44)
                    VStack(alignment:.leading,spacing:4) {
                        Text(model.gameTitle(game)).font(.headline)
                        Text(turnText)
                            .font(.subheadline).accessibilityIdentifier(game.rawValue+".turn")
                    }
                    Spacer()
                    Text(model.t("expanded.moves",save?.state.moves ?? 0)).font(.caption).monospacedDigit()
                        .accessibilityIdentifier(game.rawValue+".moves").accessibilityValue(String(save?.state.moves ?? 0))
                }
                Text(model.t("connectfour.thinking")).font(.caption).foregroundStyle(.secondary)
                    .opacity(save?.isComputerTurn == true ? 1 : 0).accessibilityHidden(save?.isComputerTurn != true)
                    .accessibilityIdentifier(game.rawValue+".thinking")
                if game == .shogi { shogiHand(.second) }
                board
                if game == .shogi {
                    shogiHand(.first)
                    if case .shogi(let board) = save?.state, board.canDeclareEnteringKing {
                        Button(model.t("expanded.shogi.declare")) {
                            _ = model.editExpanded(game) { state in
                                guard case .shogi(var b) = state, b.declareEnteringKing() else { return false }; state = .shogi(b); return true
                            }
                        }.buttonStyle(.borderedProminent).disabled(!humanTurn).accessibilityIdentifier("shogi.declare")
                    }
                }
                Text(model.t(game == .gomoku || game == .reversi ? "expanded.strategy.place" : "expanded.strategy.select"))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if case .reversi(let board) = save?.state {
                    Text(model.t("expanded.reversi.count",board.count(.first),board.count(.second))).font(.subheadline).monospacedDigit()
                    if let player = board.lastPassedPlayer { Text(model.t("expanded.reversi.pass",player.rawValue)).font(.caption) }
                }
                if checked { Text(model.t("expanded.check")).font(.headline).foregroundStyle(.orange).accessibilityIdentifier(game.rawValue+".check") }
            }.padding(16).frame(maxWidth:680).frame(maxWidth:.infinity)
        }
        .task(id:taskKey) { await computerMove() }
        .onChange(of:active) { _,value in if !value { selected = nil; drop = nil; choosingPromotion = false; promotions = [] } }
        .confirmationDialog(model.t("expanded.promotion"),isPresented:$choosingPromotion,titleVisibility:.visible) {
            ForEach(Array(promotions.enumerated()),id:\.offset) { _,action in
                Button(promotionTitle(action)) { apply(action) }.accessibilityIdentifier(game.rawValue+".promotion.\(action.promotion ?? 0)")
            }
            Button(model.t("common.cancel"),role:.cancel) { promotions = [] }
        }
    }
    private var checked: Bool {
        switch save?.state {
        case .chess(let b):return b.isInCheck(b.currentPlayer)
        case .xiangqi(let b):return b.isInCheck(b.currentPlayer)
        case .shogi(let b):return b.isInCheck(b.currentPlayer)
        default:return false
        }
    }
    private var board: some View {
        let cells = save?.state.strategyCells ?? []
        let legalTargets = targets
        // A checkmate/drop search belongs to the board render, not to every
        // cell. Shogi hands can produce hundreds of legal actions; repeating
        // the same result search 81 times stalls input and the session clock.
        let isActive = active, canPlay = humanTurn
        let showTargets = model.gameSettings(for:game).expanded?.showLegalMoves ?? true
        return ZoomBoard(size:CGSize(width:columns*unit,height:rows*unit),inputEnabled:isActive,accessibilityHidden:!isActive,
                         identifier:game.rawValue+".zoomBoard") {
            VStack(spacing:0) {
                ForEach(0..<rows,id:\.self) { row in
                    HStack(spacing:0) {
                        ForEach(0..<columns,id:\.self) { column in
                            let display = row*columns+column
                            let reversed = save?.mode == .singlePlayer && save?.humanPlayer == .second
                            let index = reversed ? cells.count-1-display : display
                            if cells.indices.contains(index) { strategyCell(index,cells:cells,legalTargets:legalTargets,canPlay:canPlay,isActive:isActive,showTargets:showTargets) }
                        }
                    }
                }
            }.background(GameMaterial.navy).environmentObject(model)
        }.frame(height:CGFloat(min(630,rows*unit+12))).background(GameBoardSurface(game:game,cornerRadius:18))
    }
    private func strategyCell(_ index: Int,cells: [Int],legalTargets: Set<Int>,canPlay: Bool,isActive: Bool,showTargets: Bool) -> some View {
        let hidden: Bool = { if case .banqi(let board) = save?.state { return !board.revealed[index] }; return false }()
        let piece = hidden ? 0 : cells[index]
        let placement = game == .gomoku || game == .reversi
        let available = canPlay && (placement ? legalTargets.contains(index) : cells[index] != 0 || legalTargets.contains(index) || hidden)
        return Button { choose(index) } label: {
            ZStack {
                Rectangle().fill(squareColor(index))
                if game == .gomoku || game == .xiangqi { intersection(index) }
                if hidden { RoundedRectangle(cornerRadius:9).fill(GameMaterial.teal).overlay { Image(systemName:"sparkle").foregroundStyle(GameMaterial.gold) }.padding(4) }
                else if piece != 0 { strategyPiece(piece).padding(game == .gomoku ? 4 : 3) }
                if showTargets, legalTargets.contains(index), !hidden {
                    if piece==0 {
                        Circle().fill(Color.blue.opacity(0.65)).frame(width:8,height:8).allowsHitTesting(false)
                    } else {
                        RoundedRectangle(cornerRadius:5).strokeBorder(Color.blue.opacity(0.8),lineWidth:2).padding(2).allowsHitTesting(false)
                    }
                }
                if selected==index { RoundedRectangle(cornerRadius:5).strokeBorder(Color.blue,lineWidth:3).padding(1) }
            }.frame(width:CGFloat(unit),height:CGFloat(unit)).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!available).accessibilityHidden(!isActive)
            .accessibilityLabel(model.t("expanded.cell",index/columns+1,index%columns+1)+", "+(hidden ? model.t("expanded.banqi.hidden") : piece==0 ? model.t("expanded.empty") : pieceName(piece)))
            .accessibilityValue(selected==index ? model.t("expanded.selected") : "")
            .accessibilityIdentifier(game.rawValue+".cell.\(index)")
    }
    private func squareColor(_ index: Int) -> Color {
        if game == .chess { return (index/8+index%8)%2==0 ? GameMaterial.ivory : GameMaterial.teal }
        if game == .reversi { return (index/8+index%8)%2==0 ? GameMaterial.teal : GameMaterial.teal.opacity(0.82) }
        return game == .banqi ? GameMaterial.navy : GameMaterial.ivory
    }
    private func intersection(_ index: Int) -> some View {
        Path { path in
            let size = CGFloat(unit), half = size/2
            path.move(to:CGPoint(x:index%columns==0 ? half : 0,y:half)); path.addLine(to:CGPoint(x:index%columns==columns-1 ? half : size,y:half))
            if game != .xiangqi || index/columns != 4 && index/columns != 5 || index%columns==0 || index%columns==columns-1 {
                path.move(to:CGPoint(x:half,y:index/columns==0 ? half : 0)); path.addLine(to:CGPoint(x:half,y:index/columns==rows-1 ? half : size))
            } else if index/columns==4 { path.move(to:CGPoint(x:half,y:0)); path.addLine(to:CGPoint(x:half,y:half)) }
            else { path.move(to:CGPoint(x:half,y:half)); path.addLine(to:CGPoint(x:half,y:CGFloat(unit))) }
        }.stroke(GameMaterial.ink.opacity(0.6),lineWidth:0.7).allowsHitTesting(false)
    }
    @ViewBuilder private func strategyPiece(_ piece: Int) -> some View {
        let positive = game == .gomoku || game == .reversi ? piece==1 : piece>0
        let belongsToFirst: Bool = {
            if case .banqi(let board) = save?.state, let firstColor = board.firstPlayerColor { return piece*firstColor>0 }
            return positive
        }()
        let rotate = save?.mode == .localTwoPlayer && !belongsToFirst
        if game == .gomoku || game == .reversi {
            Circle().fill(LinearGradient(colors:positive ? [.gray,GameMaterial.ink,.black] : [.white,GameMaterial.ivory,.gray],startPoint:.topLeading,endPoint:.bottomTrailing))
                .overlay(Circle().strokeBorder(GameMaterial.gold.opacity(0.8),lineWidth:0.8)).shadow(color:.black.opacity(0.25),radius:1.5,y:2)
        } else if game == .chess {
            Text(chessGlyph(piece)).font(.system(size:CGFloat(unit)*0.79)).foregroundStyle(positive ? GameMaterial.ivory : GameMaterial.ink)
                .shadow(color:positive ? .black : .white.opacity(0.9),radius:0.5).rotationEffect(.degrees(rotate ? 180 : 0))
        } else {
            Text(pieceGlyph(piece)).font(.system(size:CGFloat(unit)*0.48,weight:.bold,design:.serif)).minimumScaleFactor(0.7)
                .foregroundStyle(positive ? GameMaterial.coral : GameMaterial.ink)
                .frame(maxWidth:.infinity,maxHeight:.infinity).background(GameTileSurface(game:game,cornerRadius:game == .shogi ? 6 : CGFloat(unit)/2))
                .rotationEffect(.degrees(rotate ? 180 : 0))
        }
    }
    private func pieceName(_ piece: Int) -> String {
        if game == .gomoku || game == .reversi { return model.t(piece==1 ? "expanded.black" : "expanded.white") }
        let family = game == .banqi ? "xiangqi" : game.rawValue
        let name = model.t("piece.\(family).\(abs(piece))")
        if game == .chess { return model.t(piece>0 ? "expanded.white" : "expanded.black") + ", " + name }
        if game == .banqi || game == .xiangqi { return (piece>0 ? "🔴 " : "⚫️ ") + name }
        return name
    }
    private func chessGlyph(_ piece: Int) -> String { let glyphs = piece>0 ? ["","♙","♘","♗","♖","♕","♔"] : ["","♟","♞","♝","♜","♛","♚"]; return glyphs[min(abs(piece),6)] }
    private func pieceGlyph(_ piece: Int) -> String {
        if game == .shogi { return ["","歩","香","桂","銀","金","角","飛","王","と","杏","圭","全","馬","龍"][min(abs(piece),14)] }
        let glyphs = piece>0 ? ["","帥","仕","相","傌","俥","炮","兵"] : ["","將","士","象","馬","車","砲","卒"]
        return glyphs[min(abs(piece),7)]
    }
    @ViewBuilder private func shogiHand(_ player: DuelPlayer) -> some View {
        if case .shogi(let board) = save?.state {
            let canPlay = humanTurn && board.currentPlayer == player
            ScrollView(.horizontal) {
                HStack(spacing:5) {
                Text(model.t("expanded.hand",player.rawValue)).font(.caption)
                ForEach(1...7,id:\.self) { kind in
                    let count = board.hands[player.rawValue-1][kind]
                    if count>0 {
                        Button { selected = nil; drop = drop==kind ? nil : kind } label: {
                            Text(model.t("piece.shogi.\(kind)" )+" ×\(count)").font(.caption.bold()).padding(.horizontal,8).frame(minWidth:44,minHeight:44)
                        }.buttonStyle(.bordered).tint(drop==kind ? .blue : GamePalette.tint(game))
                            .disabled(!canPlay)
                            .accessibilityIdentifier("shogi.hand.\(player.rawValue).\(kind)")
                    }
                }
                }
            }.frame(maxWidth:.infinity).rotationEffect(.degrees(save?.mode == .localTwoPlayer && player == .second ? 180 : 0))
        }
    }
    private func choose(_ index: Int) {
        guard humanTurn, let board = save else { return }
        let choices: [ExpandedStrategyAction]
        if game == .gomoku || game == .reversi { choices = actions.filter{$0.to==index} }
        else if case .banqi(let b) = board.state, !b.revealed[index] { choices = [.banqi(.reveal(index))] }
        else if let drop { choices = actions.filter { action in if case .shogi(let move) = action { return move.drop==drop && move.to==index }; return false } }
        else { choices = actions.filter { $0.from==selected && $0.to==index } }
        if choices.count>1 { promotions = choices; choosingPromotion = true; return }
        if let action = choices.first { apply(action); return }
        // Placement games never select an existing stone/disc. In particular,
        // Reversi's positive 1/2 disc IDs must not enter signed-piece selection
        // and hide every legal empty destination on Black's turn.
        if game == .gomoku || game == .reversi { selected = nil; drop = nil; return }
        let piece = board.state.strategyCells[index]
        let own = game == .banqi ? { if case .banqi(let b) = board.state { return piece*(b.color ?? 0)>0 }; return false }() : piece*(board.state.currentPlayer == .first ? 1 : -1)>0
        selected = own ? index : nil; drop = nil
    }
    private func promotionTitle(_ action: ExpandedStrategyAction) -> String {
        if case .chess = action { return model.t("piece.chess.\(action.promotion ?? 5)") }
        return model.t(action.promotion == nil ? "expanded.noPromotion" : "expanded.promote")
    }
    private func apply(_ action: ExpandedStrategyAction) {
        guard humanTurn else { return }
        if model.editExpanded(game,{$0.playStrategy(action)}) { selected = nil; drop = nil; promotions = [] }
    }
    @MainActor private func computerMove() async {
        guard active, let snapshot = save, snapshot.isComputerTurn else { return }
        let key = taskKey, clock = ContinuousClock(), earliest = ContinuousClock.now.advanced(by:.milliseconds(450))
        let worker = Task.detached(priority:.userInitiated) { snapshot.state.recommendedStrategyAction(difficulty:snapshot.difficulty,seed:snapshot.seed) }
        let action = await withTaskCancellationHandler(operation:{await worker.value},onCancel:{worker.cancel()})
        do { try await clock.sleep(until:earliest) } catch { return }
        guard !Task.isCancelled, taskKey==key, active, let action, save?.state==snapshot.state else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration:0.18)) { _ = model.editExpanded(game,{$0.playStrategy(action)}) }
    }
}
