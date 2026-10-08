import Foundation
import ScreenCaptureKit

public struct ScreenCaptureAccess {
    public private(set) var preflight: Bool
    public private(set) var needsRecovery = false
    public init(preflight: Bool) { self.preflight = preflight }
    public var isAllowed: Bool { preflight && !needsRecovery }
    public mutating func updatePreflight(_ value: Bool) { preflight = value }
    public mutating func denied() { needsRecovery = true }
    public mutating func verified() { preflight = true; needsRecovery = false }
    public static func isPermissionError(_ error: Error) -> Bool {
        var candidate = error as NSError
        // Bound traversal for malformed or cyclic underlying-error chains.
        for _ in 0..<8 {
            if candidate.domain == SCStreamErrorDomain && candidate.code == -3801 { return true }
            guard let underlying = candidate.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
            candidate = underlying
        }
        return false
    }
}
