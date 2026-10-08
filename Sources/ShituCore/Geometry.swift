import Foundation
import CoreGraphics

public enum CaptureGeometry {
    public static func sourceRect(selection: CGRect, screen: CGRect) -> CGRect {
        let clipped = selection.standardized.intersection(screen)
        guard !clipped.isNull, !clipped.isEmpty else { return .zero }
        return CGRect(x: clipped.minX - screen.minX, y: screen.maxY - clipped.maxY,
                      width: clipped.width, height: clipped.height)
    }
}
