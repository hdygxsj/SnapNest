import CoreGraphics

/// Candidates are ordered front to back, as returned by the window server.
public struct WindowTarget {
    public let id: CGWindowID
    public let frame: CGRect
    public let name: String
    public init(id: CGWindowID, quartzFrame: CGRect, primaryHeight: CGFloat, name: String) {
        self.id = id
        self.frame = CGRect(x: quartzFrame.minX, y: primaryHeight - quartzFrame.maxY,
                            width: quartzFrame.width, height: quartzFrame.height)
        self.name = name
    }
    public static func hit(at point: CGPoint, in targets: [WindowTarget]) -> WindowTarget? {
        targets.first { $0.frame.contains(point) }
    }
}
