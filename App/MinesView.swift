import SwiftUI
import ChaiCore

struct MinesMenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var showPlay = false
    @State private var layout = 0
    @State private var width = 9
    @State private var height = 9
    @State private var mineCount = 10
    @State private var pending: MineConfiguration?
    private var configuration: MineConfiguration? { try? MineConfiguration(width: width, height: height, mines: mineCount) }
    private func start() {
        guard let configuration else { return }
        if model.mines != nil { pending = configuration }
        else if model.saveMines(MinesweeperBoard(configuration: configuration)) { showPlay = true }
    }
    var body: some View {
        Form {
            Section {
                GameIntroHeader(game: .minesweeper, title: model.gameTitle(.minesweeper), subtitle: model.t("mines.menu.intro"))
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            if let board = model.mines {
                Section(model.t("menu.lastGame")) {
                    Button { showPlay = true } label: {
                        ContinueCard(title: model.t(board.isFinished ? "menu.viewLast" : "menu.continue"),
                                     detail: model.summaryDetail(.mines(board)) + " · " + model.t("status." + model.summary(.minesweeper).state.rawValue))
                    }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("mines.continue")
                }
            }
            Section(model.t("mines.chooseSize")) {
                Picker(model.t("mines.chooseSize"), selection: $layout) {
                    Text("9×9").tag(0); Text("16×16").tag(1); Text("30×16").tag(2)
                    Text(model.t("difficulty.custom")).tag(3)
                }.pickerStyle(.segmented).accessibilityIdentifier("mines.size")
                if layout == 3 {
                    Stepper(model.t("mines.width", width), value: $width, in: 5...40).accessibilityIdentifier("mines.width")
                    Stepper(model.t("mines.height", height), value: $height, in: 5...40).accessibilityIdentifier("mines.height")
                }
            }
            Section(model.t("mines.chooseCount")) {
                Stepper(model.t("mines.mineCount", mineCount), value: $mineCount, in: 1...max(1, width * height - 1)).accessibilityIdentifier("mines.mineCount")
                if let configuration {
                    Text(model.t("mines.estimatedDifficulty", model.t(configuration.difficultyKey), configuration.mineDensity * 100))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(GamePalette.tint(.minesweeper))
                        .accessibilityIdentifier("mines.estimatedDifficulty")
                }
                Text(model.t("mines.difficultyExplanation")).font(.caption).foregroundStyle(.secondary)
            }
            Section(model.t("menu.newGame")) {
                Button { start() } label: {
                    Label(model.t("menu.start"), systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                        .foregroundStyle(.primary)
                        .background(GamePalette.tint(.minesweeper).opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(GamePalette.tint(.minesweeper).opacity(0.3), lineWidth: 1).allowsHitTesting(false))
                }.buttonStyle(QuietPressStyle()).disabled(configuration == nil).accessibilityIdentifier("mines.start")
                    .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                Text(model.t("mines.randomExplanation")).font(.footnote).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden).background(GameCanvas()).tint(GamePalette.tint(.minesweeper))
            .localizedNavigation().navigationTitle(model.gameTitle(.minesweeper)).navigationBarTitleDisplayMode(.inline)
            .onChange(of: layout) { _, value in
                let presets: [MineConfiguration] = [.easy, .medium, .hard]
                if presets.indices.contains(value) {
                    let preset = presets[value]; width = preset.width; height = preset.height; mineCount = preset.mineCount
                }
            }
            .onChange(of: width) { _, _ in mineCount = min(mineCount, width * height - 1) }
            .onChange(of: height) { _, _ in mineCount = min(mineCount, width * height - 1) }
            .navigationDestination(isPresented: $showPlay) { MinesPlayView() }
            .confirmationDialog(model.t("mines.replace.confirm"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                Button(model.t("menu.startNew"), role: .destructive) {
                    if let config = pending, model.saveMines(MinesweeperBoard(configuration: config)) { showPlay = true }
                    pending = nil
                }.accessibilityIdentifier("mines.confirmNew")
                Button(model.t("common.cancel"), role: .cancel) { pending = nil }
            }
    }
}

struct MinesPlayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var paused = false
    @State private var visible = false
    @State private var restart = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        GeometryReader { geometry in
            if let board = model.mines {
                let natural = CGSize(width: CGFloat(board.configuration.width * 34), height: CGFloat(board.configuration.height * 34))
                let width = max(1, geometry.size.width - 32)
                let compact = board.configuration.width <= 9 && board.configuration.height <= 9
                // A maximum, not a fixed reservation: the native viewport takes
                // the space left by the header, metrics and optional result.
                let maxViewportHeight = compact ? min(width * natural.height / natural.width, natural.height * 1.7) : natural.height
                MinesPlaySurface(board: board, naturalSize: natural, maxViewportHeight: maxViewportHeight,
                                 paused: $paused, isForeground: scenePhase == .active,
                                 tap: { i in
                                     // Deliberately bypass legacy board.mode, without changing its Codable field.
                                     if model.editMines({ $0.reveal(i) }) { model.feedback() }
                                 }, flag: { i in
                                     if model.editMines({ $0.toggleFlag(i) }) { model.feedback() }
                                 })
            }
        }.background(GameCanvas()).tint(GamePalette.tint(.minesweeper))
            .localizedNavigation().navigationTitle(model.gameTitle(.minesweeper)).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(model.t("common.restart")) { restart = true }.accessibilityIdentifier("mines.restart") }
            .confirmationDialog(model.t("mines.restart.confirm"), isPresented: $restart, titleVisibility: .visible) {
                Button(model.t("common.restart"), role: .destructive) {
                    if let config = model.mines?.configuration, model.saveMines(MinesweeperBoard(configuration: config)) { paused = false }
                }.accessibilityIdentifier("mines.confirmRestart")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
            .gameCompletionCelebration(completed: model.mines?.status == .won)
            .modifier(GameplayActivity(game: .minesweeper, active: !paused && !restart && model.mines?.isFinished == false))
            .onAppear { visible = true }.onDisappear { visible = false }
            .onReceive(timer) { _ in
                if visible && !paused && !restart && scenePhase == .active && model.mines?.status == .playing { model.editMines { $0.elapsedSeconds += 1 } }
            }
    }
}

private struct MinesPlaySurface: View {
    let board: MinesweeperBoard
    let naturalSize: CGSize
    let maxViewportHeight: CGFloat
    @Binding var paused: Bool
    let isForeground: Bool
    let tap: (Int) -> Void
    let flag: (Int) -> Void
    @EnvironmentObject var model: AppModel
    private var tint: Color { GamePalette.tint(.minesweeper) }
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 11) {
                GameArtwork(game: .minesweeper, size: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.t("mines.boardTitle", model.t(board.configuration.difficultyKey), board.configuration.width, board.configuration.height))
                        .font(.system(.headline, design: .rounded))
                    Text(model.t("mines.counters", board.configuration.mineCount - board.flags.count, board.flags.count, board.configuration.mineCount))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button { paused.toggle() } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.semibold)).frame(width: 44, height: 44)
                        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(QuietPressStyle()).accessibilityLabel(model.t(paused ? "common.resume" : "common.pause"))
                    .disabled(board.isFinished).opacity(board.isFinished ? 0.45 : 1)
                    .accessibilityIdentifier("mines.pause")
            }.fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            HStack {
                GameMetric(symbol: "timer", value: model.t("common.seconds", board.elapsedSeconds), tint: tint, identifier: "mines.timer")
                Spacer(minLength: 8)
                SessionBadge(state: GameSummary.mines(board).state, title: model.t("status." + GameSummary.mines(board).state.rawValue))
            }.fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            boardViewport.frame(maxWidth: .infinity, minHeight: 0, maxHeight: maxViewportHeight)
            if board.status == .won {
                GameResultBanner(game: .minesweeper, title: model.t("status.completed"), detail: model.t("mines.result.won"), won: true, identifier: "mines.won")
                    .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            } else if board.status == .lost {
                GameResultBanner(game: .minesweeper, title: model.t("mines.lost"), detail: model.t("mines.result.lost"), won: false, identifier: "mines.lost")
                    .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            }
            Text(model.t("mines.controls")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
        }.padding(.horizontal, 16).padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    @ViewBuilder private var boardViewport: some View {
        if paused || !isForeground {
            PauseCard(game: .minesweeper) { paused = false }
        } else {
            ZoomBoard(size: naturalSize) {
                MinesGrid(board: board, tap: tap, flag: flag).environmentObject(model)
            }.background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.18), lineWidth: 1).allowsHitTesting(false))
                .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
        }
    }
}

