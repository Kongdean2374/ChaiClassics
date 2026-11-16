import SwiftUI
import ChaiCore

struct SlidingMenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var size = 3
    @State private var difficulty = SlidingBoard.Difficulty.normal
    @State private var play = false
    @State private var confirm = false
    private func start() {
        do { if model.saveSliding(try SlidingBoard(size: size, difficulty: difficulty)) { play = true } }
        catch { model.notice = .puzzleCreation }
    }
    var body: some View {
        Form {
            Section {
                GameIntroHeader(game: .sliding, title: model.gameTitle(.sliding), subtitle: model.t("sliding.menu.intro"))
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            if let board = model.sliding {
                Section(model.t("menu.lastGame")) {
                    Button { play = true } label: {
                        ContinueCard(title: model.t(board.isComplete ? "menu.viewLast" : "menu.continue"),
                                     detail: model.summaryDetail(.sliding(board)) + " · " + model.t("common.seconds", board.elapsedSeconds))
                    }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("sliding.continue")
                }
            }
            Section(model.t("menu.newGame")) {
                Picker(model.t("sliding.size"), selection: $size) { ForEach(3...5, id: \.self) { Text("\($0)×\($0)").tag($0) } }
                    .pickerStyle(.segmented).accessibilityIdentifier("sliding.size")
                Picker(model.t("sliding.difficulty"), selection: $difficulty) {
                    ForEach(SlidingBoard.Difficulty.allCases, id: \.self) { Text(model.t("difficulty." + $0.rawValue)).tag($0) }
                }
                Button { if model.sliding != nil { confirm = true } else { start() } } label: {
                    Label(model.t("menu.start"), systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                        .foregroundStyle(.primary)
                        .background(GamePalette.tint(.sliding).opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(GamePalette.tint(.sliding).opacity(0.3), lineWidth: 1).allowsHitTesting(false))
                }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("sliding.start")
                    .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
            }
        }.scrollContentBackground(.hidden).background(GameCanvas()).tint(GamePalette.tint(.sliding))
            .localizedNavigation().navigationTitle(model.gameTitle(.sliding))
            .navigationDestination(isPresented: $play) { SlidingPlayView() }
            .confirmationDialog(model.t("sliding.replace.confirm"), isPresented: $confirm, titleVisibility: .visible) {
                Button(model.t("menu.startNew"), role: .destructive) { start() }.accessibilityIdentifier("sliding.confirmNew")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
    }
}

struct SlidingPlayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) var scenePhase
    @State private var paused = false
    @State private var visible = false
    @State private var restart = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        ScrollView {
            if let board = model.sliding {
                VStack(spacing: 18) {
                    SlidingPlayHeader(board: board, paused: $paused)
                    if board.isComplete {
                        GameResultBanner(game: .sliding, title: model.t("status.completed"), detail: model.t("sliding.result.won"), won: true, identifier: "sliding.complete")
                    }
                    if paused || scenePhase != .active {
                        PauseCard(game: .sliding) { paused = false }.frame(height: 300)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: board.size), spacing: 6) {
                            ForEach(board.tiles.indices, id: \.self) { i in
                                SlidingTile(index: i, board: board) {
                                    if model.editSliding({ $0.move(i) }) { model.feedback() }
                                }
                            }
                        }.padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                            .overlay(RoundedRectangle(cornerRadius: 24).fill(GamePalette.tint(.sliding).opacity(0.045)).allowsHitTesting(false))
                            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(GamePalette.tint(.sliding).opacity(0.2), lineWidth: 1).allowsHitTesting(false))
                            .shadow(color: .black.opacity(0.07), radius: 22, y: 9)
                    }
                    Text(model.t("sliding.controls")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(16).frame(maxWidth: 540).frame(maxWidth: .infinity)
            }
        }.background(GameCanvas()).tint(GamePalette.tint(.sliding))
            .localizedNavigation().navigationTitle(model.gameTitle(.sliding)).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(model.t("common.restart")) { restart = true }.accessibilityIdentifier("sliding.restart") }
            .confirmationDialog(model.t("sliding.restart.confirm"), isPresented: $restart, titleVisibility: .visible) {
                Button(model.t("common.restart"), role: .destructive) { model.editSliding { $0.restart() }; paused = false }.accessibilityIdentifier("sliding.confirmRestart")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
            .gameCompletionCelebration(completed: model.sliding?.isComplete == true)
            .modifier(GameplayActivity(game: .sliding, active: !paused && !restart && model.sliding?.isComplete == false))
            .onAppear { visible = true }.onDisappear { visible = false }
            .onReceive(timer) { _ in
                if visible && !paused && !restart && scenePhase == .active && model.sliding?.isComplete == false { model.editSliding { $0.elapsedSeconds += 1 } }
            }
    }
}

