import SwiftUI
import UIKit
import ChaiCore

struct MazeMenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var difficulty = MazeBoard.Difficulty.normal
    @State private var play = false
    @State private var confirm = false

    private func start() {
        if model.saveMaze(MazeBoard(difficulty: difficulty)) { play = true }
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
                    Button { play = true } label: {
                        ContinueCard(title: model.t(board.isComplete ? "menu.viewLast" : "menu.continue"),
                                     detail: model.t("maze.save.detail", board.size, board.size, board.moves, board.elapsedSeconds))
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("maze.continue")
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
                Button { if model.maze != nil { confirm = true } else { start() } } label: {
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
            .navigationDestination(isPresented: $play) { MazePlayView() }
            .confirmationDialog(model.t("maze.replace.confirm"), isPresented: $confirm, titleVisibility: .visible) {
                Button(model.t("menu.startNew"), role: .destructive) { start() }.accessibilityIdentifier("maze.confirmNew")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
    }
}

struct MazePlayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var restart = false
    @State private var blockedDirection: MazeBoard.Direction?
    private var active: Bool { model.maze?.isPaused == false && model.maze?.isComplete == false && !restart }

    private func positionText(_ board: MazeBoard) -> String {
        model.t("maze.position", board.position.row + 1, board.position.column + 1, board.size, board.size)
    }

    private func move(_ direction: MazeBoard.Direction) {
        guard scenePhase == .active, active else { return }
        var accepted = false
        let saved = model.editMaze { accepted = $0.move(direction) }
        guard saved else { return }
        if accepted, let board = model.maze {
            blockedDirection = nil
            model.feedback()
            UIAccessibility.post(notification: .announcement,
                                 argument: board.isComplete ? model.t("maze.result.won") : positionText(board))
        } else {
            blockedDirection = direction
            UIAccessibility.post(notification: .announcement,
                                 argument: model.t("maze.blocked", model.t("maze.direction." + direction.rawValue)))
        }
    }

    private func resume() {
        model.editMaze { $0.resume() }
        blockedDirection = nil
    }

    var body: some View {
        ScrollView {
            if let board = model.maze {
                VStack(spacing: 16) {
                    header(board)
                    if board.isComplete {
                        GameResultBanner(game: .maze, title: model.t("status.completed"),
                                         detail: model.t("maze.result.won"), won: true, identifier: "maze.complete")
                        Button {
                            if model.saveMaze(MazeBoard(difficulty: board.difficulty)) { blockedDirection = nil }
                        } label: {
                            Label(model.t("maze.next"), systemImage: "arrow.right.circle.fill")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("maze.next")
                    }
                    if board.isPaused || scenePhase != .active {
                        PauseCard(game: .maze, action: resume).frame(minHeight: 260)
                    } else {
                        MazeWallCanvas(board: board, tint: GamePalette.tint(.maze))
                            .aspectRatio(1, contentMode: .fit).frame(maxWidth: 600)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                            .highPriorityGesture(DragGesture(minimumDistance: 14).onEnded { value in
                                // A gesture produces exactly one input regardless of its length.
                                if let direction = MazeBoard.Direction.fromSwipe(horizontal: Double(value.translation.width), vertical: Double(value.translation.height)) {
                                    move(direction)
                                }
                            })
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(model.t("maze.board"))
                            .accessibilityValue(positionText(board))
                            .accessibilityHint(model.t("maze.accessibility.hint"))
                            .accessibilityAction(named: model.t("maze.direction.up")) { move(.up) }
                            .accessibilityAction(named: model.t("maze.direction.right")) { move(.right) }
                            .accessibilityAction(named: model.t("maze.direction.down")) { move(.down) }
                            .accessibilityAction(named: model.t("maze.direction.left")) { move(.left) }
                            .accessibilityIdentifier("maze.board")
                        legend
                        Text(positionText(board)).font(.subheadline).monospacedDigit()
                            .multilineTextAlignment(.center).accessibilityIdentifier("maze.position")
                        controls.disabled(board.isComplete || restart)
                        Text(blockedDirection.map { model.t("maze.blocked", model.t("maze.direction." + $0.rawValue)) } ?? model.t("maze.controls"))
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("maze.feedback")
                    }
                }.padding(16).frame(maxWidth: 632).frame(maxWidth: .infinity)
            }
        }.background(GameCanvas()).tint(GamePalette.tint(.maze))
            .localizedNavigation().navigationTitle(model.gameTitle(.maze)).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(model.t("common.restart")) { restart = true }.accessibilityIdentifier("maze.restart") }
            .confirmationDialog(model.t("maze.restart.confirm"), isPresented: $restart, titleVisibility: .visible) {
                Button(model.t("common.restart"), role: .destructive) {
                    model.editMaze { $0.restart() }; blockedDirection = nil
                }.accessibilityIdentifier("maze.confirmRestart")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
            .gameCompletionCelebration(completed: model.maze?.isComplete == true)
            .modifier(GameplayActivity(game: .maze, active: active))
            .modifier(SessionTimer(active: active, tick: {
                model.editMaze { if $0.elapsedSeconds < Int.max { $0.elapsedSeconds += 1 } }
            }))
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { model.editMaze { $0.pause() } }
            }
            .onDisappear { model.editMaze { $0.pause() } }
    }

    private func header(_ board: MazeBoard) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                GameArtwork(game: .maze, size: 42)
                Text(model.t("maze.difficulty.option", model.t("difficulty." + board.difficulty.rawValue), board.size, board.size))
                    .font(.system(.headline, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    if board.isPaused { resume() } else { model.editMaze { $0.pause() } }
                } label: {
                    Image(systemName: board.isPaused ? "play.fill" : "pause.fill")
                        .font(.headline).frame(width: 44, height: 44)
                        .background(GamePalette.tint(.maze).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                }.buttonStyle(QuietPressStyle()).disabled(board.isComplete)
                    .accessibilityLabel(model.t(board.isPaused ? "common.resume" : "common.pause"))
                    .accessibilityIdentifier("maze.pause")
            }
            ViewThatFits(in: .horizontal) {
                HStack { metrics(board) }
                VStack(alignment: .leading, spacing: 8) { metrics(board) }
            }
        }
    }

    @ViewBuilder private func metrics(_ board: MazeBoard) -> some View {
        GameMetric(symbol: "figure.walk", value: model.t("maze.moves", board.moves), tint: GamePalette.tint(.maze), identifier: "maze.moves")
        GameMetric(symbol: "timer", value: model.t("common.seconds", board.elapsedSeconds), tint: GamePalette.tint(.maze), identifier: "maze.timer")
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { legendItems }
            VStack(alignment: .leading, spacing: 8) { legendItems }
        }.font(.caption)
    }

    @ViewBuilder private var legendItems: some View {
        Label(model.t("maze.startMark"), systemImage: "square").foregroundStyle(.secondary)
        Label(model.t("maze.playerMark"), systemImage: "circle.inset.filled").foregroundStyle(GamePalette.tint(.maze))
        Label(model.t("maze.finishMark"), systemImage: "diamond.fill").foregroundStyle(.secondary)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            directionButton(.up, symbol: "arrow.up")
            HStack(spacing: 12) {
                directionButton(.left, symbol: "arrow.left")
                directionButton(.down, symbol: "arrow.down")
                directionButton(.right, symbol: "arrow.right")
            }
        }
    }

    private func directionButton(_ direction: MazeBoard.Direction, symbol: String) -> some View {
        Button { move(direction) } label: {
            Image(systemName: symbol).font(.title2.weight(.semibold))
                .frame(width: 56, height: 48)
                .background(GamePalette.tint(.maze).opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                .contentShape(Rectangle())
        }.buttonStyle(QuietPressStyle())
            .accessibilityLabel(model.t("maze.direction." + direction.rawValue))
            .accessibilityHint(model.t("maze.direction.hint"))
            .accessibilityIdentifier("maze." + direction.rawValue)
    }
}

