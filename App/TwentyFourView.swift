import SwiftUI
import ChaiCore

struct TwentyFourMenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var difficulty = TwentyFourDifficulty.easy
    @State private var play = false
    @State private var confirmNew = false

    private func start() {
        if model.saveTwentyFour(TwentyFourBoard(difficulty: difficulty)) {
            model.startNewSession(.twentyFour)
            play = true
        }
    }
    private func applyMenuDefaults() {
        difficulty = TwentyFourDifficulty(rawValue: model.gameSettings(for: .twentyFour).twentyFourDifficulty) ?? .easy
    }
    var body: some View {
        Form {
            Section {
                GameIntroHeader(game: .twentyFour, title: model.gameTitle(.twentyFour), subtitle: model.t("twentyfour.rules"))
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            if let board = model.twentyFour {
                Section(model.t("menu.lastGame")) {
                    ContinueGameRow(game: .twentyFour, action: {
                        model.beginContinuing(.twentyFour)
                        play = true
                    }) {
                        ContinueCard(title: model.t(board.isEnded ? "menu.viewLast" : "menu.continue"),
                                     detail: model.t("twentyfour.progress", model.t("difficulty." + board.difficulty.rawValue), board.moves, board.solvedCount) + " · " + model.t("common.seconds", board.elapsedSeconds))
                            .contentShape(Rectangle())
                    }
                }
            }
            Section(model.t("menu.newGame")) {
                Picker(model.t("twentyfour.difficulty"), selection: $difficulty) {
                    ForEach(TwentyFourDifficulty.allCases, id: \.self) { Text(model.t("difficulty." + $0.rawValue)).tag($0) }
                }.accessibilityIdentifier("twentyfour.difficulty")
                Text(model.t("twentyfour.difficulty." + difficulty.rawValue))
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { confirmNew = true } label: {
                    Label(model.t("menu.start"), systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                        .foregroundStyle(.primary)
                        .background(GamePalette.tint(.twentyFour).opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                        .contentShape(Rectangle())
                }.buttonStyle(QuietPressStyle()).disabled(model.blocked.contains(.twentyFour))
                    .accessibilityIdentifier("twentyfour.start")
                    .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
            }
        }.scrollContentBackground(.hidden).background(GameCanvas()).tint(GamePalette.tint(.twentyFour))
            .localizedNavigation().navigationTitle(model.gameTitle(.twentyFour)).navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $play) { TwentyFourPlayView() }
            .gameMenuSettings(.twentyFour)
            .newGameConfirmation(.twentyFour, isPresented: $confirmNew) { start() }
            .loadGameDefaultsOnce { applyMenuDefaults() }
            .onChange(of: model.gameSettings(for: .twentyFour).twentyFourDifficulty) { _, _ in applyMenuDefaults() }
    }
}

struct TwentyFourPlayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.gameReducedMotion) private var reduceMotion
    @State private var input = TwentyFourInput()
    private var tint: Color { GamePalette.tint(.twentyFour) }
    private var inactive: Bool {
        scenePhase != .active || !model.sessionIsPlaying(.twentyFour) || model.twentyFour?.isEnded == true
    }
    private var moveAnimation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.18) }

    var body: some View {
        Group {
            if let board = model.twentyFour {
                ViewThatFits(in: .vertical) {
                    playPanel(board).fixedSize(horizontal: false, vertical: true)
                    // Larger accessibility text and very short landscape windows
                    // may need extra space; normal play stays within the viewport.
                    ScrollView { playPanel(board) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(GameCanvas()).tint(tint)
        .navigationTitle(model.gameTitle(.twentyFour)).navigationBarTitleDisplayMode(.inline)
        .gameSessionScreen(.twentyFour)
        .onChange(of: scenePhase) { _, phase in if phase != .active { input.clear() } }
        .onChange(of: model.sessionIsPlaying(.twentyFour)) { _, playing in if !playing { input.clear() } }
        .onChange(of: model.twentyFour?.history) { _, _ in
            if let board = model.twentyFour { input.reconcile(with: board) }
            else { input.clear() }
        }
        .onChange(of: model.twentyFour?.numbers) { _, _ in input.clear() }
        .onDisappear { input.clear() }
    }

    private func playPanel(_ board: TwentyFourBoard) -> some View {
        VStack(spacing: 10) {
            header(board)
            expression(board)
            cardGrid(board)
            operators
            history(board)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: 540).frame(maxWidth: .infinity)
    }

    private func header(_ board: TwentyFourBoard) -> some View {
        HStack(spacing: 10) {
            GameArtwork(game: .twentyFour, size: 32)
            Text(model.t("difficulty." + board.difficulty.rawValue)).font(.subheadline.weight(.semibold))
            Spacer(minLength: 4)
            GameMetric(symbol: "checkmark.circle", value: model.t("twentyfour.solved", board.solvedCount), tint: tint,
                       identifier: "twentyfour.solved")
                .lineLimit(1).minimumScaleFactor(0.75)
            Button(action: stepBack) {
                Image(systemName: "arrow.uturn.backward").font(.body.weight(.semibold))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
                    .background(tint.opacity(0.12), in: Circle())
            }
            .buttonStyle(QuietPressStyle()).disabled(inactive || (input.isEmpty && !board.canUndo))
            .accessibilityLabel(model.t("twentyfour.undo"))
            .accessibilityIdentifier("twentyfour.undo")
        }
    }

    private func expression(_ board: TwentyFourBoard) -> some View {
        let cards = board.cards
        let first = cards.first { $0.id == input.firstID }
        let second = cards.first { $0.id == input.secondID }
        let dividesByZero = input.operation == .divide && second?.value.isZero == true
        let line = "\(first?.value.description ?? "—")  \(input.operation?.symbol ?? "·")  \(second?.value.description ?? "—")"
        return VStack(spacing: 4) {
            Text(line).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                .foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityIdentifier("twentyfour.preview")
            if dividesByZero {
                Text(model.t("twentyfour.zeroDivision"))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .accessibilityIdentifier("twentyfour.zeroDivision")
            } else {
                Text(model.t("twentyfour.input." + input.stage.rawValue))
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("twentyfour.stage")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func cardGrid(_ board: TwentyFourBoard) -> some View {
        let cards = board.displayCards
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(cards) { card in
                cardButton(card, board: board)
                    .transition(reduceMotion ? .identity : .scale(scale: 0.94).combined(with: .opacity))
            }
            ForEach(cards.count..<4, id: \.self) { _ in
                Color.clear.frame(height: 64).accessibilityHidden(true).allowsHitTesting(false)
            }
        }
        .padding(9).background(GameBoardSurface(game: .twentyFour, cornerRadius: 16))
        .animation(moveAnimation, value: board.history)
        .accessibilityIdentifier("twentyfour.cards")
    }

    private func cardButton(_ card: TwentyFourCard, board: TwentyFourBoard) -> some View {
        let first = input.firstID == card.id
        let second = input.secondID == card.id
        return Button { selectCard(card.id) } label: {
            VStack(spacing: 3) {
                Text(card.value.description)
                    .font(.system(.title2, design: .serif, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.65)
                if card.sourceMask.nonzeroBitCount > 1 {
                    Text(card.expression).font(.caption).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(GameMaterial.ink).frame(maxWidth: .infinity, minHeight: 64)
            .padding(.horizontal, 6)
            .background(GameTileSurface(game: .twentyFour, selected: first || second, cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietPressStyle()).disabled(inactive || board.isEnded)
        .accessibilityLabel(model.t("twentyfour.card.label", card.id + 1, card.value.description, card.expression))
        .accessibilityValue(model.t(first ? "twentyfour.input.firstCard" : second ? "twentyfour.input.secondCard" : "twentyfour.unselected"))
        .accessibilityAddTraits(first || second ? .isSelected : [])
        .accessibilityHint(model.t("twentyfour.card.hint"))
        .accessibilityIdentifier("twentyfour.card.\(card.id)")
    }

    private var operators: some View {
        HStack(spacing: 8) {
            ForEach(TwentyFourOperator.allCases, id: \.self) { operation in
                Button {
                    guard !inactive else { return }
                    if input.secondID != nil { input.stepBack() }
                    if input.selectOperator(operation) { model.feedback(for: .twentyFour) }
                } label: {
                    Text(operation.symbol).font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(tint.opacity(input.operation == operation ? 0.24 : 0.08), in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(QuietPressStyle()).disabled(inactive || input.firstID == nil)
                .accessibilityLabel(model.t("twentyfour.operator." + operation.rawValue))
                .accessibilityAddTraits(input.operation == operation ? .isSelected : [])
                .accessibilityIdentifier("twentyfour.operator." + operation.rawValue)
            }
        }
    }

    private func history(_ board: TwentyFourBoard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if board.calculationHistory.isEmpty {
                Text(model.t("twentyfour.controls")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(board.calculationHistory) { step in
                Text("\(step.first.value.description) \(step.operation.symbol) \(step.second.value.description) = \(step.result.value.description)")
                    .font(.subheadline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("twentyfour.history.step.\(step.id)")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectCard(_ id: Int) {
        guard !inactive, let board = model.twentyFour, input.selectCard(id, in: board) else { return }
        if let move = input.resolvedMove(in: board) {
            let changed = model.editTwentyFour {
                $0.combine(firstID: move.firstID, secondID: move.secondID, operation: move.operation)
            }
            guard changed else { return }
            input.clear()
        }
        model.feedback(for: .twentyFour)
    }

    private func stepBack() {
        guard !inactive else { return }
        if input.stepBack() || model.editTwentyFour({ $0.undo() }) {
            model.feedback(for: .twentyFour)
        }
    }
}
