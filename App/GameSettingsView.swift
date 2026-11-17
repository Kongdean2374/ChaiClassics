import SwiftUI
import ChaiCore

struct GameSettingsView: View {
    let game: GameID
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var dataOperationBusy = false
    @State private var showClearConfirmation = false
    @State private var clearRequest: UUID?
    @State private var clearFailed = false

    private var preferences: GamePlayPreferences { model.gameSettings(for: game) }
    private var snapshot: GameRunSnapshot { model.gameSnapshot(for: game) }
    private var statistics: GameStatistics { model.gameStatistics(for: game) }
    private var legacyStatistics: DuelStatistics? {
        guard game == .ticTacToe || game == .connectFour,
              let value = model.sessionData.legacyDuelStatistics[game],
              value.wins > 0 || value.draws > 0 || value.losses > 0 else { return nil }
        return value
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    GameArtwork(game: game, size: 48).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.gameTitle(game)).font(.headline)
                        Text(model.t("gameSettings.independent")).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6)
                Toggle(model.t("settings.haptics"), isOn: value(\.haptics))
                    .accessibilityIdentifier("gameSettings.haptics")
            } footer: {
                Text(model.t("gameSettings.haptics.detail"))
            }
            preferencesSection
            currentGameSection
            statisticsSection
            GameDataTransferSection(game: game, isBusy: $dataOperationBusy, locked: showClearConfirmation)
        }
        .scrollContentBackground(.hidden).background(GameCanvas()).tint(GamePalette.tint(game))
        .navigationTitle(model.t("gameSettings.title")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(model.t("common.done")) { dismiss() }.accessibilityIdentifier("gameSettings.done")
            }
        }
        .gameActionConfirmation(title: model.t("gameSettings.clear.title"),
                                message: model.t("gameSettings.clear.detail"),
                                isPresented: $showClearConfirmation,
                                confirmTitle: model.t("gameSettings.clear.confirm"), onConfirm: {
            guard clearRequest != nil else { return }
            clearRequest = nil
            clearFailed = !model.clearGameStatistics(game)
        }, onCancel: { clearRequest = nil })
    }

    @ViewBuilder private var preferencesSection: some View {
        Section {
            switch game {
            case .sudoku:
                Toggle(model.t("gameSettings.sudoku.pencil"), isOn: value(\.sudokuPencilByDefault))
                    .accessibilityIdentifier("gameSettings.sudoku.pencil")
            case .minesweeper:
                Stepper(model.t("mines.width", preferences.minesWidth), value: Binding(
                    get: { preferences.minesWidth }, set: { setMineDimensions(width: $0) }), in: 5...40)
                    .accessibilityIdentifier("gameSettings.mines.width")
                Stepper(model.t("mines.height", preferences.minesHeight), value: Binding(
                    get: { preferences.minesHeight }, set: { setMineDimensions(height: $0) }), in: 5...40)
                    .accessibilityIdentifier("gameSettings.mines.height")
                Stepper(model.t("mines.mineCount", preferences.minesCount), value: value(\.minesCount),
                        in: 1...max(1, preferences.minesWidth * preferences.minesHeight - 1))
                    .accessibilityIdentifier("gameSettings.mines.count")
            case .sliding:
                Picker(model.t("sliding.size"), selection: value(\.slidingSize)) {
                    ForEach(3...5, id: \.self) { Text("\($0)×\($0)").tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("gameSettings.sliding.size")
                difficultyPicker(selection: value(\.slidingDifficulty))
            case .ticTacToe, .connectFour:
                Picker(model.t("gameSettings.duel.mode"), selection: value(\.duelMode)) {
                    Text(model.t("tictactoe.mode.singlePlayer")).tag("singlePlayer")
                    Text(model.t("tictactoe.mode.localTwoPlayer")).tag("localTwoPlayer")
                }.accessibilityIdentifier("gameSettings.duel.mode")
                if preferences.duelMode == "singlePlayer" {
                    difficultyPicker(selection: value(\.duelDifficulty))
                    Picker(model.t("gameSettings.duel.first"), selection: value(\.humanPlayer)) {
                        Text(model.t("gameSettings.duel.humanFirst")).tag(1)
                        Text(model.t("gameSettings.duel.computerFirst")).tag(2)
                    }.accessibilityIdentifier("gameSettings.duel.first")
                }
            case .twentyFour:
                difficultyPicker(selection: value(\.twentyFourDifficulty))
            case .memory:
                difficultyPicker(selection: value(\.memoryMode))
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(model.t("gameSettings.memory.reveal"),
                                   value: model.t("gameSettings.memory.seconds", preferences.memoryRevealSeconds))
                    Slider(value: value(\.memoryRevealSeconds), in: 0.5...1.5, step: 0.05)
                        .accessibilityLabel(model.t("gameSettings.memory.reveal"))
                        .accessibilityIdentifier("gameSettings.memory.reveal")
                }
            case .maze:
                difficultyPicker(selection: value(\.mazeDifficulty))
                Picker(model.t("gameSettings.maze.speed"), selection: value(\.mazeSpeed)) {
                    Text(model.t("gameSettings.speed.slow")).tag(0.8)
                    Text(model.t("gameSettings.speed.normal")).tag(1.0)
                    Text(model.t("gameSettings.speed.fast")).tag(1.2)
                }.accessibilityIdentifier("gameSettings.maze.speed")
            default:
                if SolitaireVariant(rawValue:game.rawValue)==nil { difficultyPicker(selection:value(\.duelDifficulty)) }
                if game.isStrategy {
                    Picker(model.t("gameSettings.duel.mode"),selection:value(\.duelMode)) {
                        Text(model.t("tictactoe.mode.singlePlayer")).tag("singlePlayer")
                        Text(model.t("tictactoe.mode.localTwoPlayer")).tag("localTwoPlayer")
                    }.accessibilityIdentifier("gameSettings.duel.mode")
                    Picker(model.t("gameSettings.duel.first"),selection:value(\.humanPlayer)) {
                        Text(model.t("gameSettings.duel.humanFirst")).tag(1)
                        Text(model.t("gameSettings.duel.computerFirst")).tag(2)
                    }.accessibilityIdentifier("gameSettings.duel.first")
                }
                ExpandedOptionsControls(game:game,options:Binding(
                    get:{ preferences.expanded ?? .init() },
                    set:{ next in model.updateGameSettings(for:game){ $0.expanded = next } }))
            }
        } header: {
            Text(model.t("gameSettings.preferences"))
        } footer: {
            Text(model.t(game.isStrategy || game == .fallingBlocks ? "expanded.settings.detail" : game == .memory || game == .maze ? "gameSettings.live.detail" : "gameSettings.nextRound.detail"))
        }
    }

    private var currentGameSection: some View {
        Section(model.t("gameSettings.current")) {
            if snapshot.exists {
                LabeledContent(model.t("history.result"), value: snapshot.outcome.map { model.t("history.result." + $0.rawValue) }
                    ?? model.t(snapshot.ended ? "status.completed" : "status.inProgress"))
                LabeledContent(model.t("history.difficulty"), value: GameRecordText.difficulty(snapshot.difficulty, model: model))
                if !snapshot.mode.isEmpty {
                    LabeledContent(model.t("history.mode"), value: GameRecordText.mode(snapshot.mode, model: model))
                }
                LabeledContent(model.t("history.elapsed"), value: GameRecordText.duration(snapshot.elapsedSeconds))
                LabeledContent(model.t("history.moves.title"), value: String(snapshot.moves))
            } else {
                Text(model.t("gameSettings.current.empty")).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("gameSettings.current")
    }

    private var statisticsSection: some View {
        Section {
            LabeledContent(model.t("gameSettings.stats.total"), value: String(statistics.total))
            LabeledContent(model.t("history.result.won"), value: String(statistics.won))
            LabeledContent(model.t("history.result.completed"), value: String(statistics.completed))
            LabeledContent(model.t("history.result.lost"), value: String(statistics.lost))
            LabeledContent(model.t("history.result.draw"), value: String(statistics.draw))
            LabeledContent(model.t("history.result.abandoned"), value: String(statistics.abandoned))
            LabeledContent(model.t("gameSettings.stats.time"), value: GameRecordText.duration(statistics.elapsedSeconds))
            LabeledContent(model.t("gameSettings.stats.moves"), value: String(statistics.moves))
            LabeledContent(model.t("gameSettings.stats.best"),
                           value: statistics.bestTime.map(GameRecordText.duration) ?? model.t("history.unavailable"))
            if let legacy = legacyStatistics {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.t("gameSettings.stats.legacy.title")).font(.headline)
                    Text(model.t("gameSettings.stats.legacy.detail")).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 8)
                LabeledContent(model.t("history.result.won"), value: String(legacy.wins))
                    .accessibilityIdentifier("gameSettings.legacy.wins")
                LabeledContent(model.t("history.result.draw"), value: String(legacy.draws))
                    .accessibilityIdentifier("gameSettings.legacy.draws")
                LabeledContent(model.t("history.result.lost"), value: String(legacy.losses))
                    .accessibilityIdentifier("gameSettings.legacy.losses")
            }
            NavigationLink { PlayHistoryView(game: game) } label: {
                Label(model.t("history.title"), systemImage: "clock.arrow.circlepath")
            }.accessibilityIdentifier("gameSettings.history")
            Button(role: .destructive) {
                guard !dataOperationBusy, !showClearConfirmation, clearRequest == nil else { return }
                clearRequest = UUID(); showClearConfirmation = true; clearFailed = false
            } label: {
                Label(model.t("gameSettings.clear"), systemImage: "trash")
            }.disabled((statistics.total == 0 && legacyStatistics == nil) || dataOperationBusy || showClearConfirmation)
                .accessibilityIdentifier("gameSettings.clear")
            if clearFailed { Text(model.t("gameSettings.clear.failed")).font(.footnote).foregroundStyle(.orange) }
        } header: {
            Text(model.t("gameSettings.stats.title"))
        } footer: {
            Text(model.t("history.sinceUpdate"))
        }
    }

    private func difficultyPicker(selection: Binding<String>) -> some View {
        Picker(model.t("history.difficulty"), selection: selection) {
            ForEach(["easy", "normal", "hard"], id: \.self) { Text(model.t("difficulty." + $0)).tag($0) }
        }.accessibilityIdentifier("gameSettings.difficulty")
    }
    private func value<T>(_ keyPath: WritableKeyPath<GamePlayPreferences, T>) -> Binding<T> {
        Binding(get: { model.gameSettings(for: game)[keyPath: keyPath] },
                set: { newValue in model.updateGameSettings(for: game) { $0[keyPath: keyPath] = newValue } })
    }
    private func setMineDimensions(width: Int? = nil, height: Int? = nil) {
        model.updateGameSettings(for: game) {
            if let width { $0.minesWidth = width }
            if let height { $0.minesHeight = height }
            $0.minesCount = min($0.minesCount, $0.minesWidth * $0.minesHeight - 1)
        }
    }
}
