import SwiftUI
import ChaiCore

/// Display-rate simulation stays local to the playing screen. Disk writes are
/// coalesced, flushed on pause/navigation, and immediate for input and game over.
@MainActor struct ExpandedArcadeView: View {
    let game: GameID
    @EnvironmentObject private var model: AppModel
    // Only the frame subscriber needs the clock's ticks. The view observes
    // the game state, so idle display frames don't invalidate the whole view.
    @State private var clock = AnimationFrameClock()
    @State private var local: ExpandedGameSave?
    @State private var savedRevision: ExpandedGameSave?
    @State private var sessionID: UUID?
    @State private var accumulated = 0.0
    @State private var saveInterval = 0.0
    @State private var countdown: Int?
    @State private var heldInput = ArcadeInputRepeat()
    @State private var blockDrag: FallingBlockDrag?
    @GestureState private var boardDragging = false
    private var active: Bool { model.sessionIsPlaying(game) }
    private var canControl: Bool { active && countdown == nil && local?.outcome == nil }
    private var ownsSavedProgress: Bool {
        ArcadeSaveOwnership.matches(expectedSessionID:sessionID,currentSessionID:model.sessionData.sessions[game]?.id,
                                    expected:savedRevision,current:model.expandedGames[game])
    }
    var body: some View {
        VStack(spacing:12) {
            header
            // Reserve the controls' actual intrinsic height before sizing the
            // field. A fixed 180pt estimate clipped Hard Drop on an iPhone.
            GeometryReader { proxy in
                let width = game == .fallingBlocks ? min(300,max(1,proxy.size.width-84),proxy.size.height/2) : min(520,proxy.size.width,proxy.size.height)
                HStack(alignment:.top,spacing:10) {
                field.overlay {
                    if let countdown {
                        Text(String(countdown)).font(.system(size:56,weight:.bold,design:.rounded))
                            .foregroundStyle(GameMaterial.ivory).padding(20).background(.ultraThinMaterial,in:Circle())
                            .accessibilityIdentifier(game.rawValue+".countdown").allowsHitTesting(false)
                    }
                }.frame(width:width,height:game == .fallingBlocks ? width*2 : width)
                if case .fallingBlocks(let board) = local?.state {
                    ViewThatFits(in:.vertical) {
                        blockPreviews(board,count:3)
                        blockPreviews(board,count:1)
                    }.frame(width:74)
                }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
            controls.fixedSize(horizontal:false,vertical:true)
        }.padding(12).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
        .onAppear { loadCurrentRound() }
        .onChange(of:active) { _,value in
            accumulated = 0; saveInterval = 0
            if value {
                if local == nil || !ownsSavedProgress {
                    loadCurrentRound()
                }
            }
            else { heldInput.cancel(); blockDrag = nil; persist(); clock.stop() }
        }
        .task(id:active) {
            guard active else { return }
            if game != .brickBreaker {
                for value in (1...3).reversed() {
                    countdown = value
                    do { try await Task.sleep(for:.seconds(1)) } catch { return }
                    guard !Task.isCancelled, active else { return }
                }
            }
            countdown = nil; clock.start()
        }
        .onReceive(clock.$frame) { frame in advance(frame.delta) }
        .onChange(of:boardDragging) { _,value in if !value { blockDrag = nil } }
        .onDisappear { heldInput.cancel(); blockDrag = nil; persist(); clock.stop() }
    }
    private var header: some View {
        HStack(spacing:10) {
            GameArtwork(game:game,size:36)
            Text(model.gameTitle(game)).font(.headline)
            Spacer()
            Text(scoreText).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                .padding(.horizontal,10).padding(.vertical,7).background(.thinMaterial,in:Capsule())
                .accessibilityIdentifier(game.rawValue+".score")
        }
    }
    private var scoreText: String {
        switch local?.state {
        case .snake(let b):return model.t("expanded.score",b.score)
        case .fallingBlocks(let b):return model.t("expanded.blocks.score",b.score,b.lines)
        case .brickBreaker(let b):return model.t("expanded.bricks.score",b.score,b.lives)
        default:return ""
        }
    }
    private var paintedField: some View {
        Canvas { context,size in
            switch local?.state {
            case .snake(let board): drawSnake(board,context:&context,size:size)
            case .fallingBlocks(let board): drawBlocks(board,context:&context,size:size)
            case .brickBreaker(let board): drawBricks(board,context:&context,size:size)
            default:break
            }
        }.background(GameBoardSurface(game:game,cornerRadius:16)).clipShape(RoundedRectangle(cornerRadius:16))
            .contentShape(Rectangle()).accessibilityLabel(model.gameTitle(game)+", "+scoreText)
            .accessibilityIdentifier(game.rawValue+".board")
    }
    @ViewBuilder private var field: some View {
        if game == .snake {
            paintedField.modifier(SnakeSwipeControls(
                enabled: canControl, hint: model.t("expanded.snake.help"),
                label: { model.t("expanded.direction.\($0.rawValue)") }, turn: turnSnake
            ))
        } else if game == .fallingBlocks {
            paintedField.overlay {
                GeometryReader { proxy in
                    Color.clear.contentShape(Rectangle()).gesture(
                        DragGesture(minimumDistance:12).updating($boardDragging) { _,value,_ in value = true }.onChanged { value in
                            guard canControl,case .fallingBlocks(let board) = local?.state else { return }
                            heldInput.cancel()
                            if blockDrag == nil { blockDrag = FallingBlockDrag(piece:board.piecesPlaced) }
                            let moves = blockDrag?.change(x:Double(value.translation.width),y:Double(value.translation.height),
                                                          unit:Double(max(1,proxy.size.width/10)),currentPiece:board.piecesPlaced)
                            if let moves { applyDrag(moves.dx,moves.down,piece:board.piecesPlaced) }
                        }.onEnded { value in
                            defer { blockDrag = nil; persist() }
                            guard canControl,case .fallingBlocks(let board) = local?.state else { return }
                            if blockDrag?.hardDrop(y:Double(value.translation.height),predictedY:Double(value.predictedEndTranslation.height),
                                                   unit:Double(max(1,proxy.size.width/10)),currentPiece:board.piecesPlaced) == true {
                                block { $0.hardDrop() }; accumulated = 0
                            }
                        })
                        .simultaneousGesture(TapGesture().onEnded { if canControl { block { $0.rotate() } } })
                }.accessibilityHidden(true)
            }
        } else if game == .brickBreaker {
            paintedField.overlay {
                    GeometryReader { geometry in
                        Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
                            update(persistImmediately:false) { state in
                                guard case .brickBreaker(var b) = state, b.movePaddle(to:Double(value.location.x/geometry.size.width)) else { return false }
                                state = .brickBreaker(b); return true
                            }
                        })
                    }.accessibilityHidden(true)
            }
        } else { paintedField }
    }
    @ViewBuilder private var controls: some View {
        switch local?.state {
        case .snake:
            Text(model.t("expanded.snake.help")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        case .fallingBlocks(let board):
            VStack(spacing:8) {
                HStack(spacing:8) {
                    repeatControl(.left,key:"expanded.left",symbol:"arrow.left",id:"left")
                    control("expanded.rotateBack",symbol:"rotate.left",id:"rotateBack") { block{$0.rotate(clockwise:false)} }
                    control("expanded.rotate",symbol:"rotate.right",id:"rotate") { block{$0.rotate()} }
                    repeatControl(.right,key:"expanded.right",symbol:"arrow.right",id:"right")
                }
                HStack(spacing:8) {
                    control("expanded.blocks.hold",symbol:"square.on.square",id:"hold",available:!board.holdUsed) { heldInput.cancel(); block{$0.hold()}; blockDrag = nil; accumulated = 0 }
                    repeatControl(.softDrop,key:"expanded.blocks.soft",symbol:"arrow.down",id:"softDrop")
                    control("expanded.blocks.hard",symbol:"arrow.down.to.line",id:"hardDrop") { heldInput.cancel(); block{$0.hardDrop()}; blockDrag = nil; accumulated = 0 }
                }
                Text(model.t("expanded.blocks.help")).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        case .brickBreaker(let board):
            VStack(spacing:8) {
                HStack(spacing:12) {
                    control("expanded.left",symbol:"arrow.left",id:"left") { paddle(-0.08) }
                    control("expanded.launch",symbol:"play.fill",id:"launch") { update { state in guard case .brickBreaker(var b) = state, b.launch() else { return false }; state = .brickBreaker(b); return true } }
                    control("expanded.right",symbol:"arrow.right",id:"right") { paddle(0.08) }
                }
                Text(model.t(board.launched ? "expanded.bricks.drag" : "expanded.bricks.launch")).font(.caption).foregroundStyle(.secondary)
            }
        default:EmptyView()
        }
    }
    private func control(_ key: String,symbol: String,id: String,available:Bool = true,action:@escaping ()->Void) -> some View {
        Button(action:action) { Image(systemName:symbol).font(.title3).frame(maxWidth:.infinity,minHeight:48) }
            .buttonStyle(.bordered).disabled(!canControl || !available)
            .accessibilityLabel(model.t(key)).accessibilityIdentifier(game.rawValue+"."+id)
    }
    private func block(_ change: (inout FallingBlocksBoard)->Bool) {
        update { state in guard case .fallingBlocks(var b) = state, change(&b) else { return false }; state = .fallingBlocks(b); return true }
    }
    private func turnSnake(_ direction: ArcadeDirection) {
        update { state in
            guard case .snake(var board) = state, board.turn(direction) else { return false }
            state = .snake(board)
            return true
        }
    }
    private func repeatControl(_ action: ArcadeHeldAction,key:String,symbol:String,id:String) -> some View {
        ArcadeRepeatButton(title:model.t(key),symbol:symbol,identifier:game.rawValue+"."+id,enabled:canControl,
                           begin:{ if heldInput.press(action) { applyHeld(action,immediate:true) } },
                           end:{heldInput.release(action)},accessibleTap:{applyHeld(action,immediate:true)})
    }
    private func applyHeld(_ action: ArcadeHeldAction,immediate:Bool) {
        update(persistImmediately:immediate) { state in
            guard case .fallingBlocks(var board) = state else { return false }
            let changed: Bool
            switch action { case .left:changed = board.move(-1);case .right:changed = board.move(1);case .softDrop:changed = board.step(soft:true) }
            guard changed else { return false };state = .fallingBlocks(board);return true
        }
    }
    private func applyDrag(_ dx:Int,_ down:Int,piece:Int) {
        update(persistImmediately:false) { state in
            guard case .fallingBlocks(var board) = state,board.piecesPlaced == piece else { return false }
            var changed = false
            for _ in 0..<abs(dx) { if board.move(dx<0 ? -1 : 1) { changed = true } }
            for _ in 0..<down where board.piecesPlaced == piece { if board.step(soft:true) { changed = true } }
            guard changed else { return false };state = .fallingBlocks(board);return true
        }
    }
    private func blockPreviews(_ board:FallingBlocksBoard,count:Int) -> some View {
        VStack(spacing:7) {
            FallingPiecePreview(kind:board.held,title:model.t("expanded.blocks.heldTitle"),pieceName:pieceName(board.held))
                .opacity(board.holdUsed ? 0.55 : 1).accessibilityIdentifier("fallingblocks.heldPreview")
            ForEach(Array(board.next.prefix(count).enumerated()),id:\.offset) { index,kind in
                FallingPiecePreview(kind:kind,title:model.t("expanded.blocks.nextTitle",index+1),pieceName:pieceName(kind))
                    .accessibilityIdentifier("fallingblocks.nextPreview.\(index)")
            }
            Text(model.t("expanded.blocks.level",board.level)).font(.caption2).monospacedDigit()
        }
    }
    private func pieceName(_ kind:Int?) -> String { kind.map{model.t("expanded.blocks.piece.\($0)")} ?? model.t("expanded.empty") }
    private func paddle(_ delta: Double) {
        update { state in guard case .brickBreaker(var b) = state, b.movePaddle(to:b.paddle+delta) else { return false }; state = .brickBreaker(b); return true }
    }
    private func update(persistImmediately: Bool = true,_ change:(inout ExpandedGameState)->Bool) {
        guard canControl, var value = local, value.outcome==nil, change(&value.state) else { return }
        local = value
        if persistImmediately { model.feedback(for:game) }
        if persistImmediately || value.outcome != nil { persist() }
    }
    private func advance(_ delta: TimeInterval) {
        if canControl,let action = heldInput.advance(delta) { applyHeld(action,immediate:false) }
        guard active, countdown==nil, var value = local, value.outcome==nil, delta>0, delta<=0.1 else { return }
        accumulated += delta; saveInterval += delta
        switch value.state {
        case .snake(var board):
            let interval = board.stepInterval(difficulty: value.difficulty)
            while accumulated>=interval, !board.hasLost, !board.isComplete { _ = board.step(); accumulated -= interval }
            value.state = .snake(board)
        case .fallingBlocks(var board):
            let base = value.difficulty == .easy ? 0.9 : value.difficulty == .normal ? 0.65 : 0.45
            let interval = max(0.06,base/pow(1.12,Double(board.level-1)))
            while accumulated>=interval, !board.hasLost { _ = board.step(); accumulated -= interval }; value.state = .fallingBlocks(board)
        case .brickBreaker(var board): _ = board.advance(delta); value.state = .brickBreaker(board); accumulated = 0
        default:return
        }
        if value != local { local = value }
        if saveInterval>=0.25 || value.outcome != nil { persist(); saveInterval = 0 }
    }
    private func persist() {
        guard var value = local else { return }
        // A dismissed view must not resurrect a cleared round or overwrite an
        // imported/restarted save after its local display state became stale.
        guard ownsSavedProgress else {
            heldInput.cancel(); blockDrag = nil; clock.stop(); return
        }
        value.elapsedSeconds = max(value.elapsedSeconds,model.sessionData.sessions[game]?.elapsedSeconds ?? 0)
        if model.expandedGames[game] != value, !model.saveExpanded(value) {
            // Roll back to the durable state instead of stranding an unsaved
            // terminal board that can no longer retry its persistence.
            local = model.expandedGames[game]; heldInput.cancel(); blockDrag = nil
            clock.stop(); model.pauseSession(game)
        }
        savedRevision = model.expandedGames[game]
    }
    private func loadCurrentRound() {
        local = model.expandedGames[game]; savedRevision = local
        sessionID = model.sessionData.sessions[game]?.id
        heldInput.cancel(); blockDrag = nil; accumulated = 0; saveInterval = 0
    }
    private func drawSnake(_ board: SnakeBoard,context: inout GraphicsContext,size: CGSize) {
        let unit = size.width/CGFloat(board.size)
        var grid = Path()
        for index in 1..<board.size {
            let position = CGFloat(index)*unit
            grid.move(to:CGPoint(x:position,y:0));grid.addLine(to:CGPoint(x:position,y:size.height))
            grid.move(to:CGPoint(x:0,y:position));grid.addLine(to:CGPoint(x:size.width,y:position))
        }
        context.stroke(grid,with:.color(GameMaterial.ivory.opacity(0.07)),lineWidth:0.5)
        if let food = board.food {
            let rect = CGRect(x:CGFloat(food%board.size)*unit+unit*0.15,y:CGFloat(food/board.size)*unit+unit*0.15,width:unit*0.7,height:unit*0.7)
            context.fill(Path(ellipseIn:rect),with:.color(GameMaterial.coral))
        }
        for (i,cell) in board.body.enumerated() {
            let rect = CGRect(x:CGFloat(cell%board.size)*unit+1,y:CGFloat(cell/board.size)*unit+1,width:unit-2,height:unit-2)
            context.fill(Path(roundedRect:rect,cornerRadius:unit*0.25),with:.color(i==0 ? GameMaterial.gold : Color(red:0.32,green:0.76,blue:0.57)))
            if i == 0 {
                let direction = board.direction
                for side in [CGFloat(-1),CGFloat(1)] {
                    let center = CGPoint(x:rect.midX+CGFloat(direction.dx)*unit*0.2-CGFloat(direction.dy)*unit*0.17*side,
                                         y:rect.midY+CGFloat(direction.dy)*unit*0.2+CGFloat(direction.dx)*unit*0.17*side)
                    context.fill(Path(ellipseIn:CGRect(x:center.x-unit*0.055,y:center.y-unit*0.055,width:unit*0.11,height:unit*0.11)),with:.color(GameMaterial.ink))
                }
            }
        }
    }
    private func drawBlocks(_ board: FallingBlocksBoard,context: inout GraphicsContext,size: CGSize) {
        let unit = size.width/10
        let colors = ArcadePalette.blocks
        var grid = Path()
        for x in 1..<10 { grid.move(to:CGPoint(x:CGFloat(x)*unit,y:0));grid.addLine(to:CGPoint(x:CGFloat(x)*unit,y:size.height)) }
        for y in 1..<20 { grid.move(to:CGPoint(x:0,y:CGFloat(y)*unit));grid.addLine(to:CGPoint(x:size.width,y:CGFloat(y)*unit)) }
        context.stroke(grid,with:.color(GameMaterial.ivory.opacity(0.08)),lineWidth:0.5)
        func tile(_ x: Int,_ y: Int,_ kind: Int,_ ghost: Bool) {
            guard y>=0 else { return }
            let rect = CGRect(x:CGFloat(x)*unit+1,y:CGFloat(y)*unit+1,width:unit-2,height:unit-2), path = Path(roundedRect:rect,cornerRadius:3)
            context.fill(path,with:.color(colors[kind%7].opacity(ghost ? 0.18 : 0.9)))
            context.stroke(path,with:.color(ghost ? .white.opacity(0.5) : GameMaterial.ivory.opacity(0.6)),lineWidth:0.7)
        }
        for i in board.cells.indices where board.cells[i]>0 { tile(i%10,i/10,board.cells[i]-1,false) }
        if model.gameSettings(for:game).expanded?.showGhost ?? true {
            for point in FallingBlocksBoard.shape(board.active,rotation:board.rotation) { tile(point.x+board.x,point.y+board.ghostY,board.active,true) }
        }
        for point in board.activeCells { tile(point.x,point.y,board.active,false) }
    }
    private func drawBricks(_ board: BrickBreakerBoard,context: inout GraphicsContext,size: CGSize) {
        for i in board.bricks.indices where board.bricks[i]>0 {
            let rect = CGRect(x:(0.02+Double(i%8)*0.12)*size.width,y:(0.09+Double(i/8)*0.055)*size.height,width:0.112*size.width,height:0.042*size.height)
            let path = Path(roundedRect:rect,cornerRadius:3)
            context.fill(path,with:.color([GameMaterial.coral,GameMaterial.gold,Color.teal][min(board.bricks[i]-1,2)])); context.stroke(path,with:.color(GameMaterial.ivory.opacity(0.7)),lineWidth:0.7)
        }
        let paddle = CGRect(x:(board.paddle-0.12)*size.width,y:0.9*size.height,width:0.24*size.width,height:0.02*size.height)
        context.fill(Path(roundedRect:paddle,cornerRadius:5),with:.color(GameMaterial.gold))
        let ball = CGRect(x:(board.ballX-0.012)*size.width,y:(board.ballY-0.012)*size.height,width:0.024*size.width,height:0.024*size.height)
        context.fill(Path(ellipseIn:ball),with:.color(GameMaterial.ivory))
    }
}
