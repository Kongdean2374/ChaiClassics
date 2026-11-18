import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import ChaiCore

/// Optional direct manipulation in the hosted board's unscaled coordinates.
struct BoardCardPan {
    let canPickUp: (CGPoint) -> Bool
    let began: (CGPoint) -> Void
    let moved: (CGPoint) -> Void
    let ended: (CGPoint) -> Void
    let cancelled: () -> Void
}

/// Native zoom transforms preserve the hosted grid's hit-test coordinates.
struct ZoomBoard<Content: View>: UIViewRepresentable {
    let size: CGSize
    let inputEnabled: Bool
    let accessibilityHidden: Bool
    let identifier: String
    let fitWidth: Bool
    let cardPan: BoardCardPan?
    let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var inheritedInputEnabled

    init(size: CGSize, inputEnabled: Bool = true, accessibilityHidden: Bool = false, identifier: String = "mines.zoomBoard",
         fitWidth: Bool = false, cardPan: BoardCardPan? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.size = size
        self.inputEnabled = inputEnabled
        self.accessibilityHidden = accessibilityHidden
        self.identifier = identifier
        self.fitWidth = fitWidth
        self.cardPan = cardPan
        self.content = content
    }

    private var acceptsInput: Bool { inputEnabled && inheritedInputEnabled }
    private var hostedContent: HostedContent {
        HostedContent(content: content(), inputEnabled: acceptsInput, accessibilityHidden: accessibilityHidden)
    }

    func makeCoordinator() -> Coordinator { Coordinator(content: hostedContent) }
    func makeUIView(context: Context) -> CenteredBoardScrollView {
        let scroll = CenteredBoardScrollView()
        scroll.delegate = context.coordinator
        scroll.fitWidth = fitWidth
        context.coordinator.cardPan = cardPan
        scroll.delaysContentTouches = false
        scroll.canCancelContentTouches = true
        scroll.bouncesZoom = true
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.scrollsToTop = false
        scroll.isAccessibilityElement = false
        scroll.accessibilityIdentifier = identifier
        let host = context.coordinator.host.view!
        host.backgroundColor = .clear
        host.autoresizingMask = []
        scroll.addSubview(host)
        scroll.boardView = host
        scroll.configure(size: size)
        if cardPan != nil { context.coordinator.installCardPan(on: scroll) }
        updateAccessState(scroll, host: host)
        return scroll
    }
    func updateUIView(_ scroll: CenteredBoardScrollView, context: Context) {
        scroll.accessibilityIdentifier = identifier
        context.coordinator.cardPan = cardPan
        context.coordinator.host.rootView = hostedContent
        context.coordinator.host.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        updateAccessState(scroll, host: context.coordinator.host.view)
        if scroll.naturalSize != size { scroll.configure(size: size) }
    }

    private func updateAccessState(_ scroll: CenteredBoardScrollView, host: UIView) {
        // A separately hosted SwiftUI root does not inherit its caller's modal
        // accessibility tree or disabled environment. Gate both UIKit boundaries.
        scroll.accessibilityElementsHidden = accessibilityHidden
        host.accessibilityElementsHidden = accessibilityHidden
        scroll.isUserInteractionEnabled = acceptsInput
        host.isUserInteractionEnabled = acceptsInput
        scroll.isScrollEnabled = acceptsInput
        scroll.pinchGestureRecognizer?.isEnabled = acceptsInput
    }

    static func dismantleUIView(_ scroll: CenteredBoardScrollView, coordinator: Coordinator) {
        scroll.accessibilityElementsHidden = true
        scroll.isUserInteractionEnabled = false
        coordinator.host.viewIfLoaded?.accessibilityElementsHidden = true
        coordinator.host.viewIfLoaded?.isUserInteractionEnabled = false
        scroll.delegate = nil
    }

