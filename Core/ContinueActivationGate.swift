import Foundation

/// Input state for a Continue control inside a native swipe row. UIKit updates
/// this synchronously, before a delayed SwiftUI button release can navigate.
public struct ContinueActivationGate: Equatable, Sendable {
    private var contacts: [Int:Bool] = [:]
    private var blockedUntil: TimeInterval = 0
    private var suspended = false
    public init() {}
    public mutating func begin(_ id: Int) {
        guard contacts[id]==nil else { return }
        if !contacts.isEmpty {
            for key in Array(contacts.keys) { contacts[key] = true }; contacts[id] = true
        } else { contacts[id] = false }
    }
    public mutating func move(_ id: Int, travel: Double) {
        guard contacts[id] != nil else { return }
        if !travel.isFinite || travel>=8 { contacts[id] = true }
    }
    public mutating func end(_ id: Int, at now: TimeInterval, cancelled: Bool = false) {
        guard let dragged = contacts.removeValue(forKey:id) else { return }
        if (dragged || cancelled), now.isFinite { blockedUntil = max(blockedUntil,now+0.35) }
    }
    public mutating func cancelAll(at now: TimeInterval) {
        contacts = [:]; if now.isFinite { blockedUntil = max(blockedUntil,now+0.35) }
    }
    public mutating func suspend() { suspended = true }
    public mutating func resume(at now: TimeInterval) { suspended = false; cancelAll(at:now) }
    public func allowsActivation(at now: TimeInterval) -> Bool {
        !suspended && !contacts.values.contains(true) && now.isFinite && now>=blockedUntil
    }
}
