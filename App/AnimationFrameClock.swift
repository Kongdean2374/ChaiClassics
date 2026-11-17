import SwiftUI
import UIKit

struct AnimationFrameSample {
    let timestamp: TimeInterval
    let delta: TimeInterval
}

/// Scoped to an active animation, never attached to the shared AppModel. Native
/// display callbacks let ProMotion devices use their supported refresh cadence.
@MainActor final class AnimationFrameClock: ObservableObject {
    @Published private(set) var frame = AnimationFrameSample(timestamp: 0, delta: 0)
    private var displayLink: CADisplayLink?
    private var previousTimestamp: TimeInterval?
    private var powerObserver: NSObjectProtocol?
    private lazy var proxy = DisplayLinkProxy(owner: self)

    func start() {
        guard displayLink == nil else { return }
        previousTimestamp = nil
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
        displayLink = link
        updateFrameRate()
        link.add(to: .main, forMode: .common)
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateFrameRate() }
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        previousTimestamp = nil
        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
        powerObserver = nil
    }

    private func updateFrameRate() {
        let maximum = Float(UIScreen.main.maximumFramesPerSecond)
        let preferred = ProcessInfo.processInfo.isLowPowerModeEnabled ? min(60, maximum) : maximum
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, preferred), maximum: preferred, preferred: preferred)
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let delta = previousTimestamp.map { min(max(link.timestamp - $0, 0), 1.0 / 15) } ?? 0
        previousTimestamp = link.timestamp
        frame = AnimationFrameSample(timestamp: link.timestamp, delta: delta)
    }

    deinit {
        displayLink?.invalidate()
        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
    }
}

@MainActor private final class DisplayLinkProxy: NSObject {
    weak var owner: AnimationFrameClock?
    init(owner: AnimationFrameClock) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}
