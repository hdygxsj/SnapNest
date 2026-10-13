import Foundation
import CoreGraphics

public struct PixelColor: Equatable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public var hex: String { String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue)) }
    public var rgb: String { "RGB \(red), \(green), \(blue)" }
}

/// An immutable sRGB snapshot. Coordinates in the byte buffer start at the top left.
public final class ScreenPixels {
    public let width: Int
    public let height: Int
    private let context: CGContext
    public init?(image: CGImage) {
        width = image.width; height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        self.context = context
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    public func pixel(at point: CGPoint, in bounds: CGRect) -> CGPoint? {
        guard bounds.width > 0, bounds.height > 0, bounds.contains(point) else { return nil }
        return CGPoint(x: min(width - 1, Int((point.x - bounds.minX) / bounds.width * CGFloat(width))),
                       y: min(height - 1, Int((bounds.maxY - point.y) / bounds.height * CGFloat(height))))
    }
    public func color(x: Int, y: Int) -> PixelColor? {
        guard x >= 0, y >= 0, x < width, y < height, let data = context.data else { return nil }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let i = (y * width + x) * 4
        let alpha = Int(bytes[i + 3])
        func channel(_ offset: Int) -> UInt8 { alpha == 0 ? 0 : UInt8(min(255, Int(bytes[i + offset]) * 255 / alpha)) }
        return PixelColor(red: channel(0), green: channel(1), blue: channel(2))
    }
}
