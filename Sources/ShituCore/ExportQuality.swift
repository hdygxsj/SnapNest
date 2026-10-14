import Foundation

public enum ExportQuality: String, Sendable {
    case standard, highDefinition
    public var gifMaximumDimension: Int { self == .highDefinition ? 1920 : 960 }
    public var gifFramesPerSecond: Int { self == .highDefinition ? 20 : 10 }
    public static func resolved(pro: Bool, prefersHD: Bool) -> Self { pro && prefersHD ? .highDefinition : .standard }
    public func pngScale(nativeScale: Double) -> Double { self == .highDefinition ? max(1, nativeScale) : 1 }
}
