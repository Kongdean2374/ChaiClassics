import SwiftUI
import ChaiCore

struct SessionBadge: View {
    let state: SessionState
    let title: String
    var color: Color {
        switch state { case .notStarted: return .secondary; case .inProgress: return .blue; case .completed: return .green; case .failed: return .orange }
    }
    var body: some View {
        Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.primary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}
struct ContinueCard: View {
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "play.fill").font(.headline).foregroundStyle(.tint)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 10)
    }
}
struct GameplayActivity: ViewModifier {
    @EnvironmentObject var model: AppModel
    let game: GameID
    let active: Bool
    func body(content: Content) -> some View {
        content.onAppear { model.setGameActivity(game, active: active) }
            .onChange(of: active) { _, value in model.setGameActivity(game, active: value) }
            .onDisappear { model.endGameActivity(game) }
    }
}

private struct LocalizedBackButton: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        content.navigationBarBackButtonHidden(true).toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Label(model.t("common.back"), systemImage: "chevron.left") }
                    .accessibilityIdentifier("navigation.back")
            }
        }
    }
}
extension View {
    func localizedNavigation() -> some View { modifier(LocalizedBackButton()) }
}
