import SwiftUI
import ChaiCore

struct ConnectFourMenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var mode = DuelMode.singlePlayer
    @State private var difficulty = DuelDifficulty.normal
    @State private var humanPlayer = DuelPlayer.first
    @State private var play = false
    @State private var confirm = false
    private var tint: Color { GamePalette.tint(.connectFour) }

    private func start() {
        var random = SystemRandomNumberGenerator()
        let next = model.connectFour?.newRound(mode: mode, difficulty: difficulty, humanPlayer: humanPlayer, seed: random.next())
            ?? ConnectFourBoard(mode: mode, difficulty: difficulty, humanPlayer: humanPlayer, seed: random.next())
        if model.saveConnectFour(next) {
            model.updateGameSettings(for: .connectFour) {
                $0.duelMode = mode.rawValue
                $0.duelDifficulty = difficulty.rawValue
                $0.humanPlayer = humanPlayer.rawValue
            }
            model.startNewSession(.connectFour)
            play = true
        }
    }

    var body: some View {
        Form {
            Section {
                GameIntroHeader(game: .connectFour, title: model.gameTitle(.connectFour), subtitle: model.t("connectfour.intro"))
                    .padding(.vertical, 8).listRowBackground(Color.clear)
            }
            if let board = model.connectFour {
                Section(model.t("menu.lastGame")) {
                    ContinueGameRow(game: .connectFour, action: { model.beginContinuing(.connectFour); play = true }) {
                        ContinueCard(title: model.t(board.isFinished ? "menu.viewLast" : "menu.continue"),
                                     detail: model.t("connectfour.moves", board.moves) + " · " + model.t("common.seconds", board.elapsedSeconds))
                    }
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
                Button { confirm = true } label: {
                    Label(model.t("menu.start"), systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15).contentShape(Rectangle())
                        .foregroundStyle(.primary).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("connectfour.start")
                    .disabled(model.blocked.contains(.connectFour))
            }
        }.scrollContentBackground(.hidden).background(GameCanvas()).tint(tint)
            .localizedNavigation().navigationTitle(model.gameTitle(.connectFour)).navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $play) { ConnectFourPlayView() }
            .onAppear {
                let settings = model.gameSettings(for: .connectFour)
                mode = DuelMode(rawValue: settings.duelMode) ?? .singlePlayer
                difficulty = DuelDifficulty(rawValue: settings.duelDifficulty) ?? .normal
                humanPlayer = DuelPlayer(rawValue: settings.humanPlayer) ?? .first
            }
            // Settings change only the next-round choices, never the saved board.
            .onChange(of: model.gameSettings(for: .connectFour).duelMode) { _, value in mode = DuelMode(rawValue: value) ?? .singlePlayer }
            .onChange(of: model.gameSettings(for: .connectFour).duelDifficulty) { _, value in difficulty = DuelDifficulty(rawValue: value) ?? .normal }
            .onChange(of: model.gameSettings(for: .connectFour).humanPlayer) { _, value in humanPlayer = DuelPlayer(rawValue: value) ?? .first }
            .gameMenuSettings(.connectFour)
            .newGameConfirmation(.connectFour, isPresented: $confirm) { start() }
    }
}

