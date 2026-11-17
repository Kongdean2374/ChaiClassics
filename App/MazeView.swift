import SwiftUI
import UIKit
import ChaiCore

struct MazeMenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var difficulty = MazeBoard.Difficulty.normal
    @State private var play = false
    @State private var confirm = false

    private func start() {
        if model.saveMaze(MazeBoard(difficulty: difficulty)) {
            model.startNewSession(.maze)
            play = true
        }
    }

    private func loadDefaultDifficulty() {
        difficulty = MazeBoard.Difficulty(rawValue: model.gameSettings(for: .maze).mazeDifficulty) ?? .normal
    }

    var body: some View {
        Form {
            Section {
                GameIntroHeader(game: .maze, title: model.gameTitle(.maze), subtitle: model.t("maze.menu.intro"))
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            if let board = model.maze {
                Section(model.t("menu.lastGame")) {
                    ContinueGameRow(game: .maze, action: {
                        model.beginContinuing(.maze)
                        play = true
                    }) {
                        ContinueCard(title: model.t(board.isComplete ? "menu.viewLast" : "menu.continue"),
                                     detail: model.t("maze.save.detail", board.size, board.size, board.moves, board.elapsedSeconds))
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                }
            }
            Section(model.t("menu.newGame")) {
                Picker(model.t("maze.difficulty"), selection: $difficulty) {
                    ForEach(MazeBoard.Difficulty.allCases, id: \.self) { level in
                        Text(model.t("maze.difficulty.option", model.t("difficulty." + level.rawValue), level.size, level.size)).tag(level)
                    }
                }.accessibilityIdentifier("maze.difficulty")
                Text(model.t("maze.difficulty.detail." + difficulty.rawValue))
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { confirm = true } label: {
                    Label(model.t("menu.start"), systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                        .foregroundStyle(.primary)
                        .background(GamePalette.tint(.maze).opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                        .contentShape(Rectangle())
                }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("maze.start")
                    .disabled(model.blocked.contains(.maze))
                    .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
            }
        }.scrollContentBackground(.hidden).background(GameCanvas()).tint(GamePalette.tint(.maze))
            .localizedNavigation().navigationTitle(model.gameTitle(.maze)).navigationBarTitleDisplayMode(.inline)
            .gameMenuSettings(.maze)
            .navigationDestination(isPresented: $play) { MazePlayView() }
            .newGameConfirmation(.maze, isPresented: $confirm) { start() }
            .loadGameDefaultsOnce { loadDefaultDifficulty() }
            .onChange(of: model.gameSettings(for: .maze).mazeDifficulty) { _, _ in loadDefaultDifficulty() }
    }
}

struct MazePlayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var blockedDirection: MazeBoard.Direction?
    @State private var motionReset = 0
    private var active: Bool {
        scenePhase == .active && model.sessionIsPlaying(.maze) &&
            model.maze?.isPaused == false && model.maze?.isComplete == false
    }

    private func positionText(_ board: MazeBoard) -> String {
        model.t("maze.position", board.position.row + 1, board.position.column + 1, board.size, board.size)
    }

    private func move(_ direction: MazeBoard.Direction) {
        guard active, var next = model.maze else { return }
        motionReset &+= 1
        guard next.move(direction) else { reportBlocked(direction); return }
        _ = saveArrival(next)
    }

    private func reportBlocked(_ direction: MazeBoard.Direction) {
        guard blockedDirection != direction else { return }
        blockedDirection = direction
        UIAccessibility.post(notification: .announcement,
                             argument: model.t("maze.blocked", model.t("maze.direction." + direction.rawValue)))
    }

    private func saveArrival(_ board: MazeBoard) -> Bool {
        guard model.saveMaze(board) else { return false }
        blockedDirection = nil
        model.feedback(for: .maze)
        // VoiceOver receives cell centers, never a guessed route or every display frame.
        if UIAccessibility.isVoiceOverRunning || board.isComplete {
            UIAccessibility.post(notification: .announcement,
                                 argument: board.isComplete ? model.t("maze.result.won") : positionText(board))
        }
        return true
    }

    var body: some View {
        ScrollView {
            if let board = model.maze {
                VStack(spacing: 16) {
                    header(board)
                    MazeMovementSurface(board: board, enabled: active, reset: motionReset,
                                        positionText: positionText(board), move: move,
                                        saveArrival: saveArrival, reportBlocked: reportBlocked)
                    legend
                    Text(positionText(board)).font(.subheadline).monospacedDigit()
                        .multilineTextAlignment(.center).accessibilityIdentifier("maze.position")
                    Text(blockedDirection.map { model.t("maze.blocked", model.t("maze.direction." + $0.rawValue)) } ?? model.t("maze.joystick.instructions"))
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("maze.feedback")
                }.padding(16).frame(maxWidth: 632).frame(maxWidth: .infinity)
            }
        }.background(GameCanvas()).tint(GamePalette.tint(.maze))
            .navigationTitle(model.gameTitle(.maze)).navigationBarTitleDisplayMode(.inline)
            .gameSessionScreen(.maze)
            .onChange(of: model.sessionIsPlaying(.maze)) { _, playing in
                if !playing { motionReset &+= 1 }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { motionReset &+= 1 }
            }
            .onDisappear { motionReset &+= 1 }
    }

    private func header(_ board: MazeBoard) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                GameArtwork(game: .maze, size: 42)
                Text(model.t("maze.difficulty.option", model.t("difficulty." + board.difficulty.rawValue), board.size, board.size))
                    .font(.system(.headline, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            GameMetric(symbol: "figure.walk", value: model.t("maze.moves", board.moves),
                       tint: GamePalette.tint(.maze), identifier: "maze.moves")
        }
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { legendItems }
            VStack(alignment: .leading, spacing: 8) { legendItems }
        }.font(.caption)
    }

    @ViewBuilder private var legendItems: some View {
        Label { Text(model.t("maze.startMark")) } icon: {
            Image(systemName: "square").foregroundStyle(GameMaterial.gold)
        }
        Label { Text(model.t("maze.playerMark")) } icon: {
            Image(systemName: "circle.inset.filled").foregroundStyle(MazeBoardInk.amber)
        }
        Label { Text(model.t("maze.finishMark")) } icon: {
            Image(systemName: "diamond.fill").foregroundStyle(MazeBoardInk.rose)
        }
    }

}

/// Frame state lives here, so metrics and the rest of the game screen do not redraw at display frequency.
private struct MazeMovementSurface: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var clock = AnimationFrameClock()
    @State private var motion: MazeMotion
    @State private var layout: MazeWallLayout?
    @State private var input = MazeMotion.Input.zero
    @State private var thumb = CGSize.zero
    @State private var touching = false
    let board: MazeBoard
    let enabled: Bool
    let reset: Int
    let positionText: String
    let move: (MazeBoard.Direction) -> Void
    let saveArrival: (MazeBoard) -> Bool
    let reportBlocked: (MazeBoard.Direction) -> Void

    private var speed: Double {
        let configured = model.gameSettings(for: .maze).mazeSpeed
        return configured.isFinite ? min(1.2, max(0.8, configured)) : 1
    }

    init(board: MazeBoard, enabled: Bool, reset: Int, positionText: String,
         move: @escaping (MazeBoard.Direction) -> Void, saveArrival: @escaping (MazeBoard) -> Bool,
         reportBlocked: @escaping (MazeBoard.Direction) -> Void) {
        self.board = board; self.enabled = enabled; self.reset = reset; self.positionText = positionText
        self.move = move; self.saveArrival = saveArrival; self.reportBlocked = reportBlocked
        _motion = State(initialValue: MazeMotion(board: board))
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                if let layout { MazeWallLayer(layout: layout).equatable() }
                MazePlayerOverlay(row: motion.row, column: motion.column, size: board.size)
            }
            .aspectRatio(1, contentMode: .fit).frame(maxWidth: 600)
            .background(GameBoardSurface(game: .maze))
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 14).onEnded { value in
                if let direction = MazeBoard.Direction.fromSwipe(horizontal: Double(value.translation.width),
                                                                 vertical: Double(value.translation.height)) { step(direction) }
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.t("maze.board"))
            .accessibilityValue(positionText)
            .accessibilityHint(model.t("maze.accessibility.hint"))
            .accessibilityAction(named: model.t("maze.direction.up")) { step(.up) }
            .accessibilityAction(named: model.t("maze.direction.right")) { step(.right) }
            .accessibilityAction(named: model.t("maze.direction.down")) { step(.down) }
            .accessibilityAction(named: model.t("maze.direction.left")) { step(.left) }
            .accessibilityIdentifier("maze.board")

            // 120 + 12 + 148 = 280 pt, including four 44 pt fallback targets.
            HStack(spacing: 12) {
                joystick
                Spacer(minLength: 0)
                controls
            }.frame(maxWidth: 360)
                .disabled(!enabled)
        }
        .onReceive(clock.$frame) { frame in
            guard touching, !input.isZero, enabled, scenePhase == .active,
                  model.sessionIsPlaying(.maze),
                  var next = model.maze else { return }
            // MazeMotion still clamps suspended-frame time and commits only one legal center.
            switch motion.advance(delta: frame.delta * speed, input: input, board: &next) {
            case .arrived:
                if !saveArrival(next) { stopAndSettle() }
                else if next.isComplete { stopInput() }
            case .blocked(let direction): reportBlocked(direction)
            case .idle, .moving: break
            }
        }
        .onAppear { replaceLayout() }
        .onDisappear { stopAndSettle() }
        .onChange(of: enabled) { _, value in if !value { stopAndSettle() } }
        .onChange(of: model.sessionIsPlaying(.maze)) { _, value in if !value { stopAndSettle() } }
        .onChange(of: speed) { _, _ in stopAndSettle() }
        .onChange(of: reset) { _, _ in stopAndSettle() }
        .onChange(of: scenePhase) { _, value in if value != .active { stopAndSettle() } }
        .onChange(of: board.position) { _, value in
            if motion.origin != value { stopAndSettle() }
        }
        .onChange(of: board.seed) { _, _ in replaceLayout() }
        .onChange(of: board.difficulty) { _, _ in replaceLayout() }
    }

    private var joystick: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [GameMaterial.teal, GameMaterial.navy],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(GameMaterial.gold.opacity(0.8), lineWidth: 1.5)
            Image(systemName: "plus").font(.system(size: 76, weight: .ultraLight))
                .foregroundStyle(GameMaterial.ivory.opacity(0.2))
            Circle().fill(LinearGradient(colors: [GameMaterial.ivory, MazeBoardInk.amber],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { Circle().strokeBorder(GameMaterial.gold, lineWidth: 1.5) }
                .overlay { Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(GameMaterial.ink) }
                .shadow(color: GameMaterial.navy.opacity(0.5), radius: 2, y: 2)
                .frame(width: 44, height: 44).offset(thumb)
        }.frame(width: 120, height: 120).contentShape(Circle())
            .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard enabled, scenePhase == .active, model.sessionIsPlaying(.maze) else { stopInput(); return }
                let x = value.location.x - 60, y = value.location.y - 60
                let distance = hypot(x, y)
                let scale = distance > 38 ? 38 / distance : 1
                thumb = CGSize(width: x * scale, height: y * scale)
                input = MazeMotion.Input(x: Double(x / 38), y: Double(y / 38))
                touching = true
                if input.isZero { clock.stop() } else { clock.start() }
            }.onEnded { _ in stopInput() })
            // Essential direct movement stays linear, including with Reduce Motion.
            // There are no springs, inertia or implicit animations to trail the thumb.
            .transaction { $0.animation = nil }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.t("maze.joystick.title"))
            .accessibilityValue(model.t(touching && !input.isZero ? "maze.joystick.active" : "maze.joystick.stopped"))
            .accessibilityHint(model.t("maze.joystick.hint"))
            .accessibilityAdjustableAction { adjustment in
                switch adjustment { case .increment: step(.right); case .decrement: step(.left); @unknown default: break }
            }
            .accessibilityAction(named: model.t("maze.direction.up")) { step(.up) }
            .accessibilityAction(named: model.t("maze.direction.right")) { step(.right) }
            .accessibilityAction(named: model.t("maze.direction.down")) { step(.down) }
            .accessibilityAction(named: model.t("maze.direction.left")) { step(.left) }
            .accessibilityIdentifier("maze.joystick")
    }

    private func step(_ direction: MazeBoard.Direction) {
        stopAndSettle()
        move(direction)
    }

    private func stopInput() {
        touching = false; input = .zero; thumb = .zero
        clock.stop()
    }

    private func stopAndSettle() {
        stopInput()
        motion.settle(on: model.maze ?? board)
    }

    private func replaceLayout() {
        stopAndSettle()
        layout = MazeWallLayout(board: board)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            directionButton(.up, symbol: "arrow.up")
            HStack(spacing: 8) {
                directionButton(.left, symbol: "arrow.left")
                directionButton(.down, symbol: "arrow.down")
                directionButton(.right, symbol: "arrow.right")
            }
        }
    }

    private func directionButton(_ direction: MazeBoard.Direction, symbol: String) -> some View {
        Button { step(direction) } label: {
            Image(systemName: symbol).font(.title2.weight(.semibold))
                .foregroundStyle(GameMaterial.ink)
                .frame(width: 44, height: 48)
                .background(GameTileSurface(game: .maze))
                .contentShape(Rectangle())
        }.buttonStyle(QuietPressStyle())
            .accessibilityLabel(model.t("maze.direction." + direction.rawValue))
            .accessibilityHint(model.t("maze.direction.hint"))
            .accessibilityIdentifier("maze." + direction.rawValue)
    }
}