    struct HostedContent: View {
        let content: Content
        let inputEnabled: Bool
        let accessibilityHidden: Bool
        var body: some View {
            content.environment(\.isEnabled, inputEnabled)
                .disabled(!inputEnabled)
                .accessibilityHidden(accessibilityHidden)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        let host: UIHostingController<HostedContent>
        var cardPan: BoardCardPan?
        private weak var cardRecognizer: CardPanRecognizer?
        init(content: HostedContent) { host = UIHostingController(rootView: content) }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { (scrollView as? CenteredBoardScrollView)?.centerBoard() }

        func installCardPan(on scroll: UIScrollView) {
            let recognizer = CardPanRecognizer { [weak self] in self?.handleCardPan($0) }
            recognizer.maximumNumberOfTouches = 1
            recognizer.delegate = self
            scroll.addGestureRecognizer(recognizer)
            scroll.panGestureRecognizer.require(toFail: recognizer)
            cardRecognizer = recognizer
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let recognizer = gestureRecognizer as? CardPanRecognizer,
                  let origin = recognizer.origin(in: host.view) else { return false }
            return cardPan?.canPickUp(origin) == true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === cardRecognizer, let scroll = otherGestureRecognizer.view as? UIScrollView else { return false }
            return otherGestureRecognizer === scroll.panGestureRecognizer && host.view.isDescendant(of: scroll)
        }

        private func handleCardPan(_ recognizer: CardPanRecognizer) {
            let point = recognizer.location(in: host.view)
            switch recognizer.state {
            case .began:
                guard let origin = recognizer.origin(in: host.view) else { return }
                cardPan?.began(origin)
                cardPan?.moved(point)
            case .changed: cardPan?.moved(point)
            case .ended: cardPan?.ended(recognizer.releasePoint(in: host.view) ?? point)
            case .cancelled: cardPan?.cancelled()
            default: break
            }
        }
    }
}

private final class CardPanRecognizer: UIPanGestureRecognizer {
    private let onUpdate: (CardPanRecognizer) -> Void
    private var touchStart: CGPoint?
    private var touchEnd: CGPoint?

    init(onUpdate: @escaping (CardPanRecognizer) -> Void) {
        self.onUpdate = onUpdate
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(notifyUpdate))
    }

    @objc private func notifyUpdate() { onUpdate(self) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if touchStart == nil, let view, let touch = touches.first {
            touchStart = touch.location(in: view)
        }
        super.touchesBegan(touches, with: event)
    }

    func origin(in board: UIView) -> CGPoint? {
        guard let touchStart, let view else { return nil }
        return view.convert(touchStart, to: board)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let view, let touch = touches.first { touchEnd = touch.location(in: view) }
        super.touchesEnded(touches, with: event)
    }

    func releasePoint(in board: UIView) -> CGPoint? {
        guard let touchEnd, let view else { return nil }
        return view.convert(touchEnd, to: board)
    }

    override func reset() {
        super.reset()
        touchStart = nil
        touchEnd = nil
    }
}

final class CenteredBoardScrollView: UIScrollView {
    weak var boardView: UIView?
    private(set) var naturalSize: CGSize = .zero
    private var previousBounds: CGSize = .zero
    private var resetScale = true
    var fitWidth = false
    func configure(size: CGSize) {
        minimumZoomScale = 0.1; maximumZoomScale = 6
        setZoomScale(1, animated: false)
        naturalSize = size
        boardView?.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        resetScale = true
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, naturalSize.width > 0 else { return }
        if resetScale || previousBounds != bounds.size {
            let wasMinimum = abs(zoomScale - minimumZoomScale) < 0.02
            let fit = fitWidth ? min(1, bounds.width / naturalSize.width) :
                CGFloat(BoardViewport.minimumScale(boardWidth: Double(naturalSize.width), boardHeight: Double(naturalSize.height), viewportWidth: Double(bounds.width), viewportHeight: Double(bounds.height)))
            minimumZoomScale = fit; maximumZoomScale = max(3, fit * 3)
            let desired = resetScale || wasMinimum ? fit : max(fit, min(maximumZoomScale, zoomScale))
            let resetOffset = fitWidth && (resetScale || wasMinimum)
            previousBounds = bounds.size; resetScale = false
            setZoomScale(desired, animated: false)
            if resetOffset { setContentOffset(.zero, animated: false) }
        }
        centerBoard()
    }
    func centerBoard() {
        let x = CGFloat(BoardViewport.centering(content: Double(contentSize.width), viewport: Double(bounds.width)))
        let y = CGFloat(BoardViewport.centering(content: Double(contentSize.height), viewport: Double(bounds.height)))
        boardView?.center = CGPoint(x: contentSize.width / 2 + x, y: contentSize.height / 2 + y)
        showsHorizontalScrollIndicator = contentSize.width > bounds.width + 1
        showsVerticalScrollIndicator = contentSize.height > bounds.height + 1
        accessibilityValue = String(format: "%.2f", zoomScale)
    }
}
