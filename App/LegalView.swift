import SwiftUI

enum LegalDocument: String, CaseIterable, Identifiable {
    case privacy, terms, support
    var id: String { rawValue }
    var titleKey: String { "legal." + rawValue }
    var file: String { rawValue.capitalized }
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
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, text in
                    if text.hasPrefix("# ") {
                        Text(String(text.dropFirst(2))).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    } else if text.hasPrefix("## ") {
                        Text(String(text.dropFirst(3))).font(.headline).accessibilityAddTraits(.isHeader)
                    } else { Text(text).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                }
                if document == .support {
                    Link(destination: URL(string: "https://github.com/Kongdean2374/ChaiClassics/issues")!) {
                        Label(model.t("support.github"), systemImage: "arrow.up.right.square")
                    }.accessibilityIdentifier("support.github")
                    Text(model.t("support.external")).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
        }.localizedNavigation().navigationTitle(model.t(document.titleKey)).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("document." + document.rawValue)
    }
}
