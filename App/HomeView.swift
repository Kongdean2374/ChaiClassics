import SwiftUI
import ChaiCore

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(model.t("home.title"))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("home.accessibleTitle")
                    }
                    introduction
                    VStack(alignment: .leading, spacing: 14) {
                        Text(model.t("home.games"))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        CatalogGrid(items: GameCatalog.homeItems, identifier: "home")
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
            .navigationTitle(dynamicTypeSize.isAccessibilitySize ? "" : model.t("home.title"))
            .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .automatic)
            .navigationDestination(for: CatalogItemID.self) { id in
                if let item = GameCatalog.item(id) {
                    switch item.kind {
                    case let .playable(game): GameMenuDestination(game: game)
                    case .comingSoon: ComingSoonView(item: item)
                    case .folder: CatalogFolderView(folder: item)
                    }
                }
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
}

private struct GameMenuDestination: View {
    let game: GameID
    @ViewBuilder var body: some View {
        switch game {
        case .sudoku: SudokuMenuView()
        case .minesweeper: MinesMenuView()
        case .sliding: SlidingMenuView()
        case .ticTacToe: TicTacToeMenuView()
        case .connectFour: ConnectFourMenuView()
        case .twentyFour: TwentyFourMenuView()
        case .memory: MemoryMenuView()
        case .maze: MazeMenuView()
        }
    }
}

/// Cards contain only catalog information, including their VoiceOver labels.
/// Progress and storage details belong to the corresponding game's menu.
private struct CatalogGrid: View {
    let items: [CatalogItem]
    let identifier: String
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columnCount: Int {
        // At accessibility sizes a three-column phone card is narrower than a
        // few large glyphs. Widen cards while keeping every name untruncated.
        if dynamicTypeSize >= .accessibility4 { return 1 }
        return dynamicTypeSize.isAccessibilitySize ? 2 : GameRegistry.columns
    }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10, alignment: .top), count: columnCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(items) { item in
                NavigationLink(value: item.id) {
                    CatalogCard(item: item)
                        .contentShape(Rectangle())
                }
                .buttonStyle(QuietPressStyle())
                .accessibilityLabel([model.t(item.titleKey), model.t(item.descriptionKey), item.availabilityText(using: model)].joined(separator: ", "))
                .accessibilityIdentifier(item.gameID.map { "game." + $0.rawValue } ?? "catalog." + item.id.rawValue)
            }
        }
        .accessibilityIdentifier(identifier + (columnCount == 3 ? ".threeColumns" : ".accessibleColumns"))
    }
}

private struct CatalogCard: View {
    let item: CatalogItem
    @EnvironmentObject private var model: AppModel
    @ScaledMetric(relativeTo: .subheadline) private var titleMinimumHeight: CGFloat = 42
    @ScaledMetric(relativeTo: .caption2) private var detailMinimumHeight: CGFloat = 54
    private var tint: Color { GamePalette.tint(item.accent) }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                CatalogArtwork(item: item, size: min(92, max(44, geometry.size.width - 4)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 96)
            .accessibilityHidden(true)

            Text(model.t(item.titleKey))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: titleMinimumHeight)

            Text(item.availabilityText(using: model))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(tint.opacity(0.11), in: Capsule())

            Text(model.t(item.descriptionKey))
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

private struct CatalogFolderView: View {
    let folder: CatalogItem
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(model.t(folder.descriptionKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if GameCatalog.children(of: folder.id).contains(where: { $0.gameID != nil }) {
                    Text(folder.availabilityText(using: model))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GamePalette.tint(folder.accent))
                        .accessibilityIdentifier("catalog.folder.availability")
                }
                CatalogGrid(items: GameCatalog.children(of: folder.id), identifier: folder.id.rawValue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background { GameCanvas() }
        .navigationTitle(model.t(folder.titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .localizedNavigation()
        .accessibilityIdentifier("catalog.folder." + folder.id.rawValue)
    }
}

private extension CatalogItem {
    func availabilityText(using model: AppModel) -> String {
        guard kind == .folder else { return model.t(availabilityKey) }
        let children = GameCatalog.children(of: id)
        let playable = children.filter { $0.gameID != nil }.count
        guard playable > 0 else { return model.t(availabilityKey) }
        return model.t(availabilityKey, playable, children.filter { $0.kind == .comingSoon }.count)
    }
}

private struct ComingSoonView: View {
    let item: CatalogItem
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                CatalogArtwork(item: item, size: 112)
                Text(model.t(item.titleKey))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("comingSoon.title")
                Text(model.t(item.descriptionKey))
                    .font(.body)
                    .foregroundStyle(.secondary)
                Label(model.t("catalog.comingSoon.message"), systemImage: "clock")
                    .font(.headline)
                    .foregroundStyle(GamePalette.tint(item.accent))
                    .padding(18)
                    .frame(maxWidth: .infinity)
                    .background(GamePalette.tint(item.accent).opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("comingSoon.status")
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(24)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .background { GameCanvas() }
        .navigationTitle(model.t(item.titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Label(model.t("common.back"), systemImage: "chevron.left")
                }.accessibilityIdentifier("comingSoon.back")
            }
        }
        .accessibilityIdentifier("comingSoon." + item.id.rawValue)
    }
}
