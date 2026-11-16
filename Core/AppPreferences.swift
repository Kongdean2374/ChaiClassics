import Foundation

public enum AppAppearance: String, Codable, CaseIterable, Sendable { case system, light, dark }
public enum AppLanguage: String, Codable, CaseIterable, Sendable { case traditionalChinese = "zh-Hant", english = "en" }

public struct AppPreferences: Codable, Equatable, Sendable {
    public var appearance: AppAppearance = .system
    public var language: AppLanguage = .traditionalChinese
    public var haptics = true
    public var keepScreenAwake = false
    public init() {}
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
