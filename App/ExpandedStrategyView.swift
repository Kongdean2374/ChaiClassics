import SwiftUI
import ChaiCore

private struct StrategyMotion: Identifiable {
    struct Track: Identifiable {
        let from: Int
        let to: Int
        let piece: Int
        var id: Int { from }
    }

    let id = UUID()
    let tracks: [Track]

    init?(action: ExpandedStrategyAction, cells: [Int]) {
        guard let source = action.from, cells.indices.contains(source),
              cells.indices.contains(action.to), cells[source] != 0 else { return nil }
        var tracks = [Track(from: source, to: action.to, piece: cells[source])]
        if case .chess = action, abs(cells[source]) == 6, abs(source - action.to) == 2 {
            let kingSide = action.to > source
            let rookFrom = source + (kingSide ? 3 : -4)
            let rookTo = source + (kingSide ? 1 : -1)
            if cells.indices.contains(rookFrom), cells[rookFrom] != 0 {
                tracks.append(Track(from: rookFrom, to: rookTo, piece: cells[rookFrom]))
            }
        }
        self.tracks = tracks
    }
}

struct ExpandedStrategyView: View {
    let game: GameID
    @EnvironmentObject private var model: AppModel
    @Environment(\.gameReducedMotion) private var reduceMotion
    @State private var selected: Int?
    @State private var drop: Int?
    @State private var promotions: [ExpandedStrategyAction] = []
    @State private var choosingPromotion = false
    @State private var choosingChessDrawMove = false
    @State private var motion: StrategyMotion?
    @State private var shownCheckMove: Int?
    @State private var boardWidth: CGFloat = 340
    private var save: ExpandedGameSave? { model.expandedGames[game] }
    private var active: Bool { model.sessionIsPlaying(game) }
    private var humanTurn: Bool { active && motion == nil && save?.isComputerTurn == false && save?.outcome == nil }
    private var columns: Int { game == .gomoku ? 15 : [.chess,.reversi].contains(game) ? 8 : game == .banqi ? 4 : 9 }
    private var rows: Int { game == .xiangqi ? 10 : game == .banqi ? 8 : columns }
    private var unit: Int { game == .gomoku ? 34 : game == .banqi ? 58 : 42 }
    private var taskKey: String { "\(active)/\(save?.seed ?? 0)/\(save?.state.moves ?? -1)/\(save?.isComputerTurn ?? false)/\(motion == nil)" }
    private var actions: [ExpandedStrategyAction] {
        if choosingChessDrawMove, case .chess(let board) = save?.state {
            return board.drawClaimMoves.map(ExpandedStrategyAction.chess)
        }
        return save?.state.legalStrategyActions ?? []
    }
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
                if game == .chess { chessDrawControls }
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
        .task(id: checkNoticeMove) { await showCheckNotice() }
        .task(id: motion?.id) {
            // A hosted board can disappear before it reports animation
            // completion. Never leave input or the result waiting for it.
            guard let id = motion?.id else { return }
            do { try await Task.sleep(for: .milliseconds(370)) } catch { return }
            settleMotion(id)
        }
        .onChange(of:active) { _,value in
            if !value {
                selected = nil; drop = nil; choosingPromotion = false; promotions = []
                choosingChessDrawMove = false
                motion = nil
            }
        }
        .onChange(of: reduceMotion) { _, value in if value { motion = nil } }
        .onDisappear {
            if motion != nil {
                motion = nil
                model.finishSessionIfNeeded(game, resultReady: true)
            }
        }
        .confirmationDialog(model.t("expanded.promotion"),isPresented:$choosingPromotion,titleVisibility:.visible) {
            ForEach(Array(promotions.enumerated()),id:\.offset) { _,action in
                Button(promotionTitle(action)) { apply(action) }.accessibilityIdentifier(game.rawValue+".promotion.\(action.promotion ?? 0)")
            }
            Button(model.t("common.cancel"),role:.cancel) { promotions = [] }
        }
        .background(GameCanvas()).tint(GamePalette.tint(game))
        .gameSessionScreen(game, resultReady: motion == nil)
    }
    @ViewBuilder private var chessDrawControls: some View {
        if humanTurn, case .chess(let board) = save?.state {
            if board.canClaimDraw {
                Button(model.t("expanded.chess.claimDraw")) { claimChessDraw() }
                    .buttonStyle(.bordered).accessibilityIdentifier("chess.claimDraw")
            } else if choosingChessDrawMove {
                Text(model.t("expanded.chess.claimMoveHelp"))
                    .font(.caption).multilineTextAlignment(.center)
                Button(model.t("common.cancel")) { choosingChessDrawMove = false; selected = nil }
                    .buttonStyle(.bordered).accessibilityIdentifier("chess.claimDraw.cancel")
            } else if !board.drawClaimMoves.isEmpty {
                Button(model.t("expanded.chess.claimWithMove")) { choosingChessDrawMove = true; selected = nil }
                    .buttonStyle(.bordered).accessibilityIdentifier("chess.claimDraw.withMove")
            }
        }
    }

    private func claimChessDraw(after move: ChessMove? = nil) {
        guard humanTurn else { return }
        if model.editExpanded(game, { state in
            guard case .chess(var board) = state, board.claimDraw(after: move) else { return false }
            state = .chess(board)
            return true
        }) {
            selected = nil
            choosingChessDrawMove = false
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
    private var checkNoticeMove: Int? {
        guard active, motion == nil, save?.outcome == nil, checked else { return nil }
        return save?.state.moves
    }
    private func showCheckNotice() async {
        guard let move = checkNoticeMove else { shownCheckMove = nil; return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { shownCheckMove = move }
        do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
        guard !Task.isCancelled, shownCheckMove == move else { return }
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.18)) { shownCheckMove = nil }
    }
    private var board: some View {
        let cells = save?.state.strategyCells ?? []
        // A checkmate/drop search belongs to the board render, not to every
        // cell. Shogi hands can produce hundreds of legal actions; repeating
        // the same result search 81 times stalls input and the session clock.
        let isActive = active, canPlay = humanTurn
        let legalTargets = canPlay ? targets : []
        let showTargets = choosingChessDrawMove || (model.gameSettings(for:game).expanded?.showLegalMoves ?? true)
        let reversed = save?.mode == .singlePlayer && save?.humanPlayer == .second
        let size = CGSize(width: columns * unit, height: rows * unit)
        let scale = min(1, boardWidth / size.width)
        return ZoomBoard(size: size, inputEnabled:isActive,accessibilityHidden:!isActive,
                         identifier:game.rawValue+".zoomBoard", fitWidth: true) {
            ZStack {
                StrategyBoardGrid(game: game, rows: rows, columns: columns, unit: CGFloat(unit))
                VStack(spacing:0) {
                    ForEach(0..<rows,id:\.self) { row in
                        HStack(spacing:0) {
                            ForEach(0..<columns,id:\.self) { column in
                                let display = row*columns+column
                                let index = reversed ? cells.count-1-display : display
                                if cells.indices.contains(index) { strategyCell(index,cells:cells,legalTargets:legalTargets,canPlay:canPlay,isActive:isActive,showTargets:showTargets) }
                            }
                        }
                    }
                }
                if let motion {
                    movingPieces(motion, reversed: reversed)
                }
            }.frame(width: size.width, height: size.height)
                .environmentObject(model)
        }
        .frame(height: size.height * scale + 12)
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear { boardWidth = max(1, geometry.size.width) }
                    .onChange(of: geometry.size.width) { _, width in boardWidth = max(1, width) }
            }.allowsHitTesting(false)
        }
        .background(GameBoardSurface(game:game,cornerRadius:18))
        .overlay {
            if let shownCheckMove, shownCheckMove == checkNoticeMove {
                StrategyCheckSeal(title: model.t("expanded.check"))
                    .transition(reduceMotion ? .identity : .scale(scale: 0.92).combined(with: .opacity))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    private func settleMotion(_ id: UUID) {
        if motion?.id == id { motion = nil }
    }

    private func movingPieces(_ motion: StrategyMotion, reversed: Bool) -> some View {
        StrategyPieceSlide(settled: { settleMotion(motion.id) }) { landed in
            ForEach(motion.tracks) { track in
                let index = landed ? track.to : track.from
                let display = reversed ? rows * columns - 1 - index : index
                strategyPiece(track.piece).padding(3)
                    .frame(width: CGFloat(unit), height: CGFloat(unit))
                    .position(x: (CGFloat(display % columns) + 0.5) * CGFloat(unit),
                              y: (CGFloat(display / columns) + 0.5) * CGFloat(unit))
            }
        }
        .id(motion.id).allowsHitTesting(false).accessibilityHidden(true)
    }

    private func strategyCell(_ index: Int,cells: [Int],legalTargets: Set<Int>,canPlay: Bool,isActive: Bool,showTargets: Bool) -> some View {
        let hidden: Bool = { if case .banqi(let board) = save?.state { return !board.revealed[index] }; return false }()
        let piece = hidden ? 0 : cells[index]
        let placement = game == .gomoku || game == .reversi
        let available = canPlay && (placement ? legalTargets.contains(index) : cells[index] != 0 || legalTargets.contains(index) || hidden)
        let coveredBySlide = motion?.tracks.contains(where: { $0.to == index }) == true
        return Button { choose(index) } label: {
            ZStack {
                Color.clear
                if hidden { RoundedRectangle(cornerRadius:9).fill(GameMaterial.teal).overlay { Image(systemName:"sparkle").foregroundStyle(GameMaterial.gold) }.padding(4) }
                else if piece != 0, !coveredBySlide { strategyPiece(piece).padding(game == .gomoku ? 4 : 3) }
                if showTargets, legalTargets.contains(index), !hidden {
                    Circle().fill(Color.blue).frame(width: 8, height: 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: piece == 0 ? .center : .topTrailing)
                        .padding(3).allowsHitTesting(false)
                }
                if selected==index { Circle().strokeBorder(Color.blue,lineWidth:2).padding(2).allowsHitTesting(false) }
            }.frame(width:CGFloat(unit),height:CGFloat(unit)).contentShape(Rectangle())
        }.buttonStyle(QuietPressStyle()).disabled(!available).accessibilityHidden(!isActive)
            .accessibilityLabel(model.t("expanded.cell",index/columns+1,index%columns+1)+", "+(hidden ? model.t("expanded.banqi.hidden") : piece==0 ? model.t("expanded.empty") : pieceName(piece)))
            .accessibilityValue(selected==index ? model.t("expanded.selected") : "")
            .accessibilityIdentifier(game.rawValue+".cell.\(index)")
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
        if choosingChessDrawMove, case .chess(let move) = action {
            claimChessDraw(after: move)
            return
        }
        commitMove(action)
    }
    private func commitMove(_ action: ExpandedStrategyAction) {
        guard motion == nil, let save else { return }
        let slide = reduceMotion ? nil : StrategyMotion(action: action, cells: save.state.strategyCells)
        motion = slide
        guard model.editExpanded(game, resultReady: slide == nil, { $0.playStrategy(action) }) else {
            motion = nil
            return
        }
        selected = nil; drop = nil; promotions = []
    }
    @MainActor private func computerMove() async {
        guard active, motion == nil, let snapshot = save, snapshot.isComputerTurn else { return }
        let key = taskKey, clock = ContinuousClock(), earliest = ContinuousClock.now.advanced(by:.milliseconds(450))
        let worker = Task.detached(priority:.userInitiated) { snapshot.state.recommendedStrategyAction(difficulty:snapshot.difficulty,seed:snapshot.seed) }
        let action = await withTaskCancellationHandler(operation:{await worker.value},onCancel:{worker.cancel()})
        do { try await clock.sleep(until:earliest) } catch { return }
        guard !Task.isCancelled, taskKey==key, active, let action, save?.state==snapshot.state else { return }
        commitMove(action)
    }
}

private struct StrategyBoardGrid: View {
    let game: GameID
    let rows: Int
    let columns: Int
    let unit: CGFloat

    var body: some View {
        let intersections = game == .gomoku || game == .xiangqi
        ZStack {
            Color(red: 0.79, green: 0.72, blue: 0.57)
            Path { path in
                func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) {
                    path.move(to: CGPoint(x: x0 * unit, y: y0 * unit))
                    path.addLine(to: CGPoint(x: x1 * unit, y: y1 * unit))
                }
                let inset: CGFloat = intersections ? 0.5 : 0
                let endX = CGFloat(columns) - inset
                let endY = CGFloat(rows) - inset
                for row in 0..<(rows + (intersections ? 0 : 1)) {
                    let y = CGFloat(row) + inset
                    line(inset, y, endX, y)
                }
                for column in 0..<(columns + (intersections ? 0 : 1)) {
                    let x = CGFloat(column) + inset
                    if game == .xiangqi && column > 0 && column < columns - 1 {
                        line(x, inset, x, 4.5)
                        line(x, 5.5, x, endY)
                    } else {
                        line(x, inset, x, endY)
                    }
                }
                if game == .xiangqi {
                    for top: CGFloat in [0.5, 7.5] {
                        line(3.5, top, 5.5, top + 2)
                        line(5.5, top, 3.5, top + 2)
                    }
                }
            }.stroke(GameMaterial.ink.opacity(0.44), lineWidth: 0.8)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct StrategyPieceSlide<Content: View>: View {
    let settled: () -> Void
    let content: (Bool) -> Content
    @State private var landed = false

    var body: some View {
        content(landed).onAppear {
            withAnimation(.easeInOut(duration: 0.23), completionCriteria: .removed) {
                landed = true
            } completion: {
                settled()
            }
        }
    }
}

private struct StrategyCheckSeal: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 46, weight: .black, design: .serif))
            .tracking(3).foregroundStyle(GameMaterial.ivory)
            .lineLimit(1).minimumScaleFactor(0.65)
            .padding(.horizontal, 28).padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(red: 0.62, green: 0.12, blue: 0.14))
                    .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(GameMaterial.gold, lineWidth: 2) }
                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(GameMaterial.ivory.opacity(0.65), lineWidth: 1).padding(5) }
            }
            .rotationEffect(.degrees(-6))
            .shadow(color: .black.opacity(0.32), radius: 7, y: 4)
            .padding(.horizontal, 14)
    }
}
