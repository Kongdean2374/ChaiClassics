import SwiftUI
import ChaiCore

struct MemoryMenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var mode = MemoryBoard.Mode.easy
    @State private var play = false
    @State private var confirm = false

    private func start() {
        if model.saveMemory(MemoryBoard(mode: mode)) { play = true }
    }

    var body: some View {
        Form {
            Section {
                GameIntroHeader(game: .memory, title: model.gameTitle(.memory), subtitle: model.t("memory.menu.intro"))
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            if let board = model.memory {
                Section(model.t("menu.lastGame")) {
                    Button { play = true } label: {
                        ContinueCard(title: model.t(board.isComplete ? "menu.viewLast" : "menu.continue"),
                                     detail: model.t("memory.summary", board.mode.columns, board.mode.rows,
                                                     board.matchedPairCount, board.mode.pairCount, board.moves)
                                        + " · " + model.t("common.seconds", board.elapsedSeconds))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("memory.continue")
                }
            }
            Section(model.t("menu.newGame")) {
                ForEach(MemoryBoard.Mode.allCases, id: \.self) { option in
                    Button { mode = option } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.t("difficulty." + option.rawValue)).font(.headline)
                                Text(model.t("memory.mode.detail", option.columns, option.rows, option.pairCount))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: mode == option ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(GamePalette.tint(.memory)).accessibilityHidden(true)
                        }.foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(.vertical, 4).contentShape(Rectangle())
                    }.buttonStyle(QuietPressStyle())
                        .accessibilityAddTraits(mode == option ? [.isSelected] : [])
                        .accessibilityIdentifier("memory.mode." + option.rawValue)
                }
                Button { if model.memory != nil { confirm = true } else { start() } } label: {
                    Label(model.t("menu.start"), systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44).padding(.vertical, 8)
                        .foregroundStyle(.primary)
                        .background(GamePalette.tint(.memory).opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                        .contentShape(Rectangle())
                }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("memory.start")
                    .disabled(model.blocked.contains(.memory))
                    .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
            }
            Section(model.t("memory.rules.title")) {
                Text(model.t("memory.rules")).fixedSize(horizontal: false, vertical: true)
            }
        }.scrollContentBackground(.hidden).background(GameCanvas()).tint(GamePalette.tint(.memory))
            .localizedNavigation().navigationTitle(model.gameTitle(.memory)).navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $play) { MemoryPlayView() }
            .confirmationDialog(model.t("memory.replace.confirm"), isPresented: $confirm, titleVisibility: .visible) {
                Button(model.t("menu.startNew"), role: .destructive) { start() }.accessibilityIdentifier("memory.confirmNew")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
    }
}

private struct MemoryResolutionKey: Hashable {
    let session: UUID
    let seed: UInt64
    let moves: Int
    let selection: [Int]
    let active: Bool
}

struct MemoryPlayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var paused = false
    @State private var restart = false
    @State private var newDeck = false
    @State private var session = UUID()

    private var active: Bool {
        !paused && !restart && !newDeck && scenePhase == .active && model.memory?.isComplete == false
    }
    private var resolutionKey: MemoryResolutionKey? {
        guard let board = model.memory else { return nil }
        return MemoryResolutionKey(session: session, seed: board.seed, moves: board.moves,
                                   selection: board.selectedIndices, active: active)
    }

    private func settle() { model.editMemory { $0.settleUnmatchedCards() } }
    private func togglePause() {
        if !paused { settle() }
        paused.toggle()
    }
    private func restartDeck() {
        session = UUID()
        if model.editMemory({ $0.restart() }) { paused = false }
    }
    private func startNewDeck() {
        guard let mode = model.memory?.mode else { return }
        if model.saveMemory(MemoryBoard(mode: mode)) { session = UUID(); paused = false }
    }

    var body: some View {
        ScrollView {
            if let board = model.memory {
                VStack(spacing: 16) {
                    MemoryPlayHeader(board: board, paused: paused, togglePause: togglePause)
                    if board.isComplete {
                        GameResultBanner(game: .memory, title: model.t("status.completed"),
                                         detail: model.t("memory.result.complete", board.moves, board.elapsedSeconds),
                                         won: true, identifier: "memory.complete")
                    }
                    if paused || scenePhase != .active {
                        PauseCard(game: .memory) { paused = false }.frame(minHeight: 280)
                    } else {
                        // At 320 pt: (320 - 24 outer - 8 inner - 20 gaps) / 6 = 44.7 pt.
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 44), spacing: 4),
                                                count: board.mode.columns), spacing: 4) {
                            ForEach(board.cards.indices, id: \.self) { index in
                                MemoryCard(index: index, board: board) {
                                    if model.editMemory({ $0.select(index) }) { model.feedback() }
                                }
                            }
                        }.padding(4)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(GamePalette.tint(.memory).opacity(0.18), lineWidth: 1).allowsHitTesting(false))
                            .accessibilityIdentifier("memory.board")
                    }
                    Text(model.t("memory.controls")).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Button {
                        if board.isComplete { startNewDeck() } else { newDeck = true }
                    } label: {
                        Label(model.t(board.isComplete ? "memory.playAgain" : "memory.newDeck"), systemImage: "shuffle")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 44).padding(.vertical, 5)
                            .background(GamePalette.tint(.memory).opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                            .contentShape(Rectangle())
                    }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("memory.newDeck")
                }.padding(.horizontal, 12).padding(.vertical, 16)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
        }.background(GameCanvas()).tint(GamePalette.tint(.memory))
            .localizedNavigation().navigationTitle(model.gameTitle(.memory)).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button(model.t("common.restart")) { restart = true }.accessibilityIdentifier("memory.restart")
            }
            .confirmationDialog(model.t("memory.restart.confirm"), isPresented: $restart, titleVisibility: .visible) {
                Button(model.t("common.restart"), role: .destructive) { restartDeck() }
                    .accessibilityIdentifier("memory.confirmRestart")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
            .confirmationDialog(model.t("memory.newDeck.confirm"), isPresented: $newDeck, titleVisibility: .visible) {
                Button(model.t("memory.newDeck"), role: .destructive) { startNewDeck() }
                    .accessibilityIdentifier("memory.confirmNewDeck")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
            .gameCompletionCelebration(completed: model.memory?.isComplete == true)
            .modifier(GameplayActivity(game: .memory, active: active))
            .modifier(SessionTimer(active: active, tick: { model.editMemory { $0.elapsedSeconds += 1 } }))
            .onAppear { settle() }
            .onDisappear { settle() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { settle(); paused = true }
            }
            .task(id: resolutionKey) {
                guard active, let board = model.memory, board.phase == .mismatch else { return }
                let expectedSession = session, expectedSeed = board.seed
                let expectedMoves = board.moves, expectedSelection = board.selectedIndices
                do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
                guard !Task.isCancelled, active, session == expectedSession,
                      model.memory?.seed == expectedSeed else { return }
                model.editMemory { $0.resolveMismatch(expectedMoves: expectedMoves, expectedSelection: expectedSelection) }
            }
    }
}

