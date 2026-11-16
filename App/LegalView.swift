import SwiftUI
import UIKit
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
    var body: some View {
        ScrollView {
            if document == .support {
                SupportContent()
                    .padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Link(destination: OfficialWebsite.url(for: document.websitePage, language: model.preferences.language)) {
                            Label(model.t("legal.online"), systemImage: "arrow.up.right.square")
                        }.accessibilityIdentifier("legal.online." + document.rawValue)
                        Label(model.t("legal.offline"), systemImage: "doc.text")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    BundledDocumentContent(document: document)
                }.padding(24).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .background(document == .support ? Color(.systemGroupedBackground) : Color(.systemBackground))
        .localizedNavigation().navigationTitle(model.t(document.titleKey)).navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("document." + document.rawValue)
    }
}

private struct SupportContent: View {
    @EnvironmentObject var model: AppModel
    @State private var copiedAddress = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.t("support.intro"))
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                SupportEmailLink(identifier: "support.email", fillsWidth: true)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Text(model.t("support.email.detail")).font(.footnote).foregroundStyle(.secondary)
                Divider()
                Link(destination: OfficialWebsite.url(for: .support, language: model.preferences.language)) {
                    HStack {
                        Label(model.t("support.helpWebsite"), systemImage: "globe")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                    }.padding(.vertical, 4)
                }.accessibilityIdentifier("legal.online.support")
            }.supportCard()

            VStack(alignment: .leading, spacing: 12) {
                Text(model.t("support.manual.title")).font(.headline).accessibilityAddTraits(.isHeader)
                Text(model.t("support.manual.detail")).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(OfficialWebsite.supportEmail).font(.callout.weight(.medium)).textSelection(.enabled)
                    .accessibilityIdentifier("support.email.address")
                Button {
                    UIPasteboard.general.string = OfficialWebsite.supportEmail
                    copiedAddress = true
                } label: {
                    Label(model.t(copiedAddress ? "support.addressCopied" : "support.copyAddress"),
                          systemImage: copiedAddress ? "checkmark" : "doc.on.doc")
                }.buttonStyle(.bordered).controlSize(.small).accessibilityIdentifier("support.email.copy")
            }.supportCard()

            BundledDocumentContent(document: .support, showsMetadata: false)
                .padding(.horizontal, 4)
        }
    }
}

private struct BundledDocumentContent: View {
    let document: LegalDocument
    var showsMetadata = true
    @EnvironmentObject var model: AppModel
    private var paragraphs: [String] {
        guard let url = AppText(language: model.preferences.language).bundle.url(forResource: document.file, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [model.t("legal.unavailable")] }
        let paragraphs = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return showsMetadata ? paragraphs : Array(paragraphs.dropFirst(2))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, text in
                if text.hasPrefix("# ") {
                    Text(String(text.dropFirst(2))).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                } else if text.hasPrefix("## ") {
                    Text(String(text.dropFirst(3))).font(.headline).padding(.top, 6).accessibilityAddTraits(.isHeader)
                } else {
                    Text(text).font(document == .support ? .subheadline : .body).lineSpacing(4)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private extension View {
    func supportCard() -> some View {
        padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.05), lineWidth: 1))
    }
}