struct ConnectFourPlayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.gameReducedMotion) private var reduceMotion
    @State private var visible = false
    @State private var generation = UUID()
    @State private var presentation = ConnectFourPresentation()

    private struct ComputerTaskID: Hashable {
        let generation: UUID
        let seed: UInt64
        let history: [Int]
        let active: Bool
    }
    private var interactive: Bool { visible && scenePhase == .active && model.sessionIsPlaying(.connectFour) }
    private var computerTaskID: ComputerTaskID {
        ComputerTaskID(generation: generation, seed: model.connectFour?.seed ?? 0,
                       history: model.connectFour?.history ?? [],
                       active: active && !presentation.isDropping && model.connectFour?.isComputerTurn == true)
    }
    private var active: Bool { interactive && model.connectFour?.isFinished == false }

    var body: some View {
        ScrollView {
            if let board = model.connectFour {
                VStack(spacing: 18) {
                    header(board)
                    ConnectFourGrid(board: board, acceptsInput: active && !presentation.isDropping && !board.isComputerTurn,
                                    falling: presentation.drop, reduceMotion: reduceMotion, settled: finishDrop) { column in
                        guard active, !presentation.isDropping,
                              let current = model.connectFour, !current.isComputerTurn else { return }
                        acceptDrop(column, on: current)
                    }
                    Text(model.t("connectfour.controls")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(16).frame(maxWidth: 580).frame(maxWidth: .infinity)
            }
        }.background(GameCanvas()).tint(GamePalette.tint(.connectFour))
            .gameSessionScreen(.connectFour, resultReady: !presentation.isDropping)
            .onAppear { visible = true }
            .onDisappear { visible = false; invalidatePresentation() }
            .onChange(of: interactive) { _, value in if !value { invalidatePresentation() } }
            .onChange(of: reduceMotion) { _, _ in invalidatePresentation() }
            .task(id: computerTaskID) { await computerMove() }
    }

    @ViewBuilder private func header(_ board: ConnectFourBoard) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                GameArtwork(game: .connectFour, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.t("connectfour.mode." + board.mode.rawValue)).font(.headline)
                    ZStack(alignment: .leading) {
                        if board.mode == .singlePlayer {
                            Text(model.t("connectfour.turn.human")).hidden().accessibilityHidden(true)
                            Text(model.t("connectfour.turn.computerMove")).hidden().accessibilityHidden(true)
                        }
                        Text(board.isFinished ? "" : turnTitle(board))
                            .accessibilityIdentifier("connectfour.turn")
                    }.font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .transaction { $0.animation = nil }
                }
                Spacer(minLength: 4)
            }
            // Both labels reserve their full natural height. Entering/leaving the
            // computer turn changes opacity, never the grid's position.
            ZStack(alignment: .leading) {
                Text(model.t("connectfour.thinking")).hidden().accessibilityHidden(true)
                Text(model.t("connectfour.dropping")).hidden().accessibilityHidden(true)
                Text(model.t(presentation.isDropping ? "connectfour.dropping" : "connectfour.thinking"))
                    .opacity(interactive && (presentation.isDropping || board.isComputerTurn) ? 1 : 0)
                    .accessibilityHidden(!interactive || (!presentation.isDropping && !board.isComputerTurn))
                    .accessibilityIdentifier(presentation.isDropping ? "connectfour.dropping" : "connectfour.thinking")
            }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transaction { $0.animation = nil }
            HStack {
                GameMetric(symbol: "circle.grid.3x3", value: model.t("connectfour.moves", board.moves), tint: GamePalette.tint(.connectFour), identifier: "connectfour.moves")
                Spacer(minLength: 4)
            }.transaction { $0.animation = nil }
        }
    }

    private func turnTitle(_ board: ConnectFourBoard) -> String {
        if board.mode == .singlePlayer { return model.t(board.isComputerTurn ? "connectfour.turn.computerMove" : "connectfour.turn.human") }
        return model.t("connectfour.turn.player", board.currentPlayer.rawValue)
    }

    /// The accepted board reaches disk before the visual piece starts falling.
    /// Presentation is separate so pause/navigation settles that piece safely.
    @MainActor private func acceptDrop(_ column: Int, on before: ConnectFourBoard) {
        guard active, !presentation.isDropping, model.connectFour == before else { return }
        var after = before
        guard after.drop(in: column, player: before.currentPlayer) else { return }
        withTransaction(Transaction(animation: nil)) {
            if model.saveConnectFour(after) {
                presentation.begin(before: before, after: after)
                model.feedback(for: .connectFour)
            }
        }
    }

    @MainActor private func finishDrop(_ drop: ConnectFourPresentation.Drop) {
        guard interactive, presentation.drop == drop,
              model.connectFour?.history == drop.history else { return }
        withTransaction(Transaction(animation: nil)) { _ = presentation.settle(id: drop.id) }
    }

    @MainActor private func invalidatePresentation() {
        withTransaction(Transaction(animation: nil)) {
            generation = UUID()
            presentation.cancel()
        }
    }

    /// One stable request owns both computation and its minimum response time.
    /// Its clock starts after the preceding disc lands, never during that drop.
    @MainActor private func computerMove() async {
        let request = computerTaskID
        guard request.active, let snapshot = model.connectFour else { return }
        let clock = ContinuousClock()
        let earliestResponse = clock.now.advanced(by: .milliseconds(450))
        let worker = Task.detached(priority: .userInitiated) { snapshot.recommendedMove() }
        let column = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        do { try await clock.sleep(until: earliestResponse) }
        catch { return }
        guard !Task.isCancelled, computerTaskID == request, interactive, !presentation.isDropping, let column,
              let current = model.connectFour, current.seed == snapshot.seed,
              current.history == snapshot.history, current.mode == snapshot.mode,
              current.difficulty == snapshot.difficulty, current.humanPlayer == snapshot.humanPlayer,
              current.isComputerTurn else { return }
        acceptDrop(column, on: current)
    }
}

private struct ConnectFourGrid: View {
    @EnvironmentObject var model: AppModel
    let board: ConnectFourBoard
    let acceptsInput: Bool
    let falling: ConnectFourPresentation.Drop?
    let reduceMotion: Bool
    let settled: (ConnectFourPresentation.Drop) -> Void
    let drop: (Int) -> Void

