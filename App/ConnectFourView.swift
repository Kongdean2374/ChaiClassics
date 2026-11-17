import SwiftUI
import ChaiCore

struct ConnectFourMenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var mode = DuelMode.singlePlayer
    @State private var difficulty = DuelDifficulty.normal
    @State private var humanPlayer = DuelPlayer.first
    @State private var play = false
    @State private var confirm = false
    @State private var clearRecords = false
    @State private var loadedSettings = false

    private func start() {
        var random = SystemRandomNumberGenerator()
        let next = model.connectFour?.newRound(mode: mode, difficulty: difficulty, humanPlayer: humanPlayer, seed: random.next())
            ?? ConnectFourBoard(mode: mode, difficulty: difficulty, humanPlayer: humanPlayer, seed: random.next())
        if model.saveConnectFour(next) { play = true }
    }

    var body: some View {
        Form {
            Section {
                GameIntroHeader(game: .connectFour, title: model.gameTitle(.connectFour), subtitle: model.t("connectfour.intro"))
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            if let board = model.connectFour {
                Section(model.t("menu.lastGame")) {
                    Button { play = true } label: {
                        ContinueCard(title: model.t(board.isFinished ? "menu.viewLast" : "menu.continue"),
                                     detail: model.t("connectfour.moves", board.moves) + " · " + model.t("common.seconds", board.elapsedSeconds))
                            .contentShape(Rectangle())
                    }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("connectfour.continue")
                }
            }
            Section(model.t("menu.newGame")) {
                Picker(model.t("connectfour.mode"), selection: $mode) {
                    ForEach(DuelMode.allCases, id: \.self) { Text(model.t("connectfour.mode." + $0.rawValue)).tag($0) }
                }.accessibilityIdentifier("connectfour.mode")
                if mode == .singlePlayer {
                    Picker(model.t("connectfour.difficulty"), selection: $difficulty) {
                        ForEach(DuelDifficulty.allCases, id: \.self) { Text(model.t("difficulty." + $0.rawValue)).tag($0) }
                    }.accessibilityIdentifier("connectfour.difficulty")
                    Picker(model.t("connectfour.first"), selection: $humanPlayer) {
                        Text(model.t("connectfour.first.human")).tag(DuelPlayer.first)
                        Text(model.t("connectfour.first.computer")).tag(DuelPlayer.second)
                    }.accessibilityIdentifier("connectfour.first")
                    Text(model.t("connectfour.ai." + difficulty.rawValue)).font(.caption).foregroundStyle(.secondary)
                }
                Button { if model.connectFour != nil { confirm = true } else { start() } } label: {
                    Label(model.t("menu.start"), systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                        .foregroundStyle(.primary)
                        .background(GamePalette.tint(.connectFour).opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                        .contentShape(Rectangle())
                }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("connectfour.start")
                    .disabled(model.blocked.contains(.connectFour))
            }
            if let board = model.connectFour {
                Section(model.t("connectfour.records")) {
                    Text(model.t("connectfour.records.values", board.statistics.wins, board.statistics.draws, board.statistics.losses))
                        .accessibilityIdentifier("connectfour.statistics")
                    Text(model.t("connectfour.records.explanation")).font(.caption).foregroundStyle(.secondary)
                    Button(model.t("connectfour.records.clear"), role: .destructive) { clearRecords = true }
                        .accessibilityIdentifier("connectfour.clearStatistics")
                }
            }
        }.scrollContentBackground(.hidden).background(GameCanvas()).tint(GamePalette.tint(.connectFour))
            .localizedNavigation().navigationTitle(model.gameTitle(.connectFour)).navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $play) { ConnectFourPlayView() }
            .onAppear {
                if !loadedSettings, let board = model.connectFour {
                    mode = board.mode; difficulty = board.difficulty; humanPlayer = board.humanPlayer
                }
                loadedSettings = true
            }
            .confirmationDialog(model.t("connectfour.replace.confirm"), isPresented: $confirm, titleVisibility: .visible) {
                Button(model.t("menu.startNew"), role: .destructive) { start() }.accessibilityIdentifier("connectfour.confirmNew")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
            .confirmationDialog(model.t("connectfour.records.confirm"), isPresented: $clearRecords, titleVisibility: .visible) {
                Button(model.t("connectfour.records.clear"), role: .destructive) { model.editConnectFour { $0.clearStatistics() } }
                    .accessibilityIdentifier("connectfour.confirmClearStatistics")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
    }
}

struct ConnectFourPlayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var paused = false
    @State private var visible = false
    @State private var restart = false

    private struct ComputerTaskID: Hashable {
        let seed: UInt64
        let history: [Int]
        let active: Bool
    }
    private var computerTaskID: ComputerTaskID {
        ComputerTaskID(seed: model.connectFour?.seed ?? 0, history: model.connectFour?.history ?? [],
                       active: visible && !paused && !restart && scenePhase == .active && model.connectFour?.isComputerTurn == true)
    }
    private var active: Bool { !paused && !restart && model.connectFour?.isFinished == false }

    var body: some View {
        ScrollView {
            if let board = model.connectFour {
                VStack(spacing: 18) {
                    header(board)
                    if board.isFinished {
                        GameResultBanner(game: .connectFour, title: resultTitle(board), detail: model.t(board.isDraw ? "connectfour.result.draw" : "connectfour.result.line"),
                                         won: board.winner == (board.mode == .singlePlayer ? board.humanPlayer : .first), identifier: "connectfour.result")
                    }
                    if paused || scenePhase != .active {
                        PauseCard(game: .connectFour) { paused = false }.frame(height: 300)
                    } else {
                        ConnectFourGrid(board: board, acceptsInput: visible && !restart && !board.isComputerTurn) { column in
                            guard !paused, !restart, scenePhase == .active, visible, !board.isComputerTurn else { return }
                            if model.editConnectFour({ $0.drop(in: column, player: board.currentPlayer) }) { model.feedback() }
                        }
                    }
                    Text(model.t("connectfour.controls")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text(model.t("connectfour.records.values", board.statistics.wins, board.statistics.draws, board.statistics.losses))
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("connectfour.statistics")
                    if board.isFinished {
                        Button { model.editConnectFour { $0.restart() }; paused = false } label: {
                            Label(model.t("connectfour.replay"), systemImage: "arrow.clockwise")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12).contentShape(Rectangle())
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("connectfour.replay")
                    }
                }.padding(16).frame(maxWidth: 580).frame(maxWidth: .infinity)
            }
        }.background(GameCanvas()).tint(GamePalette.tint(.connectFour))
            .localizedNavigation().navigationTitle(model.gameTitle(.connectFour)).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button(model.t("common.restart")) { restart = true }.accessibilityIdentifier("connectfour.restart")
            }
            .confirmationDialog(model.t("connectfour.restart.confirm"), isPresented: $restart, titleVisibility: .visible) {
                Button(model.t("common.restart"), role: .destructive) {
                    model.editConnectFour { $0.restart() }; paused = false
                }.accessibilityIdentifier("connectfour.confirmRestart")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
            .modifier(GameplayActivity(game: .connectFour, active: active))
            .modifier(SessionTimer(active: active, tick: { model.editConnectFour { $0.elapsedSeconds += 1 } }))
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .task(id: computerTaskID) { await computerMove() }
    }

    private func resultTitle(_ board: ConnectFourBoard) -> String {
        guard let winner = board.winner else { return model.t("connectfour.draw") }
        if board.mode == .singlePlayer { return model.t(winner == board.humanPlayer ? "connectfour.youWon" : "connectfour.computerWon") }
        return model.t("connectfour.playerWon", winner.rawValue)
    }

    @ViewBuilder private func header(_ board: ConnectFourBoard) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                GameArtwork(game: .connectFour, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.t("connectfour.mode." + board.mode.rawValue)).font(.headline)
                    Text(board.isFinished ? resultTitle(board) : turnTitle(board))
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("connectfour.turn")
                }
                Spacer(minLength: 4)
                Button { paused.toggle() } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.semibold)).frame(width: 44, height: 44)
                        .background(GamePalette.tint(.connectFour).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(QuietPressStyle()).disabled(board.isFinished)
                    .accessibilityLabel(model.t(paused ? "common.resume" : "common.pause"))
                    .accessibilityIdentifier("connectfour.pause")
            }
            HStack {
                GameMetric(symbol: "circle.grid.3x3", value: model.t("connectfour.moves", board.moves), tint: GamePalette.tint(.connectFour), identifier: "connectfour.moves")
                Spacer(minLength: 4)
                GameMetric(symbol: "timer", value: model.t("common.seconds", board.elapsedSeconds), tint: GamePalette.tint(.connectFour), identifier: "connectfour.timer")
            }
        }
    }

    private func turnTitle(_ board: ConnectFourBoard) -> String {
        if board.mode == .singlePlayer { return model.t(board.isComputerTurn ? "connectfour.turn.computer" : "connectfour.turn.human") }
        return model.t("connectfour.turn.player", board.currentPlayer.rawValue)
    }

    /// The background result is committed only if this task and its original
    /// board are still current. Pause, background, navigation and restart cancel it.
    @MainActor private func computerMove() async {
        guard computerTaskID.active, let snapshot = model.connectFour else { return }
        let worker = Task.detached(priority: .userInitiated) { snapshot.recommendedMove() }
        let column = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        guard !Task.isCancelled, computerTaskID.active, let column,
              let current = model.connectFour, current.seed == snapshot.seed,
              current.history == snapshot.history, current.mode == snapshot.mode,
              current.difficulty == snapshot.difficulty, current.humanPlayer == snapshot.humanPlayer,
              current.isComputerTurn else { return }
        if model.editConnectFour({ $0.drop(in: column, player: snapshot.currentPlayer) }) { model.feedback() }
    }
}