private struct MinesGrid: View {
    let board: MinesweeperBoard
    let tap: (Int) -> Void
    let flag: (Int) -> Void
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<board.configuration.height, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<board.configuration.width, id: \.self) { col in
                        let i = row * board.configuration.width + col
                        let open = board.revealed.contains(i)
                        let marked = board.flags.contains(i)
                        MinesCellFace(board: board, index: i).frame(width: 34, height: 34).contentShape(Rectangle())
                            .gesture(LongPressGesture(minimumDuration: 0.45, maximumDistance: 12).exclusively(before: TapGesture()).onEnded { value in
                                switch value { case .first: flag(i); case .second: tap(i) }
                            })
                            .accessibilityElement().accessibilityAddTraits(.isButton)
                            .accessibilityLabel(model.t("mines.cell.label", row + 1, col + 1, marked ? model.t("mines.flagged") : open ? model.t("mines.revealed", board.adjacentMines(i)) : model.t("mines.covered")))
                            .accessibilityValue(model.t(marked ? "mines.flagged" : open ? "mines.revealed.value" : "mines.covered"))
                            .accessibilityHint(model.t("mines.cell.hint"))
                            .accessibilityAction { tap(i) }
                            .accessibilityAction(named: model.t(marked ? "mines.unflag" : "mines.flag")) { flag(i) }
                            .accessibilityIdentifier("mines.cell.\(i)")
                    }
                }
            }
        }
    }
}

