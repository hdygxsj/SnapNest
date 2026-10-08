import AppKit

/// Keeps only accepted strips; grayscale comparison runs off the main actor.
public actor LongCapture {
    public init() {}
    private var parts: [CGImage] = []
    private var last: [UInt8] = []
    private var width = 0
    private var frameHeight = 0
    private(set) var totalHeight = 0
    private(set) var count = 0
    private let sampleWidth = 64
    public enum Update { case added(Int, Int), duplicate, unmatched, limit }

    public func append(_ image: CGImage) throws -> Update {
        guard let gray = grayscale(image) else { throw CaptureFailure(message: "无法读取截图像素。") }
        if parts.isEmpty {
            width = image.width; frameHeight = image.height
            guard width * frameHeight <= 80_000_000 else { return .limit }
            parts = [image]; last = gray; totalHeight = image.height; count = 1
            return .added(count, totalHeight)
        }
        guard image.width == width, image.height == frameHeight else { return .unmatched }
        guard let shift = OverlapMatcher.displacement(previous: last, next: gray, width: sampleWidth, height: frameHeight) else { return .unmatched }
        guard shift > 0 else { return .duplicate }
        guard width * (totalHeight + shift) <= 80_000_000, totalHeight + shift <= 40_000 else { return .limit }
        guard let strip = image.cropping(to: CGRect(x: 0, y: image.height - shift, width: width, height: shift)) else { return .unmatched }
        parts.append(strip); last = gray; totalHeight += shift; count += 1
        return .added(count, totalHeight)
    }
    public func result() throws -> CGImage {
        guard !parts.isEmpty,
              let context = CGContext(data: nil, width: width, height: totalHeight, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CaptureFailure(message: "长截图为空或内存不足。")
        }
        var top = totalHeight
        for part in parts {
            top -= part.height
            context.draw(part, in: CGRect(x: 0, y: top, width: width, height: part.height))
        }
        guard let image = context.makeImage() else { throw CaptureFailure(message: "无法生成长截图。") }
        return image
    }
    private func grayscale(_ image: CGImage) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: sampleWidth * image.height)
        let success = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: sampleWidth, height: image.height, bitsPerComponent: 8, bytesPerRow: sampleWidth, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: image.height))
            return true
        }
        return success ? bytes : nil
    }
}
