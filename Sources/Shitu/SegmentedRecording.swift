import AppKit
import ScreenCaptureKit
import ShituCore

/// Each pause closes a complete MP4. Joining finished segments removes paused time without rewriting timestamps in capture callbacks.
@MainActor
final class SegmentedRecording: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    private enum State { case idle, recording, paused, changing, finished }
    private var state: State = .idle
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration
    private let destination: URL
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SnapNest-Recording-\(UUID().uuidString)", isDirectory: true)
    private var segments: [URL] = []
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var segmentWaiter: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    var finished: ((Result<Void, Error>) -> Void)?

    init(filter: SCContentFilter, configuration: SCStreamConfiguration, destination: URL) {
        self.filter = filter; self.configuration = configuration; self.destination = destination
    }
    func start() async throws {
        guard state == .idle else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do { try await openSegment() }
        catch { cleanup(); throw error }
    }
    private func openSegment() async throws {
        state = .changing
        let url = directory.appendingPathComponent("\(segments.count).mp4")
        let config = SCRecordingOutputConfiguration()
        config.outputURL = url; config.outputFileType = .mp4; config.videoCodecType = .h264
        let output = SCRecordingOutput(configuration: config, delegate: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addRecordingOutput(output)
        self.output = output; self.stream = stream
        try await stream.startCapture()
        guard state != .finished else { throw CaptureFailure(message: "录屏已中断。") }
        segments.append(url)
        state = .recording
    }
    func pause() async throws {
        guard state == .recording else { return }
        do { try await closeSegment(); state = .paused }
        catch { throw abandon(error) }
    }
    func resume() async throws {
        guard state == .paused else { return }
        do { try await openSegment() }
        catch { throw abandon(error) }
    }
    func stop() async throws {
        guard state == .recording || state == .paused else { return }
        do {
            if state == .recording { try await closeSegment() }
            state = .changing
            try await RecordingSegments.export(segments, to: destination)
            state = .finished
            cleanup()
            let callback = finished; finished = nil
            callback?(.success(()))
        } catch { throw abandon(error) }
    }
    private func closeSegment() async throws {
        guard let stream, let output else { throw CaptureFailure(message: "录屏会话不可用。") }
        state = .changing
        // Install the waiter before stopping: the delegate may run before stopCapture returns.
        try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, Error>) in
            segmentWaiter = waiter
            Task { [weak self] in
                do { try await stream.stopCapture() }
                catch { self?.segmentEnded(output, result: .failure(error)) }
            }
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                self?.segmentEnded(output, result: .failure(CaptureFailure(message: "等待录屏文件写入超时。")))
            }
        }
        self.stream = nil; self.output = nil
    }
    private func segmentEnded(_ output: SCRecordingOutput, result: Result<Void, Error>) {
        guard self.output === output, state != .finished else { return }
        timeout?.cancel(); timeout = nil
        if let waiter = segmentWaiter {
            segmentWaiter = nil
            self.output = nil
            waiter.resume(with: result)
        } else {
            let error: Error
            if case .failure(let cause) = result { error = cause }
            else { error = CaptureFailure(message: "录屏意外结束，请重新开始。") }
            let failure = abandon(error)
            let callback = finished; finished = nil
            callback?(.failure(failure))
        }
    }
    private func abandon(_ error: Error) -> Error {
        state = .finished
        timeout?.cancel(); timeout = nil
        let oldStream = stream
        stream = nil; output = nil
        Task { try? await oldStream?.stopCapture() }
        // Keep completed fragments for recovery if final export or a later segment fails.
        return CaptureFailure(message: "\(error.localizedDescription)\n已录制片段保留在：\(directory.path)")
    }
    private func cleanup() {
        stream = nil; output = nil
        try? FileManager.default.removeItem(at: directory)
    }
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {}
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.segmentEnded(recordingOutput, result: .success(())) }
    }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in self.segmentEnded(recordingOutput, result: .failure(error)) }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.stream === stream, let output = self.output else { return }
            self.segmentEnded(output, result: .failure(error))
        }
    }
}
