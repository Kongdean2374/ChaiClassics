import Foundation

/// Verified public contact details shared by the App's offline documents and Settings.
public enum OfficialWebsite {
    public enum Page: String, CaseIterable, Sendable {
        case home, privacy, terms, support
    }

    public static let supportEmail = "a090825159@icloud.com"

    public static func url(for page: Page, language: AppLanguage) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "classics.chaihome.cc"
        let prefix = language == .english ? "/en/" : "/"
        components.path = prefix + (page == .home ? "" : page.rawValue + "/")
        return components.url!
    }

    /// Opens a draft in the user's mail app; constructing the URL never sends a message.
    public static func emailURL(subject: String, body: String) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url!
    }
}
