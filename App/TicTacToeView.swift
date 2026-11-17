import SwiftUI
import ChaiCore

struct TicTacToeMenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var mode = DuelMode.singlePlayer
    @State private var difficulty = DuelDifficulty.normal
    @State private var humanPlayer = DuelPlayer.first
    @State private var play = false
    @State private var confirm = false
    private var tint: Color { GamePalette.tint(.ticTacToe) }

    private func start() {
        let next = model.ticTacToe?.newGame(mode: mode, difficulty: difficulty, humanPlayer: humanPlayer)
            ?? TicTacToeBoard(mode: mode, difficulty: difficulty, humanPlayer: humanPlayer)
        if model.saveTicTacToe(next) {
            model.updateGameSettings(for: .ticTacToe) {
                $0.duelMode = mode.rawValue
                $0.duelDifficulty = difficulty.rawValue
                $0.humanPlayer = humanPlayer.rawValue
            }
            model.startNewSession(.ticTacToe)
            play = true
        }
    }

    var body: some View {
        Form {
            Section {
                GameIntroHeader(game: .ticTacToe, title: model.gameTitle(.ticTacToe), subtitle: model.t("tictactoe.intro"))
                    .padding(.vertical, 8).listRowBackground(Color.clear)
                Text(model.t("tictactoe.rules")).font(.subheadline).foregroundStyle(.secondary)
            }
            if let board = model.ticTacToe {
                Section(model.t("menu.lastGame")) {
                    ContinueGameRow(game: .ticTacToe, action: { model.beginContinuing(.ticTacToe); play = true }) {
                        ContinueCard(title: model.t(board.isFinished ? "menu.viewLast" : "menu.continue"),
                                     detail: model.t("tictactoe.moves", board.moves) + " · " + model.t("common.seconds", board.elapsedSeconds))
                    }
                }
            }
            Section(model.t("menu.newGame")) {
                Picker(model.t("tictactoe.mode"), selection: $mode) {
                    ForEach(DuelMode.allCases, id: \.self) { Text(model.t("tictactoe.mode." + $0.rawValue)).tag($0) }
                }.accessibilityIdentifier("tictactoe.mode")
                if mode == .singlePlayer {
                    Picker(model.t("tictactoe.difficulty"), selection: $difficulty) {
                        ForEach(DuelDifficulty.allCases, id: \.self) { Text(model.t("difficulty." + $0.rawValue)).tag($0) }
                    }.accessibilityIdentifier("tictactoe.difficulty")
                    Picker(model.t("tictactoe.first"), selection: $humanPlayer) {
                        Text(model.t("tictactoe.first.human")).tag(DuelPlayer.first)
                        Text(model.t("tictactoe.first.computer")).tag(DuelPlayer.second)
                    }.accessibilityIdentifier("tictactoe.first")
                    Text(model.t("tictactoe.difficulty.detail")).font(.caption).foregroundStyle(.secondary)
                }
                Button { confirm = true } label: {
                    Label(model.t("menu.start"), systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15).contentShape(Rectangle())
                        .foregroundStyle(.primary).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("tictactoe.start")
                    .disabled(model.blocked.contains(.ticTacToe))
            }
        }.scrollContentBackground(.hidden).background(GameCanvas()).tint(tint)
            .localizedNavigation().navigationTitle(model.gameTitle(.ticTacToe)).navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $play) { TicTacToePlayView() }
            .onAppear {
                let settings = model.gameSettings(for: .ticTacToe)
                mode = DuelMode(rawValue: settings.duelMode) ?? .singlePlayer
                difficulty = DuelDifficulty(rawValue: settings.duelDifficulty) ?? .normal
                humanPlayer = DuelPlayer(rawValue: settings.humanPlayer) ?? .first
            }
            // Settings change only the next-round choices, never the saved board.
            .onChange(of: model.gameSettings(for: .ticTacToe).duelMode) { _, value in mode = DuelMode(rawValue: value) ?? .singlePlayer }
            .onChange(of: model.gameSettings(for: .ticTacToe).duelDifficulty) { _, value in difficulty = DuelDifficulty(rawValue: value) ?? .normal }
            .onChange(of: model.gameSettings(for: .ticTacToe).humanPlayer) { _, value in humanPlayer = DuelPlayer(rawValue: value) ?? .first }
            .gameMenuSettings(.ticTacToe)
            .newGameConfirmation(.ticTacToe, isPresented: $confirm) { start() }
    }
}

