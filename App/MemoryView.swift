import SwiftUI
import ChaiCore

struct MemoryMenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var mode = MemoryBoard.Mode.easy
    @State private var play = false
    @State private var confirm = false

    private func start() {
        if model.saveMemory(MemoryBoard(mode: mode)) {
            model.startNewSession(.memory)
            play = true
        }
    }

    private func applyMenuDefaults() {
        mode = MemoryBoard.Mode(rawValue: model.gameSettings(for: .memory).memoryMode) ?? .easy
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
                    ContinueGameRow(game: .memory, action: {
                        model.beginContinuing(.memory)
                        play = true
                    }) {
                        ContinueCard(title: model.t(board.isComplete ? "menu.viewLast" : "menu.continue"),
                                     detail: model.t("memory.summary", board.mode.columns, board.mode.rows,
                                                     board.matchedPairCount, board.mode.pairCount, board.moves)
                                        + " · " + model.t("common.seconds", board.elapsedSeconds))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
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
                Button { confirm = true } label: {
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
            .gameMenuSettings(.memory)
            .newGameConfirmation(.memory, isPresented: $confirm) { start() }
            .onAppear { applyMenuDefaults() }
            .onChange(of: model.gameSettings(for: .memory).memoryMode) { _, _ in applyMenuDefaults() }
    }
}

private struct MemoryMismatchTurn: Hashable {
    let seed: UInt64
    let moves: Int
    let selection: [Int]
}

private struct MemoryHoldKey: Hashable {
    let token: UInt64
    let turn: MemoryMismatchTurn
    let deadline: TimeInterval
}

struct MemoryPlayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentation = MemoryTurnPresentation()
    @State private var mismatchTurn: MemoryMismatchTurn?
    @State private var holdDeadline: TimeInterval?
    @State private var turnRevealSeconds = MemoryTurnPresentation.mismatchHoldDuration

    private var presentationActive: Bool {
        model.sessionIsPlaying(.memory) && scenePhase == .active
    }
    private var active: Bool { presentationActive && model.memory?.isComplete == false }
    private var holdKey: MemoryHoldKey? {
        guard presentationActive, presentation.phase == .holding, let mismatchTurn, let holdDeadline else { return nil }
        return MemoryHoldKey(token: presentation.token, turn: mismatchTurn, deadline: holdDeadline)
    }

    private func cancelPresentation() { presentation.cancel(); mismatchTurn = nil; holdDeadline = nil }
    private func settle() {
        cancelPresentation()
        model.editMemory { $0.settleUnmatchedCards() }
    }
    private func select(_ index: Int) {
        guard active, presentation.acceptsSelection, var next = model.memory else { return }
        let secondSelection = next.selectedIndices.count == 1
        guard next.select(index), model.saveMemory(next) else { return }
        if secondSelection {
            let mismatch = next.phase == .mismatch ? next.selectedIndices : []
            mismatchTurn = mismatch.isEmpty ? nil : MemoryMismatchTurn(seed: next.seed, moves: next.moves, selection: mismatch)
            let configured = model.gameSettings(for: .memory).memoryRevealSeconds
            turnRevealSeconds = configured.isFinite ? min(1.5, max(0.5, configured)) : 0.65
            holdDeadline = nil
            presentation.beginPair(secondCard: index, mismatchedCards: mismatch)
        }
        model.feedback(for: .memory)
    }
    private func flipCompleted(card: Int, faceUp: Bool, token: UInt64) {
        guard presentationActive, token == presentation.token else { return }
        if faceUp {
            if presentation.revealCompleted(card: card, token: token, at: 0), presentation.phase == .holding {
                holdDeadline = ProcessInfo.processInfo.systemUptime + turnRevealSeconds
            }
        } else if presentation.closeCompleted(card: card, token: token), let turn = mismatchTurn {
            guard model.memory?.seed == turn.seed else { return }
            if model.editMemory({ $0.resolveMismatch(expectedMoves: turn.moves, expectedSelection: turn.selection) }) {
                presentation.finishClosing(token: token)
                mismatchTurn = nil
                holdDeadline = nil
            }
        }
    }

    var body: some View {
        ScrollView {
            if let board = model.memory {
                VStack(spacing: 16) {
                    MemoryPlayHeader(board: board)
                    // At 320 pt: (320 - 24 outer - 8 inner - 20 gaps) / 6 = 44.7 pt.
                    // At most 36 eager cards keep completion callbacks alive
                    // when a selected card scrolls beyond the viewport.
                    VStack(spacing: 4) {
                        ForEach(0..<board.mode.rows, id: \.self) { row in
                            HStack(spacing: 4) {
                                ForEach(0..<board.mode.columns, id: \.self) { column in
                                    let index = row * board.mode.columns + column
                                    MemoryCard(index: index, board: board,
                                               faceUp: board.isFaceUp(index) && !presentation.closingCards.contains(index),
                                               inputAllowed: active && presentation.acceptsSelection,
                                               token: presentation.token,
                                               reveal: { select(index) }, flipCompleted: flipCompleted)
                                        .frame(minWidth: 44, maxWidth: .infinity)
                                }
                            }
                        }
                    }.id(board.seed).padding(4)
                        .background(GameBoardSurface(game: .memory, cornerRadius: 18))
                    Text(model.t("memory.controls")).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }.padding(.horizontal, 12).padding(.vertical, 16)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
        }.background(GameCanvas()).tint(GamePalette.tint(.memory))
            .navigationTitle(model.gameTitle(.memory)).navigationBarTitleDisplayMode(.inline)
            .gameSessionScreen(.memory, resultReady: presentation.acceptsSelection)
            .onAppear { settle() }
            .onDisappear { settle() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { settle() }
            }
            .onChange(of: model.sessionIsPlaying(.memory)) { _, playing in if !playing { settle() } }
            .task(id: holdKey) {
                guard let expected = holdKey else { return }
                // Snapshot the configured real-time hold after the second reveal.
                // The core's fixed logical deadline remains an animation gate.
                while !Task.isCancelled, holdKey == expected {
                    let remaining = expected.deadline - ProcessInfo.processInfo.systemUptime
                    if remaining <= 0 {
                        presentation.beginClosing(token: expected.token, at: MemoryTurnPresentation.mismatchHoldDuration)
                        return
                    }
                    do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
                }
            }
    }
}

private struct MemoryPlayHeader: View {
    let board: MemoryBoard
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
            }
            LazyVGrid(columns: [GridItem(dynamicTypeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 138), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                GameMetric(symbol: "rectangle.on.rectangle", value: model.t("memory.pairs", board.matchedPairCount, board.mode.pairCount),
                           tint: tint, identifier: "memory.pairs")
                GameMetric(symbol: "hand.tap", value: model.t("memory.moves", board.moves), tint: tint, identifier: "memory.moves")
            }
        }
    }
}

