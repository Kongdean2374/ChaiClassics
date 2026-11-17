import SwiftUI
import ChaiCore

struct TwentyFourMenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var difficulty = TwentyFourDifficulty.easy
    @State private var play = false
    @State private var confirmNew = false

    private func start() {
        if model.saveTwentyFour(TwentyFourBoard(difficulty: difficulty)) { play = true }
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
                    Button { play = true } label: {
                        ContinueCard(title: model.t(board.isComplete ? "menu.viewLast" : "menu.continue"),
                                     detail: model.t("twentyfour.progress", model.t("difficulty." + board.difficulty.rawValue), board.moves, board.solvedCount) + " · " + model.t("common.seconds", board.elapsedSeconds))
                            .contentShape(Rectangle())
                    }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("twentyfour.continue")
                }
            }
            Section(model.t("menu.newGame")) {
                Picker(model.t("twentyfour.difficulty"), selection: $difficulty) {
                    ForEach(TwentyFourDifficulty.allCases, id: \.self) { Text(model.t("difficulty." + $0.rawValue)).tag($0) }
                }.accessibilityIdentifier("twentyfour.difficulty")
                Text(model.t("twentyfour.difficulty." + difficulty.rawValue))
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { if model.twentyFour != nil { confirmNew = true } else { start() } } label: {
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
            .confirmationDialog(model.t("twentyfour.replace.confirm"), isPresented: $confirmNew, titleVisibility: .visible) {
                Button(model.t("menu.startNew"), role: .destructive) { start() }.accessibilityIdentifier("twentyfour.confirmNew")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
    }
}

struct TwentyFourPlayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var paused = false
    @State private var confirmReset = false
    @State private var confirmNext = false
    @State private var input = TwentyFourInput()
    @Namespace private var cardPositions
    private var tint: Color { GamePalette.tint(.twentyFour) }
    private var inactive: Bool { paused || scenePhase != .active || confirmReset || confirmNext }
    private var moveAnimation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.2) }
    private func clearSelection() { input.clear() }
    private func next() {
        if model.editTwentyFour({ $0.nextPuzzle() }) { clearSelection(); paused = false }
    }
    var body: some View {
        ScrollView {
            if let board = model.twentyFour {
                VStack(spacing: 18) {
                    header(board)
                    if board.isComplete {
                        GameResultBanner(game: .twentyFour, title: model.t("twentyfour.won"), detail: model.t("twentyfour.won.detail"), won: true, identifier: "twentyfour.complete")
                    }
                    if paused || scenePhase != .active {
                        PauseCard(game: .twentyFour) { paused = false }.frame(minHeight: 320)
                    } else {
                        puzzle(board)
                    }
                }.padding(16).frame(maxWidth: 580).frame(maxWidth: .infinity)
            }
        }.background(GameCanvas()).tint(tint)
            .localizedNavigation().navigationTitle(model.gameTitle(.twentyFour)).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button(model.t("twentyfour.reset")) { confirmReset = true }.accessibilityIdentifier("twentyfour.reset")
            }
            .confirmationDialog(model.t("twentyfour.reset.confirm"), isPresented: $confirmReset, titleVisibility: .visible) {
                Button(model.t("twentyfour.reset"), role: .destructive) {
                    model.editTwentyFour { $0.reset() }
                    clearSelection(); paused = false
                }.accessibilityIdentifier("twentyfour.confirmReset")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
            .confirmationDialog(model.t("twentyfour.next.confirm"), isPresented: $confirmNext, titleVisibility: .visible) {
                Button(model.t("twentyfour.next"), role: .destructive) { next() }.accessibilityIdentifier("twentyfour.confirmNext")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
            .gameCompletionCelebration(completed: model.twentyFour?.isComplete == true)
            .modifier(GameplayActivity(game: .twentyFour, active: !inactive && model.twentyFour?.isEnded == false))
            .modifier(SessionTimer(active: !inactive && model.twentyFour?.isEnded == false, tick: {
                model.editTwentyFour { $0.elapsedSeconds += 1 }
            }))
            .onChange(of: scenePhase) { _, phase in if phase != .active { clearSelection() } }
            // Observe puzzle changes only: timer publishes must leave the pending expression intact.
            .onChange(of: model.twentyFour?.history) { _, _ in clearSelection() }
            .onChange(of: model.twentyFour?.numbers) { _, _ in clearSelection() }
            .onDisappear { clearSelection() }
    }
    private func header(_ board: TwentyFourBoard) -> some View {
        VStack(spacing: 14) {
            HStack {
                GameArtwork(game: .twentyFour, size: 42)
                Text(model.t("difficulty." + board.difficulty.rawValue)).font(.system(.headline, design: .rounded))
                Spacer()
                Button { paused.toggle(); clearSelection() } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .frame(width: 44, height: 44).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                }.buttonStyle(QuietPressStyle()).disabled(board.isEnded)
                    .accessibilityLabel(model.t(paused ? "common.resume" : "common.pause"))
                    .accessibilityIdentifier("twentyfour.pause")
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    GameMetric(symbol: "checkmark.circle", value: model.t("twentyfour.solved", board.solvedCount), tint: tint, identifier: "twentyfour.solved")
                    Spacer(minLength: 4)
                    GameMetric(symbol: "timer", value: model.t("common.seconds", board.elapsedSeconds), tint: tint, identifier: "twentyfour.timer")
                }
                VStack(alignment: .leading) {
                    GameMetric(symbol: "checkmark.circle", value: model.t("twentyfour.solved", board.solvedCount), tint: tint, identifier: "twentyfour.solved")
                    GameMetric(symbol: "timer", value: model.t("common.seconds", board.elapsedSeconds), tint: tint, identifier: "twentyfour.timer")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func puzzle(_ board: TwentyFourBoard) -> some View {
        VStack(spacing: 16) {
            Text(model.t("twentyfour.target")).font(.system(.title2, design: .serif, weight: .bold))
                .foregroundStyle(GameMaterial.gold)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(GameBoardSurface(game: .twentyFour, cornerRadius: 18))
            Text(model.t("twentyfour.controls")).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if !board.isEnded { pendingExpression(board) }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(board.displayCards) { card in
                    cardButton(card, board: board)
                        .matchedGeometryEffect(id: card.id, in: cardPositions)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
                }
            }.padding(12).frame(minHeight: 250, alignment: .top)
                .background(GameBoardSurface(game: .twentyFour))
                .animation(moveAnimation, value: board.history)
                .animation(moveAnimation, value: input)
                .accessibilityIdentifier("twentyfour.cards")
            if !board.isEnded { calculation(board) }
            if board.isEnded && !board.isComplete {
                Text(model.t("twentyfour.tryAgain")).font(.headline).multilineTextAlignment(.center)
                    .accessibilityIdentifier("twentyfour.incorrect")
            }
            puzzleActions(board)
            history(board)
            Text(model.t("twentyfour.difficulty." + board.difficulty.rawValue))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(tint.opacity(0.18), lineWidth: 1).allowsHitTesting(false))
    }
    private func pendingExpression(_ board: TwentyFourBoard) -> some View {
        VStack(spacing: 10) {
            Text(model.t("twentyfour.input." + input.stage.rawValue))
                .font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 36)
                .accessibilityIdentifier("twentyfour.stage")
            HStack(spacing: 8) {
                operandSlot(board.cards.first { $0.id == input.firstID }, role: 1)
                VStack(spacing: 5) {
                    Text(model.t("twentyfour.input.operatorLabel")).font(.caption2).foregroundStyle(.secondary)
                    Text(input.operation?.symbol ?? "?").font(.system(.title2, design: .rounded, weight: .bold))
                        .frame(minHeight: 36)
                }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(tint.opacity(input.operation == nil ? 0.035 : 0.12), in: RoundedRectangle(cornerRadius: 14))
                operandSlot(board.cards.first { $0.id == input.secondID }, role: 2)
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel(preview(board)).accessibilityIdentifier("twentyfour.preview")
        }.animation(moveAnimation, value: input)
    }
    private func operandSlot(_ card: TwentyFourCard?, role: Int) -> some View {
        let color: Color = role == 1 ? tint : .teal
        return VStack(spacing: 5) {
            Text(model.t(role == 1 ? "twentyfour.input.firstLabel" : "twentyfour.input.secondLabel"))
                .font(.caption2).foregroundStyle(.secondary)
            Text(card?.value.description ?? "—").font(.system(.title2, design: .rounded, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.65).monospacedDigit().frame(minHeight: 36)
        }.frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(color.opacity(card == nil ? 0.035 : 0.14), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(card == nil ? 0.12 : 0.55), lineWidth: 1).allowsHitTesting(false))
    }
    private func cardButton(_ card: TwentyFourCard, board: TwentyFourBoard) -> some View {
        let role = input.firstID == card.id ? 1 : (input.secondID == card.id ? 2 : 0)
        let color: Color = role == 2 ? .teal : tint
        let caption = role == 1 ? "twentyfour.input.firstCard" : role == 2 ? "twentyfour.input.secondCard" : card.id >= 4 ? "twentyfour.resultCard" : "twentyfour.select"
        return Button {
            if input.selectCard(card.id, in: board) { model.feedback() }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    if role != 0 { Image(systemName: role == 1 ? "1.circle.fill" : "2.circle.fill").font(.caption).foregroundStyle(color) }
                    Text(model.t(caption)).font(.caption).foregroundStyle(GameMaterial.ink.opacity(0.75))
                }
                Text(card.value.description).font(.system(.title, design: .serif, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(GameMaterial.ink)
                    .minimumScaleFactor(0.65).lineLimit(1)
                Text(card.sourceMask.nonzeroBitCount > 1 ? card.expression : " ")
                    .font(.caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(GameMaterial.ink.opacity(0.8))
            }.frame(maxWidth: .infinity, minHeight: 90).padding(10)
                .background(GameTileSurface(game: .twentyFour, selected: role != 0, cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(color.opacity(role == 0 ? 0.18 : 0.8), lineWidth: role == 0 ? 1 : 2).allowsHitTesting(false))
                .contentShape(Rectangle())
        }.buttonStyle(QuietPressStyle()).disabled(inactive || board.isEnded)
            .accessibilityLabel(model.t("twentyfour.card.label", card.id + 1, card.value.description, card.expression))
            .accessibilityValue(model.t(role == 1 ? "twentyfour.input.firstCard" : role == 2 ? "twentyfour.input.secondCard" : "twentyfour.unselected"))
            .accessibilityAddTraits(role == 0 ? [] : .isSelected)
            .accessibilityHint(model.t("twentyfour.card.hint"))
            .accessibilityIdentifier("twentyfour.card.\(card.id)")
    }
    private func calculation(_ board: TwentyFourBoard) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(TwentyFourOperator.allCases, id: \.self) { item in
                    Button {
                        if input.selectOperator(item) { model.feedback() }
                    } label: {
                        Text(item.symbol).font(.title2.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                            .background(tint.opacity(input.operation == item ? 0.2 : 0.055), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(input.operation == item ? 0.8 : 0.12), lineWidth: 1).allowsHitTesting(false))
                            .contentShape(Rectangle())
                    }.buttonStyle(QuietPressStyle()).disabled(inactive || input.firstID == nil)
                        .accessibilityLabel(model.t("twentyfour.operator." + item.rawValue))
                        .accessibilityAddTraits(input.operation == item ? .isSelected : [])
                        .accessibilityIdentifier("twentyfour.operator." + item.rawValue)
                }
            }.animation(moveAnimation, value: input.operation)
            HStack(spacing: 12) {
                Button { clearSelection(); model.feedback() } label: {
                    Label(model.t("twentyfour.input.clear"), systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.bordered).disabled(input.isEmpty || inactive).accessibilityIdentifier("twentyfour.clear")
                Button { if input.swap() { model.feedback() } } label: {
                    Label(model.t("twentyfour.swap"), systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.bordered).disabled(input.secondID == nil || inactive).accessibilityIdentifier("twentyfour.swap")
            }
            Button {
                guard let first = input.firstID, let second = input.secondID, let operation = input.operation else { return }
                if model.editTwentyFour({ $0.combine(firstID: first, secondID: second, operation: operation) }) {
                    clearSelection(); model.feedback()
                }
            } label: {
                HStack(spacing: 10) {
                    Text("=").font(.system(.title2, design: .rounded, weight: .bold))
                    Text(model.t("twentyfour.apply")).font(.headline)
                }.frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
            }.buttonStyle(.borderedProminent).disabled(inactive || !input.canApply(to: board))
                .accessibilityIdentifier("twentyfour.apply")
            if input.stage == .ready && input.operation == .divide,
               board.cards.first(where: { $0.id == input.secondID })?.value.isZero == true {
                Text(model.t("twentyfour.zeroDivision")).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("twentyfour.zeroDivision")
            }
        }
    }
    private func puzzleActions(_ board: TwentyFourBoard) -> some View {
        HStack(spacing: 12) {
            Button {
                let changed = model.editTwentyFour { $0.undo() }
                clearSelection()
                if changed { model.feedback() }
            } label: {
                Label(model.t("twentyfour.undo"), systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.bordered).disabled(!board.canUndo || inactive).accessibilityIdentifier("twentyfour.undo")
            Button {
                if board.isComplete { next() } else { confirmNext = true }
            } label: {
                Label(model.t("twentyfour.next"), systemImage: "arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.borderedProminent).disabled(inactive).accessibilityIdentifier("twentyfour.next")
        }
    }
    private func history(_ board: TwentyFourBoard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.t("twentyfour.history.title"), systemImage: "list.number")
                .font(.headline)
            Text(model.t("twentyfour.history.start", board.numbers.map(String.init).joined(separator: " · ")))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if board.calculationHistory.isEmpty {
                Text(model.t("twentyfour.history.empty")).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(board.calculationHistory) { step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(step.id + 1)").font(.caption.weight(.semibold))
                        .frame(width: 26, height: 26).background(tint.opacity(0.13), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(step.first.value.description) \(step.operation.symbol) \(step.second.value.description) = \(step.result.value.description)")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text(step.result.expression).font(.caption).foregroundStyle(.secondary)
                    }.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(tint.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("twentyfour.history.step.\(step.id)")
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            .accessibilityIdentifier("twentyfour.history")
    }
    private func preview(_ board: TwentyFourBoard) -> String {
        guard let first = board.cards.first(where: { $0.id == input.firstID }) else { return model.t("twentyfour.input.first") }
        guard let operation = input.operation else { return first.value.description + ", " + model.t("twentyfour.input.operation") }
        guard let second = board.cards.first(where: { $0.id == input.secondID }) else {
            return first.value.description + " " + operation.symbol + ", " + model.t("twentyfour.input.second")
        }
        return model.t("twentyfour.preview.format", first.value.description, operation.symbol, second.value.description)
    }
}
