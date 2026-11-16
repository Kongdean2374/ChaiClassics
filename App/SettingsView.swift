import SwiftUI
import ChaiCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Form {
            Section(model.t("settings.appearance")) {
                Picker(model.t("settings.appearance"), selection: Binding(get: { model.preferences.appearance }, set: { value in model.updatePreferences { $0.appearance = value } })) {
                    ForEach(AppAppearance.allCases, id: \.self) { value in Text(model.t("theme." + value.rawValue)).tag(value) }
                }.pickerStyle(.segmented).accessibilityIdentifier("settings.appearance")
                Text(model.t("theme.effective", model.t(colorScheme == .dark ? "theme.dark" : "theme.light")))
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("settings.resolvedAppearance")
            }
            Section(model.t("settings.language")) {
                Picker(model.t("settings.language"), selection: Binding(get: { model.preferences.language }, set: { value in model.updatePreferences { $0.language = value } })) {
                    Text("繁體中文").tag(AppLanguage.traditionalChinese)
                    Text("English").tag(AppLanguage.english)
                }.pickerStyle(.segmented).accessibilityIdentifier("settings.language")
            }
            Section(model.t("settings.gamePreferences")) {
                Toggle(model.t("settings.haptics"), isOn: Binding(get: { model.preferences.haptics }, set: { value in model.updatePreferences { $0.haptics = value }; if value { model.feedback() } }))
                    .accessibilityIdentifier("settings.haptics")
                Text(model.t("settings.haptics.detail")).font(.caption).foregroundStyle(.secondary)
                Toggle(model.t("settings.awake"), isOn: Binding(get: { model.preferences.keepScreenAwake }, set: { value in model.updatePreferences { $0.keepScreenAwake = value } }))
                    .accessibilityIdentifier("settings.awake")
                Text(model.t("settings.awake.detail")).font(.caption).foregroundStyle(.secondary)
                Label(model.t("settings.autosave"), systemImage: "checkmark.shield")
                Text(model.t("settings.autosave.detail")).font(.caption).foregroundStyle(.secondary)
            }
            Section(model.t("settings.legal")) {
                ForEach(LegalDocument.allCases) { document in
                    NavigationLink { LegalView(document: document) } label: { Label(model.t(document.titleKey), systemImage: document.symbol) }
                        .accessibilityIdentifier("legal." + document.rawValue)
                }
            }
            Section(model.t("settings.about")) {
                LabeledContent(model.t("settings.name"), value: "Chai Classics")
                LabeledContent(model.t("settings.version"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1")
                LabeledContent(model.t("settings.games"), value: String(GameRegistry.games.count))
                Text(model.t("settings.freeOffline"))
                Text(model.t("settings.storage")).foregroundStyle(.secondary)
            }
        }.localizedNavigation().navigationTitle(model.t("settings.title"))
    }
}
