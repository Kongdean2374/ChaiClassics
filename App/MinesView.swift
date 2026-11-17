import SwiftUI
import ChaiCore

struct MinesMenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var showPlay = false
    @State private var layout = 0
    @State private var width = 9
    @State private var height = 9
    @State private var mineCount = 10
    @State private var confirmNew = false
    private var configuration: MineConfiguration? { try? MineConfiguration(width: width, height: height, mines: mineCount) }
    private func start() {
        guard let configuration else { return }
        if model.saveMines(MinesweeperBoard(configuration: configuration)) {
            model.startNewSession(.minesweeper)
            showPlay = true
        }
    }
    private func selectLayout(_ value: Int) {
        layout = value
        let presets: [MineConfiguration] = [.easy, .medium, .hard]
        guard presets.indices.contains(value) else { return }
        let preset = presets[value]
        width = preset.width; height = preset.height; mineCount = preset.mineCount
    }
    private func loadNewGameDefaults() {
        let preferences = model.gameSettings(for: .minesweeper)
        width = preferences.minesWidth
        height = preferences.minesHeight
        mineCount = preferences.minesCount
        switch (width, height) {
        case (9, 9): layout = 0
        case (16, 16): layout = 1
        case (30, 16): layout = 2
        default: layout = 3
        }
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
                    ContinueGameRow(game: .minesweeper, action: {
                        model.beginContinuing(.minesweeper)
                        showPlay = true
                    }) {
                        ContinueCard(title: model.t(board.isFinished ? "menu.viewLast" : "menu.continue"),
                                     detail: model.summaryDetail(.mines(board)) + " · " + model.t("status." + model.summary(.minesweeper).state.rawValue))
                    }
                }
            }
            Section(model.t("mines.chooseSize")) {
                Picker(model.t("mines.chooseSize"), selection: Binding(get: { layout }, set: selectLayout)) {
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
                Button { confirmNew = true } label: {
                    Label(model.t("menu.start"), systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                        .foregroundStyle(.primary)
                        .background(GamePalette.tint(.minesweeper).opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(GamePalette.tint(.minesweeper).opacity(0.3), lineWidth: 1).allowsHitTesting(false))
                }.buttonStyle(QuietPressStyle()).disabled(configuration == nil || model.blocked.contains(.minesweeper)).accessibilityIdentifier("mines.start")
                    .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                Text(model.t("mines.randomExplanation")).font(.footnote).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden).background(GameCanvas()).tint(GamePalette.tint(.minesweeper))
            .localizedNavigation().navigationTitle(model.gameTitle(.minesweeper)).navigationBarTitleDisplayMode(.inline)
            .gameMenuSettings(.minesweeper)
            .loadGameDefaultsOnce { loadNewGameDefaults() }
            .onChange(of: [model.gameSettings(for: .minesweeper).minesWidth,
                           model.gameSettings(for: .minesweeper).minesHeight,
                           model.gameSettings(for: .minesweeper).minesCount]) { _, _ in loadNewGameDefaults() }
            .onChange(of: width) { _, _ in mineCount = min(mineCount, width * height - 1) }
            .onChange(of: height) { _, _ in mineCount = min(mineCount, width * height - 1) }
            .navigationDestination(isPresented: $showPlay) { MinesPlayView() }
            .newGameConfirmation(.minesweeper, isPresented: $confirmNew) { start() }
    }
}

struct MinesPlayView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        GeometryReader { geometry in
            if let board = model.mines {
                let natural = CGSize(width: CGFloat(board.configuration.width * 34), height: CGFloat(board.configuration.height * 34))
                let width = max(1, geometry.size.width - 32)
                let compact = board.configuration.width <= 9 && board.configuration.height <= 9
                // A maximum, not a fixed reservation: the native viewport takes
                // the space left by the header and status.
                let maxViewportHeight = compact ? min(width * natural.height / natural.width, natural.height * 1.7) : natural.height
                MinesPlaySurface(board: board, naturalSize: natural, maxViewportHeight: maxViewportHeight,
                                 tap: { i in
                                     guard model.sessionIsPlaying(.minesweeper), !board.isFinished else { return }
                                     // Deliberately bypass legacy board.mode, without changing its Codable field.
                                     if model.editMines({ $0.reveal(i) }) { model.feedback(for: .minesweeper) }
                                 }, flag: { i in
                                     guard model.sessionIsPlaying(.minesweeper), !board.isFinished else { return }
                                     if model.editMines({ $0.toggleFlag(i) }) { model.feedback(for: .minesweeper) }
                                 })
            }
        }.background(GameCanvas()).tint(GamePalette.tint(.minesweeper))
            .navigationTitle(model.gameTitle(.minesweeper)).navigationBarTitleDisplayMode(.inline)
            .gameSessionScreen(.minesweeper)
    }
}

