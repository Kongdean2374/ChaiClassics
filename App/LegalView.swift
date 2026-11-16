import SwiftUI
import ChaiCore

enum LegalDocument: String, CaseIterable, Identifiable {
    case privacy, terms, support
    var id: String { rawValue }
    var titleKey: String { "legal." + rawValue }
    var file: String { rawValue.capitalized }
    var websitePage: OfficialWebsite.Page {
        switch self { case .privacy: return .privacy; case .terms: return .terms; case .support: return .support }
    }
    var symbol: String { switch self { case .privacy: return "hand.raised"; case .terms: return "doc.text"; case .support: return "questionmark.circle" } }
}

struct LegalView: View {
    let document: LegalDocument
    @EnvironmentObject var model: AppModel
    private var paragraphs: [String] {
        guard let url = AppText(language: model.preferences.language).bundle.url(forResource: document.file, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [model.t("legal.unavailable")] }
        return text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.t("legal.offline")).font(.caption).foregroundStyle(.secondary)
                Link(destination: OfficialWebsite.url(for: document.websitePage, language: model.preferences.language)) {
                    Label(model.t("legal.online"), systemImage: "globe")
                }.accessibilityIdentifier("legal.online." + document.rawValue)
                if document == .support {
                    SupportEmailLink(identifier: "support.email")
                    Text(OfficialWebsite.supportEmail).textSelection(.enabled)
                        .accessibilityIdentifier("support.email.address")
                    Text(model.t("support.email.detail")).font(.callout).foregroundStyle(.secondary)
                }
                Divider()
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, text in
                    if text.hasPrefix("# ") {
                        Text(String(text.dropFirst(2))).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    } else if text.hasPrefix("## ") {
                        Text(String(text.dropFirst(3))).font(.headline).accessibilityAddTraits(.isHeader)
                    } else { Text(text).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                }
                Text(model.t("support.external")).font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
        }.localizedNavigation().navigationTitle(model.t(document.titleKey)).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("document." + document.rawValue)
    }
}