struct TicTacToePlayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var turnGeneration = UUID()
    private var tint: Color { GamePalette.tint(.ticTacToe) }
    private var active: Bool { visible && scenePhase == .active && model.sessionIsPlaying(.ticTacToe) && model.ticTacToe?.isFinished == false }
    private var aiRequest: String? {
        guard active, let board = model.ticTacToe, board.isComputerTurn else { return nil }
        return turnGeneration.uuidString + ":" + board.sessionID.uuidString + ":" + board.history.map(String.init).joined(separator: ",")
    }
    var body: some View {
        ScrollView {
            if let board = model.ticTacToe {
                VStack(spacing: 18) {
                    header(board)
                    TicTacToeGrid(board: board, enabled: active) { index in
                        guard let current = model.ticTacToe,
                              current.canHumanPlay(at: index, active: active) else { return }
                        if model.editTicTacToe({ _ = $0.play(at: index, by: current.currentPlayer) }) { model.feedback(for: .ticTacToe) }
                    }
                    Text(model.t("tictactoe.controls")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(16).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
        }.background(GameCanvas()).tint(tint)
            .gameSessionScreen(.ticTacToe)
            .onAppear { visible = true }
            .onDisappear { visible = false; turnGeneration = UUID() }
            .onChange(of: active) { _, value in if !value { turnGeneration = UUID() } }
            .task(id: aiRequest) { await computerMove() }
    }

    /// The response deadline runs alongside the bounded search. Even a one-step
    /// win remains visible as a computer turn, without blocking the main actor.
    @MainActor private func computerMove() async {
        guard let request = aiRequest, let snapshot = model.ticTacToe else { return }
        let clock = ContinuousClock()
        let responseDeadline = clock.now.advanced(by: .seconds(0.45))
        let computation = Task.detached(priority: .userInitiated) { snapshot.computerMove() }
        do {
            let move = try await withTaskCancellationHandler(operation: {
                let choice = await computation.value
                try await clock.sleep(until: responseDeadline)
                return choice
            }, onCancel: { computation.cancel() })
            guard !Task.isCancelled, aiRequest == request, let move,
                  let current = model.ticTacToe, current.sessionID == snapshot.sessionID,
                  current.history == snapshot.history, current.isComputerTurn else { return }
            if model.editTicTacToe({ _ = $0.play(at: move, by: snapshot.currentPlayer) }) { model.feedback(for: .ticTacToe) }
        } catch {
            // Pause, background, navigation and restart cancel the pending turn.
        }
    }

    private func playerName(_ player: DuelPlayer, board: TicTacToeBoard) -> String {
        if board.mode == .singlePlayer { return model.t(player == board.humanPlayer ? "tictactoe.you" : "tictactoe.computer") }
        return model.t(player == .first ? "tictactoe.player1" : "tictactoe.player2")
    }
    private func header(_ board: TicTacToeBoard) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.t("tictactoe.mode." + board.mode.rawValue)).font(.headline)
                    ZStack(alignment: .leading) {
                        // Reserve both possible turn labels at large text sizes.
                        Text(model.t("tictactoe.turn", playerName(.first, board: board), "X")).hidden().accessibilityHidden(true)
                        Text(model.t("tictactoe.turn", playerName(.second, board: board), "O")).hidden().accessibilityHidden(true)
                        Text(board.isFinished ? "" : model.t("tictactoe.turn", playerName(board.currentPlayer, board: board), board.currentPlayer == .first ? "X" : "O"))
                            .accessibilityIdentifier("tictactoe.turn")
                    }.font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        .transaction { $0.animation = nil }
                    // Keep exactly the same layout on human and computer turns.
                    Text(model.t("tictactoe.thinking")).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(board.isComputerTurn && active ? 1 : 0)
                        .accessibilityHidden(!board.isComputerTurn || !active)
                        .accessibilityIdentifier("tictactoe.thinking")
                }
                Spacer(minLength: 4)
            }
            HStack {
                GameMetric(symbol: "hand.tap", value: model.t("tictactoe.moves", board.moves), tint: tint, identifier: "tictactoe.moves")
                Spacer(minLength: 4)
            }
        }
    }
}