private struct MemoryCard: View {
    let index: Int
    let board: MemoryBoard
    let faceUp: Bool
    let inputAllowed: Bool
    let token: UInt64
    let reveal: () -> Void
    let flipCompleted: (Int, Bool, UInt64) -> Void
    @EnvironmentObject var model: AppModel
    @Environment(\.gameReducedMotion) private var reduceMotion
    @State private var rotation: Double

    init(index: Int, board: MemoryBoard, faceUp: Bool, inputAllowed: Bool, token: UInt64,
         reveal: @escaping () -> Void, flipCompleted: @escaping (Int, Bool, UInt64) -> Void) {
        self.index = index; self.board = board; self.faceUp = faceUp
        self.inputAllowed = inputAllowed; self.token = token
        self.reveal = reveal; self.flipCompleted = flipCompleted
        _rotation = State(initialValue: faceUp ? 180 : 0)
    }

    private var canSelect: Bool { inputAllowed && board.canSelect(index) }

    private var spokenLabel: String {
        let row = index / board.mode.columns + 1, column = index % board.mode.columns + 1
        guard faceUp else { return model.t("memory.card.hidden", row, column) }
        return model.t(board.matched[index] ? "memory.card.matched" : "memory.card.revealed", row, column,
                       model.t("memory.symbol.\(board.cards[index])"))
    }

    private func animateFlip(to revealed: Bool) {
        let expectedToken = token
        if reduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { rotation = revealed ? 180 : 0 }
            flipCompleted(index, revealed, expectedToken)
        } else {
            withAnimation(.linear(duration: MemoryTurnPresentation.flipDuration), completionCriteria: .removed) {
                rotation = revealed ? 180 : 0
            } completion: {
                flipCompleted(index, revealed, expectedToken)
            }
        }
    }

    var body: some View {
        Button(action: reveal) {
            MemoryFlipFace(rotation: rotation, symbol: board.cards[index], matched: board.matched[index])
                .aspectRatio(1, contentMode: .fit).contentShape(Rectangle())
                .accessibilityHidden(true)
        }.buttonStyle(MemoryCardPressStyle()).disabled(!canSelect)
            .accessibilityLabel(spokenLabel)
            .accessibilityHint(canSelect ? model.t("memory.card.hint") : "")
            .accessibilityIdentifier("memory.card.\(index)")
            .onChange(of: faceUp) { _, revealed in animateFlip(to: revealed) }
            .onChange(of: reduceMotion) { _, _ in animateFlip(to: faceUp) }
    }
}

