import SwiftUI
import ChaiCore

struct SlidingMenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var size = 3
    @State private var difficulty = SlidingBoard.Difficulty.normal
    @State private var play = false
    @State private var confirm = false
    private func start() {
        do {
            if model.saveSliding(try SlidingBoard(size: size, difficulty: difficulty)) {
                model.startNewSession(.sliding)
                play = true
            }
        }
        catch { model.notice = .puzzleCreation }
    }
    private func loadNewGameDefaults() {
        let preferences = model.gameSettings(for: .sliding)
        size = preferences.slidingSize
        difficulty = SlidingBoard.Difficulty(rawValue: preferences.slidingDifficulty) ?? .normal
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
                    ContinueGameRow(game: .sliding, action: {
                        model.beginContinuing(.sliding)
                        play = true
                    }) {
                        ContinueCard(title: model.t(board.isComplete ? "menu.viewLast" : "menu.continue"),
                                     detail: model.summaryDetail(.sliding(board)) + " · " + model.t("common.seconds", board.elapsedSeconds))
                    }
                }
            }
            Section(model.t("menu.newGame")) {
                Picker(model.t("sliding.size"), selection: $size) { ForEach(3...5, id: \.self) { Text("\($0)×\($0)").tag($0) } }
                    .pickerStyle(.segmented).accessibilityIdentifier("sliding.size")
                Picker(model.t("sliding.difficulty"), selection: $difficulty) {
                    ForEach(SlidingBoard.Difficulty.allCases, id: \.self) { Text(model.t("difficulty." + $0.rawValue)).tag($0) }
                }
                Button { confirm = true } label: {
                    Label(model.t("menu.start"), systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                        .foregroundStyle(.primary)
                        .background(GamePalette.tint(.sliding).opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(GamePalette.tint(.sliding).opacity(0.3), lineWidth: 1).allowsHitTesting(false))
                }.buttonStyle(QuietPressStyle()).disabled(model.blocked.contains(.sliding)).accessibilityIdentifier("sliding.start")
                    .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
            }
        }.scrollContentBackground(.hidden).background(GameCanvas()).tint(GamePalette.tint(.sliding))
            .localizedNavigation().navigationTitle(model.gameTitle(.sliding)).navigationBarTitleDisplayMode(.inline)
            .gameMenuSettings(.sliding)
            .onAppear { loadNewGameDefaults() }
            .onChange(of: model.gameSettings(for: .sliding).slidingSize) { _, _ in loadNewGameDefaults() }
            .onChange(of: model.gameSettings(for: .sliding).slidingDifficulty) { _, _ in loadNewGameDefaults() }
            .navigationDestination(isPresented: $play) { SlidingPlayView() }
            .newGameConfirmation(.sliding, isPresented: $confirm) { start() }
    }
}

struct SlidingPlayView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            if let board = model.sliding {
                VStack(spacing: 18) {
                    SlidingPlayHeader(board: board)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: board.size), spacing: 6) {
                        ForEach(board.tiles.indices, id: \.self) { i in
                            SlidingTile(index: i, board: board, enabled: model.sessionIsPlaying(.sliding) && !board.isComplete) {
                                guard model.sessionIsPlaying(.sliding), !board.isComplete else { return }
                                if model.editSliding({ $0.move(i) }) { model.feedback(for: .sliding) }
                            }
                        }
                    }.padding(12)
                        .background { GameBoardSurface(game: .sliding) }
                        .shadow(color: .black.opacity(0.07), radius: 22, y: 9)
                    Text(model.t("sliding.controls")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(16).frame(maxWidth: 540).frame(maxWidth: .infinity)
            }
        }.background(GameCanvas()).tint(GamePalette.tint(.sliding))
            .navigationTitle(model.gameTitle(.sliding)).navigationBarTitleDisplayMode(.inline)
            .gameSessionScreen(.sliding)
    }
}

private struct SlidingPlayHeader: View {
    let board: SlidingBoard
    @EnvironmentObject var model: AppModel
    private var tint: Color { GamePalette.tint(.sliding) }
    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 11) {
                GameArtwork(game: .sliding, size: 42)
                Text(model.t("sliding.boardTitle", board.size, board.size, model.t("difficulty." + board.difficulty.rawValue)))
                    .font(.system(.headline, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
            }
            HStack {
                GameMetric(symbol: "square.grid.2x2", value: model.t("sliding.moves", board.moves), tint: tint, identifier: "sliding.moves")
                Spacer(minLength: 8)
            }
        }
    }
}

private struct SlidingTile: View {
    let index: Int
    let board: SlidingBoard
    let enabled: Bool
    let move: () -> Void
    @EnvironmentObject var model: AppModel
    @GestureState private var translation = CGSize.zero
    private func offset(step: CGFloat) -> CGSize {
        guard enabled else { return .zero }
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
            }.buttonStyle(.plain).disabled(!enabled || !board.canMove(index))
                .highPriorityGesture(DragGesture(minimumDistance: 10, coordinateSpace: .local)
                    .updating($translation) { value, state, _ in if enabled { state = value.translation } }
                    .onEnded { value in
                        guard enabled else { return }
                        if SlidingInput.accepts(tile: index, board: board, horizontal: Double(value.translation.width), vertical: Double(value.translation.height), minimumDistance: Double(max(18, geometry.size.width * 0.2))) { move() }
                    }, including: enabled ? .all : .none)
                .accessibilityLabel(board.tiles[index] == 0 ? model.t("sliding.blank") : model.t("sliding.tile", board.tiles[index]))
                .accessibilityHint(model.t("sliding.tile.hint"))
                .accessibilityIdentifier("sliding.tile.\(index)")
        }.aspectRatio(1, contentMode: .fit).zIndex(translation == .zero ? 0 : 1)
    }
}

private struct SlidingTileFace: View {
    let value: Int
    let side: CGFloat
    private var corner: CGFloat { min(18, max(10, side * 0.16)) }
    var body: some View {
        ZStack {
            if value == 0 {
                RoundedRectangle(cornerRadius: corner).fill(GameMaterial.navy.opacity(0.7))
                RoundedRectangle(cornerRadius: corner).strokeBorder(GameMaterial.gold.opacity(0.42), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            } else {
                GameTileSurface(game: .sliding, cornerRadius: corner)
                Text("\(value)")
                    .font(.system(size: min(42, max(24, side * 0.36)), weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(GameMaterial.ink)
            }
        }
    }
}