/// One vector path for all walls. There are no per-cell view trees or image assets.
private struct MazeWallCanvas: View {
    let board: MazeBoard
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 3
            let step = (min(size.width, size.height) - inset * 2) / CGFloat(board.size)
            func center(_ cell: MazeBoard.Cell) -> CGPoint {
                CGPoint(x: inset + (CGFloat(cell.column) + 0.5) * step,
                        y: inset + (CGFloat(cell.row) + 0.5) * step)
            }
            var walls = Path()
            for row in 0..<board.size {
                for column in 0..<board.size {
                    let index = row * board.size + column
                    guard board.walls.indices.contains(index) else { continue }
                    let mask = board.walls[index]
                    let x = inset + CGFloat(column) * step, y = inset + CGFloat(row) * step
                    if mask & 1 != 0 { walls.move(to: CGPoint(x: x, y: y)); walls.addLine(to: CGPoint(x: x + step, y: y)) }
                    if mask & 8 != 0 { walls.move(to: CGPoint(x: x, y: y)); walls.addLine(to: CGPoint(x: x, y: y + step)) }
                    if row == board.size - 1 && mask & 4 != 0 {
                        walls.move(to: CGPoint(x: x, y: y + step)); walls.addLine(to: CGPoint(x: x + step, y: y + step))
                    }
                    if column == board.size - 1 && mask & 2 != 0 {
                        walls.move(to: CGPoint(x: x + step, y: y)); walls.addLine(to: CGPoint(x: x + step, y: y + step))
                    }
                }
            }
            context.stroke(walls, with: .color(.primary.opacity(0.86)), style: StrokeStyle(lineWidth: board.size == 21 ? 1.15 : 1.55, lineCap: .square))
            let start = center(board.start), goal = center(board.goal), player = center(board.position)
            let marker = step * 0.27
            let startRect = CGRect(x: start.x - marker, y: start.y - marker, width: marker * 2, height: marker * 2)
            context.stroke(Path(startRect), with: .color(.secondary), lineWidth: 1.5)
            var finish = Path()
            finish.move(to: CGPoint(x: goal.x, y: goal.y - marker))
            finish.addLine(to: CGPoint(x: goal.x + marker, y: goal.y))
            finish.addLine(to: CGPoint(x: goal.x, y: goal.y + marker))
            finish.addLine(to: CGPoint(x: goal.x - marker, y: goal.y))
            finish.closeSubpath()
            context.fill(finish, with: .color(.primary))
            let radius = step * 0.34
            let playerPath = Path(ellipseIn: CGRect(x: player.x - radius, y: player.y - radius, width: radius * 2, height: radius * 2))
            context.fill(playerPath, with: .color(tint))
            context.stroke(playerPath, with: .color(.primary), lineWidth: 1.2)
            let dot = radius * 0.36
            context.fill(Path(ellipseIn: CGRect(x: player.x - dot, y: player.y - dot, width: dot * 2, height: dot * 2)), with: .color(.white))
        }
    }
}
