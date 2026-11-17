import SwiftUI
import UIKit
import ChaiCore

struct PlayHistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var selectedGame: GameID?
    @State private var selectedDifficulty: String?
    @State private var selectedOutcome: GameOutcome?
    @State private var dateWindow = HistoryDateWindow.all
    @State private var sort = HistorySort.newest
    @State private var presentation: HistoryPresentation?
    @State private var dismissKeyboardOnOutsideTap = false
    @FocusState private var searching: Bool

    init(game: GameID? = nil) { _selectedGame = State(initialValue: game) }

    private var difficulties: [String] {
        Set(model.playRecords.filter { selectedGame == nil || $0.gameID == selectedGame }.map(\.difficulty)).sorted()
    }
    private var records: [GamePlayRecord] {
        let en = AppText(language: .english), zh = AppText(language: .traditionalChinese)
        let names = Dictionary(uniqueKeysWithValues: GameID.allCases.map { game in
            (game, [en.text("game." + game.rawValue), zh.text("game." + game.rawValue), game.rawValue].joined(separator: " "))
        })
        let results = Dictionary(uniqueKeysWithValues: GameOutcome.allCases.map { outcome in
            (outcome, en.text("history.result." + outcome.rawValue) + " " + zh.text("history.result." + outcome.rawValue))
        })
        let difficultyLabels = Dictionary(uniqueKeysWithValues: ["easy", "medium", "normal", "hard", "custom"].map { value in
            (value, en.text("difficulty." + value) + " " + zh.text("difficulty." + value))
        })
        let modeKeys = ["singlePlayer": "tictactoe.mode.singlePlayer", "localTwoPlayer": "tictactoe.mode.localTwoPlayer",
                        "answer": "sudoku.answerPen", "pencil": "sudoku.pencil"]
        let modes = Dictionary(uniqueKeysWithValues: modeKeys.map { value, key in
            (value, en.text(key) + " " + zh.text(key))
        })
        let tokens = search.split(whereSeparator: \.isWhitespace).map(String.init)
        let minimum = dateWindow.minimumDate()
        let now = Date()
        return model.playRecords.filter { record in
            guard selectedGame == nil || selectedGame == record.gameID,
                  selectedDifficulty == nil || selectedDifficulty == record.difficulty,
                  selectedOutcome == nil || selectedOutcome == record.result else { return false }
            if let minimum, record.finishedAt < minimum || record.finishedAt > now { return false }
            guard !tokens.isEmpty else { return true }
            let corpus = [names[record.gameID] ?? "", record.difficulty, record.mode, record.result.rawValue,
                          results[record.result] ?? "", difficultyLabels[record.difficulty] ?? "", modes[record.mode] ?? "",
                          GameRecordText.date(record.finishedAt, model: model),
                          GameRecordText.searchDate(record.finishedAt),
                          GameRecordText.duration(record.elapsedSeconds), String(record.moves)].joined(separator: " ")
            return tokens.allSatisfy { corpus.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }.sorted { first, second in
            if sort == .newest || sort == .oldest {
                if first.finishedAt != second.finishedAt { return sort == .newest ? first.finishedAt > second.finishedAt : first.finishedAt < second.finishedAt }
            } else if sort == .shortest || sort == .longest {
                if first.elapsedSeconds != second.elapsedSeconds { return sort == .shortest ? first.elapsedSeconds < second.elapsedSeconds : first.elapsedSeconds > second.elapsedSeconds }
            } else if first.moves != second.moves {
                return sort == .fewestMoves ? first.moves < second.moves : first.moves > second.moves
            }
            if first.finishedAt != second.finishedAt { return first.finishedAt > second.finishedAt }
            return first.id.uuidString < second.id.uuidString
        }
    }

    var body: some View {
        let visibleRecords = records
        List {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(model.t("history.search.placeholder"), text: $search)
                        .focused($searching).submitLabel(.done).autocorrectionDisabled()
                        .onSubmit { searching = false }.accessibilityIdentifier("history.search")
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.borderless).accessibilityLabel(model.t("history.search.clear"))
                            .accessibilityIdentifier("history.search.clear")
                    }
                }
                .background {
                    HistoryOutsideSearchTap(isActive: dismissKeyboardOnOutsideTap) { searching = false }
                        .frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
                }
                Text(filterDescription).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("history.filters.summary")
            }
            if model.playRecords.isEmpty {
                emptyState(hasRecords: false)
            } else if visibleRecords.isEmpty {
                emptyState(hasRecords: true)
            } else {
                Section(model.t("history.count", visibleRecords.count)) {
                    ForEach(visibleRecords) { record in
                        Button {
                            searching = false
                            guard presentation == nil else { return }
                            presentation = .record(record)
                        } label: { HistoryRecordRow(record: record) }
                            .buttonStyle(.plain).accessibilityIdentifier("history.record." + record.id.uuidString)
                    }
                }
            }
            Section {
                Text(model.t("history.sinceUpdate")).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.listRowBackground(Color.clear)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("history.list")
        .onAppear { dismissKeyboardOnOutsideTap = true }
        .onDisappear { dismissKeyboardOnOutsideTap = false }
        .localizedNavigation().navigationTitle(model.t("history.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { filterMenu }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(model.t("common.done")) { searching = false }.accessibilityIdentifier("history.keyboard.done")
            }
        }
        .sheet(item: $presentation) { item in
            NavigationStack {
                switch item {
                case let .filter(kind):
                    HistoryFilterView(kind: kind, selectedGame: $selectedGame, difficulty: $selectedDifficulty,
                                      outcome: $selectedOutcome, dateWindow: $dateWindow, sort: $sort,
                                      difficulties: difficulties)
                case let .record(record): HistoryRecordDetail(record: record)
                }
            }
        }
    }

    private var filterDescription: String {
        [selectedGame.map(model.gameTitle) ?? model.t("history.allGames"),
         selectedDifficulty.map { GameRecordText.difficulty($0, model: model) } ?? model.t("history.allDifficulties"),
         selectedOutcome.map { model.t("history.result." + $0.rawValue) } ?? model.t("history.allResults"),
         model.t("history.window." + dateWindow.rawValue)].joined(separator: " · ")
    }
    private var filterMenu: some View {
        Menu {
            ForEach(HistoryFilterKind.allCases) { kind in
                Button(model.t(kind.titleKey)) {
                    searching = false
                    guard presentation == nil else { return }
                    presentation = .filter(kind)
                }.accessibilityIdentifier("history.filter." + kind.rawValue)
            }
            Divider()
            Button(model.t("history.resetFilters"), action: resetFilters)
        } label: {
            Label(model.t("history.filters"), systemImage: "line.3.horizontal.decrease.circle")
        }.accessibilityIdentifier("history.filters")
            .simultaneousGesture(TapGesture().onEnded { searching = false })
    }
    private func emptyState(hasRecords: Bool) -> some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: hasRecords ? "magnifyingglass" : "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.secondary)
                Text(model.t(hasRecords ? "history.noResults" : "history.empty")).font(.headline)
                Text(model.t(hasRecords ? "history.noResults.detail" : "history.empty.detail"))
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if hasRecords {
                    Button(model.t("history.resetSearch")) { search = ""; resetFilters() }
                        .buttonStyle(.bordered).accessibilityIdentifier("history.resetSearch")
                }
            }.frame(maxWidth: .infinity).padding(.vertical, 24)
        }
    }
    private func resetFilters() {
        selectedGame = nil; selectedDifficulty = nil; selectedOutcome = nil; dateWindow = .all; sort = .newest
        searching = false
    }
}