private struct MemoryCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // A matched card keeps its full enamel colors while the native Button
        // remains disabled for input and accessibility.
        configuration.label.opacity(configuration.isPressed ? 0.9 : 1)
    }
}

/// One culled face rotates through 180°, so symbols never appear mirrored or
/// bleed through the back. SwiftUI interpolates at the display's native cadence.
private struct MemoryFlipFace: View, Animatable {
    var rotation: Double
    let symbol: Int
    let matched: Bool
    var animatableData: Double {
        get { rotation }
        set { rotation = newValue }
    }

    private var enamel: Color {
        switch symbol {
        case 0, 2, 6, 15: return Color(red: 0.75, green: 0.43, blue: 0.05)
        case 1: return Color(red: 0.32, green: 0.34, blue: 0.61)
        case 3, 5, 10: return Color(red: 0.77, green: 0.22, blue: 0.18)
        case 4, 12: return Color(red: 0.12, green: 0.43, blue: 0.29)
        case 7, 8, 11: return Color(red: 0.16, green: 0.40, blue: 0.66)
        case 9, 17: return Color(red: 0.04, green: 0.43, blue: 0.47)
        case 13, 16: return Color(red: 0.57, green: 0.25, blue: 0.43)
        default: return Color(red: 0.52, green: 0.31, blue: 0.15)
        }
    }

    var body: some View {
        let front = rotation >= 90
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack(alignment: .bottomTrailing) {
                if front {
                    GameTileSurface(game: .memory, cornerRadius: 10)
                    Circle().fill(.white.opacity(0.2))
                        .overlay(Circle().strokeBorder(GameMaterial.gold.opacity(0.24), lineWidth: 0.7))
                        .frame(width: side * 0.76, height: side * 0.76)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Image(systemName: MemoryBoard.symbols[symbol])
                        .font(.system(size: min(44, side * 0.47), weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [enamel.opacity(0.75), enamel, enamel],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: GameMaterial.ink.opacity(0.24), radius: 0, y: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if matched {
                        ZStack {
                            Circle().fill(GameMaterial.teal)
                            Circle().strokeBorder(GameMaterial.gold, lineWidth: 0.8)
                            Image(systemName: "checkmark")
                                .font(.system(size: min(11, side * 0.15), weight: .bold))
                                .foregroundStyle(GameMaterial.ivory)
                        }.frame(width: min(19, side * 0.27), height: min(19, side * 0.27)).padding(4)
                    }
                } else {
                    GameBoardSurface(game: .memory, cornerRadius: 10)
                    MemoryCardBackPattern()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .rotation3DEffect(.degrees(front ? rotation - 180 : rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        }
    }
}

/// A few fixed vector strokes form a foil-stamped back, without textures,
/// per-frame noise, blur, or any symbol from the hidden face.
private struct MemoryCardBackPattern: View {
    var body: some View {
        Canvas { context, bounds in
            let side = min(bounds.width, bounds.height)
            let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
            for scale in [0.25, 0.18] {
                let radius = side * scale
                var diamond = Path()
                diamond.move(to: CGPoint(x: center.x, y: center.y - radius))
                diamond.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                diamond.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                diamond.addLine(to: CGPoint(x: center.x - radius, y: center.y))
                diamond.closeSubpath()
                context.stroke(diamond, with: .color(GameMaterial.gold.opacity(scale == 0.25 ? 0.7 : 0.35)), lineWidth: 0.75)
            }
            let bead = max(1.5, side * 0.065)
            context.fill(Path(ellipseIn: CGRect(x: center.x - bead / 2, y: center.y - bead / 2, width: bead, height: bead)),
                         with: .color(GameMaterial.ivory.opacity(0.9)))
            let inset = max(7, side * 0.13), pip = max(1, side * 0.018)
            for x in [inset, bounds.width - inset] {
                for y in [inset, bounds.height - inset] {
                    context.fill(Path(ellipseIn: CGRect(x: x - pip / 2, y: y - pip / 2, width: pip, height: pip)),
                                 with: .color(GameMaterial.gold.opacity(0.65)))
                }
            }
        }
    }
}
