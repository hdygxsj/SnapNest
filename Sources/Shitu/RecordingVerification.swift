import AppKit
import AVFoundation
import ScreenCaptureKit
import ShituCore

@MainActor
enum RecordingVerification {
    static func run() async -> Bool {
        guard CGPreflightScreenCaptureAccess() else { print("Recording verification requires screen capture permission"); return false }
        guard let screen = NSScreen.main,
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        let region = CaptureRegion(displayID: id.uint32Value, screenFrame: screen.frame,
            rect: CGRect(x: screen.frame.minX + 30, y: screen.frame.minY + 30, width: 160, height: 120), scale: screen.backingScaleFactor)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SnapNest-recording-check-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = CaptureEngine()
        var result: Result<Void, Error>?
        engine.recordingFinished = { result = $0 }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            print("Capture displays: \(content.displays.map(\.displayID)); AppKit display: \(id.uint32Value)")
            try await engine.startRecording(region, audio: true, to: url)
            try await Task.sleep(for: .seconds(1.2))
            try await engine.pauseRecording()
            guard result == nil else { print("FAIL pause prematurely finished recording"); return false }
            try await Task.sleep(for: .seconds(1.5))
            try await engine.resumeRecording()
            try await Task.sleep(for: .seconds(1.2))
            try await engine.pauseRecording()
            try await engine.stopRecording()
            guard case .success? = result else { print("FAIL recording completion: \(String(describing: result))"); return false }
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            guard duration > 1.8, duration < 3.2 else { print("FAIL active duration \(duration)"); return false }
            let generator = AVAssetImageGenerator(asset: asset)
            let image = try await generator.image(at: CMTime(seconds: duration - 0.3, preferredTimescale: 600)).image
            guard image.width > 0 else { return false }
            print("Live recording verified: pause/resume, stop while paused, playable MP4 duration \(duration)s excludes 1.5s pause")
            return true
        } catch { print("FAIL live recording: \(error)"); return false }
    }
}
