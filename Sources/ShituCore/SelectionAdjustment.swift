import CoreGraphics

public enum SelectionAdjustment {
    public static func fit(_ rect: CGRect, inside bounds: CGRect) -> CGRect {
        let width = min(bounds.width, max(8, rect.width)), height = min(bounds.height, max(8, rect.height))
        return CGRect(x: max(bounds.minX, min(rect.minX, bounds.maxX - width)),
                      y: max(bounds.minY, min(rect.minY, bounds.maxY - height)), width: width, height: height)
    }
    public static func drag(_ rect: CGRect, delta: CGPoint, edges: Int, bounds: CGRect) -> CGRect {
        if edges == 0 { return fit(rect.offsetBy(dx: delta.x, dy: delta.y), inside: bounds) }
        var left = rect.minX, right = rect.maxX, bottom = rect.minY, top = rect.maxY
        if edges & 1 != 0 { left = max(bounds.minX, min(right - 8, left + delta.x)) }
        if edges & 2 != 0 { right = min(bounds.maxX, max(left + 8, right + delta.x)) }
        if edges & 4 != 0 { bottom = max(bounds.minY, min(top - 8, bottom + delta.y)) }
        if edges & 8 != 0 { top = min(bounds.maxY, max(bottom + 8, top + delta.y)) }
        return CGRect(x: left, y: bottom, width: right-left, height: top-bottom)
    }
}
