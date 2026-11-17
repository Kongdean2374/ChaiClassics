import SwiftUI
import ChaiCore

@main
struct ChaiClassicsApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            HomeView().modifier(UITestDisplayOptions()).environmentObject(model)
                .tint(GamePalette.tint(.sudoku))
                .environment(\.locale, Locale(identifier: model.preferences.language.rawValue))
                .preferredColorScheme(model.preferences.appearance == .system ? nil : model.preferences.appearance == .dark ? .dark : .light)
                .alert(model.t("storage.title"), isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
                    Button(model.t("common.ok")) { model.notice = nil }
                } message: { Text(model.noticeText) }
                .onChange(of: scenePhase) { _, phase in
                    model.setSceneActive(phase == .active)
                    if phase != .active { model.store?.flush() }
                }
        }
    }
}
