import SwiftUI
import ChaiCore

@main
struct ChaiClassicsApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            HomeView().environmentObject(model)
                .alert("本機資料需要處理", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                    Button("知道了") { model.error = nil }
                } message: { Text(model.error ?? "") }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { model.store?.flush() }
                }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sudoku = SudokuProgress()
    @Published private(set) var sliding: SlidingBoard?
    @Published private(set) var mines: MinesweeperBoard?
    @Published private(set) var puzzles: [SudokuPuzzle] = []
    @Published var error: String?
    @Published private(set) var blocked: Set<GameID> = []
    let store: SaveStore?

    init() {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("ChaiClassics", isDirectory: true)
            store = try SaveStore(directory: directory)
        } catch { store = nil; self.error = "無法開啟存檔資料夾，遊戲暫停以保護進度：\(error.localizedDescription)"; blocked = Set(GameID.allCases) }
        do {
            puzzles = try SudokuPuzzle.bundled()
            if let saved = try store?.load(SudokuProgress.self, namespace: "sudoku") {
                guard saved.boards.allSatisfy({ id, board in
                    guard let puzzle = puzzles.first(where: { $0.id == id }) else { return false }
                    return board.isValidSave(for: puzzle)
                }), saved.currentID == nil || puzzles.contains(where: { $0.id == saved.currentID }) else {
                    throw SaveStore.StoreError.corrupt
                }
                sudoku = saved
            }
            if store?.recoveredBackup == true { error = "已從上一份完整備份恢復數獨進度。" }
        } catch { blocked.insert(.sudoku); self.error = "數獨資料無法讀取，已保留原檔並停止覆寫：\(error.localizedDescription)" }
        do {
            if let saved = try store?.load(MinesweeperBoard.self, namespace: "minesweeper") {
                guard saved.isValidSave else { throw SaveStore.StoreError.corrupt }
                mines = saved
            }
            if store?.recoveredBackup == true { error = "已從上一份完整備份恢復踩地雷進度。" }
        } catch { blocked.insert(.minesweeper); self.error = "踩地雷資料無法讀取，已停止覆寫：\(error.localizedDescription)" }
        do {
            if let saved = try store?.load(SlidingBoard.self, namespace: "sliding") {
                guard saved.isValidSave else { throw SaveStore.StoreError.corrupt }
                sliding = saved
            }
            if store?.recoveredBackup == true { error = "已從上一份完整備份恢復滑塊拼圖進度。" }
        } catch { blocked.insert(.sliding); self.error = "滑塊拼圖資料無法讀取，已停止覆寫：\(error.localizedDescription)" }
    }

    func saveSudoku(_ next: SudokuProgress) {
        guard !blocked.contains(.sudoku), let store else { return }
        do { try store.save(next, namespace: "sudoku"); sudoku = next }
        catch { self.error = "寫入失敗，本次操作未儲存：\(error.localizedDescription)" }
    }
    func open(_ puzzle: SudokuPuzzle, restart: Bool = false) {
        var next = sudoku
        if restart || next.boards[puzzle.id] == nil { next.boards[puzzle.id] = SudokuBoard(puzzle: puzzle) }
        next.currentID = puzzle.id
        saveSudoku(next)
    }
    func edit(_ puzzle: SudokuPuzzle, _ change: (inout SudokuBoard) -> Void) {
        guard var board = sudoku.boards[puzzle.id] else { return }
        change(&board)
        var next = sudoku; next.record(board, puzzle: puzzle); saveSudoku(next)
    }
    func hasSave(_ game: GameID) -> Bool {
        switch game { case .sudoku: return sudoku.currentID != nil; case .minesweeper: return mines != nil; case .sliding: return sliding != nil }
    }
}


extension AppModel {
    func saveMines(_ next: MinesweeperBoard) {
        guard !blocked.contains(.minesweeper), let store else { return }
        do { try store.save(next, namespace: "minesweeper"); mines = next }
        catch { self.error = "寫入失敗，本次操作未儲存：\(error.localizedDescription)" }
    }
    func editMines(_ change: (inout MinesweeperBoard) -> Void) {
        guard var board = mines else { return }
        change(&board); saveMines(board)
    }
}


extension AppModel {
    func saveSliding(_ next: SlidingBoard) {
        guard !blocked.contains(.sliding), let store else { return }
        do { try store.save(next, namespace: "sliding"); sliding = next }
        catch { self.error = "寫入失敗，本次操作未儲存：\(error.localizedDescription)" }
    }
    func editSliding(_ change: (inout SlidingBoard) -> Void) {
        guard var board = sliding else { return }
        change(&board); saveSliding(board)
    }
}
