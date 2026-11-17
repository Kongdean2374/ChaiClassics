import Foundation
import XCTest
@testable import ChaiCore

final class GraphicsPreferencesTests: XCTestCase {
    func testReleasedPreferencesKeepEveryValueWhenGraphicsFieldIsAbsent() throws {
        let legacy = Data(#"{"appearance":"dark","language":"en","haptics":false,"keepScreenAwake":true}"#.utf8)
        let value = try JSONDecoder().decode(AppPreferences.self, from: legacy)
        XCTAssertEqual(value.appearance, .dark)
        XCTAssertEqual(value.language, .english)
        XCTAssertFalse(value.haptics)
        XCTAssertTrue(value.keepScreenAwake)
        XCTAssertEqual(value.graphicsQuality, .high)
    }

    func testQualityRoundTripsWithoutTouchingGameNamespaces() throws {
        let suite = "graphics.preferences." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([1, 2, 3]), forKey: "released.game.sentinel")
        let store = PreferencesStore(defaults: defaults)
        for quality in GraphicsQuality.allCases {
            var value = AppPreferences()
            value.graphicsQuality = quality
            value.language = .english
            store.save(value)
            XCTAssertEqual(store.load(), value)
            XCTAssertEqual(defaults.data(forKey: "released.game.sentinel"), Data([1, 2, 3]))
        }
        XCTAssertLessThan(GraphicsQuality.low.celebrationParticleCount, GraphicsQuality.medium.celebrationParticleCount)
        XCTAssertLessThan(GraphicsQuality.medium.celebrationParticleCount, GraphicsQuality.high.celebrationParticleCount)
    }
}
