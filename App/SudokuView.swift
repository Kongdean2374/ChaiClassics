import SwiftUI
import ChaiCore

struct SudokuMenuView: View {
    @EnvironmentObject var model: AppModel
    private let tint = GamePalette.tint(.sudoku)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GameIntroHeader(game: .sudoku, title: model.gameTitle(.sudoku), subtitle: model.t("sudoku.menu.subtitle"))
                if let id = model.sudoku.currentID, let puzzle = model.puzzles.first(where: { $0.id == id }), let board = model.sudoku.boards[id] {
                    VStack(alignment: .leading, spacing: 10) {
                        SudokuSectionLabel(title: model.t("menu.lastGame"))
                        NavigationLink { SudokuPlayView(puzzle: puzzle) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: board.isComplete(puzzle: puzzle) ? "checkmark.seal" : "play.fill")
                                    .font(.title3.weight(.semibold)).foregroundStyle(tint)
                                    .frame(width: 44, height: 44).background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(model.t(board.isComplete(puzzle: puzzle) ? "menu.viewLast" : "menu.continue"))
                                        .font(.headline).foregroundStyle(.primary)
                                    Text(model.summaryDetail(model.summary(.sudoku)))
                                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(tint)
                            }.padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(tint.opacity(0.13), lineWidth: 1) }
                        }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("sudoku.continue")
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    SudokuSectionLabel(title: model.t("menu.newGame"))
                    ForEach(SudokuDifficulty.allCases, id: \.self) { difficulty in
                        let catalog = model.puzzles.filter { $0.difficulty == difficulty }
                        let completed = catalog.filter { model.sudoku.completed.contains($0.id) }.count
                        NavigationLink { SudokuLevelsView(difficulty: difficulty) } label: {
                            SudokuDifficultyCard(difficulty: difficulty, completed: completed, total: catalog.count)
                        }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("sudoku.difficulty." + difficulty.rawValue)
                    }
                }
                Label {
                    Text(model.t("sudoku.paper")).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "pencil.and.outline").foregroundStyle(tint)
                }.font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
            }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background { GameCanvas() }.tint(tint)
            .localizedNavigation().navigationTitle(model.gameTitle(.sudoku)).navigationBarTitleDisplayMode(.inline)
    }
}

private struct SudokuSectionLabel: View {
    let title: String
    var body: some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SudokuDifficultyCard: View {
    let difficulty: SudokuDifficulty
    let completed: Int
    let total: Int
    @EnvironmentObject private var model: AppModel
    private let tint = GamePalette.tint(.sudoku)
    private var difficultyMark: String {
        switch difficulty { case .easy: return "leaf"; case .medium: return "circle.lefthalf.filled"; case .hard: return "sparkle" }
    }

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: difficultyMark).font(.title3).foregroundStyle(tint)
                .frame(width: 42, height: 42).background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.t("difficulty." + difficulty.rawValue)).font(.headline).foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                }
                Text(model.t("sudoku.difficulty.progress", completed, total))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ProgressView(value: Double(completed), total: Double(max(1, total)))
                    .tint(tint).accessibilityHidden(true)
            }
        }.padding(17).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.04), lineWidth: 1) }
            .accessibilityElement(children: .combine)
    }
}

struct SudokuLevelsView: View {
    let difficulty: SudokuDifficulty
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let tint = GamePalette.tint(.sudoku)
    private var catalog: [SudokuPuzzle] { model.puzzles.filter { $0.difficulty == difficulty } }
    private var completed: Int { catalog.filter { model.sudoku.completed.contains($0.id) }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GameIntroHeader(game: .sudoku, title: model.t("difficulty." + difficulty.rawValue), subtitle: model.t("sudoku.levels.subtitle"))
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.t("sudoku.difficulty.progress", completed, catalog.count))
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    ProgressView(value: Double(completed), total: Double(max(1, catalog.count)))
                        .tint(tint).accessibilityHidden(true)
                }.padding(17).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 130 : 86, maximum: 180), spacing: 12)], spacing: 12) {
                    ForEach(catalog) { puzzle in
                        let unlocked = model.sudoku.isUnlocked(puzzle, catalog: model.puzzles)
                        let current = model.sudoku.boards[puzzle.id]
                        let inProgress = current.map { !$0.isComplete(puzzle: puzzle) } ?? false
                        let finished = model.sudoku.completed.contains(puzzle.id)
                        NavigationLink { SudokuPlayView(puzzle: puzzle) } label: {
                            SudokuLevelCard(number: puzzle.number, unlocked: unlocked, inProgress: inProgress, finished: finished)
                        }.buttonStyle(QuietPressStyle()).disabled(!unlocked).accessibilityIdentifier(puzzle.id)
                    }
                }
            }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background { GameCanvas() }.tint(tint)
            .localizedNavigation().navigationTitle(model.t("difficulty." + difficulty.rawValue)).navigationBarTitleDisplayMode(.inline)
    }
}

