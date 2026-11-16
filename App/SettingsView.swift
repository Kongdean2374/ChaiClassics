import SwiftUI
import ChaiCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Form {
            Section(model.t("settings.general")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.t("settings.appearance")).font(.subheadline)
                    Picker(model.t("settings.appearance"), selection: Binding(get: { model.preferences.appearance }, set: { value in model.updatePreferences { $0.appearance = value } })) {
                        ForEach(AppAppearance.allCases, id: \.self) { value in Text(model.t("theme." + value.rawValue)).tag(value) }
                    }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("settings.appearance")
                    Text(model.t("theme.effective", model.t(colorScheme == .dark ? "theme.dark" : "theme.light")))
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("settings.resolvedAppearance")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.t("settings.language")).font(.subheadline)
                    Picker(model.t("settings.language"), selection: Binding(get: { model.preferences.language }, set: { value in model.updatePreferences { $0.language = value } })) {
                        Text("繁體中文").tag(AppLanguage.traditionalChinese)
                        Text("English").tag(AppLanguage.english)
                    }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("settings.language")
                }
            }
            Section {
                Toggle(isOn: Binding(get: { model.preferences.haptics }, set: { value in model.updatePreferences { $0.haptics = value }; if value { model.feedback() } })) {
                    preferenceLabel("settings.haptics", detail: "settings.haptics.detail")
                }.accessibilityIdentifier("settings.haptics")
                Toggle(isOn: Binding(get: { model.preferences.keepScreenAwake }, set: { value in model.updatePreferences { $0.keepScreenAwake = value } })) {
                    preferenceLabel("settings.awake", detail: "settings.awake.detail")
                }.accessibilityIdentifier("settings.awake")
                Label(model.t("settings.autosave"), systemImage: "checkmark.shield")
            } header: {
                Text(model.t("settings.gamePreferences"))
            } footer: {
                Text(model.t("settings.autosave.detail"))
            }
            Section(model.t("settings.support")) {
                NavigationLink { LegalView(document: .support) } label: {
                    Label(model.t("legal.support"), systemImage: "questionmark.circle")
                }.accessibilityIdentifier("legal.support")
                Link(destination: OfficialWebsite.url(for: .home, language: model.preferences.language)) {
                    Label(model.t("support.website"), systemImage: "globe")
                }.accessibilityIdentifier("settings.website")
                SupportEmailLink(identifier: "settings.email")
            }
            Section(model.t("settings.legal")) {
                ForEach([LegalDocument.privacy, .terms]) { document in
                    NavigationLink { LegalView(document: document) } label: { Label(model.t(document.titleKey), systemImage: document.symbol) }
                        .accessibilityIdentifier("legal." + document.rawValue)
                }
            }
            Section {
                LabeledContent(model.t("settings.name"), value: "ChaiClassics")
                LabeledContent(model.t("settings.version"), value: AppInformation.version)
            } header: {
                Text(model.t("settings.about"))
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.t("settings.freeOffline"))
                    Text(model.t("settings.storage"))
                }
            }
        }.localizedNavigation().navigationTitle(model.t("settings.title"))
    }
    private func preferenceLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.t(title))
            Text(model.t(detail)).font(.caption).foregroundStyle(.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }
}
