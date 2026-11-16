import SwiftUI
import ChaiCore

struct SlidingMenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var size = 3
    @State private var difficulty = SlidingBoard.Difficulty.normal
    @State private var play = false
    @State private var confirm = false
    private func start() {
        do { model.saveSliding(try SlidingBoard(size: size, difficulty: difficulty)); play = true }
        catch { model.error = "無法建立拼圖：\(error.localizedDescription)" }
    }
    var body: some View {
        Form {
            if model.sliding != nil { Button("繼續遊戲") { play = true }.accessibilityIdentifier("sliding.continue") }
            Section("新遊戲") {
                Picker("盤面", selection: $size) { ForEach(3...5, id: \.self) { Text("\($0)×\($0)").tag($0) } }.pickerStyle(.segmented)
                Picker("難度", selection: $difficulty) { ForEach(SlidingBoard.Difficulty.allCases, id: \.self) { Text($0.title).tag($0) } }
                Button("開始遊戲") { if model.sliding != nil { confirm = true } else { start() } }.accessibilityIdentifier("sliding.start")
            }
        }.navigationTitle("滑塊拼圖")
            .navigationDestination(isPresented: $play) { SlidingPlayView() }
            .confirmationDialog("新遊戲將取代滑塊拼圖存檔。", isPresented: $confirm, titleVisibility: .visible) {
                Button("開始新遊戲", role: .destructive) { start() }
            }
    }
}

struct SlidingPlayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) var scenePhase
    @State private var paused = false
    @State private var visible = false
    @State private var restart = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        ScrollView {
            if let board = model.sliding {
                VStack(spacing: 20) {
                    HStack {
                        Text("\(board.size)×\(board.size) · \(board.difficulty.title)")
                        Spacer(); Text("\(board.moves) 步 · \(board.elapsedSeconds) 秒").monospacedDigit()
                    }.font(.subheadline).foregroundStyle(.secondary)
                    if board.isComplete { Text("完成").font(.title2).accessibilityIdentifier("sliding.complete") }
                    if paused || scenePhase != .active {
                        Button("繼續遊戲") { paused = false }.frame(height: 300).frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: board.size), spacing: 6) {
                            ForEach(board.tiles.indices, id: \.self) { i in
                                Button { model.editSliding { $0.move(i) } } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7).fill(board.tiles[i] == 0 ? Color.clear : Color(.secondarySystemGroupedBackground))
                                        if board.tiles[i] != 0 { Text("\(board.tiles[i])").font(.system(.title, design: .serif)).foregroundStyle(.primary) }
                                    }.aspectRatio(1, contentMode: .fit)
                                }.buttonStyle(.plain).disabled(board.tiles[i] == 0 || board.isComplete)
                                    .accessibilityLabel(board.tiles[i] == 0 ? "空格" : "方塊 \(board.tiles[i])")
                                    .accessibilityIdentifier("sliding.tile.\(i)")
                            }
                        }.padding(8).background(Color(.systemGray4), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button(paused ? "繼續" : "暫停", systemImage: paused ? "play" : "pause") { paused.toggle() }.buttonStyle(.bordered)
                }.padding().frame(maxWidth: 540)
            }
        }.background(Color(.systemGroupedBackground))
            .navigationTitle("滑塊拼圖").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("重新開始") { restart = true } }
            .confirmationDialog("恢復本局最初盤面並清除步數與計時？", isPresented: $restart, titleVisibility: .visible) {
                Button("重新開始", role: .destructive) { model.editSliding { $0.restart() } }
            }
            .onAppear { visible = true }.onDisappear { visible = false }
            .onReceive(timer) { _ in
                if visible && !paused && scenePhase == .active && model.sliding?.isComplete == false {
                    model.editSliding { $0.elapsedSeconds += 1 }
                }
            }
    }
}