private struct SlidingPlayHeader: View {
    let board: SlidingBoard
    @Binding var paused: Bool
    @EnvironmentObject var model: AppModel
    private var tint: Color { GamePalette.tint(.sliding) }
    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 11) {
                GameArtwork(game: .sliding, size: 42)
                Text(model.t("sliding.boardTitle", board.size, board.size, model.t("difficulty." + board.difficulty.rawValue)))
                    .font(.system(.headline, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button { paused.toggle() } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.semibold)).frame(width: 44, height: 44)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(QuietPressStyle()).accessibilityLabel(model.t(paused ? "common.resume" : "common.pause"))
                    .accessibilityIdentifier("sliding.pause")
            }
            HStack {
                GameMetric(symbol: "square.grid.2x2", value: model.t("sliding.moves", board.moves), tint: tint, identifier: "sliding.moves")
                Spacer(minLength: 8)
                GameMetric(symbol: "timer", value: model.t("common.seconds", board.elapsedSeconds), tint: tint, identifier: "sliding.timer")
            }
        }
    }
}

private struct SlidingTile: View {
    let index: Int
    let board: SlidingBoard
    let move: () -> Void
    @EnvironmentObject var model: AppModel
    @GestureState private var translation = CGSize.zero
    private func offset(step: CGFloat) -> CGSize {
        guard let direction = SlidingInput.direction(tile: index, board: board) else { return .zero }
        switch direction {
        case .left: return CGSize(width: max(-step, min(0, translation.width)), height: 0)
        case .right: return CGSize(width: min(step, max(0, translation.width)), height: 0)
        case .up: return CGSize(width: 0, height: max(-step, min(0, translation.height)))
        case .down: return CGSize(width: 0, height: min(step, max(0, translation.height)))
        }
    }
    var body: some View {
        GeometryReader { geometry in
            Button(action: move) {
                SlidingTileFace(value: board.tiles[index], side: geometry.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                    .offset(offset(step: geometry.size.width + 6))
            }.buttonStyle(.plain).disabled(!board.canMove(index))
                .highPriorityGesture(DragGesture(minimumDistance: 10, coordinateSpace: .local)
                    .updating($translation) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        if SlidingInput.accepts(tile: index, board: board, horizontal: Double(value.translation.width), vertical: Double(value.translation.height), minimumDistance: Double(max(18, geometry.size.width * 0.2))) { move() }
                    })
                .accessibilityLabel(board.tiles[index] == 0 ? model.t("sliding.blank") : model.t("sliding.tile", board.tiles[index]))
                .accessibilityHint(model.t("sliding.tile.hint"))
                .accessibilityIdentifier("sliding.tile.\(index)")
        }.aspectRatio(1, contentMode: .fit).zIndex(translation == .zero ? 0 : 1)
    }
}

private struct SlidingTileFace: View {
    let value: Int
    let side: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    private var tint: Color { GamePalette.tint(.sliding) }
    private var corner: CGFloat { min(18, max(10, side * 0.16)) }
    var body: some View {
        ZStack {
            if value == 0 {
                RoundedRectangle(cornerRadius: corner).fill(tint.opacity(colorScheme == .dark ? 0.045 : 0.055))
                RoundedRectangle(cornerRadius: corner).strokeBorder(tint.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            } else {
                RoundedRectangle(cornerRadius: corner).fill(Color(.secondarySystemGroupedBackground))
                RoundedRectangle(cornerRadius: corner)
                    .fill(LinearGradient(colors: [tint.opacity(0.045), tint.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: corner).strokeBorder(tint.opacity(colorScheme == .dark ? 0.32 : 0.22), lineWidth: 1)
                RoundedRectangle(cornerRadius: max(8, corner - 2))
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.75), lineWidth: 1).padding(2)
                Text("\(value)")
                    .font(.system(size: min(42, max(24, side * 0.36)), weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(.primary)
            }
        }
    }
}
