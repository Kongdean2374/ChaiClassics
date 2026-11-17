import Foundation

public enum AppAppearance: String, Codable, CaseIterable, Sendable { case system, light, dark }
public enum AppLanguage: String, Codable, CaseIterable, Sendable { case traditionalChinese = "zh-Hant", english = "en" }
/// Changes decorative detail only. Animation cadence always follows the display.
public enum GraphicsQuality: String, Codable, CaseIterable, Sendable {
    case low, medium, high
    public var celebrationParticleCount: Int {
        switch self { case .low: return 18; case .medium: return 42; case .high: return 72 }
    }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var appearance: AppAppearance = .system
    public var language: AppLanguage = .traditionalChinese
    public var haptics = true
    public var keepScreenAwake = false
    public var graphicsQuality: GraphicsQuality = .high
    public init() {}
    private enum CodingKeys: String, CodingKey { case appearance, language, haptics, keepScreenAwake, graphicsQuality }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try values.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        language = try values.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .traditionalChinese
        haptics = try values.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        keepScreenAwake = try values.decodeIfPresent(Bool.self, forKey: .keepScreenAwake) ?? false
        graphicsQuality = try values.decodeIfPresent(GraphicsQuality.self, forKey: .graphicsQuality) ?? .high
    }
    public func shouldKeepAwake(gameIsActive: Bool, appIsActive: Bool) -> Bool {
        keepScreenAwake && gameIsActive && appIsActive
    }
}

/// Separate from the released schema-1 game envelopes. Never reads or deletes saves.
public final class PreferencesStore {
    public static let key = "chaiclassics.preferences.v1"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> AppPreferences {
        guard let data = defaults.data(forKey: Self.key), let value = try? JSONDecoder().decode(AppPreferences.self, from: data) else { return AppPreferences() }
        return value
    }
    public func save(_ value: AppPreferences) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: Self.key) }
    }
}
