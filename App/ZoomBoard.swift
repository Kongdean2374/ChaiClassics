import SwiftUI
import UIKit
import ChaiCore

/// Native zoom transforms preserve the hosted grid's hit-test coordinates.
struct ZoomBoard<Content: View>: UIViewRepresentable {
    let size: CGSize
    let inputEnabled: Bool
    let accessibilityHidden: Bool
    let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var inheritedInputEnabled

    init(size: CGSize, inputEnabled: Bool = true, accessibilityHidden: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.size = size
        self.inputEnabled = inputEnabled
        self.accessibilityHidden = accessibilityHidden
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
        scroll.delaysContentTouches = false
        scroll.canCancelContentTouches = true
        scroll.bouncesZoom = true
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.scrollsToTop = false
        scroll.isAccessibilityElement = false
        scroll.accessibilityIdentifier = "mines.zoomBoard"
        let host = context.coordinator.host.view!
        host.backgroundColor = .clear
        host.autoresizingMask = []
        scroll.addSubview(host)
        scroll.boardView = host
        scroll.configure(size: size)
        updateAccessState(scroll, host: host)
        return scroll
    }
    func updateUIView(_ scroll: CenteredBoardScrollView, context: Context) {
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

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let host: UIHostingController<HostedContent>
        init(content: HostedContent) { host = UIHostingController(rootView: content) }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { (scrollView as? CenteredBoardScrollView)?.centerBoard() }
    }
}

final class CenteredBoardScrollView: UIScrollView {
    weak var boardView: UIView?
    private(set) var naturalSize: CGSize = .zero
    private var previousBounds: CGSize = .zero
    private var resetScale = true
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
            let fit = CGFloat(BoardViewport.minimumScale(boardWidth: Double(naturalSize.width), boardHeight: Double(naturalSize.height), viewportWidth: Double(bounds.width), viewportHeight: Double(bounds.height)))
            minimumZoomScale = fit; maximumZoomScale = max(3, fit * 3)
            let desired = resetScale || wasMinimum ? fit : max(fit, min(maximumZoomScale, zoomScale))
            previousBounds = bounds.size; resetScale = false
            setZoomScale(desired, animated: false)
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
