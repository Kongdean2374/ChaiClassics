import SwiftUI
import ChaiCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var dataOperationBusy = false
    var body: some View {
        Form {
            generalSection
            gameSection
            Section(model.t("settings.playData")) {
                NavigationLink { PlayHistoryView() } label: {
                    Label(model.t("history.title"), systemImage: "clock.arrow.circlepath")
                }.accessibilityIdentifier("settings.history")
                NavigationLink { GameSettingsDirectoryView() } label: {
                    Label(model.t("settings.individualGames"), systemImage: "slider.horizontal.3")
                }.accessibilityIdentifier("settings.individualGames")
            }
            GameDataTransferSection(game: nil, allowsImport: true, isBusy: $dataOperationBusy)
            Section(model.t("settings.support")) {
                SupportEmailLink(identifier: "settings.email")
                NavigationLink { LegalView(document: .support) } label: {
                    Label(model.t("legal.support"), systemImage: "questionmark.circle")
                }.accessibilityIdentifier("legal.support")
                Link(destination: OfficialWebsite.url(for: .home, language: model.preferences.language)) {
                    Label(model.t("support.website"), systemImage: "globe")
                }.accessibilityIdentifier("settings.website")
            }
            Section(model.t("settings.legal")) {
                ForEach([LegalDocument.privacy, .terms]) { document in
                    NavigationLink { LegalView(document: document) } label: { Label(model.t(document.titleKey), systemImage: document.symbol) }
                        .accessibilityIdentifier("legal." + document.rawValue)
                }
            }
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ChaiClassics").font(.system(.title3, design: .rounded, weight: .semibold))
                        Text(model.t("settings.about.subtitle")).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.vertical, 8)
                LabeledContent(model.t("settings.version"), value: AppInformation.version)
                    .monospacedDigit().accessibilityIdentifier("settings.version")
            } header: {
                Text(model.t("settings.about"))
            } footer: {
                Text(model.t("settings.freeOffline"))
            }
        }.localizedNavigation().navigationTitle(model.t("settings.title"))
    }
    private var generalSection: some View {
        Section(model.t("settings.general")) {
            VStack(alignment: .leading, spacing: 12) {
                Label(model.t("settings.appearance"), systemImage: "circle.lefthalf.filled").font(.subheadline)
                Picker(model.t("settings.appearance"), selection: Binding(get: { model.preferences.appearance }, set: { value in model.updatePreferences { $0.appearance = value } })) {
                    ForEach(AppAppearance.allCases, id: \.self) { value in Text(model.t("theme." + value.rawValue)).tag(value) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("settings.appearance")
                Text(model.t("theme.effective", model.t(colorScheme == .dark ? "theme.dark" : "theme.light")))
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("settings.resolvedAppearance")
            }.padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 12) {
                Label(model.t("settings.language"), systemImage: "globe").font(.subheadline)
                Picker(model.t("settings.language"), selection: Binding(get: { model.preferences.language }, set: { value in model.updatePreferences { $0.language = value } })) {
                    Text("繁體中文").tag(AppLanguage.traditionalChinese)
                    Text("English").tag(AppLanguage.english)
                }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("settings.language")
            }.padding(.vertical, 4)
        }
    }
    private var gameSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(model.t("settings.graphics"), systemImage: "sparkles").font(.subheadline)
                Picker(model.t("settings.graphics"), selection: Binding(get: { model.preferences.graphicsQuality }, set: { value in model.updatePreferences { $0.graphicsQuality = value } })) {
                    ForEach(GraphicsQuality.allCases, id: \.self) { value in Text(model.t("graphics." + value.rawValue)).tag(value) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("settings.graphics")
                Text(model.t("settings.graphics.detail")).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, 4)
            Toggle(isOn: Binding(get: { model.preferences.haptics }, set: { value in model.updatePreferences { $0.haptics = value }; if value { model.feedback() } })) {
                preferenceLabel("settings.haptics", detail: "settings.haptics.detail")
            }.accessibilityIdentifier("settings.haptics")
            Toggle(isOn: Binding(get: { model.preferences.keepScreenAwake }, set: { value in model.updatePreferences { $0.keepScreenAwake = value } })) {
                preferenceLabel("settings.awake", detail: "settings.awake.detail")
            }.accessibilityIdentifier("settings.awake")
            HStack {
                Label(model.t("settings.autosave"), systemImage: "checkmark.shield")
                Spacer()
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
            }
        } header: {
            Text(model.t("settings.gamePreferences"))
        } footer: {
            Text(model.t("settings.autosave.detail"))
        }
    }
    private func preferenceLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.t(title))
            Text(model.t(detail)).font(.caption).foregroundStyle(.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }
}

private struct GameSettingsDirectoryView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        List(GameRegistry.games) { descriptor in
            NavigationLink { GameSettingsView(game: descriptor.id) } label: {
                Label(model.gameTitle(descriptor.id), systemImage: descriptor.symbol)
            }.accessibilityIdentifier("settings.game." + descriptor.id.rawValue)
        }
        .localizedNavigation().navigationTitle(model.t("settings.individualGames"))
    }
}
