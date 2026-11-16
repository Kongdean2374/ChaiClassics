import Foundation
import XCTest
@testable import ChaiCore

final class OfficialWebsiteTests: XCTestCase {
    func testAllOfficialPagesUseVerifiedCanonicalLocalizedURLs() throws {
        let expected: [(AppLanguage, [String])] = [
            (.traditionalChinese, [
                "https://classics.chaihome.cc/",
                "https://classics.chaihome.cc/privacy/",
                "https://classics.chaihome.cc/terms/",
                "https://classics.chaihome.cc/support/"
            ]),
            (.english, [
                "https://classics.chaihome.cc/en/",
                "https://classics.chaihome.cc/en/privacy/",
                "https://classics.chaihome.cc/en/terms/",
                "https://classics.chaihome.cc/en/support/"
            ])
        ]
        XCTAssertEqual(OfficialWebsite.Page.allCases, [.home, .privacy, .terms, .support])
        var destinations = Set<URL>()
        for (language, urls) in expected {
            XCTAssertEqual(urls.count, OfficialWebsite.Page.allCases.count)
            for (page, canonical) in zip(OfficialWebsite.Page.allCases, urls) {
                let url = OfficialWebsite.url(for: page, language: language)
                let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
                XCTAssertEqual(url.absoluteString, canonical)
                XCTAssertEqual(components.scheme, "https")
                XCTAssertEqual(components.host, "classics.chaihome.cc")
                XCTAssertNil(components.port)
                XCTAssertNil(components.user)
                XCTAssertNil(components.password)
                XCTAssertNil(components.query)
                XCTAssertNil(components.fragment)
                destinations.insert(url)
            }
        }
        XCTAssertEqual(destinations.count, 8)
    }

    func testMailDraftPreservesUnicodeNewlinesAndReservedCharacters() throws {
        let subject = "ChaiClassics｜問題回報 🧩 & ? # = + %"
        let body = "遊戲：數獨\n重現步驟：1 & 2?\r\n網址：https://example.com/?a=1&b=2#part\n回覆：玩家+test@example.com\nEmoji：🎮"
        let url = OfficialWebsite.emailURL(subject: subject, body: body)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(OfficialWebsite.supportEmail, "a090825159@icloud.com")
        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, "a090825159@icloud.com")
        XCTAssertNil(components.host)
        XCTAssertNil(components.fragment)
        XCTAssertEqual(components.queryItems, [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ])
        XCTAssertFalse(url.absoluteString.contains("\n"))
        XCTAssertFalse(url.absoluteString.contains("\r"))
        XCTAssertFalse(url.absoluteString.contains(" "))
    }

    func testDraftContentCannotAddRecipientsOrQueryFields() throws {
        let subject = "&cc=other@example.com&bcc=another@example.com#fragment"
        let body = "\r\nTo: different@example.com\r\n?subject=replaced&body=altered"
        let components = try XCTUnwrap(URLComponents(
            url: OfficialWebsite.emailURL(subject: subject, body: body),
            resolvingAgainstBaseURL: false
        ))
        XCTAssertEqual(components.path, "a090825159@icloud.com")
        XCTAssertNil(components.fragment)
        XCTAssertEqual(components.queryItems?.map(\.name), ["subject", "body"])
        XCTAssertEqual(components.queryItems?.first?.value, subject)
        XCTAssertEqual(components.queryItems?.last?.value, body)
    }

    func testEmptyDraftFieldsRemainValidAndSeparate() throws {
        let components = try XCTUnwrap(URLComponents(
            url: OfficialWebsite.emailURL(subject: "", body: ""),
            resolvingAgainstBaseURL: false
        ))
        XCTAssertEqual(components.path, "a090825159@icloud.com")
        XCTAssertEqual(components.queryItems, [
            URLQueryItem(name: "subject", value: ""),
            URLQueryItem(name: "body", value: "")
        ])
    }
}