/// List rows can move independently of SwiftUI preference delivery when the
/// keyboard appears. Read the live native search-row bounds at touch time,
/// rather than comparing a cached frame with another gesture's coordinates.
private struct HistoryOutsideSearchTap: UIViewRepresentable {
    let isActive: Bool
    let dismissKeyboard: () -> Void
    func makeUIView(context: Context) -> HistoryOutsideSearchTapView {
        let view = HistoryOutsideSearchTapView()
        view.configure(isActive: isActive, dismissKeyboard: dismissKeyboard)
        return view
    }
    func updateUIView(_ view: HistoryOutsideSearchTapView, context: Context) {
        view.configure(isActive: isActive, dismissKeyboard: dismissKeyboard)
    }
    static func dismantleUIView(_ view: HistoryOutsideSearchTapView, coordinator: ()) { view.detach() }
}

private final class HistoryOutsideSearchTapView: UIView, UIGestureRecognizerDelegate {
    private weak var installedWindow: UIWindow?
    private var active = false
    private var dismissKeyboard: (() -> Void)?
    private lazy var outsideTap = HistoryOutsideTapRecognizer(target: self, action: #selector(tappedOutside))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        outsideTap.cancelsTouchesInView = false
        outsideTap.delaysTouchesBegan = false
        outsideTap.delaysTouchesEnded = false
        outsideTap.delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateRegistration()
    }
    func configure(isActive: Bool, dismissKeyboard: @escaping () -> Void) {
        active = isActive
        self.dismissKeyboard = dismissKeyboard
        updateRegistration()
    }
    func detach() {
        installedWindow?.removeGestureRecognizer(outsideTap)
        installedWindow = nil
    }
    private func updateRegistration() {
        guard active, let window else { detach(); return }
        guard installedWindow !== window else { return }
        detach()
        window.addGestureRecognizer(outsideTap)
        installedWindow = window
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard active, window != nil, !isHidden else { return false }
        // This native view fills the search row, including its clear button.
        // UIKit converts the live touch directly, including any scroll offset.
        guard !bounds.contains(touch.location(in: self)) else { return false }
        var target = touch.view
        while let view = target {
            if view is UITextField || view is UITextView || view is UIInputView { return false }
            target = view.superview
        }
        return true
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    @objc private func tappedOutside() { dismissKeyboard?() }
}

/// A native Menu can prevent an ordinary window UITapGestureRecognizer from
/// ending. Observe a stationary release independently, without cancelling the
/// Menu/record's own touch or stealing a scroll gesture.
private final class HistoryOutsideTapRecognizer: UIGestureRecognizer {
    private var start: CGPoint?
    private var eligible = false
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>,with event: UIEvent) {
        guard start == nil, touches.count == 1, let touch = touches.first else { eligible = false; return }
        start = touch.location(in:view); eligible = true
    }
    override func touchesMoved(_ touches: Set<UITouch>,with event: UIEvent) {
        guard let start, let touch = touches.first else { return }
        let point = touch.location(in:view)
        if hypot(point.x-start.x,point.y-start.y)>=8 { eligible = false }
    }
    override func touchesEnded(_ touches: Set<UITouch>,with event: UIEvent) { state = eligible ? .recognized : .failed }
    override func touchesCancelled(_ touches: Set<UITouch>,with event: UIEvent) { state = .failed }
    override func reset() { start = nil; eligible = false; super.reset() }
}