private enum MazeBoardInk {
    static let inset: CGFloat = 10
    static let amber = Color(red: 1, green: 0.70, blue: 0.27)
    static let rose = Color(red: 0.96, green: 0.49, blue: 0.52)
}

/// Unit-cell vector geometry is built when the seeded layout changes, never on a display frame.
private struct MazeWallLayout: Equatable {
    let seed: UInt64
    let size: Int
    let walls: Path
    let start: Path
    let finish: Path
    let exitHalo: Path

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.seed == rhs.seed && lhs.size == rhs.size }

    init(board: MazeBoard) {
        seed = board.seed; size = board.size
        var path = Path()
        for row in 0..<board.size {
            for column in 0..<board.size {
                let index = row * board.size + column
                guard board.walls.indices.contains(index) else { continue }
                let mask = board.walls[index], x = CGFloat(column), y = CGFloat(row)
                if mask & 1 != 0 { path.move(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: x + 1, y: y)) }
                if mask & 8 != 0 { path.move(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: x, y: y + 1)) }
                if row == board.size - 1 && mask & 4 != 0 {
                    path.move(to: CGPoint(x: x, y: y + 1)); path.addLine(to: CGPoint(x: x + 1, y: y + 1))
                }
                if column == board.size - 1 && mask & 2 != 0 {
                    path.move(to: CGPoint(x: x + 1, y: y)); path.addLine(to: CGPoint(x: x + 1, y: y + 1))
                }
            }
        }
        walls = path
        start = Path(CGRect(x: 0.23, y: 0.23, width: 0.54, height: 0.54))
        let goal = CGFloat(board.size) - 0.5
        exitHalo = Path(ellipseIn: CGRect(x: goal - 0.4, y: goal - 0.4, width: 0.8, height: 0.8))
        var diamond = Path()
        diamond.move(to: CGPoint(x: goal, y: goal - 0.27))
        diamond.addLine(to: CGPoint(x: goal + 0.27, y: goal))
        diamond.addLine(to: CGPoint(x: goal, y: goal + 0.27))
        diamond.addLine(to: CGPoint(x: goal - 0.27, y: goal))
        diamond.closeSubpath()
        finish = diamond
    }
}

