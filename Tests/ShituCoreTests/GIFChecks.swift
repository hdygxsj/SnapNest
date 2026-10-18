import Foundation
import AVFoundation
import CoreVideo
import ImageIO
import ShituCore

func checkGIFExport() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Shitu-Tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let video = directory.appendingPathComponent("fixture.mp4")
    let gif = directory.appendingPathComponent("fixture.gif")
    let writer = try AVAssetWriter(outputURL: video, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 100, AVVideoHeightKey: 80])
    let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 100, kCVPixelBufferHeightKey as String: 80])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error! }
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<10 {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 100, 80, kCVPixelFormatType_32ARGB, nil, &buffer)
        guard let buffer else { throw CaptureFailure(message: "Test pixel buffer failed") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let address = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<80 { for x in 0..<100 {
            let i = y * stride + x * 4
            address[i] = 255; address[i + 1] = UInt8(frame * 24); address[i + 2] = UInt8(x * 2); address[i + 3] = UInt8(y * 3)
        } }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed { throw writer.error! }
            try await Task.sleep(for: .milliseconds(5))
        }
        guard adapter.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)) else { throw writer.error! }
    }
    writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error! }
    let joined = directory.appendingPathComponent("joined.mp4")
    try await RecordingSegments.export([video, video], to: joined)
    let joinedAsset = AVURLAsset(url: joined)
    let duration = try await joinedAsset.load(.duration)
    XCTAssertEqual(abs(duration.seconds - 2) < 0.02, true)
    let generator = AVAssetImageGenerator(asset: joinedAsset)
    generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
    let before = try await generator.image(at: CMTime(value: 3, timescale: 10)).image
    let after = try await generator.image(at: CMTime(value: 13, timescale: 10)).image
    XCTAssertEqual(ScreenPixels(image: before)?.color(x: 50, y: 40), ScreenPixels(image: after)?.color(x: 50, y: 40))
    let joinedGIF = directory.appendingPathComponent("joined.gif")
    try await GIFExporter.export(video: joined, to: joinedGIF)
    let joinedSource = CGImageSourceCreateWithURL(joinedGIF as CFURL, nil)!
    XCTAssertEqual(CGImageSourceGetCount(joinedSource), 20)
    print("Recording segments verified: concatenated duration, frame order, GIF export without pause gaps")
    try await checkRecordingAudio(video: video, directory: directory)
    try await GIFExporter.export(video: video, to: gif)
    guard let source = CGImageSourceCreateWithURL(gif as CFURL, nil) else { throw CaptureFailure(message: "GIF not readable") }
    XCTAssertEqual(CGImageSourceGetCount(source), 10)
    let first = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    XCTAssertEqual(first.width, 100); XCTAssertEqual(first.height, 80)
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
    let frameGIF = properties[kCGImagePropertyGIFDictionary] as! NSDictionary
    XCTAssertEqual((frameGIF[kCGImagePropertyGIFDelayTime] as! NSNumber).doubleValue, 0.1)
    let global = CGImageSourceCopyProperties(source, nil)! as NSDictionary
    let gifInfo = global[kCGImagePropertyGIFDictionary] as! NSDictionary
    XCTAssertEqual((gifInfo[kCGImagePropertyGIFLoopCount] as! NSNumber).intValue, 0)
    print("GIF export verified: 10 frames, 100 × 80, 0.1s delay, infinite loop")
    let hdGIF = directory.appendingPathComponent("hd.gif")
    try await GIFExporter.export(video: video, to: hdGIF, quality: .highDefinition)
    let hdSource = CGImageSourceCreateWithURL(hdGIF as CFURL, nil)!
    XCTAssertEqual(CGImageSourceGetCount(hdSource), 20)
    let hdImage = CGImageSourceCreateImageAtIndex(hdSource, 0, nil)!
    XCTAssertEqual(hdImage.width, 100) // Never invent extra pixels for a small source.
    XCTAssertEqual(hdImage.height, 80)
    let hdProperties = CGImageSourceCopyPropertiesAtIndex(hdSource, 0, nil)! as NSDictionary
    let hdFrame = hdProperties[kCGImagePropertyGIFDictionary] as! NSDictionary
    XCTAssertEqual((hdFrame[kCGImagePropertyGIFUnclampedDelayTime] as! NSNumber).doubleValue, 0.05)
    XCTAssertEqual(ExportQuality.standard.pngScale(nativeScale: 2), 1)
    XCTAssertEqual(ExportQuality.highDefinition.pngScale(nativeScale: 2), 2)
    print("HD quality verified: 20 fps timing, no upscaling and Retina PNG scale")
}

private func checkRecordingAudio(video: URL, directory: URL) async throws {
    let soundURL = directory.appendingPathComponent("tone.wav")
    var wave = Data()
    func u16(_ value: UInt16) { var value = value.littleEndian; withUnsafeBytes(of: &value) { wave.append(contentsOf: $0) } }
    func u32(_ value: UInt32) { var value = value.littleEndian; withUnsafeBytes(of: &value) { wave.append(contentsOf: $0) } }
    wave.append(Data("RIFF".utf8)); u32(36 + 44100 * 2); wave.append(Data("WAVEfmt ".utf8))
    u32(16); u16(1); u16(1); u32(44100); u32(88200); u16(2); u16(16)
    wave.append(Data("data".utf8)); u32(44100 * 2)
    for i in 0..<44100 { u16(UInt16(bitPattern: Int16(sin(Double(i) * 2 * .pi * 440 / 44100) * 6000))) }
    try wave.write(to: soundURL)
    let composition = AVMutableComposition()
    let videoAsset = AVURLAsset(url: video)
    let soundAsset = AVURLAsset(url: soundURL)
    // Keep source assets alive while their tracks are inserted and exported.
    defer { withExtendedLifetime((videoAsset, soundAsset)) {} }
    let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video)[0]
    let sourceAudio = try await soundAsset.loadTracks(withMediaType: .audio)[0]
    let range = CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1))
    try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(range, of: sourceVideo, at: .zero)
    try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(range, of: sourceAudio, at: .zero)
    let withAudio = directory.appendingPathComponent("with-audio.mp4")
    try await AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!.export(to: withAudio, as: .mp4)
    let result = directory.appendingPathComponent("joined-audio.mp4")
    try await RecordingSegments.export([withAudio, video, withAudio], to: result)
    let asset = AVURLAsset(url: result)
    XCTAssertEqual(abs(try await asset.load(.duration).seconds - 3) < 0.08, true)
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    XCTAssertEqual(tracks.count, 1)
    guard let track = tracks.first else { return }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(output)
    guard reader.startReading() else { throw reader.error! }
    var first = false, last = false, unexpectedMiddle = false
    while let sample = output.copyNextSampleBuffer() {
        let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        first = first || seconds < 0.9; last = last || seconds > 2.1
        unexpectedMiddle = unexpectedMiddle || (seconds > 1.1 && seconds < 1.9)
    }
    XCTAssertEqual(reader.status == .completed, true)
    XCTAssertEqual(first && last && !unexpectedMiddle, true)
    print("Recording audio verified: audio retained before/after silent segment, timestamps remain aligned")
}
