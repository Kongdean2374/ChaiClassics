import SwiftUI
import ChaiCore

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: GameRegistry.columns)
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.t("home.tagline")).font(.title3.weight(.medium))
                        Label(model.t("home.promise"), systemImage: "leaf").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(GameRegistry.games) { game in
                            let summary = model.summary(game.id)
                            NavigationLink(value: game.id) {
                                VStack(spacing: 11) {
                                    Image(systemName: game.symbol).font(.system(size: 28, weight: .medium))
                                        .foregroundStyle(.tint).frame(width: 54, height: 54)
                                        .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                                    Text(model.gameTitle(game.id)).font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85).frame(minHeight: 36)
                                    SessionBadge(state: summary.state, title: model.t(model.blocked.contains(game.id) ? "storage.attention" : "status." + summary.state.rawValue))
                                    Text(model.blocked.contains(game.id) ? model.t("storage.preserved") : model.summaryDetail(summary))
                                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                        .lineLimit(4).fixedSize(horizontal: false, vertical: true).frame(minHeight: 50, alignment: .top)
                                }.padding(.horizontal, 5).padding(.vertical, 16)
                                    .frame(maxWidth: .infinity, minHeight: 214, alignment: .top)
                                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.06), lineWidth: 1))
                                    .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
                            }.buttonStyle(.plain).disabled(model.blocked.contains(game.id))
                                .accessibilityLabel(model.gameTitle(game.id) + ", " + model.t(model.blocked.contains(game.id) ? "storage.attention" : "status." + summary.state.rawValue) + ", " + model.summaryDetail(summary))
                                .accessibilityIdentifier("game.\(game.id.rawValue)")
                        }
                    }.accessibilityIdentifier("home.threeColumns")
                    Text(model.t("home.autosave")).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }.padding(.horizontal, 16).padding(.bottom, 24).frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
            }.background(Color(.systemGroupedBackground))
                .navigationTitle(model.t("home.title"))
                .navigationDestination(for: GameID.self) { id in
                    switch id { case .sudoku: SudokuMenuView(); case .minesweeper: MinesMenuView(); case .sliding: SlidingMenuView() }
                }
                .toolbar {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(model.t("settings.title")).accessibilityIdentifier("settings.open")
                }
        }
    }
}
