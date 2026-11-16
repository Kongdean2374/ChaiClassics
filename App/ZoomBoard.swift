import SwiftUI
import UIKit

/// A full-sized touch board hosted in a native pan/zoom viewport.
struct ZoomBoard<Content: View>: UIViewRepresentable {
    let size: CGSize
    @ViewBuilder let content: () -> Content
    func makeCoordinator() -> Coordinator { Coordinator(content: content()) }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 3
        scroll.bouncesZoom = true; scroll.delaysContentTouches = false
        let host = context.coordinator.host.view!
        host.backgroundColor = .clear; host.frame = CGRect(origin: .zero, size: size)
        scroll.addSubview(host); scroll.contentSize = size
        return scroll
    }
    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.host.rootView = content()
        if context.coordinator.size != size {
            scroll.setZoomScale(1, animated: false)
            context.coordinator.host.view.frame = CGRect(origin: .zero, size: size)
            scroll.contentSize = size; context.coordinator.size = size
        }
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        let host: UIHostingController<Content>
        var size: CGSize = .zero
        init(content: Content) { host = UIHostingController(rootView: content) }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }
    }
}
