import SwiftUI
import UIKit
import ChaiCore

/// Native zoom transforms preserve the hosted grid's hit-test coordinates.
struct ZoomBoard<Content: View>: UIViewRepresentable {
    let size: CGSize
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme
    func makeCoordinator() -> Coordinator { Coordinator(content: content()) }
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
        return scroll
    }
    func updateUIView(_ scroll: CenteredBoardScrollView, context: Context) {
        context.coordinator.host.rootView = content()
        context.coordinator.host.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        if scroll.naturalSize != size { scroll.configure(size: size) }
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        let host: UIHostingController<Content>
        init(content: Content) { host = UIHostingController(rootView: content) }
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
