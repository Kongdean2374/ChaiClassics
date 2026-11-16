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
            if let board = model.sliding {
                Section(model.t("menu.lastGame")) {
                    Button { play = true } label: {
                        ContinueCard(title: model.t(board.isComplete ? "menu.viewLast" : "menu.continue"),
                                     detail: model.summaryDetail(.sliding(board)) + " · " + model.t("common.seconds", board.elapsedSeconds))
                    }.accessibilityIdentifier("sliding.continue")
                }
            }
            Section(model.t("menu.newGame")) {
                Picker(model.t("sliding.size"), selection: $size) { ForEach(3...5, id: \.self) { Text("\($0)×\($0)").tag($0) } }
                    .pickerStyle(.segmented).accessibilityIdentifier("sliding.size")
                Picker(model.t("sliding.difficulty"), selection: $difficulty) {
                    ForEach(SlidingBoard.Difficulty.allCases, id: \.self) { Text(model.t("difficulty." + $0.rawValue)).tag($0) }
                }
                Button(model.t("menu.start")) { if model.sliding != nil { confirm = true } else { start() } }.accessibilityIdentifier("sliding.start")
            }
        }.localizedNavigation().navigationTitle(model.gameTitle(.sliding))
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
                    HStack {
                        Text(model.t("sliding.boardTitle", board.size, board.size, model.t("difficulty." + board.difficulty.rawValue)))
                        Spacer()
                        if board.isComplete { Text(model.t("status.completed")).fontWeight(.semibold).accessibilityIdentifier("sliding.complete") }
                    }.font(.subheadline)
                    HStack {
                        Text(model.t("sliding.moves", board.moves)).accessibilityIdentifier("sliding.moves")
                        Spacer()
                        Text(model.t("common.seconds", board.elapsedSeconds)).accessibilityIdentifier("sliding.timer")
                    }.font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    if paused || scenePhase != .active {
                        Button(model.t("common.resume")) { paused = false }.frame(height: 300).frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: board.size), spacing: 6) {
                            ForEach(board.tiles.indices, id: \.self) { i in
                                Button {
                                    if model.editSliding({ $0.move(i) }) { model.feedback() }
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 9).fill(board.tiles[i] == 0 ? Color.clear : Color(.secondarySystemGroupedBackground))
                                        if board.tiles[i] != 0 { Text("\(board.tiles[i])").font(.system(.title, design: .serif)).foregroundStyle(.primary) }
                                    }.aspectRatio(1, contentMode: .fit)
                                }.buttonStyle(.plain).disabled(!board.canMove(i))
                                    .accessibilityLabel(board.tiles[i] == 0 ? model.t("sliding.blank") : model.t("sliding.tile", board.tiles[i]))
                                    .accessibilityIdentifier("sliding.tile.\(i)")
                            }
                        }.padding(8).background(Color(.systemGray4), in: RoundedRectangle(cornerRadius: 14))
                    }
                    Button(model.t(paused ? "common.resume" : "common.pause"), systemImage: paused ? "play" : "pause") { paused.toggle() }
                        .buttonStyle(.bordered).accessibilityIdentifier("sliding.pause")
                }.padding(16).frame(maxWidth: 540).frame(maxWidth: .infinity)
            }
        }.background(Color(.systemGroupedBackground))
            .localizedNavigation().navigationTitle(model.gameTitle(.sliding)).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(model.t("common.restart")) { restart = true }.accessibilityIdentifier("sliding.restart") }
            .confirmationDialog(model.t("sliding.restart.confirm"), isPresented: $restart, titleVisibility: .visible) {
                Button(model.t("common.restart"), role: .destructive) { model.editSliding { $0.restart() }; paused = false }.accessibilityIdentifier("sliding.confirmRestart")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
            .modifier(GameplayActivity(game: .sliding, active: !paused && !restart && model.sliding?.isComplete == false))
            .onAppear { visible = true }.onDisappear { visible = false }
            .onReceive(timer) { _ in
                if visible && !paused && !restart && scenePhase == .active && model.sliding?.isComplete == false { model.editSliding { $0.elapsedSeconds += 1 } }
            }
    }
}
