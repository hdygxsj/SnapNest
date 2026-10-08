import AppKit
import ShituCore

@MainActor
enum EditorVerification {
    static func fixture(width: Int = 900, height: Int = 540) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor(calibratedRed: 0.1, green: 0.23, blue: 0.2, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: height - 120, width: width, height: 120))
        context.setFillColor(NSColor.systemMint.cgColor)
        context.fill(CGRect(x: 45, y: height - 86, width: 260, height: 34))
        for row in 0..<5 {
            context.setFillColor(NSColor(calibratedWhite: 0.85 - Double(row) * 0.06, alpha: 1).cgColor)
            context.fill(CGRect(x: 45, y: 45 + row * 50, width: width - 90 - row * 40, height: 18))
        }
        return context.makeImage()!
    }
    static func run() -> Bool {
        let document = EditorDocument(image: fixture(width: 400, height: 400))
        document.add(Annotation(tool: .rectangle, points: [CGPoint(x: 20, y: 150), CGPoint(x: 170, y: 230)], color: .red, lineWidth: 6))
        document.add(Annotation(tool: .arrow, points: [CGPoint(x: 220, y: 200), CGPoint(x: 300, y: 260)], color: .blue, lineWidth: 4))
        document.add(Annotation(tool: .text, points: [CGPoint(x: 30, y: 250)], color: .black, lineWidth: 4, text: "编辑测试"))
        guard let annotated = document.render(), let data = annotated.dataProvider?.data, let pixels = CFDataGetBytePtr(data) else { return false }
        let offset = 150 * annotated.bytesPerRow + 80 * 4
        guard pixels[offset] > 200, pixels[offset + 1] < 40 else { print("FAIL rectangle orientation/color"); return false }
        let mosaicRect = CGRect(x: 200, y: 0, width: 120, height: 180)
        guard let patch = document.pixelated(mosaicRect) else { return false }
        document.add(Annotation(tool: .mosaic, points: [mosaicRect.origin, CGPoint(x: mosaicRect.maxX, y: mosaicRect.maxY)], color: .red, lineWidth: 4, patch: patch))
        guard let mosaic = document.render() else { return false }
        guard mosaic.width == 400, patch.width < 120 else { return false }
        document.crop(CGRect(x: 10, y: 100, width: 200, height: 220))
        guard document.image.width == 200, document.image.height == 220, document.history.current.cropOrigin == CGPoint(x: 10, y: 100) else { return false }
        document.undo()
        guard document.image.width == 400, document.history.current.annotations.count == 4, document.history.current.cropOrigin == .zero else { return false }
        document.redo()
        guard document.image.width == 200 else { return false }
        print("Editor checks passed: annotation pixel/color, mosaic, crop, undo/redo")
        return true
    }
}