private struct MemoryPlayHeader: View {
    let board: MemoryBoard
    let paused: Bool
    let togglePause: () -> Void
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var tint: Color { GamePalette.tint(.memory) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                GameArtwork(game: .memory, size: 40)
                Text(model.t("memory.board.title", board.mode.columns, board.mode.rows))
                    .font(.system(.headline, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(action: togglePause) {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.semibold)).frame(width: 44, height: 44)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                }.buttonStyle(QuietPressStyle()).accessibilityLabel(model.t(paused ? "common.resume" : "common.pause"))
                    .accessibilityIdentifier("memory.pause").disabled(board.isComplete)
            }
            LazyVGrid(columns: [GridItem(dynamicTypeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 138), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                GameMetric(symbol: "rectangle.on.rectangle", value: model.t("memory.pairs", board.matchedPairCount, board.mode.pairCount),
                           tint: tint, identifier: "memory.pairs")
                GameMetric(symbol: "hand.tap", value: model.t("memory.moves", board.moves), tint: tint, identifier: "memory.moves")
                GameMetric(symbol: "timer", value: model.t("common.seconds", board.elapsedSeconds), tint: tint, identifier: "memory.timer")
            }
        }
    }
}

private struct MemoryCard: View {
    let index: Int
    let board: MemoryBoard
    let reveal: () -> Void
    @EnvironmentObject var model: AppModel
    @Environment(\.gameReducedMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    private var faceUp: Bool { board.isFaceUp(index) }
    private var isMatched: Bool { board.matched[index] }
    private var tint: Color { GamePalette.tint(.memory) }

    private var spokenLabel: String {
        let row = index / board.mode.columns + 1, column = index % board.mode.columns + 1
        guard faceUp else { return model.t("memory.card.hidden", row, column) }
        return model.t(isMatched ? "memory.card.matched" : "memory.card.revealed", row, column,
                       model.t("memory.symbol.\(board.cards[index])"))
    }

    var body: some View {
        Button(action: reveal) {
            GeometryReader { geometry in
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(faceUp ? Color(.secondarySystemGroupedBackground) : tint.opacity(colorScheme == .dark ? 0.24 : 0.12))
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(tint.opacity(isMatched ? 0.55 : 0.23), lineWidth: isMatched ? 2 : 1)
                    Group {
                        if faceUp {
                            Image(systemName: MemoryBoard.symbols[board.cards[index]])
                        } else {
                            Image(systemName: "questionmark")
                        }
                    }.font(.system(size: min(40, geometry.size.width * 0.46), weight: .semibold))
                        .foregroundStyle(tint).frame(maxWidth: .infinity, maxHeight: .infinity)
                    if isMatched {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: min(15, geometry.size.width * 0.25), weight: .semibold))
                            .foregroundStyle(tint).padding(3)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }.aspectRatio(1, contentMode: .fit)
        }.buttonStyle(.plain).disabled(!board.canSelect(index))
            .accessibilityLabel(spokenLabel)
            .accessibilityHint(board.canSelect(index) ? model.t("memory.card.hint") : "")
            .accessibilityIdentifier("memory.card.\(index)")
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: faceUp)
    }
}
