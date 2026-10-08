import Foundation
import Darwin
import ScreenCaptureKit
import CoreGraphics

import ShituCore

final class CoreTests {
    func testSelectionOnLeftDisplayUsesLocalTopOrigin() {
        XCTAssertEqual(CaptureGeometry.sourceRect(selection: CGRect(x: -1800, y: 200, width: 400, height: 300), screen: CGRect(x: -1920, y: -100, width: 1920, height: 1080)), CGRect(x: 120, y: 480, width: 400, height: 300))
    }
    func testSelectionClampsToDisplay() {
        XCTAssertEqual(CaptureGeometry.sourceRect(selection: CGRect(x: -20, y: 80, width: 60, height: 60), screen: CGRect(x: 0, y: 0, width: 100, height: 100)), CGRect(x: 0, y: 0, width: 40, height: 20))
    }
    func frame(offset: Int, width: Int = 64, height: Int = 160) -> [UInt8] {
        var result: [UInt8] = []
        for y in 0..<height { for x in 0..<width {
            let row = y + offset
            let value = row * 73 + x * 37 + row * x * 13
            result.append(UInt8(value % 251))
        } }
        return result
    }
    func testFindsDownwardScroll() {
        XCTAssertEqual(OverlapMatcher.displacement(previous: frame(offset: 0), next: frame(offset: 47), width: 64, height: 160), 47)
    }
    func testDuplicateFrameDoesNotAppend() {
        XCTAssertEqual(OverlapMatcher.displacement(previous: frame(offset: 0), next: frame(offset: 0), width: 64, height: 160), 0)
    }
    func testUnrelatedAndBlankFramesRejected() {
        XCTAssertNil(OverlapMatcher.displacement(previous: frame(offset: 0), next: Array(repeating: 0, count: 64 * 160), width: 64, height: 160))
        XCTAssertNil(OverlapMatcher.displacement(previous: [], next: [], width: 0, height: 0))
        XCTAssertNil(OverlapMatcher.displacement(previous: Array(repeating: 250, count: 64 * 160), next: Array(repeating: 255, count: 64 * 160), width: 64, height: 160))
    }
    func testSmallRenderingNoiseStillMatches() {
        let next = frame(offset: 28).map { UInt8(min(255, Int($0) + 2)) }
        XCTAssertEqual(OverlapMatcher.displacement(previous: frame(offset: 0), next: next, width: 64, height: 160), 28)
    }
}

var failures = 0
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    if actual != expected { print("FAIL \(file):\(line): \(actual) != \(expected)"); failures += 1 }
}
func XCTAssertNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    if value != nil { print("FAIL \(file):\(line): expected nil, got \(String(describing: value))"); failures += 1 }
}
let tests = CoreTests()
tests.testSelectionOnLeftDisplayUsesLocalTopOrigin()
tests.testSelectionClampsToDisplay()
tests.testFindsDownwardScroll()
tests.testDuplicateFrameDoesNotAppend()
tests.testUnrelatedAndBlankFramesRejected()
tests.testSmallRenderingNoiseStillMatches()

// Verify actual CGImage orientation and appended strips, not just matching offsets.
func makeImage(offset: Int) -> CGImage {
    let bytes = tests.frame(offset: offset)
    let data = Data(bytes) as CFData
    return CGImage(width: 64, height: 160, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 64,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
        provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}
let stitcher = LongCapture()
_ = try await stitcher.append(makeImage(offset: 0))
_ = try await stitcher.append(makeImage(offset: 47))
_ = try await stitcher.append(makeImage(offset: 47))
_ = try await stitcher.append(makeImage(offset: 90))
let stitched = try await stitcher.result()
XCTAssertEqual(stitched.width, 64)
XCTAssertEqual(stitched.height, 250)
let data = stitched.dataProvider!.data!
let pixels = CFDataGetBytePtr(data)!
let expected = tests.frame(offset: 0, height: 250)
var maxDelta = 0
for y in 0..<250 { for x in 0..<64 {
    let actual = Int(pixels[y * stitched.bytesPerRow + x * 4])
    maxDelta = max(maxDelta, abs(actual - Int(expected[y * 64 + x])))
} }
XCTAssertEqual(maxDelta <= 1, true)
var history = EditHistory([1])
history.commit([1, 2]); history.commit([1, 2, 3]); history.undo()
XCTAssertEqual(history.current, [1, 2])
history.redo(); XCTAssertEqual(history.current, [1, 2, 3])
history.undo(); history.commit([7])
XCTAssertEqual(history.canRedo, false)
history.undo(); XCTAssertEqual(history.current, [1, 2])
// A stale preflight result must not hide an actual ScreenCaptureKit denial.
var access = ScreenCaptureAccess(preflight: true)
XCTAssertEqual(access.isAllowed, true)
access.denied()
XCTAssertEqual(access.isAllowed, false)
access.updatePreflight(true)
XCTAssertEqual(access.isAllowed, false)
XCTAssertEqual(access.needsRecovery, true)
access.verified()
XCTAssertEqual(access.isAllowed, true)
XCTAssertEqual(access.needsRecovery, false)
let denied = NSError(domain: SCStreamErrorDomain, code: -3801)
XCTAssertEqual(ScreenCaptureAccess.isPermissionError(denied), true)
let wrapped = NSError(domain: "Wrapper", code: 1, userInfo: [NSUnderlyingErrorKey: denied])
XCTAssertEqual(ScreenCaptureAccess.isPermissionError(wrapped), true)
XCTAssertEqual(ScreenCaptureAccess.isPermissionError(NSError(domain: "Unrelated", code: -3801)), false)
XCTAssertEqual(ScreenCaptureAccess.isPermissionError(NSError(domain: SCStreamErrorDomain, code: -3802)), false)
// Floating tools remain adjacent to the original screen selection, including secondary displays.
let desktop = CGRect(x: 0, y: 0, width: 1440, height: 900)
let toolbarSize = CGSize(width: 520, height: 88)
let middleSelection = CGRect(x: 300, y: 400, width: 600, height: 300)
let below = FloatingEditorLayout.toolbar(selection: middleSelection, visibleScreen: desktop, size: toolbarSize)
XCTAssertEqual(below, CGRect(x: 380, y: 304, width: 520, height: 88))
let bottomSelection = CGRect(x: 1200, y: 10, width: 200, height: 100)
let above = FloatingEditorLayout.toolbar(selection: bottomSelection, visibleScreen: desktop, size: toolbarSize)
XCTAssertEqual(above.minY, 118)
XCTAssertEqual(desktop.contains(above), true)
let leftScreen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
let leftSelection = CGRect(x: -1910, y: 0, width: 100, height: 150)
XCTAssertEqual(leftScreen.contains(FloatingEditorLayout.toolbar(selection: leftSelection, visibleScreen: leftScreen, size: toolbarSize)), true)
XCTAssertEqual(desktop.contains(FloatingEditorLayout.toolbar(selection: desktop, visibleScreen: desktop, size: toolbarSize)), true)
let cropFrame = FloatingEditorLayout.canvas(selection: middleSelection, originalPixels: CGSize(width: 1200, height: 600), crop: CGRect(x: 100, y: 40, width: 600, height: 200))
XCTAssertEqual(cropFrame, CGRect(x: 350, y: 580, width: 300, height: 100))
await checkLoginItems()
try await checkGIFExport()
print("12 test groups, \(failures) failures")
exit(failures == 0 ? 0 : 1)
