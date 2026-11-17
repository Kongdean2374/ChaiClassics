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
    @State private var paused = false
    @State private var confirmReset = false
    @State private var confirmNext = false
    @State private var selected: [Int] = []
    @State private var operation = TwentyFourOperator.add
    private var tint: Color { GamePalette.tint(.twentyFour) }
    private var inactive: Bool { paused || scenePhase != .active || confirmReset || confirmNext }
    private func clearSelection() { selected = [] }
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
                    if model.editTwentyFour({ $0.reset() }) { clearSelection(); paused = false }
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
            Text(model.t("twentyfour.target")).font(.system(.title2, design: .rounded, weight: .bold))
            Text(model.t("twentyfour.controls")).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(board.cards) { card in cardButton(card) }
            }.accessibilityIdentifier("twentyfour.cards")
            if !board.isEnded { calculation(board) }
            if board.isEnded && !board.isComplete {
                Text(model.t("twentyfour.tryAgain")).font(.headline).multilineTextAlignment(.center)
                    .accessibilityIdentifier("twentyfour.incorrect")
            }
            HStack(spacing: 12) {
                Button {
                    if model.editTwentyFour({ $0.undo() }) { clearSelection(); model.feedback() }
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
            Text(model.t("twentyfour.difficulty." + board.difficulty.rawValue))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(tint.opacity(0.18), lineWidth: 1).allowsHitTesting(false))
    }
    private func cardButton(_ card: TwentyFourCard) -> some View {
        let position = selected.firstIndex(of: card.id)
        return Button {
            if let index = selected.firstIndex(of: card.id) { selected.remove(at: index) }
            else if selected.count < 2 { selected.append(card.id) }
            model.feedback()
        } label: {
            VStack(spacing: 6) {
                Text(card.value.description).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                    .minimumScaleFactor(0.7).lineLimit(1)
                if card.sourceMask.nonzeroBitCount > 1 {
                    Text(card.expression).font(.caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                Text(position.map { model.t("twentyfour.selected", $0 + 1) } ?? model.t("twentyfour.select"))
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 108).padding(8)
                .background(tint.opacity(position == nil ? 0.055 : 0.19), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(tint.opacity(position == nil ? 0.18 : 0.8), lineWidth: position == nil ? 1 : 2).allowsHitTesting(false))
                .contentShape(Rectangle())
        }.buttonStyle(QuietPressStyle()).disabled(inactive || model.twentyFour?.isEnded == true)
            .accessibilityLabel(model.t("twentyfour.card.label", card.id + 1, card.value.description, card.expression))
            .accessibilityValue(position.map { model.t("twentyfour.selected", $0 + 1) } ?? model.t("twentyfour.unselected"))
            .accessibilityHint(model.t("twentyfour.card.hint"))
            .accessibilityIdentifier("twentyfour.card.\(card.id)")
    }
    private func calculation(_ board: TwentyFourBoard) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(TwentyFourOperator.allCases, id: \.self) { item in
                    Button { operation = item } label: {
                        Text(item.symbol).font(.title2.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                            .background(tint.opacity(operation == item ? 0.2 : 0.07), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(operation == item ? 0.8 : 0.12), lineWidth: 1).allowsHitTesting(false))
                            .contentShape(Rectangle())
                    }.buttonStyle(QuietPressStyle()).disabled(inactive)
                        .accessibilityLabel(model.t("twentyfour.operator." + item.rawValue))
                        .accessibilityAddTraits(operation == item ? .isSelected : [])
                        .accessibilityIdentifier("twentyfour.operator." + item.rawValue)
                }
            }
            Text(preview(board)).font(.system(.headline, design: .rounded)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("twentyfour.preview")
            HStack(spacing: 12) {
                Button { selected.reverse() } label: {
                    Label(model.t("twentyfour.swap"), systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.bordered).disabled(selected.count != 2 || inactive).accessibilityIdentifier("twentyfour.swap")
                Button {
                    guard selected.count == 2 else { return }
                    if model.editTwentyFour({ $0.combine(firstID: selected[0], secondID: selected[1], operation: operation) }) {
                        clearSelection(); model.feedback()
                    }
                } label: {
                    Text(model.t("twentyfour.apply")).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.borderedProminent)
                    .disabled(selected.count != 2 || inactive || !board.canCombine(firstID: selected.first ?? -1, secondID: selected.last ?? -1, operation: operation))
                    .accessibilityIdentifier("twentyfour.apply")
            }
            if selected.count == 2, operation == .divide,
               board.cards.first(where: { $0.id == selected[1] })?.value.isZero == true {
                Text(model.t("twentyfour.zeroDivision")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func preview(_ board: TwentyFourBoard) -> String {
        guard selected.count == 2,
              let first = board.cards.first(where: { $0.id == selected[0] }),
              let second = board.cards.first(where: { $0.id == selected[1] }) else { return model.t("twentyfour.chooseTwo") }
        return model.t("twentyfour.preview.format", first.value.description, operation.symbol, second.value.description)
    }
}
