import SwiftUI
import UIKit
import ChaiCore

@MainActor final class ContinueTouchObserver: ObservableObject {
    private var gate = ContinueActivationGate()
    var allowsActivation: Bool { gate.allowsActivation(at:ProcessInfo.processInfo.systemUptime) }
    func begin(_ id: Int) { gate.begin(id) }
    func move(_ id: Int, travel: Double) { gate.move(id,travel:travel) }
    func end(_ id: Int,cancelled: Bool) { gate.end(id,at:ProcessInfo.processInfo.systemUptime,cancelled:cancelled) }
    func cancelAll() { gate.cancelAll(at:ProcessInfo.processInfo.systemUptime) }
    func suspend() { gate.suspend() }
    func resume() { gate.resume(at:ProcessInfo.processInfo.systemUptime) }
}

/// Observe the real row touch stream without competing with List's native
/// swipe, scrolling or button recognizers. Geometry is read live for each touch.
struct ContinueTouchMonitor: UIViewRepresentable {
    let observer: ContinueTouchObserver
    let enabled: Bool
    func makeUIView(context: Context) -> ContinueTouchView { ContinueTouchView(observer:observer) }
    func updateUIView(_ view: ContinueTouchView,context: Context) { view.observationEnabled = enabled }
    static func dismantleUIView(_ view: ContinueTouchView,coordinator: ()) { view.detach() }
}

@MainActor final class ContinueTouchView: UIView, UIGestureRecognizerDelegate {
    var observationEnabled = true
    private let observer: ContinueTouchObserver
    private weak var observingWindow: UIWindow?
    private lazy var recognizer = ContinueTouchRecognizer(observer:observer)
    init(observer: ContinueTouchObserver) {
        self.observer = observer; super.init(frame:.zero)
        isUserInteractionEnabled = false; isAccessibilityElement = false
        recognizer.delegate = self; recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false; recognizer.delaysTouchesEnded = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if observingWindow !== window { detach(); if let window { window.addGestureRecognizer(recognizer); observingWindow = window } }
    }
    func detach() { observingWindow?.removeGestureRecognizer(recognizer); observingWindow = nil; observer.cancelAll() }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,shouldReceive touch: UITouch) -> Bool {
        guard observationEnabled, window != nil, !isHidden, alpha>0.01 else { return false }
        return bounds.contains(touch.location(in:self))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}

@MainActor private final class ContinueTouchRecognizer: UIGestureRecognizer {
    private let observer: ContinueTouchObserver
    private var starts: [ObjectIdentifier:CGPoint] = [:]
    private var identifiers: [ObjectIdentifier:Int] = [:]
    private var nextID = 0
    init(observer: ContinueTouchObserver) { self.observer = observer; super.init(target:nil,action:nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>,with event: UIEvent) {
        for touch in touches {
            let key = ObjectIdentifier(touch); nextID += 1; starts[key] = touch.location(in:view); identifiers[key] = nextID; observer.begin(nextID)
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>,with event: UIEvent) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard let start = starts[key], let id = identifiers[key] else { continue }
            let point = touch.location(in:view), travel = hypot(point.x-start.x,point.y-start.y)
            observer.move(id,travel:Double(travel))
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>,with event: UIEvent) { finish(touches,cancelled:false) }
    override func touchesCancelled(_ touches: Set<UITouch>,with event: UIEvent) { finish(touches,cancelled:true) }
    private func finish(_ touches: Set<UITouch>,cancelled: Bool) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            if let id = identifiers.removeValue(forKey:key) { observer.end(id,cancelled:cancelled) }; starts[key] = nil
        }
        if identifiers.isEmpty { state = .failed }
    }
    override func reset() {
        if !identifiers.isEmpty { observer.cancelAll() }
        starts = [:]; identifiers = [:]; super.reset()
    }
}