private enum HistoryDateWindow: String, CaseIterable, Identifiable {
    case all, today, week, month
    var id: String { rawValue }
    func minimumDate(now: Date = Date()) -> Date? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        switch self {
        case .all: return nil
        case .today: return start
        case .week: return calendar.date(byAdding: .day, value: -6, to: start)
        case .month: return calendar.date(byAdding: .day, value: -29, to: start)
        }
    }
}
private enum HistorySort: String, CaseIterable, Identifiable {
    case newest, oldest, shortest, longest, fewestMoves, mostMoves
    var id: String { rawValue }
}
private enum HistoryFilterKind: String, CaseIterable, Identifiable {
    case game, difficulty, result, date, sort
    var id: String { rawValue }
    var titleKey: String { "history.filter." + rawValue }
}
private enum HistoryPresentation: Identifiable, Equatable {
    case filter(HistoryFilterKind), record(GamePlayRecord)
    var id: String {
        switch self { case let .filter(kind): return "filter." + kind.rawValue
        case let .record(record): return "record." + record.id.uuidString }
    }
}

private struct HistoryFilterView: View {
    let kind: HistoryFilterKind
    @Binding var selectedGame: GameID?
    @Binding var difficulty: String?
    @Binding var outcome: GameOutcome?
    @Binding var dateWindow: HistoryDateWindow
    @Binding var sort: HistorySort
    let difficulties: [String]
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            switch kind {
            case .game:
                option(model.t("history.allGames"), selected: selectedGame == nil) { selectedGame = nil; difficulty = nil }
                ForEach(GameID.allCases) { game in
                    option(model.gameTitle(game), selected: selectedGame == game) { selectedGame = game; difficulty = nil }
                }
            case .difficulty:
                option(model.t("history.allDifficulties"), selected: difficulty == nil) { difficulty = nil }
                ForEach(difficulties, id: \.self) { value in
                    option(GameRecordText.difficulty(value, model: model), selected: difficulty == value) { difficulty = value }
                }
            case .result:
                option(model.t("history.allResults"), selected: outcome == nil) { outcome = nil }
                ForEach(GameOutcome.allCases, id: \.self) { value in
                    option(model.t("history.result." + value.rawValue), selected: outcome == value) { outcome = value }
                }
            case .date:
                ForEach(HistoryDateWindow.allCases) { value in
                    option(model.t("history.window." + value.rawValue), selected: dateWindow == value) { dateWindow = value }
                }
            case .sort:
                ForEach(HistorySort.allCases) { value in
                    option(model.t("history.sort." + value.rawValue), selected: sort == value) { sort = value }
                }
            }
        }
        .navigationTitle(model.t(kind.titleKey)).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(model.t("common.done")) { dismiss() } } }
    }
    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action(); dismiss()
        } label: {
            HStack { Text(title).foregroundStyle(.primary); Spacer(); if selected { Image(systemName: "checkmark").foregroundStyle(.tint) } }
        }
    }
}

