import Foundation
import AVFoundation

public enum RecordingSegments {
    public static func export(_ urls: [URL], to destination: URL) async throws {
        guard !urls.isEmpty else { throw CaptureFailure(message: "没有可保存的录屏片段。") }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CaptureFailure(message: "录屏目标文件已存在，无法覆盖。")
        }
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CaptureFailure(message: "无法创建录屏视频轨道。")
        }
        var audio: AVMutableCompositionTrack?
        var cursor = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .video).first else {
                throw CaptureFailure(message: "录屏片段缺少视频内容。")
            }
            let range = try await source.load(.timeRange)
            guard range.duration.seconds.isFinite, range.duration.seconds > 0 else {
                throw CaptureFailure(message: "录屏片段过短，请稍后再暂停或结束。")
            }
            if urls.count == 1 { try FileManager.default.copyItem(at: url, to: destination); return }
            if cursor == .zero { video.preferredTransform = try await source.load(.preferredTransform) }
            try video.insertTimeRange(range, of: source, at: cursor)
            if let sound = try await asset.loadTracks(withMediaType: .audio).first {
                if audio == nil { audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) }
                let audioRange = CMTimeRangeGetIntersection(try await sound.load(.timeRange), otherRange: range)
                if audioRange.duration.seconds > 0 {
                    // Preserve the sound track's offset within each segment.
                    try audio?.insertTimeRange(audioRange, of: sound, at: cursor + audioRange.start - range.start)
                }
            }
            cursor = cursor + range.duration
        }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw CaptureFailure(message: "无法合并录屏片段。")
        }
        do { try await exporter.export(to: destination, as: .mp4) }
        catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
}