private struct SudokuLevelCard: View {
    let number: Int
    let unlocked: Bool
    let inProgress: Bool
    let finished: Bool
    @EnvironmentObject private var model: AppModel
    private let tint = GamePalette.tint(.sudoku)
    private var stateKey: String { !unlocked ? "sudoku.locked" : inProgress ? "status.inProgress" : finished ? "status.completed" : "status.notStarted" }
    private var symbol: String { !unlocked ? "lock.fill" : inProgress ? "pencil.line" : finished ? "checkmark.circle.fill" : "circle.dotted" }

    var body: some View {
        VStack(spacing: 10) {
            Text(String(format: "%03d", number)).font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.65)
                .foregroundStyle(unlocked ? Color.primary : Color.secondary)
            Image(systemName: symbol).font(.caption).foregroundStyle(unlocked ? tint : Color.secondary.opacity(0.6))
                .accessibilityHidden(true)
            Text(model.t(stateKey)).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 91).padding(.horizontal, 6).padding(.vertical, 12)
            .background(unlocked ? Color(.secondarySystemGroupedBackground) : Color(.secondarySystemGroupedBackground).opacity(0.55), in: RoundedRectangle(cornerRadius: 19))
            .overlay { RoundedRectangle(cornerRadius: 19).strokeBorder(inProgress ? tint.opacity(0.35) : tint.opacity(unlocked ? 0.12 : 0.035), lineWidth: 1) }
            .accessibilityElement(children: .combine)
    }
}

struct SudokuPlayView: View {
    let puzzle: SudokuPuzzle
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) var scenePhase
    @State private var paused = false
    @State private var confirmRestart = false
    private let tint = GamePalette.tint(.sudoku)
    private var board: SudokuBoard { model.sudoku.boards[puzzle.id] ?? SudokuBoard(puzzle: puzzle) }
    private var complete: Bool { board.isComplete(puzzle: puzzle) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    GameMetric(symbol: "square.grid.3x3", value: model.t("sudoku.level.title", model.t("difficulty." + puzzle.difficulty.rawValue), puzzle.number), tint: tint)
                    Spacer(minLength: 0)
                    Image(systemName: board.mode == .answer ? "pencil.tip" : "pencil")
                        .font(.subheadline).foregroundStyle(tint).padding(10).background(tint.opacity(0.08), in: Circle())
                        .accessibilityHidden(true)
                }
                if complete {
                    GameResultBanner(game: .sudoku, title: model.t("status.completed"), detail: model.t("sudoku.completion.detail"), won: true, identifier: "sudoku.complete")
                }
                if paused || scenePhase != .active {
                    PauseCard(game: .sudoku) { paused = false }.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                } else {
                    SudokuGrid(puzzle: puzzle, board: board) { index in
                        if model.edit(puzzle, { $0.selected = index }) { model.feedback() }
                    }
                }
                VStack(spacing: 14) {
                    Picker(model.t("sudoku.tools"), selection: Binding(get: { board.mode }, set: { mode in model.edit(puzzle) { $0.mode = mode } })) {
                        Text(model.t("sudoku.answerPen")).tag(SudokuBoard.Mode.answer)
                        Text(model.t("sudoku.pencil")).tag(SudokuBoard.Mode.pencil)
                    }.pickerStyle(.segmented).disabled(paused || complete).accessibilityIdentifier("sudoku.tools")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(1...9, id: \.self) { digit in
                            Button {
                                if model.edit(puzzle, { $0.enter(digit, puzzle: puzzle) }) { model.feedback() }
                            } label: {
                                Text("\(digit)").font(.system(.title3, design: .rounded, weight: .medium).monospacedDigit())
                                    .lineLimit(1).minimumScaleFactor(0.6)
                                    .foregroundStyle(Color.blue).frame(maxWidth: .infinity).frame(height: 48)
                                    .background(tint.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("sudoku.digit.\(digit)")
                        }
                        Button {
                            if model.edit(puzzle, { $0.erase(puzzle: puzzle) }) { model.feedback() }
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: "eraser").font(.subheadline)
                                Text(model.t("sudoku.erase")).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                            }.foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 48)
                                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(QuietPressStyle()).accessibilityIdentifier("sudoku.erase")
                    }.disabled(paused || complete)
                }.padding(14).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                    .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.04), lineWidth: 1) }
                Button { paused.toggle() } label: {
                    Label(model.t(paused ? "common.resume" : "common.pause"), systemImage: paused ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(QuietPressStyle()).foregroundStyle(tint).disabled(complete).opacity(complete ? 0.45 : 1)
                    .accessibilityIdentifier("sudoku.pause")
            }.padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.background { GameCanvas() }.tint(tint)
            .localizedNavigation().navigationTitle(model.gameTitle(.sudoku)).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(model.t("common.restart")) { confirmRestart = true }.accessibilityIdentifier("sudoku.restart") }
            .confirmationDialog(model.t("sudoku.restart.confirm"), isPresented: $confirmRestart, titleVisibility: .visible) {
                Button(model.t("common.restart"), role: .destructive) { model.open(puzzle, restart: true); paused = false }.accessibilityIdentifier("sudoku.confirmRestart")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
            .modifier(GameplayActivity(game: .sudoku, active: !paused && !confirmRestart && !complete))
            .gameCompletionCelebration(completed: complete)
            .onAppear { model.open(puzzle) }
    }
}

