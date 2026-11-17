import SwiftUI
import ChaiCore

extension View {
    func gameSessionScreen(_ game: GameID, resultReady: Bool = true) -> some View {
        modifier(GameSessionScreen(game: game, resultReady: resultReady))
    }
    func gameMenuSettings(_ game: GameID) -> some View { modifier(GameMenuSettings(game: game)) }
    func loadGameDefaultsOnce(_ action: @escaping () -> Void) -> some View {
        modifier(InitialGameDefaults(action: action))
    }
    func newGameConfirmation(_ game: GameID, isPresented: Binding<Bool>, onConfirm: @escaping () -> Void) -> some View {
        modifier(NewGameConfirmation(game: game, isPresented: isPresented, onConfirm: onConfirm))
    }
    func gameActionConfirmation(title: String, message: String, isPresented: Binding<Bool>, confirmTitle: String,
                                onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void = {}) -> some View {
        modifier(GameActionConfirmation(title: title, message: message, isPresented: isPresented,
                                         confirmTitle: confirmTitle, prefix: "action", onConfirm: onConfirm, onCancel: onCancel))
    }
}

/// Returning from a native confirmation must not replace the selected difficulty
/// with defaults before its accepted callback creates the board.
private struct InitialGameDefaults: ViewModifier {
    let action: () -> Void
    @State private var loaded = false
    func body(content: Content) -> some View {
        content.onAppear {
            guard !loaded else { return }
            loaded = true; action()
        }
    }
}

private struct SessionDialog<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ZStack {
            Color.black.opacity(0.38).ignoresSafeArea().contentShape(Rectangle())
            ScrollView {
                VStack(spacing: 20) { content }
                    .padding(24).frame(maxWidth: 420)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
                    .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(.primary.opacity(0.09)) }
                    .shadow(color: .black.opacity(0.18), radius: 28, y: 12)
                    .frame(maxWidth: .infinity).padding(24)
            }.scrollBounceBehavior(.basedOnSize).defaultScrollAnchor(.center)
        }.accessibilityAddTraits(.isModal)
    }
}

private struct GameActionConfirmation: ViewModifier {
    let title: String
    let message: String
    @Binding var isPresented: Bool
    let confirmTitle: String
    let prefix: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @EnvironmentObject private var model: AppModel
    @State private var gate = GameActionGate()
    @State private var decision: Bool?

    private func resolve(_ token: UUID?, accepting: Bool) {
        guard isPresented, let token, gate.resolve(token) else { return }
        decision = accepting
        isPresented = false
    }
    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented, onDismiss: {
            let accepted = decision == true
            decision = nil
            if accepted { onConfirm() } else { onCancel() }
        }) {
            let token = gate.id
            SessionDialog {
                Image(systemName: "questionmark.circle.fill").font(.system(size: 38)).foregroundStyle(.tint)
                Text(title).font(.system(.title2, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
                Text(message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(confirmTitle) { resolve(token, accepting: true) }
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                    .accessibilityIdentifier(prefix + ".confirm")
                Button(model.t("common.cancel")) { resolve(token, accepting: false) }
                    .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
                    .accessibilityIdentifier(prefix + ".cancel")
            }
            .presentationBackground(.clear).interactiveDismissDisabled()
            .onAppear { if gate.id == nil { _ = gate.begin() } }
        }
            .onChange(of: isPresented) { _, presented in
                if presented { decision = nil; _ = gate.begin() } else { gate.invalidate() }
            }
    }
}

private struct NewGameConfirmation: ViewModifier {
    let game: GameID
    @Binding var isPresented: Bool
    let onConfirm: () -> Void
    @EnvironmentObject private var model: AppModel
    func body(content: Content) -> some View {
        content.modifier(GameActionConfirmation(title: model.t("session.new.title"),
            message: model.t(model.gameSnapshot(for: game).exists ? "session.new.overwrite" : "session.new.detail"),
            isPresented: $isPresented, confirmTitle: model.t("session.new.agree"), prefix: game.rawValue + ".new",
            onConfirm: { model.performNewGameRequest(game, action: onConfirm) }, onCancel: {}))
            .onChange(of: isPresented) { _, value in if value { model.preparePreviousSession(game) } }
    }
}

private struct GameMenuSettings: ViewModifier {
    let game: GameID
    @EnvironmentObject private var model: AppModel
    @State private var settings = false
    func body(content: Content) -> some View {
        content.disabled(model.navigationTouchLocked).allowsHitTesting(!model.navigationTouchLocked).toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { guard !model.navigationTouchLocked else { return }; settings = true } label: { Image(systemName: "gearshape") }
                    .disabled(model.navigationTouchLocked)
                    .accessibilityLabel(model.t("gameSettings.title"))
                    .accessibilityIdentifier(game.rawValue + ".menu.settings")
            }
        }.sheet(isPresented: $settings) { NavigationStack { GameSettingsView(game: game) } }
    }
}

