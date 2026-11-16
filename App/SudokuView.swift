import SwiftUI
import ChaiCore

struct SudokuMenuView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        List {
            if let id = model.sudoku.currentID, let puzzle = model.puzzles.first(where: { $0.id == id }), let board = model.sudoku.boards[id] {
                Section(model.t("menu.lastGame")) {
                    NavigationLink { SudokuPlayView(puzzle: puzzle) } label: {
                        ContinueCard(title: model.t(board.isComplete(puzzle: puzzle) ? "menu.viewLast" : "menu.continue"), detail: model.summaryDetail(model.summary(.sudoku)))
                    }.accessibilityIdentifier("sudoku.continue")
                }
            }
            Section(model.t("menu.newGame")) {
                ForEach(SudokuDifficulty.allCases, id: \.self) { difficulty in
                    let catalog = model.puzzles.filter { $0.difficulty == difficulty }
                    let completed = catalog.filter { model.sudoku.completed.contains($0.id) }.count
                    NavigationLink { SudokuLevelsView(difficulty: difficulty) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(model.t("difficulty." + difficulty.rawValue)).font(.headline)
                                Text(model.t("sudoku.difficulty.progress", completed, catalog.count)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "square.grid.3x3").foregroundStyle(.tint)
                        }.padding(.vertical, 6)
                    }.accessibilityIdentifier("sudoku.difficulty." + difficulty.rawValue)
                }
            }
            Section { Text(model.t("sudoku.paper")).font(.footnote).foregroundStyle(.secondary) }
        }.localizedNavigation().navigationTitle(model.gameTitle(.sudoku))
    }
}

struct SudokuLevelsView: View {
    let difficulty: SudokuDifficulty
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                ForEach(model.puzzles.filter { $0.difficulty == difficulty }) { puzzle in
                    let unlocked = model.sudoku.isUnlocked(puzzle, catalog: model.puzzles)
                    let current = model.sudoku.boards[puzzle.id]
                    let inProgress = current.map { !$0.isComplete(puzzle: puzzle) } ?? false
                    let finished = model.sudoku.completed.contains(puzzle.id)
                    NavigationLink { SudokuPlayView(puzzle: puzzle) } label: {
                        VStack(spacing: 7) {
                            Text(String(format: "%03d", puzzle.number)).font(.headline.monospacedDigit())
                            Image(systemName: !unlocked ? "lock" : inProgress ? "pencil" : finished ? "checkmark.circle.fill" : "circle")
                                .font(.caption).foregroundStyle(finished && !inProgress ? Color.green : Color.secondary)
                            Text(model.t(!unlocked ? "sudoku.locked" : inProgress ? "status.inProgress" : finished ? "status.completed" : "status.notStarted"))
                                .font(.caption2).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                        }.frame(maxWidth: .infinity, minHeight: 88).padding(.vertical, 8)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).disabled(!unlocked).accessibilityIdentifier(puzzle.id)
                }
            }.padding(16).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(Color(.systemGroupedBackground)).localizedNavigation().navigationTitle(model.t("difficulty." + difficulty.rawValue))
    }
}

struct SudokuPlayView: View {
    let puzzle: SudokuPuzzle
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) var scenePhase
    @State private var paused = false
    @State private var confirmRestart = false
    private var board: SudokuBoard { model.sudoku.boards[puzzle.id] ?? SudokuBoard(puzzle: puzzle) }
    private var complete: Bool { board.isComplete(puzzle: puzzle) }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text(model.t("sudoku.level.title", model.t("difficulty." + puzzle.difficulty.rawValue), puzzle.number))
                    Spacer()
                    if complete { Text(model.t("status.completed")).fontWeight(.semibold).accessibilityIdentifier("sudoku.complete") }
                }.font(.subheadline).foregroundStyle(.secondary)
                if paused || scenePhase != .active {
                    Button(model.t("common.resume")) { paused = false }.frame(height: 320).frame(maxWidth: .infinity)
                } else {
                    SudokuGrid(puzzle: puzzle, board: board) { index in
                        if model.edit(puzzle, { $0.selected = index }) { model.feedback() }
                    }
                }
                Picker(model.t("sudoku.tools"), selection: Binding(get: { board.mode }, set: { mode in model.edit(puzzle) { $0.mode = mode } })) {
                    Text(model.t("sudoku.answerPen")).tag(SudokuBoard.Mode.answer)
                    Text(model.t("sudoku.pencil")).tag(SudokuBoard.Mode.pencil)
                }.pickerStyle(.segmented).disabled(paused || complete).accessibilityIdentifier("sudoku.tools")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(1...9, id: \.self) { digit in
                        Button {
                            if model.edit(puzzle, { $0.enter(digit, puzzle: puzzle) }) { model.feedback() }
                        } label: { Text("\(digit)").font(.title3.monospacedDigit()).frame(maxWidth: .infinity).frame(height: 44) }
                            .buttonStyle(.bordered).accessibilityIdentifier("sudoku.digit.\(digit)")
                    }
                }.disabled(paused || complete)
                HStack {
                    Button(model.t("sudoku.erase"), systemImage: "eraser") {
                        if model.edit(puzzle, { $0.erase(puzzle: puzzle) }) { model.feedback() }
                    }.disabled(paused || complete).accessibilityIdentifier("sudoku.erase")
                    Spacer()
                    Button(model.t(paused ? "common.resume" : "common.pause"), systemImage: paused ? "play" : "pause") { paused.toggle() }
                        .accessibilityIdentifier("sudoku.pause")
                }.buttonStyle(.bordered)
            }.padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.background(Color(.systemGroupedBackground))
            .localizedNavigation().navigationTitle(model.gameTitle(.sudoku)).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(model.t("common.restart")) { confirmRestart = true }.accessibilityIdentifier("sudoku.restart") }
            .confirmationDialog(model.t("sudoku.restart.confirm"), isPresented: $confirmRestart, titleVisibility: .visible) {
                Button(model.t("common.restart"), role: .destructive) { model.open(puzzle, restart: true); paused = false }.accessibilityIdentifier("sudoku.confirmRestart")
                Button(model.t("common.cancel"), role: .cancel) {}
            }
            .modifier(GameplayActivity(game: .sudoku, active: !paused && !confirmRestart && !complete))
            .onAppear { model.open(puzzle) }
    }
}

struct SudokuGrid: View {
    let puzzle: SudokuPuzzle
    let board: SudokuBoard
    let select: (Int) -> Void
    @EnvironmentObject var model: AppModel
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
                                        Rectangle().fill(board.selected == i ? Color.accentColor.opacity(0.16) : Color(.secondarySystemGroupedBackground))
                                        if board.cells[i] != 0 {
                                            Text("\(board.cells[i])").font(.system(size: size * 0.58, weight: puzzle.givens[i] == 0 ? .regular : .semibold, design: .serif))
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
                }.stroke(.primary.opacity(0.25), lineWidth: 0.5).allowsHitTesting(false)
                Path { path in
                    for n in stride(from: 0, through: 9, by: 3) {
                        let offset = CGFloat(n) * size
                        path.move(to: CGPoint(x: offset, y: 0)); path.addLine(to: CGPoint(x: offset, y: geo.size.width))
                        path.move(to: CGPoint(x: 0, y: offset)); path.addLine(to: CGPoint(x: geo.size.width, y: offset))
                    }
                }.stroke(.primary, lineWidth: 1.8).allowsHitTesting(false)
            }
        }.aspectRatio(1, contentMode: .fit)
    }
}
