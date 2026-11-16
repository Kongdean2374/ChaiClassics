import SwiftUI
import ChaiCore

struct SudokuMenuView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        List {
            if let id = model.sudoku.currentID, let puzzle = model.puzzles.first(where: { $0.id == id }) {
                Section {
                    NavigationLink("繼續：\(puzzle.difficulty.title) \(String(format: "%03d", puzzle.number))") {
                        SudokuPlayView(puzzle: puzzle)
                    }.accessibilityIdentifier("sudoku.continue")
                }
            }
            Section("選擇難度") {
                ForEach(SudokuDifficulty.allCases, id: \.self) { difficulty in
                    NavigationLink(difficulty.title) { SudokuLevelsView(difficulty: difficulty) }
                }
            }
        }.navigationTitle("數獨")
    }
}

struct SudokuLevelsView: View {
    let difficulty: SudokuDifficulty
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(model.puzzles.filter { $0.difficulty == difficulty }) { puzzle in
                    let unlocked = model.sudoku.isUnlocked(puzzle, catalog: model.puzzles)
                    NavigationLink {
                        SudokuPlayView(puzzle: puzzle).onAppear { model.open(puzzle) }
                    } label: {
                        VStack(spacing: 8) {
                            Text(String(format: "%03d", puzzle.number)).font(.headline.monospacedDigit())
                            Text(model.sudoku.completed.contains(puzzle.id) ? "已完成" : model.sudoku.boards[puzzle.id] != nil ? "進行中" : unlocked ? "未完成" : "未解鎖")
                                .font(.caption2)
                        }.frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).disabled(!unlocked)
                        .accessibilityIdentifier(puzzle.id)
                }
            }.padding()
        }.navigationTitle(difficulty.title)
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
            VStack(spacing: 18) {
                HStack {
                    Text("\(puzzle.difficulty.title) · \(String(format: "%03d", puzzle.number))")
                    Spacer()
                    if complete { Text("完成").fontWeight(.semibold).accessibilityIdentifier("sudoku.complete") }
                }.font(.subheadline).foregroundStyle(.secondary)
                if paused || scenePhase != .active {
                    Button("繼續遊戲") { paused = false }.frame(height: 340).frame(maxWidth: .infinity)
                } else {
                    SudokuGrid(puzzle: puzzle, board: board) { index in model.edit(puzzle) { $0.selected = index } }
                }
                Picker("工具", selection: Binding(get: { board.mode }, set: { mode in model.edit(puzzle) { $0.mode = mode } })) {
                    Text("答案筆").tag(SudokuBoard.Mode.answer)
                    Text("鉛筆").tag(SudokuBoard.Mode.pencil)
                }.pickerStyle(.segmented).disabled(paused || complete)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 9), spacing: 5) {
                    ForEach(1...9, id: \.self) { digit in
                        Button { model.edit(puzzle) { $0.enter(digit, puzzle: puzzle) } } label: {
                            Text("\(digit)").font(.title3.monospacedDigit()).frame(maxWidth: .infinity).frame(height: 48)
                        }.buttonStyle(.bordered).accessibilityIdentifier("sudoku.digit.\(digit)")
                    }
                }.disabled(paused || complete)
                HStack {
                    Button("擦除", systemImage: "eraser") { model.edit(puzzle) { $0.erase(puzzle: puzzle) } }.disabled(paused || complete)
                    Spacer()
                    Button(paused ? "繼續" : "暫停", systemImage: paused ? "play" : "pause") { paused.toggle() }
                }.buttonStyle(.bordered)
            }.padding().frame(maxWidth: 560)
        }
        .background(Color(.systemBackground))
        .navigationTitle("數獨").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("重新開始") { confirmRestart = true } }
        .confirmationDialog("清除本題盤面與筆記？已完成紀錄會保留。", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("重新開始", role: .destructive) { model.open(puzzle, restart: true) }
        }
        .onAppear { model.open(puzzle) }
    }
}

struct SudokuGrid: View {
    let puzzle: SudokuPuzzle
    let board: SudokuBoard
    let select: (Int) -> Void
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
                                        Rectangle().fill(board.selected == i ? Color.accentColor.opacity(0.15) : Color.clear)
                                        if board.cells[i] != 0 {
                                            Text("\(board.cells[i])").font(.system(size: size * 0.58, weight: puzzle.givens[i] == 0 ? .regular : .semibold, design: .serif))
                                        } else {
                                            VStack(spacing: 0) {
                                                ForEach(0..<3, id: \.self) { nr in
                                                    HStack(spacing: 0) {
                                                        ForEach(1...3, id: \.self) { nc in
                                                            let d = nr * 3 + nc
                                                            Text(board.notes[i].contains(d) ? "\(d)" : " ")
                                                                .font(.system(size: size * 0.23)).frame(maxWidth: .infinity, maxHeight: .infinity)
                                                        }
                                                    }
                                                }
                                            }.padding(2)
                                        }
                                    }.frame(width: size, height: size).contentShape(Rectangle())
                                }.buttonStyle(.plain).foregroundStyle(.primary)
                                    .accessibilityLabel("第\(row + 1)列第\(col + 1)格，\(board.cells[i] == 0 ? "空白" : String(board.cells[i]))\(puzzle.givens[i] == 0 ? "" : "，題目數字")")
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
