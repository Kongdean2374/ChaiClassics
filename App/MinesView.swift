import SwiftUI
import ChaiCore

struct MinesMenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var showPlay = false
    @State private var customWidth = 9
    @State private var customHeight = 9
    @State private var customMines = 10
    @State private var pending: MineConfiguration?
    private func start(_ config: MineConfiguration) {
        if model.mines != nil { pending = config }
        else if model.saveMines(MinesweeperBoard(configuration: config)) { showPlay = true }
    }
    var body: some View {
        Form {
            if let board = model.mines {
                Section(model.t("menu.lastGame")) {
                    Button { showPlay = true } label: {
                        ContinueCard(title: model.t(board.isFinished ? "menu.viewLast" : "menu.continue"),
                                     detail: model.summaryDetail(.mines(board)) + " · " + model.t("status." + model.summary(.minesweeper).state.rawValue))
                    }.accessibilityIdentifier("mines.continue")
                }
            }
            Section(model.t("menu.newGame")) {
                ForEach([MineConfiguration.easy, .medium, .hard], id: \.difficultyKey) { config in
                    Button { start(config) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.t(config.difficultyKey)).font(.headline)
                            Text(model.t("mines.preset", config.width, config.height, config.mineCount)).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier(config == .easy ? "mines.easy" : config == .medium ? "mines.medium" : "mines.hard")
                }
            }
            Section(model.t("difficulty.custom")) {
                Stepper(model.t("mines.width", customWidth), value: $customWidth, in: 5...40)
                Stepper(model.t("mines.height", customHeight), value: $customHeight, in: 5...40)
                Stepper(model.t("mines.mineCount", customMines), value: $customMines, in: 1...max(1, customWidth * customHeight - 1))
                Button(model.t("mines.startCustom")) {
                    if let config = try? MineConfiguration(width: customWidth, height: customHeight, mines: customMines) { start(config) }
                }.accessibilityIdentifier("mines.custom")
            }
        }.localizedNavigation().navigationTitle(model.gameTitle(.minesweeper))
            .onChange(of: customWidth) { _, _ in customMines = min(customMines, customWidth * customHeight - 1) }
            .onChange(of: customHeight) { _, _ in customMines = min(customMines, customWidth * customHeight - 1) }
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
                let availableHeight = max(160, geometry.size.height - 155)
                let compact = board.configuration.width <= 9 && board.configuration.height <= 9
                let viewportHeight = min(availableHeight, compact ? width * natural.height / natural.width : natural.height)
                VStack(spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.t("mines.boardTitle", model.t(board.configuration.difficultyKey), board.configuration.width, board.configuration.height)).font(.headline)
                            Text(model.t("mines.counters", board.configuration.mineCount - board.flags.count, board.flags.count, board.configuration.mineCount)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button { paused.toggle() } label: { Image(systemName: paused ? "play.fill" : "pause.fill").frame(width: 38, height: 38) }
                            .buttonStyle(.bordered).accessibilityLabel(model.t(paused ? "common.resume" : "common.pause")).accessibilityIdentifier("mines.pause")
                    }
                    HStack {
                        Text(model.t("common.seconds", board.elapsedSeconds)).monospacedDigit().accessibilityIdentifier("mines.timer")
                        Spacer()
                        if board.status == .won { Text(model.t("status.completed")).fontWeight(.semibold).accessibilityIdentifier("mines.won") }
                        if board.status == .lost { Text(model.t("mines.lost")).fontWeight(.semibold).accessibilityIdentifier("mines.lost") }
                    }.font(.subheadline)
                    if paused || scenePhase != .active {
                        Button(model.t("common.resume")) { paused = false }
                            .frame(maxWidth: .infinity).frame(height: viewportHeight)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        ZoomBoard(size: natural) {
                            MinesGrid(board: board, tap: { i in
                                // Deliberately bypass legacy board.mode, without changing its Codable field.
                                if model.editMines({ $0.reveal(i) }) { model.feedback() }
                            }, flag: { i in
                                if model.editMines({ $0.toggleFlag(i) }) { model.feedback() }
                            }).environmentObject(model)
                        }.frame(height: viewportHeight).background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Text(model.t("mines.controls")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 16).padding(.top, 8)
            }
        }.background(Color(.systemGroupedBackground))
            .localizedNavigation().navigationTitle(model.gameTitle(.minesweeper)).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(model.t("common.restart")) { restart = true }.accessibilityIdentifier("mines.restart") }
            .confirmationDialog(model.t("mines.restart.confirm"), isPresented: $restart, titleVisibility: .visible) {
                Button(model.t("common.restart"), role: .destructive) {
                    if let config = model.mines?.configuration, model.saveMines(MinesweeperBoard(configuration: config)) { paused = false }
                }.accessibilityIdentifier("mines.confirmRestart")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
            .modifier(GameplayActivity(game: .minesweeper, active: !paused && !restart && model.mines?.isFinished == false))
            .onAppear { visible = true }.onDisappear { visible = false }
            .onReceive(timer) { _ in
                if visible && !paused && !restart && scenePhase == .active && model.mines?.status == .playing { model.editMines { $0.elapsedSeconds += 1 } }
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
                        ZStack {
                            Rectangle().fill(Color(open ? .systemGray5 : .systemGray3))
                            Rectangle().strokeBorder(open ? Color.primary.opacity(0.12) : Color.primary.opacity(0.2), lineWidth: open ? 0.5 : 1.5)
                            if board.status == .lost && board.mines.contains(i) { Image(systemName: "burst.fill") }
                            else if marked { Image(systemName: "flag.fill") }
                            else if open && board.adjacentMines(i) > 0 {
                                Text("\(board.adjacentMines(i))").font(.system(size: 18, weight: .bold, design: .monospaced))
                            }
                        }.foregroundStyle(.primary).frame(width: 34, height: 34).contentShape(Rectangle())
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