private struct HistoryRecordRow: View {
    let record: GamePlayRecord
    @EnvironmentObject private var model: AppModel
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GameArtwork(game: record.gameID, size: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(model.gameTitle(record.gameID)).font(.headline).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(model.t("history.result." + record.result.rawValue)).font(.caption.weight(.semibold))
                        .foregroundStyle(GamePalette.tint(record.gameID))
                }
                Text(GameRecordText.difficulty(record.difficulty, model: model) + " · " + GameRecordText.date(record.finishedAt, model: model))
                    .font(.caption).foregroundStyle(.secondary)
                Text(GameRecordText.duration(record.elapsedSeconds) + " · " + model.t("history.moves", record.moves))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6).contentShape(Rectangle())
    }
}

private struct HistoryRecordDetail: View {
    let record: GamePlayRecord
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section {
                LabeledContent(model.t("history.game"), value: model.gameTitle(record.gameID))
                LabeledContent(model.t("history.result"), value: model.t("history.result." + record.result.rawValue))
                LabeledContent(model.t("history.difficulty"), value: GameRecordText.difficulty(record.difficulty, model: model))
                if !record.mode.isEmpty { LabeledContent(model.t("history.mode"), value: GameRecordText.mode(record.mode, model: model)) }
                LabeledContent(model.t("history.started"), value: GameRecordText.date(record.startedAt, model: model))
                LabeledContent(model.t("history.finished"), value: GameRecordText.date(record.finishedAt, model: model))
                LabeledContent(model.t("history.elapsed"), value: GameRecordText.duration(record.elapsedSeconds))
                LabeledContent(model.t("history.moves.title"), value: String(record.moves))
            }
        }.navigationTitle(model.t("history.recordDetail")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(model.t("common.done")) { dismiss() } } }
    }
}

@MainActor enum GameRecordText {
    private static let chineseDate = dateFormatter(locale: "zh-Hant")
    private static let englishDate = dateFormatter(locale: "en")
    private static let isoDate: DateFormatter = {
        let value = DateFormatter(); value.locale = Locale(identifier: "en_US_POSIX")
        value.dateFormat = "yyyy-MM-dd"; return value
    }()
    private static func dateFormatter(locale: String) -> DateFormatter {
        let value = DateFormatter(); value.locale = Locale(identifier: locale)
        value.dateStyle = .medium; value.timeStyle = .short; return value
    }
    static func date(_ date: Date, model: AppModel) -> String {
        (model.preferences.language == .english ? englishDate : chineseDate).string(from: date)
    }
    static func searchDate(_ date: Date) -> String { isoDate.string(from: date) }
    static func duration(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
    static func difficulty(_ value: String, model: AppModel) -> String {
        guard !value.isEmpty else { return model.t("history.unspecified") }
        let key = "difficulty." + value, translated = model.t("difficulty." + value)
        return translated == key ? value : translated
    }
    static func modeKey(_ value: String) -> String? {
        switch value {
        case "singlePlayer", "localTwoPlayer": return "tictactoe.mode." + value
        case "answer": return "sudoku.answerPen"
        case "pencil": return "sudoku.pencil"
        default: return GameID(rawValue:value).map { "game."+$0.rawValue }
        }
    }
    static func mode(_ value: String, model: AppModel) -> String {
        guard !value.isEmpty else { return model.t("history.unspecified") }
        return modeKey(value).map { model.t($0) } ?? value
    }
}