    var body: some View {
        let cells = board.cells
        let winning = falling == nil ? Set(board.winningLine) : Set<Int>()
        HStack(alignment: .top, spacing: 4) {
            ForEach(0..<7, id: \.self) { column in
                Button { drop(column) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "arrow.down").font(.caption.weight(.semibold))
                            .frame(height: 22).foregroundStyle(GameMaterial.ivory.opacity(0.9))
                        ForEach(0..<6, id: \.self) { row in
                            let index = row * 7 + column
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [Color.black.opacity(0.65), GameMaterial.navy], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .overlay {
                                        Circle().strokeBorder(GameMaterial.ivory.opacity(0.10), lineWidth: 1).padding(2)
                                    }
                                if let player = cells[index], falling?.column != column || falling?.row != row {
                                    ConnectFourDisc(player: player)
                                }
                                Circle().strokeBorder(winning.contains(index) ? GameMaterial.ivory : GameMaterial.gold.opacity(0.40), lineWidth: winning.contains(index) ? 3 : 1)
                                if winning.contains(index) {
                                    Circle().strokeBorder(GameMaterial.gold, lineWidth: 1).padding(4)
                                }
                            }.aspectRatio(1, contentMode: .fit)
                        }
                    }.frame(maxWidth: .infinity).padding(.vertical, 5).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .disabled(!acceptsInput || !board.canDrop(in: column))
                    .accessibilityLabel(columnLabel(column, cells: cells))
                    .accessibilityHint(model.t(board.canDrop(in: column) ? "connectfour.column.hint" : "connectfour.column.full"))
                    .accessibilityIdentifier("connectfour.column.\(column)")
            }
        }.overlay {
            GeometryReader { geometry in
                if let falling {
                    let side = max(1, (geometry.size.width - 24) / 7)
                    let destination = 32 + CGFloat(falling.row) * (side + 5) + side / 2
                    ConnectFourFallingDisc(drop: falling, distance: destination - side / 2,
                                           reduceMotion: reduceMotion, settled: settled)
                        .frame(width: side, height: side)
                        .position(x: CGFloat(falling.column) * (side + 4) + side / 2, y: destination)
                        .id(falling.id)
                }
            }.allowsHitTesting(false).accessibilityHidden(true)
        }.padding(14)
            .background(GameBoardSurface(game: .connectFour))
    }

    private func columnLabel(_ column: Int, cells: [DuelPlayer?]) -> String {
        let slots = (0..<6).map { row in
            model.t(board.winningLine.contains(row * 7 + column) ? "connectfour.slot.winning" : "connectfour.slot", row + 1, model.t(cells[row * 7 + column].map { "connectfour.piece.\($0.rawValue)" } ?? "connectfour.empty"))
        }.joined(separator: ", ")
        return model.t("connectfour.column", column + 1) + ": " + slots
    }
}

private struct ConnectFourDisc: View {
    let player: DuelPlayer
    private var colors: [Color] {
        player == .first
            ? [GameMaterial.ivory, Color(red: 1, green: 0.76, blue: 0.26), GameMaterial.gold]
            : [Color(red: 1, green: 0.75, blue: 0.58), GameMaterial.coral, Color(red: 0.76, green: 0.20, blue: 0.15)]
    }
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().strokeBorder(GameMaterial.gold, lineWidth: 1.2)
                Circle().strokeBorder(GameMaterial.ivory.opacity(0.6), lineWidth: 1).padding(max(2, side * 0.07))
                Image(systemName: player == .first ? "star.fill" : "circle.fill")
                    .resizable().scaledToFit().padding(side * 0.27)
                    .foregroundStyle(GameMaterial.navy)
                    .shadow(color: GameMaterial.ivory.opacity(0.45), radius: 0, y: 0.7)
            }
        }.shadow(color: .black.opacity(0.3), radius: 1, y: 2)
    }
}

private struct ConnectFourFallingDisc: View {
    let drop: ConnectFourPresentation.Drop
    let distance: CGFloat
    let reduceMotion: Bool
    let settled: (ConnectFourPresentation.Drop) -> Void
    @State private var landed = false
    private var duration: Double { 0.28 + Double(drop.row) * 0.028 }
    var body: some View {
        ConnectFourDisc(player: drop.player)
            .offset(y: reduceMotion || landed ? 0 : -distance)
            .opacity(reduceMotion && !landed ? 0 : 1)
            .onAppear {
                let animation: Animation = reduceMotion ? .easeInOut(duration: 0.12)
                    : .timingCurve(0.42, 0, 1, 1, duration: duration)
                withAnimation(animation, completionCriteria: .removed) { landed = true } completion: { settled(drop) }
            }
    }
}