struct SudokuGrid: View {
    let puzzle: SudokuPuzzle
    let board: SudokuBoard
    let select: (Int) -> Void
    @EnvironmentObject var model: AppModel
    private let tint = GamePalette.tint(.sudoku)

    private func label(_ i: Int, row: Int, column: Int) -> String {
        let value = board.cells[i] == 0 ? model.t("sudoku.blank") : String(board.cells[i])
        let given = puzzle.givens[i] == 0 ? "" : model.t("sudoku.given")
        let notes = board.notes[i].sorted().map(String.init).joined(separator: ", ")
        return model.t("sudoku.cell.label", row + 1, column + 1, value, given) + (notes.isEmpty ? "" : ", " + model.t("sudoku.notes", notes))
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size.width / 9
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<9, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<9, id: \.self) { col in
                                let i = row * 9 + col
                                Button { select(i) } label: {
                                    ZStack {
                                        Rectangle().fill(board.selected == i ? tint.opacity(0.12) : Color(.secondarySystemGroupedBackground))
                                        if board.cells[i] != 0 {
                                            Text("\(board.cells[i])").font(.system(size: size * 0.56, weight: puzzle.givens[i] == 0 ? .regular : .semibold, design: .serif))
                                                .foregroundStyle(puzzle.givens[i] == 0 ? Color.blue : Color.primary)
                                        } else {
                                            VStack(spacing: 0) {
                                                ForEach(0..<3, id: \.self) { nr in
                                                    HStack(spacing: 0) {
                                                        ForEach(1...3, id: \.self) { nc in
                                                            let d = nr * 3 + nc
                                                            Text(board.notes[i].contains(d) ? "\(d)" : " ")
                                                                .font(.system(size: size * 0.23)).foregroundStyle(Color.blue).frame(maxWidth: .infinity, maxHeight: .infinity)
                                                        }
                                                    }
                                                }
                                            }.padding(2)
                                        }
                                        if board.selected == i {
                                            Rectangle().strokeBorder(tint.opacity(0.55), lineWidth: 1.5)
                                        }
                                    }.frame(width: size, height: size).contentShape(Rectangle())
                                }.buttonStyle(.plain).foregroundStyle(.primary)
                                    .accessibilityLabel(label(i, row: row, column: col))
                                    .accessibilityValue(board.notes[i].isEmpty ? (board.cells[i] == 0 ? model.t("sudoku.blank") : String(board.cells[i])) : model.t("sudoku.notes", board.notes[i].sorted().map(String.init).joined(separator: ", ")))
                                    .accessibilityIdentifier("sudoku.cell.\(i)")
                            }
                        }
                    }
                }
                Path { path in
                    for n in 0...9 where n % 3 != 0 {
                        let offset = CGFloat(n) * size
                        path.move(to: CGPoint(x: offset, y: 0)); path.addLine(to: CGPoint(x: offset, y: geo.size.width))
                        path.move(to: CGPoint(x: 0, y: offset)); path.addLine(to: CGPoint(x: geo.size.width, y: offset))
                    }
                }.stroke(.primary.opacity(0.16), lineWidth: 0.5).allowsHitTesting(false)
                Path { path in
                    for n in stride(from: 3, through: 6, by: 3) {
                        let offset = CGFloat(n) * size
                        path.move(to: CGPoint(x: offset, y: 0)); path.addLine(to: CGPoint(x: offset, y: geo.size.width))
                        path.move(to: CGPoint(x: 0, y: offset)); path.addLine(to: CGPoint(x: geo.size.width, y: offset))
                    }
                }.stroke(.primary.opacity(0.65), lineWidth: 1.4).allowsHitTesting(false)
            }.background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.75), lineWidth: 1.8).allowsHitTesting(false) }
        }.aspectRatio(1, contentMode: .fit).padding(8)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15))
            .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(tint.opacity(0.09), lineWidth: 1) }
            .shadow(color: .black.opacity(0.035), radius: 12, y: 4)
    }
}
