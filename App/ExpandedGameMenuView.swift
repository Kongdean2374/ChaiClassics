import SwiftUI
import ChaiCore

struct ExpandedGameMenuView: View {
    let game: GameID
    @EnvironmentObject private var model: AppModel
    @State private var difficulty = DuelDifficulty.normal
    @State private var mode = DuelMode.singlePlayer
    @State private var human = DuelPlayer.first
    @State private var options = ExpandedGamePreferences()
    @State private var play = false
    @State private var confirm = false
    @State private var preparing = false
    @State private var prepared: ExpandedGameSave?
    @State private var preparation: Task<Void,Never>?
    @State private var requestID: UUID?
    private var tint: Color { GamePalette.tint(game) }
    var body: some View {
        Form {
            Section {
                GameIntroHeader(game:game,title:model.gameTitle(game),subtitle:model.t("catalog.description."+game.rawValue))
                    .padding(.vertical,8).listRowBackground(Color.clear)
            }
            if let board = model.expandedGames[game] {
                Section(model.t("menu.lastGame")) {
                    ContinueGameRow(game:game,action:{ model.beginContinuing(game); play = true }) {
                        ContinueCard(title:model.t(board.outcome == nil ? "menu.continue" : "menu.viewLast"),
                                     detail:model.t("expanded.moves",board.state.moves)+" · "+GameRecordText.duration(board.elapsedSeconds))
                    }
                }
            }
            Section(model.t("menu.newGame")) {
                if SolitaireVariant(rawValue:game.rawValue)==nil {
                    Picker(model.t("connectfour.difficulty"),selection:$difficulty) {
                        ForEach(DuelDifficulty.allCases,id:\.self) { Text(model.t("difficulty."+$0.rawValue)).tag($0) }
                    }.accessibilityIdentifier(game.rawValue+".difficulty")
                }
                if game.isStrategy {
                    Picker(model.t("gameSettings.duel.mode"),selection:$mode) {
                        ForEach(DuelMode.allCases,id:\.self) { Text(model.t("tictactoe.mode."+$0.rawValue)).tag($0) }
                    }.accessibilityIdentifier(game.rawValue+".mode")
                    if mode == .singlePlayer {
                        Picker(model.t("gameSettings.duel.first"),selection:$human) {
                            Text(model.t("gameSettings.duel.humanFirst")).tag(DuelPlayer.first)
                            Text(model.t("gameSettings.duel.computerFirst")).tag(DuelPlayer.second)
                        }.accessibilityIdentifier(game.rawValue+".first")
                    }
                }
                ExpandedOptionsControls(game:game,options:$options)
                Button(action:prepare) {
                    HStack {
                        if preparing { ProgressView() } else { Image(systemName:"play.fill") }
                        Text(model.t(preparing ? "expanded.preparing" : "menu.start"))
                    }.font(.headline).frame(maxWidth:.infinity).padding(.vertical,15)
                        .background(tint.opacity(0.14),in:RoundedRectangle(cornerRadius:16))
                }.buttonStyle(QuietPressStyle()).accessibilityIdentifier(game.rawValue+".start")
                    .disabled(preparing || model.blocked.contains(game))
            }.disabled(preparing)
            Section(model.t("expanded.rules")) {
                Text(model.t("rules."+game.rawValue)).font(.subheadline).fixedSize(horizontal:false,vertical:true)
                    .accessibilityIdentifier(game.rawValue+".rules")
            }
        }.scrollContentBackground(.hidden).background(GameCanvas()).tint(tint)
            .navigationTitle(model.gameTitle(game)).navigationBarTitleDisplayMode(.inline).localizedNavigation()
            .navigationDestination(isPresented:$play) { ExpandedGamePlayView(game:game) }
            .loadGameDefaultsOnce(loadDefaults)
            .onChange(of:model.gameSettings(for:game)) { _,_ in loadDefaults() }
            .onDisappear { preparation?.cancel(); requestID = nil; preparing = false }
            .gameMenuSettings(game)
            .newGameConfirmation(game,isPresented:$confirm) {
                guard let prepared, model.saveExpanded(prepared) else { return }
                model.updateGameSettings(for:game) { prefs in
                    prefs.duelMode = mode.rawValue; prefs.duelDifficulty = difficulty.rawValue
                    prefs.humanPlayer = human.rawValue; prefs.expanded = options
                }
                model.startNewSession(game); play = true
            }
    }
    private func loadDefaults() {
        let prefs = model.gameSettings(for:game)
        difficulty = DuelDifficulty(rawValue:prefs.duelDifficulty) ?? .normal
        mode = DuelMode(rawValue:prefs.duelMode) ?? .singlePlayer
        human = DuelPlayer(rawValue:prefs.humanPlayer) ?? .first; options = prefs.expanded ?? .init()
    }
    private func prepare() {
        guard !preparing else { return }; let token = UUID(); requestID = token; preparing = true
        let game = game, level = difficulty, mode = mode, human = human, options = options
        preparation = Task { @MainActor in
            let worker = Task.detached(priority:.userInitiated) { () -> ExpandedGameSave? in
                var random = SystemRandomNumberGenerator()
                return ExpandedGameSave(game:game,seed:random.next(),difficulty:level,mode:mode,humanPlayer:human,options:options)
            }
            let result = await withTaskCancellationHandler(operation:{ await worker.value },onCancel:{ worker.cancel() })
            guard !Task.isCancelled, requestID==token else { return }
            preparing = false; requestID = nil
            guard let result, result.isValidSave else { model.notice = .puzzleCreation; return }
            prepared = result; confirm = true
        }
    }
}

struct ExpandedOptionsControls: View {
    let game: GameID
    @Binding var options: ExpandedGamePreferences
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Group {
            if game == .klondike {
                Picker(model.t("expanded.drawCount"),selection:$options.drawCount) {
                    Text(model.t("expanded.drawOne")).tag(1); Text(model.t("expanded.drawThree")).tag(3)
                }.accessibilityIdentifier("expanded.drawCount")
            }
            if game == .spider {
                Picker(model.t("expanded.spiderSuits"),selection:$options.spiderSuits) {
                    ForEach([1,2,4],id:\.self) { Text(model.t("expanded.suitCount",$0)).tag($0) }
                }.accessibilityIdentifier("expanded.spiderSuits")
            }
            if game.isStrategy {
                Toggle(model.t("expanded.legalMoves"),isOn:$options.showLegalMoves).accessibilityIdentifier("expanded.legalMoves")
            }
            if game == .fallingBlocks {
                Toggle(model.t("expanded.ghost"),isOn:$options.showGhost).accessibilityIdentifier("expanded.ghost")
            }
        }
    }
}

struct ExpandedGamePlayView: View {
    let game: GameID
    var body: some View {
        Group {
            if game.isStrategy { ExpandedStrategyView(game:game) }
            else if SolitaireVariant(rawValue:game.rawValue) != nil { ExpandedSolitaireView(game:game) }
            else if [.snake,.fallingBlocks,.brickBreaker].contains(game) { ExpandedArcadeView(game:game) }
            else { ExpandedPuzzleView(game:game) }
        }.background {
            if SolitaireVariant(rawValue: game.rawValue) != nil { SolitaireFelt() }
            else { GameCanvas() }
        }.tint(GamePalette.tint(game))
            .gameSessionScreen(game,resultReady:true)
    }
}
