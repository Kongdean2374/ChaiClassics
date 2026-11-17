import SwiftUI
import ChaiCore

/// Display-rate simulation stays local to the playing screen. Disk writes are
/// coalesced, flushed on pause/navigation, and immediate for input and game over.
struct ExpandedArcadeView: View {
    let game: GameID
    @EnvironmentObject private var model: AppModel
    @StateObject private var clock = AnimationFrameClock()
    @State private var local: ExpandedGameSave?
    @State private var accumulated = 0.0
    @State private var saveInterval = 0.0
    @State private var countdown: Int?
    private var active: Bool { model.sessionIsPlaying(game) }
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing:12) {
                header
                let maxHeight = max(180,proxy.size.height-180)
                let width = game == .fallingBlocks ? min(300,maxHeight/2) : min(520,proxy.size.width-24,maxHeight)
                field.overlay {
                    if let countdown {
                        Text(String(countdown)).font(.system(size:56,weight:.bold,design:.rounded))
                            .foregroundStyle(GameMaterial.ivory).padding(20).background(.ultraThinMaterial,in:Circle())
                            .accessibilityIdentifier(game.rawValue+".countdown").allowsHitTesting(false)
                    }
                }.frame(width:width,height:game == .fallingBlocks ? width*2 : width)
                    .frame(maxWidth:.infinity)
                controls
            }.padding(12).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
        }
        .onAppear { local = model.expandedGames[game] }
        .onChange(of:active) { _,value in
            accumulated = 0; saveInterval = 0
            if value { if local==nil { local = model.expandedGames[game] } }
            else { persist(); clock.stop() }
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
        .onDisappear { persist(); clock.stop() }
    }
    private var header: some View {
        HStack(spacing:10) {
            GameArtwork(game:game,size:36)
            Text(model.gameTitle(game)).font(.headline)
            Spacer()
            Text(scoreText).font(.subheadline.weight(.semibold)).monospacedDigit()
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
    private var field: some View {
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
            .overlay {
                if game == .brickBreaker {
                    GeometryReader { geometry in
                        Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
                            update(persistImmediately:false) { state in
                                guard case .brickBreaker(var b) = state, b.movePaddle(to:Double(value.location.x/geometry.size.width)) else { return false }
                                state = .brickBreaker(b); return true
                            }
                        })
                    }.accessibilityHidden(true)
                }
            }
    }
    @ViewBuilder private var controls: some View {
        switch local?.state {
        case .snake:
            HStack(spacing:12) {
                ForEach(ArcadeDirection.allCases,id:\.self) { direction in
                    control("expanded.direction.\(direction.rawValue)",symbol:["arrow.up","arrow.right","arrow.down","arrow.left"][direction.rawValue],id:"direction.\(direction.rawValue)") {
                        update { state in guard case .snake(var b) = state, b.turn(direction) else { return false }; state = .snake(b); return true }
                    }
                }
            }
        case .fallingBlocks(let b):
            VStack(spacing:8) {
                HStack {
                    Text(model.t("expanded.blocks.next",b.next.first.map { $0+1 } ?? 0)).font(.caption)
                    Text(model.t("expanded.blocks.held",b.held.map { $0+1 } ?? 0)).font(.caption)
                }
                HStack(spacing:8) {
                    control("expanded.left",symbol:"arrow.left",id:"left") { block{$0.move(-1)} }
                    control("expanded.rotateBack",symbol:"rotate.left",id:"rotateBack") { block{$0.rotate(clockwise:false)} }
                    control("expanded.rotate",symbol:"rotate.right",id:"rotate") { block{$0.rotate()} }
                    control("expanded.right",symbol:"arrow.right",id:"right") { block{$0.move(1)} }
                }
                HStack(spacing:8) {
                    control("expanded.blocks.hold",symbol:"square.on.square",id:"hold") { block{$0.hold()} }
                    control("expanded.blocks.soft",symbol:"arrow.down",id:"softDrop") { block{$0.step(soft:true)} }
                    control("expanded.blocks.hard",symbol:"arrow.down.to.line",id:"hardDrop") { block{$0.hardDrop()} }
                }
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
    private func control(_ key: String,symbol: String,id: String,action:@escaping ()->Void) -> some View {
        Button(action:action) { Image(systemName:symbol).font(.title3).frame(minWidth:46,minHeight:44) }
            .buttonStyle(.bordered).disabled(!active || countdown != nil || local?.outcome != nil)
            .accessibilityLabel(model.t(key)).accessibilityIdentifier(game.rawValue+"."+id)
    }
    private func block(_ change: (inout FallingBlocksBoard)->Bool) {
        update { state in guard case .fallingBlocks(var b) = state, change(&b) else { return false }; state = .fallingBlocks(b); return true }
    }
    private func paddle(_ delta: Double) {
        update { state in guard case .brickBreaker(var b) = state, b.movePaddle(to:b.paddle+delta) else { return false }; state = .brickBreaker(b); return true }
    }
    private func update(persistImmediately: Bool = true,_ change:(inout ExpandedGameState)->Bool) {
        guard active, var value = local, value.outcome==nil, change(&value.state) else { return }
        local = value; if persistImmediately { persist() }
    }
    private func advance(_ delta: TimeInterval) {
        guard active, countdown==nil, var value = local, value.outcome==nil, delta>0, delta<=0.1 else { return }
        accumulated += delta; saveInterval += delta
        switch value.state {
        case .snake(var board):
            let interval = value.difficulty == .easy ? 0.18 : value.difficulty == .normal ? 0.13 : 0.09
            while accumulated>=interval, !board.hasLost, !board.isComplete { _ = board.step(); accumulated -= interval }
            value.state = .snake(board)
        case .fallingBlocks(var board):
            let base = value.difficulty == .easy ? 0.9 : value.difficulty == .normal ? 0.65 : 0.45
            let interval = max(0.06,base/pow(1.12,Double(board.level-1)))
            while accumulated>=interval, !board.hasLost { _ = board.step(); accumulated -= interval }; value.state = .fallingBlocks(board)
        case .brickBreaker(var board): _ = board.advance(delta); value.state = .brickBreaker(board); accumulated = 0
        default:return
        }
        local = value
        if saveInterval>=0.25 || value.outcome != nil { persist(); saveInterval = 0 }
    }
    private func persist() {
        guard var value = local else { return }
        value.elapsedSeconds = max(value.elapsedSeconds,model.sessionData.sessions[game]?.elapsedSeconds ?? 0)
        if model.expandedGames[game] != value { _ = model.saveExpanded(value) }
    }
    private func drawSnake(_ board: SnakeBoard,context: inout GraphicsContext,size: CGSize) {
        let unit = size.width/CGFloat(board.size)
        if let food = board.food {
            let rect = CGRect(x:CGFloat(food%board.size)*unit+unit*0.15,y:CGFloat(food/board.size)*unit+unit*0.15,width:unit*0.7,height:unit*0.7)
            context.fill(Path(ellipseIn:rect),with:.color(GameMaterial.coral))
        }
        for (i,cell) in board.body.enumerated() {
            let rect = CGRect(x:CGFloat(cell%board.size)*unit+1,y:CGFloat(cell/board.size)*unit+1,width:unit-2,height:unit-2)
            context.fill(Path(roundedRect:rect,cornerRadius:unit*0.25),with:.color(i==0 ? GameMaterial.gold : Color(red:0.32,green:0.76,blue:0.57)))
        }
    }
    private func drawBlocks(_ board: FallingBlocksBoard,context: inout GraphicsContext,size: CGSize) {
        let unit = size.width/10
        let colors: [Color] = [.cyan,.yellow,.purple,.green,.red,.blue,.orange]
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