private struct MinesCellFace: View {
    let board: MinesweeperBoard
    let index: Int
    @Environment(\.colorScheme) private var colorScheme
    private var open: Bool { board.revealed.contains(index) }
    private var tint: Color { GamePalette.tint(.minesweeper) }
    private var exploded: Bool { board.status == .lost && board.exploded == index }
    private var clueColor: Color {
        switch board.adjacentMines(index) {
        case 1: return .blue
        case 2: return colorScheme == .dark ? .mint : Color(red: 0.13, green: 0.45, blue: 0.33)
        case 3: return .red
        case 4: return .indigo
        case 5: return colorScheme == .dark ? .orange : Color(red: 0.58, green: 0.29, blue: 0.16)
        case 6: return colorScheme == .dark ? .cyan : Color(red: 0.08, green: 0.43, blue: 0.49)
        default: return .primary
        }
    }
    var body: some View {
        ZStack {
            if open {
                Rectangle().fill(exploded ? Color.red.opacity(0.16) : Color(.systemGray6))
                Rectangle().strokeBorder(tint.opacity(0.12), lineWidth: 0.5)
            } else {
                Rectangle().fill(Color(.systemGray4))
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(.systemGray5), Color(.systemGray4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 3).fill(tint.opacity(0.045)))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.7))
                    .overlay(alignment: .top) { Rectangle().fill(.white.opacity(colorScheme == .dark ? 0.09 : 0.6)).frame(height: 1) }
                    .padding(1)
            }
            if board.status == .lost && board.mines.contains(index) {
                Image(systemName: "burst.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(exploded ? Color.red : Color.primary)
            } else if board.flags.contains(index) {
                Image(systemName: "flag.fill").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? Color.mint : Color(red: 0.08, green: 0.39, blue: 0.35))
            } else if open && board.adjacentMines(index) > 0 {
                Text("\(board.adjacentMines(index))").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(clueColor)
            }
        }
    }
}