private struct TicTacToeGrid: View {
    let board: TicTacToeBoard
    let enabled: Bool
    let move: (Int) -> Void
    @EnvironmentObject var model: AppModel
    @Environment(\.gameReducedMotion) private var reduceMotion
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(0..<9, id: \.self) { index in
                let value = board.cells[index]
                let winning = board.winningLine.contains(index)
                Button { move(index) } label: {
                    ZStack {
                        TicTacToeEnamelTile(winning: winning)
                        TicTacToePiece(player: value ?? .first)
                            .opacity(value == nil ? 0 : 1)
                            // Only a changed mark fades; timer updates never animate the board.
                            .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.16), value: value)
                            .accessibilityHidden(true)
                        if winning {
                            Image(systemName: "checkmark.seal.fill").font(.caption.weight(.bold))
                                .foregroundStyle(GameMaterial.ivory)
                                .background(GameMaterial.navy, in: Circle())
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(8)
                        }
                    }.aspectRatio(1, contentMode: .fit).contentShape(Rectangle())
                }.buttonStyle(QuietPressStyle()).disabled(!board.canHumanPlay(at: index, active: enabled))
                    .accessibilityLabel(model.t("tictactoe.cell", index / 3 + 1, index % 3 + 1, value == .first ? "X" : value == .second ? "O" : model.t("tictactoe.empty")))
                    .accessibilityValue(winning ? model.t("tictactoe.winningCell") : "")
                    .accessibilityIdentifier("tictactoe.cell.\(index)")
            }
        }.overlay {
            if board.winningLine.count == 3 {
                GeometryReader { geometry in
                    let stride = (geometry.size.width + 8) / 3
                    let half = (geometry.size.width - 16) / 6
                    let start = board.winningLine[0], end = board.winningLine[2]
                    Path { path in
                        path.move(to: CGPoint(x: CGFloat(start % 3) * stride + half, y: CGFloat(start / 3) * stride + half))
                        path.addLine(to: CGPoint(x: CGFloat(end % 3) * stride + half, y: CGFloat(end / 3) * stride + half))
                    }.stroke(GameMaterial.ivory.opacity(0.88), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .shadow(color: GameMaterial.gold.opacity(0.8), radius: 1)
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        }.padding(14).background(GameBoardSurface(game: .ticTacToe))
    }
}

/// A recessed enamel square matches the illustrated cabinet while the marks
/// remain crisp native vectors at every device size and appearance.
private struct TicTacToeEnamelTile: View {
    let winning: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(LinearGradient(colors: [GameMaterial.navy, GameMaterial.teal.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(GameMaterial.gold.opacity(winning ? 1 : 0.42), lineWidth: winning ? 2.5 : 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13).strokeBorder(GameMaterial.ivory.opacity(0.10), lineWidth: 1).padding(3)
            }
            .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct TicTacToePiece: View {
    let player: DuelPlayer
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let stroke = max(4, side * 0.105)
            let colors = player == .first
                ? [GameMaterial.ivory, Color(red: 1, green: 0.77, blue: 0.29), GameMaterial.gold]
                : [Color(red: 1, green: 0.76, blue: 0.60), GameMaterial.coral, Color(red: 0.77, green: 0.20, blue: 0.16)]
            ZStack {
                TicTacToeMark(cross: player == .first)
                    .stroke(GameMaterial.navy, style: StrokeStyle(lineWidth: stroke + 3, lineCap: .round, lineJoin: .round))
                    .offset(y: 2)
                TicTacToeMark(cross: player == .first)
                    .stroke(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
            }.shadow(color: .black.opacity(0.24), radius: 1, y: 2)
        }
    }
}

private struct TicTacToeMark: Shape {
    let cross: Bool
    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: rect.width * 0.25, dy: rect.height * 0.25)
        var path = Path()
        if cross {
            path.move(to: CGPoint(x: inset.minX, y: inset.minY))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
            path.move(to: CGPoint(x: inset.maxX, y: inset.minY))
            path.addLine(to: CGPoint(x: inset.minX, y: inset.maxY))
        } else { path.addEllipse(in: inset) }
        return path
    }
}
