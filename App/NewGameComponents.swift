import SwiftUI
import ChaiCore

private struct GameReducedMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var gameReducedMotion: Bool {
        get { self[GameReducedMotionKey.self] }
        set { self[GameReducedMotionKey.self] = newValue }
    }
}

/// Applies real SwiftUI layout constraints only in an isolated Simulator test.
/// 320pt has no iOS17-compatible physical Simulator device; it is a layout viewport,
/// never presented as a native-device App Store screenshot.
struct UITestDisplayOptions: ViewModifier {
    @Environment(\.dynamicTypeSize) private var systemDynamicType
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        content.frame(width: UITestBootstrap.viewportWidth)
            .environment(\.dynamicTypeSize, UITestBootstrap.dynamicTypeSize ?? systemDynamicType)
            .environment(\.gameReducedMotion, systemReducedMotion || UITestBootstrap.forceReducedMotion)
        #else
        content.environment(\.gameReducedMotion, systemReducedMotion)
        #endif
    }
}

/// Elapsed time advances only while this game's actual play view is visible.
/// Persisted counters never derive from wall-clock gaps across a background or pause.
struct SessionTimer: ViewModifier {
    let active: Bool
    let tick: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        content
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .onReceive(timer) { _ in
                if visible && active && scenePhase == .active { tick() }
            }
    }
}

/// Recovery is explicitly scoped to one namespace; future schemas remain protected.
struct GameStorageRecoveryView: View {
    let game: GameID
    @EnvironmentObject private var model: AppModel
    @State private var confirming = false

    var body: some View {
        if model.blocked.contains(game) {
            VStack(alignment: .leading, spacing: 12) {
                Label(model.t("storage.attention"), systemImage: "externaldrive.badge.exclamationmark")
                    .font(.headline)
                Text(model.t(model.newerSaves.contains(game) ? "storage.newerVersion" : "storage.recovery.explanation"))
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if !model.newerSaves.contains(game), model.store != nil {
                    Button(model.t("storage.recovery.action")) { confirming = true }
                        .buttonStyle(.bordered).frame(minHeight: 44)
                        .accessibilityIdentifier("storage.recover." + game.rawValue)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
            .confirmationDialog(model.t("storage.recovery.confirm"), isPresented: $confirming, titleVisibility: .visible) {
                Button(model.t("storage.recovery.action"), role: .destructive) { model.recoverGame(game) }
                    .accessibilityIdentifier("storage.confirmRecovery." + game.rawValue)
                Button(model.t("common.cancel"), role: .cancel) {}
            }
        }
    }
}
