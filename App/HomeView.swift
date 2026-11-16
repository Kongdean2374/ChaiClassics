import SwiftUI
import ChaiCore

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: GameRegistry.columns)
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("隨時開始，隨時繼續。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(GameRegistry.games) { game in
                            NavigationLink(value: game.id) {
                                VStack(spacing: 14) {
                                    Image(systemName: game.symbol).font(.system(size: 32, weight: .light)).frame(height: 40)
                                    Text(game.name).font(.headline)
                                    Text(model.hasSave(game.id) ? "繼續遊戲" : "開始遊戲").font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 22)
                                .background(.background, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
                            }
                            .buttonStyle(.plain).disabled(model.blocked.contains(game.id))
                            .accessibilityIdentifier("game.\(game.id.rawValue)")
                        }
                    }.accessibilityIdentifier("home.threeColumns")
                }.padding().frame(maxWidth: 700)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("經典小遊戲")
            .navigationDestination(for: GameID.self) { id in
                switch id { case .sudoku: SudokuMenuView(); case .minesweeper: MinesMenuView(); case .sliding: SlidingMenuView() }
            }
            .toolbar { NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }.accessibilityLabel("設定") }
        }
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Section("關於") {
                LabeledContent("名稱", value: "Chai Classics")
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")
                LabeledContent("遊戲數量", value: "\(GameRegistry.games.count)")
                Text("永久免費、沒有廣告。所有遊戲皆可離線遊玩，不需帳號。")
                Text("進度只保存在這台裝置；移除 App 可能刪除所有進度。")
                    .foregroundStyle(.secondary)
            }
        }.navigationTitle("設定")
    }
}
