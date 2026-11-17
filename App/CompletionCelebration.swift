import SwiftUI
import ChaiCore

private struct CompletionCelebration: ViewModifier {
    let completed: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var policy = CelebrationPolicy()
    @State private var event: UUID?
    @State private var startedAt: Date?
    #if DEBUG && targetEnvironment(simulator)
    @State private var testStarts = 0
    #endif

    private var effectiveReduceMotion: Bool {
        #if DEBUG && targetEnvironment(simulator)
        reduceMotion || UITestBootstrap.forceReducedMotion
        #else
        reduceMotion
        #endif
    }
    private var effectiveLowPower: Bool {
        #if DEBUG && targetEnvironment(simulator)
        lowPower || ProcessInfo.processInfo.isLowPowerModeEnabled || UITestBootstrap.forceLowPower
        #else
        lowPower || ProcessInfo.processInfo.isLowPowerModeEnabled
        #endif
    }

    func body(content: Content) -> some View {
        content.overlay {
            if let startedAt {
                CelebrationBurst(startedAt: startedAt, quality: model.preferences.graphicsQuality)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }.overlay(alignment: .bottomLeading) {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-celebration-probe") {
                Text("Celebration")
                    .font(.system(size: 1)).foregroundStyle(.clear)
                    .accessibilityLabel("Celebration test status")
                    .accessibilityValue("starts=\(testStarts);active=\(startedAt == nil ? 0 : 1)")
                    .accessibilityIdentifier("uitest.celebration.probe")
                    .allowsHitTesting(false)
            }
            #endif
        }
        .onAppear {
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            policy.synchronize(completed: completed)
        }
        .onChange(of: completed) { _, value in
            let shouldCelebrate = policy.observe(completed: value, isActive: scenePhase == .active,
                                                  reduceMotion: effectiveReduceMotion, lowPower: effectiveLowPower)
            if shouldCelebrate {
                startedAt = Date(); event = UUID()
                #if DEBUG && targetEnvironment(simulator)
                testStarts += 1
                #endif
            } else if !value { stop() }
        }
        .onChange(of: scenePhase) { _, value in
            if value != .active { stop() }
            else { lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
        .onChange(of: effectiveReduceMotion) { _, value in if value { stop() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            if effectiveLowPower { stop() }
        }
        .onDisappear { stop(); policy = CelebrationPolicy() }
        .task(id: event) {
            guard let current = event else { return }
            do { try await Task.sleep(for: .milliseconds(2200)) } catch { return }
            if event == current { stop() }
        }
    }
    private func stop() { startedAt = nil; event = nil }
}

/// One canvas with bounded, deterministic particles. The display clock exists
/// only for this burst; quality changes detail without lowering frame cadence.
private struct CelebrationBurst: View {
    let startedAt: Date
    let quality: GraphicsQuality
    @StateObject private var clock = AnimationFrameClock()
    @State private var firstTimestamp: TimeInterval?
    private let colors: [Color] = [.indigo, .teal, .orange, .pink, .yellow, .cyan]
    var body: some View {
        Canvas { context, size in
                let elapsed = firstTimestamp.map { max(0, clock.frame.timestamp - $0) } ?? 0
                let progress = max(0, min(1, elapsed / 2.2))
                for index in 0..<quality.celebrationParticleCount {
                    let side = index.isMultiple(of: 2) ? 1.0 : -1.0
                    let seed = Double((index * 37 + 11) % 101) / 100
                    let spread = Double((index * 19 + 7) % 97) / 96
                    let origin = side > 0 ? 0.04 : 0.96
                    let x = (origin + side * (0.24 + seed * 0.7) * progress) * size.width
                    let y = (0.57 - (1.12 + spread * 0.5) * progress + 1.9 * progress * progress) * size.height
                    var piece = context
                    piece.opacity = max(0, min(1, (1 - progress) * 3))
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .degrees(Double(index * 41) + side * progress * 420))
                    let rect = CGRect(x: -3, y: -5, width: 4 + seed * 3, height: 7 + spread * 5)
                    piece.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(colors[index % colors.count]))
                    if quality == .high && index.isMultiple(of: 6) {
                        piece.opacity *= 0.45
                        piece.fill(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(.white))
                    }
                }
        }
        .onAppear { clock.start() }
        .onReceive(clock.$frame) { frame in
            if firstTimestamp == nil && frame.timestamp > 0 { firstTimestamp = frame.timestamp }
        }
        .onDisappear { clock.stop() }
    }
}

extension View {
    func gameCompletionCelebration(completed: Bool) -> some View { modifier(CompletionCelebration(completed: completed)) }
}
