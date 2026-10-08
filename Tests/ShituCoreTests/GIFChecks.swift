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
}
