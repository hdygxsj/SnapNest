import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public enum GIFExporter {
    public static let fps = 10
    public static let maximumDuration = 30.0
    public static func export(video: URL, to destination: URL, quality: ExportQuality = .standard, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let fps = quality.gifFramesPerSecond
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw CaptureFailure(message: "录制时间太短，无法生成 GIF。") }
        let length = min(duration, maximumDuration)
        let count = max(1, Int(ceil(length * Double(fps))))
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let output = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw CaptureFailure(message: "无法创建 GIF 文件，请检查保存目录。")
        }
        CGImageDestinationSetProperties(output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: quality.gifMaximumDimension, height: quality.gifMaximumDimension)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        for frame in 0..<count {
            try Task.checkCancellation()
            let time = CMTime(seconds: Double(frame) / Double(fps), preferredTimescale: 600)
            let result = try await generator.image(at: time)
            let delay = max(0.02, min(1.0 / Double(fps), length - Double(frame) / Double(fps)))
            CGImageDestinationAddImage(output, result.image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
            progress(Double(frame + 1) / Double(count))
        }
        guard CGImageDestinationFinalize(output) else { throw CaptureFailure(message: "GIF 导出失败。") }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