/// A real horizontal swipe works both in Forms and Sudoku's ScrollView.
/// A drag never dispatches the Continue action when the finger lifts.
struct ContinueGameRow<Label: View>: View {
    let game: GameID
    let action: () -> Void
    let label: Label
    init(game: GameID, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.game = game; self.action = action; self.label = label()
    }
    @EnvironmentObject private var model: AppModel
    @State private var revealed = false
    @GestureState private var dragging = false
    @State private var suppressContinueUntil: TimeInterval = 0
    @State private var confirmDelete = false
    @State private var deletionSession: UUID?
    private var continueID: String { (game == .minesweeper ? "mines" : game == .twentyFour ? "twentyfour" : game.rawValue) + ".continue" }

    var body: some View {
        Group {
            if game == .sudoku {
                // Sudoku's level/menu pages use ScrollView rather than List.
                customScrollRow
            } else {
                continueButton.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { requestDeletion() } label: {
                        Label(model.t("session.delete.action"), systemImage: "trash")
                    }.accessibilityIdentifier(game.rawValue + ".continue.delete")
                }
            }
        }
        .modifier(GameActionConfirmation(title: model.t("session.delete.title"), message: model.t("session.delete.detail"),
            isPresented: $confirmDelete, confirmTitle: model.t("session.delete.action"), prefix: game.rawValue + ".delete",
            onConfirm: {
                if let deletionSession, model.deleteCurrentGame(game, expectedSessionID: deletionSession) { revealed = false }
                deletionSession = nil
            }, onCancel: { deletionSession = nil }))
    }
    private var continueButton: some View {
        Button {
            guard !dragging, ProcessInfo.processInfo.systemUptime >= suppressContinueUntil,
                  !confirmDelete, !model.navigationTouchLocked else { return }
            if revealed { revealed = false } else { action() }
        } label: { label.frame(maxWidth: .infinity).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityIdentifier(continueID)
    }
    private var customScrollRow: some View {
        HStack(spacing: 12) {
            continueButton
                .accessibilityAction(named: model.t("session.delete.action")) { requestDeletion() }
                .simultaneousGesture(DragGesture(minimumDistance: 18)
                    .updating($dragging) { _, active, _ in active = true }
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                        suppressContinueUntil = ProcessInfo.processInfo.systemUptime + 0.28
                        if value.translation.width < -35 { revealed = true }
                        if value.translation.width > 35 { revealed = false }
                    }.onEnded { _ in
                        // GestureState resets on both completion and cancellation;
                        // the remaining release cannot activate Continue underneath.
                        suppressContinueUntil = ProcessInfo.processInfo.systemUptime + 0.28
                    })
            if revealed {
                Button(role: .destructive) { requestDeletion() } label: {
                    Image(systemName: "trash.fill").font(.title3).frame(width: 52, height: 64)
                        .foregroundStyle(.white).background(.red, in: RoundedRectangle(cornerRadius: 16))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(model.t("session.delete.action"))
                    .accessibilityIdentifier(game.rawValue + ".continue.delete")
            }
        }
    }
    private func requestDeletion() {
        guard !confirmDelete, !model.navigationTouchLocked else { return }
        model.preparePreviousSession(game)
        guard let session = model.sessionData.sessions[game] else { return }
        deletionSession = session.id; confirmDelete = true
    }
}

