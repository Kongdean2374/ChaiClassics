import SwiftUI
import UIKit
import ChaiCore

enum AppInformation {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.3"
    }
}

/// Opening a draft never sends mail or attaches game saves. The user chooses
/// what to add and confirms sending in their mail app.
struct SupportEmailLink: View {
    let identifier: String
    var fillsWidth = false
    @EnvironmentObject var model: AppModel
    private var destination: URL {
        OfficialWebsite.emailURL(
            subject: model.t("support.email.subject"),
            body: model.t("support.email.body", AppInformation.version, UIDevice.current.systemVersion)
        )
    }
    var body: some View {
        Link(destination: destination) {
            Label(model.t("support.email"), systemImage: "envelope")
                .foregroundStyle(fillsWidth ? Color(.systemBackground) : GamePalette.tint(.sudoku))
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }.accessibilityIdentifier(identifier)
    }
}
