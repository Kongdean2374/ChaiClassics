import SwiftUI
import ChaiCore

struct MinesMenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var showPlay = false
    @State private var customWidth = 9
    @State private var customHeight = 9
    @State private var customMines = 10
    @State private var pending: MineConfiguration?
    private func start(_ config: MineConfiguration) {
        if model.mines != nil { pending = config }
        else { model.saveMines(MinesweeperBoard(configuration: config)); showPlay = true }
    }
    var body: some View {
        Form {
            if model.mines != nil {
                Button("繼續遊戲") { showPlay = true }.accessibilityIdentifier("mines.continue")
            }
            Section("新遊戲") {
                Button("簡單 · 9×9 · 10 雷") { start(.easy) }.accessibilityIdentifier("mines.easy")
                Button("中等 · 16×16 · 40 雷") { start(.medium) }
                Button("困難 · 30×16 · 99 雷") { start(.hard) }
            }
            Section("自訂") {
                Stepper("寬度：\(customWidth)", value: $customWidth, in: 5...40)
                Stepper("高度：\(customHeight)", value: $customHeight, in: 5...40)
                Stepper("地雷：\(customMines)", value: $customMines, in: 1...max(1, customWidth * customHeight - 1))
                Button("開始自訂遊戲") {
                    if let config = try? MineConfiguration(width: customWidth, height: customHeight, mines: customMines) { start(config) }
                }
            }
        }.navigationTitle("踩地雷")
            .onChange(of: customWidth) { _, _ in customMines = min(customMines, customWidth * customHeight - 1) }
            .onChange(of: customHeight) { _, _ in customMines = min(customMines, customWidth * customHeight - 1) }
            .navigationDestination(isPresented: $showPlay) { MinesPlayView() }
            .confirmationDialog("開始新遊戲將取代踩地雷存檔。", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                Button("開始新遊戲", role: .destructive) {
                    if let config = pending { model.saveMines(MinesweeperBoard(configuration: config)); showPlay = true }
                    pending = nil
                }
            }
    }
}

struct MinesPlayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var paused = false
    @State private var visible = false
    @State private var restart = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 12) {
            if let board = model.mines {
                HStack {
                    Text("雷 \(board.configuration.mineCount) · 旗 \(board.flags.count)")
                    Spacer(); Text("\(board.elapsedSeconds) 秒").monospacedDigit()
                }.font(.subheadline).padding(.horizontal)
                if board.status == .won { Text("完成").font(.headline).accessibilityIdentifier("mines.won") }
                if board.status == .lost { Text("遊戲結束").font(.headline).accessibilityIdentifier("mines.lost") }
                Picker("操作", selection: Binding(get: { board.mode }, set: { mode in model.editMines { $0.mode = mode } })) {
                    Text("揭開").tag(MinesweeperBoard.Mode.reveal)
                    Text("插旗").tag(MinesweeperBoard.Mode.flag)
                }.pickerStyle(.segmented).padding(.horizontal)
                if paused || scenePhase != .active {
                    Button("繼續遊戲") { paused = false }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ZoomBoard(size: CGSize(width: board.configuration.width * 34, height: board.configuration.height * 34)) {
                        MinesGrid(board: board, tap: { i in model.editMines { $0.tap(i) } }, flag: { i in model.editMines { $0.toggleFlag(i) } })
                    }.accessibilityIdentifier("mines.zoomBoard")
                }
                HStack {
                    Text("拖曳移動 · 雙指縮放 · 長按插旗").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(paused ? "繼續" : "暫停") { paused.toggle() }
                }.padding(.horizontal)
            }
        }.padding(.vertical).navigationTitle("踩地雷").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("重新開始") { restart = true } }
            .confirmationDialog("重新產生踩地雷盤面？", isPresented: $restart, titleVisibility: .visible) {
                Button("重新開始", role: .destructive) {
                    if let config = model.mines?.configuration { model.saveMines(MinesweeperBoard(configuration: config)) }
                }
            }
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .onReceive(timer) { _ in
                if visible && !paused && scenePhase == .active && model.mines?.status == .playing {
                    model.editMines { $0.elapsedSeconds += 1 }
                }
            }
    }
}

private struct MinesGrid: View {
    let board: MinesweeperBoard
    let tap: (Int) -> Void
    let flag: (Int) -> Void
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<board.configuration.height, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<board.configuration.width, id: \.self) { col in
                        let i = row * board.configuration.width + col
                        let open = board.revealed.contains(i)
                        ZStack {
                            Rectangle().fill(open ? Color(white: 0.88) : Color(white: 0.72))
                            Rectangle().strokeBorder(open ? Color.gray : Color.white, lineWidth: open ? 0.5 : 2)
                            if board.status == .lost && board.mines.contains(i) {
                                Image(systemName: "burst.fill").foregroundStyle(.black)
                            } else if board.flags.contains(i) {
                                Image(systemName: "flag.fill").foregroundStyle(.black)
                            } else if open && board.adjacentMines(i) > 0 {
                                Text("\(board.adjacentMines(i))").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(.black)
                            }
                        }.frame(width: 34, height: 34).contentShape(Rectangle())
                            .gesture(LongPressGesture(minimumDuration: 0.45).exclusively(before: TapGesture()).onEnded { value in
                                switch value { case .first: flag(i); case .second: tap(i) }
                            })
                            .accessibilityElement().accessibilityAddTraits(.isButton)
                            .accessibilityLabel("第\(row + 1)列第\(col + 1)格，\(board.flags.contains(i) ? "旗標" : open ? "已揭開 \(board.adjacentMines(i))" : "未揭開")")
                            .accessibilityAction { tap(i) }
                            .accessibilityAction(named: "插旗") { flag(i) }
                            .accessibilityIdentifier("mines.cell.\(i)")
                    }
                }
            }
        }
    }
}