private struct GameSessionScreen: ViewModifier {
    let game: GameID
    let resultReady: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = false
    @State private var exiting = false
    @State private var interactionReady = false
    @State private var pauseGate = GameActionGate()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var phase: GameSessionPhase { model.sessionPhase(for: game) }
    private var snapshot: GameRunSnapshot { model.gameSnapshot(for: game) }
    private var modal: Bool { phase == .paused || phase == .result }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) { timerBar }
            .blur(radius: modal ? 8 : 0)
            .disabled(phase != .playing || exiting || !interactionReady)
            .allowsHitTesting(phase == .playing && !exiting && interactionReady)
            .accessibilityHidden(modal || phase == .reviewing)
            .overlay {
                if phase == .paused { pauseDialog }
                if phase == .result { resultDialog }
                if phase == .reviewing {
                    Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                        .allowsHitTesting(interactionReady).accessibilityHidden(!interactionReady)
                        .onTapGesture {
                            guard interactionReady, !exiting, phase == .reviewing else { return }
                            model.showSessionResult(game)
                        }
                        .accessibilityElement().accessibilityLabel(model.t("session.result.show"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            guard interactionReady, !exiting, phase == .reviewing else { return }
                            model.showSessionResult(game)
                        }
                        .accessibilityIdentifier(game.rawValue + ".session.reviewBoard")
                }
            }
            .gameCompletionCelebration(completed: snapshot.ended && resultReady && (snapshot.outcome == .won || snapshot.outcome == .completed))
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { exit() } label: { Label(model.t("common.back"), systemImage: "chevron.left") }
                        .accessibilityIdentifier("navigation.back").disabled(exiting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard !settings, !exiting, phase == .playing || phase == .paused else { return }
                        model.pauseSession(game); settings = true
                    } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(model.t("gameSettings.title"))
                        .accessibilityIdentifier(game.rawValue + ".session.settings")
                        .disabled((phase != .playing && phase != .paused) || exiting)
                }
            }
            .sheet(isPresented: $settings) { NavigationStack { GameSettingsView(game: game) } }
            .onAppear { exiting = false; model.enterSession(game, resultReady: resultReady) }
            .task(id: phase) {
                interactionReady = false
                if phase == .paused { if pauseGate.id == nil { _ = pauseGate.begin() } }
                else { pauseGate.invalidate() }
                guard phase == .playing || phase == .reviewing else { return }
                // Consume the second touch of a double-tapped modal button here,
                // before the board becomes interactive at the same coordinates.
                do { try await Task.sleep(for: .milliseconds(280)) } catch { return }
                guard !Task.isCancelled, phase == .playing || phase == .reviewing else { return }
                interactionReady = true
            }
            .onDisappear { model.leaveSession(game) }
            .onReceive(timer) { _ in if scenePhase == .active { model.tickSession(game, resultReady: resultReady) } }
            .onChange(of: resultReady) { _, ready in model.finishSessionIfNeeded(game, resultReady: ready) }
            .onChange(of: snapshot.ended) { _, _ in model.finishSessionIfNeeded(game, resultReady: resultReady) }
            .onChange(of: scenePhase) { _, value in if value != .active { model.pauseSession(game) } }
    }
    private var timerBar: some View {
        HStack(spacing: 12) {
            Label(GameRecordText.duration(snapshot.elapsedSeconds), systemImage: "timer").monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.t("history.elapsed"))
                .accessibilityValue(GameRecordText.duration(snapshot.elapsedSeconds))
                .accessibilityIdentifier(game.rawValue + ".timer")
            Spacer()
            Button { model.pauseSession(game) } label: { Image(systemName: "pause.fill").frame(width: 44, height: 44) }
                .accessibilityLabel(model.t("common.pause"))
                .accessibilityIdentifier(game.rawValue + ".session.pause").disabled(phase != .playing || snapshot.ended)
        }.font(.subheadline.weight(.semibold)).padding(.horizontal, 20).padding(.vertical, 4)
            .background(.ultraThinMaterial)
    }
    private var pauseDialog: some View {
        let token = pauseGate.id
        return SessionDialog {
            Image(systemName: "pause.circle.fill").font(.system(size: 42)).foregroundStyle(GamePalette.tint(game))
            Text(model.t("game.paused")).font(.system(.title, design: .rounded, weight: .bold))
            Text(model.t("session.paused.detail")).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            LabeledContent(model.t("history.elapsed"), value: GameRecordText.duration(snapshot.elapsedSeconds))
                .monospacedDigit().accessibilityElement(children: .ignore)
                .accessibilityLabel(model.t("history.elapsed")).accessibilityValue(GameRecordText.duration(snapshot.elapsedSeconds))
                .accessibilityIdentifier(game.rawValue + ".session.paused.elapsed")
            Button(model.t("session.paused.resume")) {
                guard !exiting, !settings, phase == .paused, let token, pauseGate.resolve(token) else { return }
                if !model.resumeSession(game), phase == .paused { _ = pauseGate.begin() }
            }.buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier(game.rawValue + ".session.resume")
            Button(model.t("session.paused.exit")) {
                guard phase == .paused, let token, pauseGate.resolve(token) else { return }
                exit()
            }
                .buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier(game.rawValue + ".session.exit")
        }.accessibilityIdentifier(game.rawValue + ".session.paused")
    }
    private var resultDialog: some View {
        SessionDialog {
            Image(systemName: snapshot.outcome == .lost ? "flag.checkered" : snapshot.outcome == .draw ? "equal.circle.fill" : "checkmark.seal.fill")
                .font(.system(size: 44)).foregroundStyle(GamePalette.tint(game))
            Text(model.t("session.result." + (snapshot.outcome ?? .completed).rawValue))
                .font(.system(.title, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
            VStack(spacing: 10) {
                LabeledContent(model.t("history.elapsed"), value: GameRecordText.duration(snapshot.elapsedSeconds))
                    .accessibilityElement(children: .ignore).accessibilityLabel(model.t("history.elapsed"))
                    .accessibilityValue(GameRecordText.duration(snapshot.elapsedSeconds))
                    .accessibilityIdentifier(game.rawValue + ".session.result.elapsed")
                LabeledContent(model.t("history.moves.title"), value: String(snapshot.moves))
                    .accessibilityElement(children: .ignore).accessibilityLabel(model.t("history.moves.title"))
                    .accessibilityValue(String(snapshot.moves))
                    .accessibilityIdentifier(game.rawValue + ".session.result.moves")
                LabeledContent(model.t("history.difficulty"), value: GameRecordText.difficulty(snapshot.difficulty, model: model))
                    .accessibilityElement(children: .ignore).accessibilityLabel(model.t("history.difficulty"))
                    .accessibilityValue(GameRecordText.difficulty(snapshot.difficulty, model: model))
                    .accessibilityIdentifier(game.rawValue + ".session.result.difficulty")
            }.font(.subheadline).monospacedDigit()
            Button(model.t("common.done")) {
                guard !exiting, phase == .result, model.closeSession(game) else { return }
                exiting = true; dismiss()
            }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier(game.rawValue + ".session.done")
            Button(model.t("session.result.review")) {
                guard !exiting, phase == .result else { return }
                model.reviewSession(game)
            }.buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier(game.rawValue + ".session.review")
        }.accessibilityIdentifier(game.rawValue + ".session.result")
    }
    private func exit() {
        guard !exiting else { return }
        exiting = true; model.pauseSession(game); model.protectNavigationTransition(); dismiss()
    }
}