private struct ConnectFourGrid: View {
    @EnvironmentObject var model: AppModel
    let board: ConnectFourBoard
    let acceptsInput: Bool
    let drop: (Int) -> Void

    var body: some View {
        let cells = board.cells
        let winning = Set(board.winningLine)
        HStack(alignment: .top, spacing: 4) {
            ForEach(0..<7, id: \.self) { column in
                Button { drop(column) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "arrow.down").font(.caption.weight(.semibold))
                            .frame(height: 22).foregroundStyle(GamePalette.tint(.connectFour))
                        ForEach(0..<6, id: \.self) { row in
                            let index = row * 7 + column
                            ZStack {
                                Circle().fill(Color(.secondarySystemGroupedBackground))
                                if let player = cells[index] {
                                    Circle().fill((player == .first ? Color.orange : Color.blue).opacity(0.22))
                                    Image(systemName: player == .first ? "star.fill" : "circle.fill")
                                        .resizable().scaledToFit().padding(11)
                                        .foregroundStyle(player == .first ? Color.orange : Color.blue)
                                }
                                Circle().strokeBorder(winning.contains(index) ? Color.primary : GamePalette.tint(.connectFour).opacity(0.2), lineWidth: winning.contains(index) ? 3 : 1)
                            }.aspectRatio(1, contentMode: .fit)
                        }
                    }.frame(maxWidth: .infinity).padding(.vertical, 5).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .disabled(!acceptsInput || !board.canDrop(in: column))
                    .accessibilityLabel(columnLabel(column, cells: cells))
                    .accessibilityHint(model.t(board.canDrop(in: column) ? "connectfour.column.hint" : "connectfour.column.full"))
                    .accessibilityIdentifier("connectfour.column.\(column)")
            }
        }.padding(9)
            .background(GamePalette.tint(.connectFour).opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(GamePalette.tint(.connectFour).opacity(0.2), lineWidth: 1).allowsHitTesting(false))
    }

    private func columnLabel(_ column: Int, cells: [DuelPlayer?]) -> String {
        let slots = (0..<6).map { row in
            model.t(board.winningLine.contains(row * 7 + column) ? "connectfour.slot.winning" : "connectfour.slot", row + 1, model.t(cells[row * 7 + column].map { "connectfour.piece.\($0.rawValue)" } ?? "connectfour.empty"))
        }.joined(separator: ", ")
        return model.t("connectfour.column", column + 1) + ": " + slots
    }
}
