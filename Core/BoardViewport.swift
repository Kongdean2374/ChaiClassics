import Foundation

/// The UIKit scroll view performs the actual transform; these values never remap taps.
public enum BoardViewport {
    public static func minimumScale(boardWidth: Double, boardHeight: Double, viewportWidth: Double, viewportHeight: Double) -> Double {
        guard boardWidth > 0, boardHeight > 0, viewportWidth > 0, viewportHeight > 0 else { return 1 }
        if boardWidth <= 306 && boardHeight <= 306 {
            return max(0.4, min(1.7, viewportWidth / boardWidth, viewportHeight / boardHeight))
        }
        return 1
    }
    public static func centering(content: Double, viewport: Double) -> Double { max(0, (viewport - content) / 2) }
}
