import AppKit
import ScreenCaptureKit
import AVFoundation
import ShituCore

@MainActor
final class CaptureEngine: NSObject {
    private var recording: SegmentedRecording?
    var recordingFinished: ((Result<Void, Error>) -> Void)?

    func verifyPermission() async throws {
        // Preflight can be stale after granting access or replacing an ad-hoc build.
        // Use the same API as the real capture path, without taking an image.
        _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    func configuration(for region: CaptureRegion, audio: Bool = false) async throws -> (SCContentFilter, SCStreamConfiguration) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard !content.displays.isEmpty else {
            throw CaptureFailure(message: "未找到可捕获的显示器。请先解锁 Mac，并确认屏幕录制权限后重试。")
        }
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw CaptureFailure(message: "所选显示器已断开，请重新选择。")
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = CaptureGeometry.sourceRect(selection: region.rect, screen: region.screenFrame)
        guard config.sourceRect.width >= 2, config.sourceRect.height >= 2 else {
            throw CaptureFailure(message: "选择区域太小，请重新选择。")
        }
        // Still images retain odd pixel dimensions; the recording path aligns its encoder dimensions separately.
        config.width = max(2, Int((config.sourceRect.width * region.scale).rounded()))
        config.height = max(2, Int((config.sourceRect.height * region.scale).rounded()))
        config.showsCursor = false
        config.capturesAudio = audio
        config.excludesCurrentProcessAudio = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        return (filter, config)
    }
    func screenshot(_ region: CaptureRegion, quality: ExportQuality = .highDefinition) async throws -> CGImage {
        if let id = region.windowID {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw CaptureFailure(message: "所选窗口已关闭或隐藏，请重新选择。")
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = max(2, Int((window.frame.width * quality.pngScale(nativeScale: Double(filter.pointPixelScale))).rounded()))
            config.height = max(2, Int((window.frame.height * quality.pngScale(nativeScale: Double(filter.pointPixelScale))).rounded()))
            config.ignoreShadowsSingleWindow = true
            config.showsCursor = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        }
        let (filter, config) = try await configuration(for: region)
        config.width = max(2, Int((config.sourceRect.width * quality.pngScale(nativeScale: Double(filter.pointPixelScale))).rounded()))
        config.height = max(2, Int((config.sourceRect.height * quality.pngScale(nativeScale: Double(filter.pointPixelScale))).rounded()))
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
    func startRecording(_ region: CaptureRegion, audio: Bool, to url: URL, gif: Bool = false, quality: ExportQuality = .standard) async throws {
        let (filter, config) = try await configuration(for: region, audio: audio)
        // H.264 encoder limit: preserve aspect ratio on large Retina displays.
        let ratio = gif
            ? min(1, Double(quality.gifMaximumDimension) / Double(max(config.width, config.height)))
            : min(1, min(3840.0 / Double(config.width), 2160.0 / Double(config.height)))
        if gif { config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(quality.gifFramesPerSecond)) }
        config.width = max(2, Int(Double(config.width) * ratio) / 2 * 2)
        config.height = max(2, Int(Double(config.height) * ratio) / 2 * 2)
        config.showsCursor = true
        let session = SegmentedRecording(filter: filter, configuration: config, destination: url)
        session.finished = { [weak self] result in
            guard let self else { return }
            self.recording = nil
            let callback = self.recordingFinished
            self.recordingFinished = nil
            callback?(result)
        }
        recording = session
        do { try await session.start() }
        catch { recording = nil; recordingFinished = nil; throw error }
    }
    func pauseRecording() async throws { try await recording?.pause() }
    func resumeRecording() async throws { try await recording?.resume() }
    func stopRecording() async throws { try await recording?.stop() }
}
