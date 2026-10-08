import Foundation
import CoreGraphics

public enum FloatingEditorLayout {
    public static func toolbar(selection: CGRect, visibleScreen: CGRect, size: CGSize) -> CGRect {
        let gap: CGFloat = 8
        let width = min(size.width, visibleScreen.width)
        let height = min(size.height, visibleScreen.height)
        let x = min(max(selection.maxX - width, visibleScreen.minX), visibleScreen.maxX - width)
        let below = selection.minY - gap - height
        let above = selection.maxY + gap
        let y: CGFloat
        if below >= visibleScreen.minY { y = below }
        else if above + height <= visibleScreen.maxY { y = above }
        else { y = visibleScreen.minY + gap }
        return CGRect(x: x, y: min(max(y, visibleScreen.minY), visibleScreen.maxY - height), width: width, height: height)
    }
    public static func canvas(selection: CGRect, originalPixels: CGSize, crop: CGRect) -> CGRect {
        guard originalPixels.width > 0, originalPixels.height > 0 else { return .zero }
        let scaleX = selection.width / originalPixels.width
        let scaleY = selection.height / originalPixels.height
        return CGRect(x: selection.minX + crop.minX * scaleX,
                      y: selection.maxY - crop.maxY * scaleY,
                      width: crop.width * scaleX, height: crop.height * scaleY)
    }
}
