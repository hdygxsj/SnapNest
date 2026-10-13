import Foundation
import CoreGraphics

public struct SavedCaptureRegion: Codable {
    public let displayIdentity: String
    public let localRect: CGRect
    public init(displayIdentity: String, localRect: CGRect) {
        self.displayIdentity = displayIdentity; self.localRect = localRect
    }
    public func rect(on screen: CGRect) -> CGRect? {
        guard localRect.minX.isFinite, localRect.minY.isFinite,
              localRect.width.isFinite, localRect.height.isFinite,
              localRect.width >= 8, localRect.height >= 8,
              CGRect(origin: .zero, size: screen.size).contains(localRect) else { return nil }
        return localRect.offsetBy(dx: screen.minX, dy: screen.minY)
    }
}