private struct MinesPlaySurface: View {
    let board: MinesweeperBoard
    let naturalSize: CGSize
    let maxViewportHeight: CGFloat
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
            }.fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            HStack {
                SessionBadge(state: GameSummary.mines(board).state, title: model.t("status." + GameSummary.mines(board).state.rawValue))
                Spacer(minLength: 8)
            }.fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            boardViewport.frame(maxWidth: .infinity, minHeight: 0, maxHeight: maxViewportHeight)
            Text(model.t("mines.controls")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
        }.padding(.horizontal, 16).padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    private var boardViewport: some View {
        ZoomBoard(size: naturalSize) {
            MinesGrid(board: board, enabled: model.sessionIsPlaying(.minesweeper) && !board.isFinished, tap: tap, flag: flag)
                .environmentObject(model)
        }.background { GameBoardSurface(game: .minesweeper, cornerRadius: 12) }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(GameMaterial.gold.opacity(0.8), lineWidth: 1.2).allowsHitTesting(false))
            .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }
}

private struct MinesGrid: View {
    let board: MinesweeperBoard
    let enabled: Bool
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
                                guard enabled else { return }
                                switch value { case .first: flag(i); case .second: tap(i) }
                            })
                            .accessibilityElement().accessibilityAddTraits(.isButton)
                            .accessibilityLabel(model.t("mines.cell.label", row + 1, col + 1, marked ? model.t("mines.flagged") : open ? model.t("mines.revealed", board.adjacentMines(i)) : model.t("mines.covered")))
                            .accessibilityValue(model.t(marked ? "mines.flagged" : open ? "mines.revealed.value" : "mines.covered"))
                            .accessibilityHint(model.t("mines.cell.hint"))
                            .accessibilityAction { if enabled { tap(i) } }
                            .accessibilityAction(named: model.t(marked ? "mines.unflag" : "mines.flag")) { if enabled { flag(i) } }
                            .accessibilityIdentifier("mines.cell.\(i)")
                            .disabled(!enabled)
                    }
                }
            }
        }.background(GameMaterial.navy).allowsHitTesting(enabled)
    }
}

private struct MinesCellFace: View {
    let board: MinesweeperBoard
    let index: Int
    private var open: Bool { board.revealed.contains(index) }
    private var exploded: Bool { board.status == .lost && board.exploded == index }
    private var clueColor: Color {
        switch board.adjacentMines(index) {
        case 1: return Color(red: 0.08, green: 0.30, blue: 0.75)
        case 2: return Color(red: 0.13, green: 0.45, blue: 0.33)
        case 3: return Color(red: 0.75, green: 0.17, blue: 0.13)
        case 4: return Color(red: 0.33, green: 0.26, blue: 0.69)
        case 5: return Color(red: 0.58, green: 0.29, blue: 0.16)
        case 6: return Color(red: 0.08, green: 0.43, blue: 0.49)
        default: return GameMaterial.ink
        }
    }
    var body: some View {
        ZStack {
            if open {
                Rectangle().fill(GameMaterial.ivory)
                Rectangle().fill(exploded ? GameMaterial.coral.opacity(0.24) : GameMaterial.teal.opacity(0.10))
                Rectangle().strokeBorder(GameMaterial.teal.opacity(0.38), lineWidth: 0.6)
            } else {
                GameTileSurface(game: .minesweeper, cornerRadius: 4).padding(1)
            }
            if board.status == .lost && board.mines.contains(index) {
                Image(systemName: "burst.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(GameMaterial.ink)
            } else if board.flags.contains(index) {
                Image(systemName: "flag.fill").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GameMaterial.coral)
            } else if open && board.adjacentMines(index) > 0 {
                Text("\(board.adjacentMines(index))").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(clueColor)
            }
        }
    }
}