/// Equatable static layer: moving the separate player overlay does not rebuild or redraw wall geometry.
private struct MazeWallLayer: View, Equatable {
    let layout: MazeWallLayout
    var body: some View {
        Canvas { context, size in
            let inset = MazeBoardInk.inset
            let step = (min(size.width, size.height) - inset * 2) / CGFloat(layout.size)
            let transform = CGAffineTransform(translationX: inset, y: inset).scaledBy(x: step, y: step)
            let walls = layout.walls.applying(transform)
            let width: CGFloat = layout.size == 21 ? 1.35 : 1.85
            context.stroke(walls, with: .color(GameMaterial.gold.opacity(0.16)),
                           style: StrokeStyle(lineWidth: width + 2, lineCap: .round, lineJoin: .round))
            context.stroke(walls, with: .color(GameMaterial.ivory),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            context.fill(layout.start.applying(transform), with: .color(GameMaterial.gold.opacity(0.16)))
            context.stroke(layout.start.applying(transform), with: .color(GameMaterial.gold), lineWidth: 1.5)
            context.fill(layout.exitHalo.applying(transform), with: .color(MazeBoardInk.rose.opacity(0.17)))
            context.fill(layout.finish.applying(transform), with: .color(MazeBoardInk.rose))
            context.stroke(layout.finish.applying(transform), with: .color(GameMaterial.ivory.opacity(0.8)), lineWidth: 0.8)
        }.accessibilityHidden(true)
    }
}

private struct MazePlayerOverlay: View {
    let row: Double
    let column: Double
    let size: Int
    var body: some View {
        GeometryReader { geometry in
            let inset = MazeBoardInk.inset
            let step = (min(geometry.size.width, geometry.size.height) - inset * 2) / CGFloat(size)
            Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.52), MazeBoardInk.amber],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { Circle().strokeBorder(GameMaterial.ivory.opacity(0.9), lineWidth: 0.9) }
                .overlay { Circle().fill(GameMaterial.ink).frame(width: step * 0.20, height: step * 0.20) }
                .frame(width: step * 0.68, height: step * 0.68)
                .shadow(color: GameMaterial.navy.opacity(0.65), radius: 1, y: 1)
                .position(x: inset + (CGFloat(column) + 0.5) * step, y: inset + (CGFloat(row) + 0.5) * step)
        }.transaction { $0.animation = nil }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
