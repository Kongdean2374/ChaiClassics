import SwiftUI
import ChaiCore

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10, alignment: .top), count: GameRegistry.columns)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    introduction
                    VStack(alignment: .leading, spacing: 14) {
                        Text(model.t("home.games"))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(GameRegistry.games) { game in
                                NavigationLink(value: game.id) {
                                    GameCard(game: game)
                                }
                                .buttonStyle(QuietPressStyle())
                                .disabled(model.blocked.contains(game.id))
                                .accessibilityLabel(cardLabel(game.id))
                                .accessibilityIdentifier("game.\(game.id.rawValue)")
                            }
                        }
                        .accessibilityIdentifier("home.threeColumns")
                    }
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "tray.and.arrow.down")
                            .accessibilityHidden(true)
                        Text(model.t("home.autosave"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("home.autosave")
                }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
            }
                .background { GameCanvas() }
                .navigationTitle(model.t("home.title"))
                .navigationDestination(for: GameID.self) { id in
                    switch id { case .sudoku: SudokuMenuView(); case .minesweeper: MinesMenuView(); case .sliding: SlidingMenuView() }
                }
                .toolbar {
                    NavigationLink { SettingsView() } label: {
                        Image(systemName: "gearshape")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(model.t("settings.title"))
                    .accessibilityIdentifier("settings.open")
                }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.t("home.tagline"))
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Label(model.t("home.promise"), systemImage: "leaf")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color(.secondarySystemGroupedBackground).opacity(0.85), in: Capsule())
        }
    }

    private func cardLabel(_ id: GameID) -> String {
        let summary = model.summary(id)
        let status = model.t(model.blocked.contains(id) ? "storage.attention" : "status." + summary.state.rawValue)
        let detail = model.blocked.contains(id) ? model.t("storage.preserved") : model.summaryDetail(summary)
        return [model.gameTitle(id), status, detail].joined(separator: ", ")
    }
}

private struct GameCard: View {
    let game: GameDescriptor
    @EnvironmentObject var model: AppModel
    @ScaledMetric(relativeTo: .subheadline) private var titleMinimumHeight: CGFloat = 42
    @ScaledMetric(relativeTo: .caption2) private var detailMinimumHeight: CGFloat = 54
    private var summary: GameSummary { model.summary(game.id) }
    private var tint: Color { GamePalette.tint(game.id) }
    private var status: String { model.t(model.blocked.contains(game.id) ? "storage.attention" : "status." + summary.state.rawValue) }
    private var detail: String { model.blocked.contains(game.id) ? model.t("storage.preserved") : model.summaryDetail(summary) }
    private var statusColor: Color {
        if model.blocked.contains(game.id) { return .orange }
        switch summary.state {
        case .notStarted: return .secondary
        case .inProgress: return tint
        case .completed: return .green
        case .failed: return .orange
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                GameArtwork(game: game.id, size: min(92, max(44, geometry.size.width - 4)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 96)
            .accessibilityHidden(true)

            Text(model.gameTitle(game.id))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: titleMinimumHeight)

            Text(status)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(statusColor.opacity(0.11), in: Capsule())

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: detailMinimumHeight, alignment: .top)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 280, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.08), tint.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(tint.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
    }
}
