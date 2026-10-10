import AppKit
import ScreenCaptureKit
import AVFoundation
import ShituCore

@MainActor
final class CaptureEngine: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    var recordingFinished: ((Result<Void, Error>) -> Void)?
    private var didFinish = false

    func verifyPermission() async throws {
        // Preflight can be stale after granting access or replacing an ad-hoc build.
        // Use the same API as the real capture path, without taking an image.
        _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    func configuration(for region: CaptureRegion, audio: Bool = false) async throws -> (SCContentFilter, SCStreamConfiguration) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
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
        config.width = max(2, Int(config.sourceRect.width * region.scale) / 2 * 2)
        config.height = max(2, Int(config.sourceRect.height * region.scale) / 2 * 2)
        config.showsCursor = false
        config.capturesAudio = audio
        config.excludesCurrentProcessAudio = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        return (filter, config)
    }
    func screenshot(_ region: CaptureRegion) async throws -> CGImage {
        if let id = region.windowID {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw CaptureFailure(message: "所选窗口已关闭或隐藏，请重新选择。")
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = max(2, Int(window.frame.width * region.scale))
            config.height = max(2, Int(window.frame.height * region.scale))
            config.ignoreShadowsSingleWindow = true
            config.showsCursor = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        }
        let (filter, config) = try await configuration(for: region)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
    func startRecording(_ region: CaptureRegion, audio: Bool, to url: URL, gif: Bool = false) async throws {
        let (filter, config) = try await configuration(for: region, audio: audio)
        // H.264 encoder limit: preserve aspect ratio on large Retina displays.
        let ratio = gif
            ? min(1, 960.0 / Double(max(config.width, config.height)))
            : min(1, min(3840.0 / Double(config.width), 2160.0 / Double(config.height)))
        if gif { config.minimumFrameInterval = CMTime(value: 1, timescale: 10) }
        config.width = max(2, Int(Double(config.width) * ratio) / 2 * 2)
        config.height = max(2, Int(Double(config.height) * ratio) / 2 * 2)
        config.showsCursor = true
        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = url
        recordingConfig.outputFileType = .mp4
        recordingConfig.videoCodecType = .h264
        let recordingOutput = SCRecordingOutput(configuration: recordingConfig, delegate: self)
        let captureStream = SCStream(filter: filter, configuration: config, delegate: self)
        try captureStream.addRecordingOutput(recordingOutput)
        didFinish = false
        stream = captureStream
        output = recordingOutput
        do { try await captureStream.startCapture() }
        catch { stream = nil; output = nil; throw error }
    }
    func stopRecording() async throws { try await stream?.stopCapture() }
    private func finish(_ result: Result<Void, Error>) {
        guard !didFinish else { return }
        didFinish = true
        let oldStream = stream
        stream = nil
        output = nil
        if case .failure = result { Task { try? await oldStream?.stopCapture() } }
        recordingFinished?(result)
        recordingFinished = nil
    }
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {}
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.finish(.success(())) }
    }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }
}
