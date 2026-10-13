import AppKit

@MainActor
enum ProductivityVerification {
    static func run() -> Bool {
        _ = NSApplication.shared
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 260,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); CGRect(x: 0, y: 0, width: 900, height: 260).fill()
        "SnapNest 123".draw(at: CGPoint(x: 40, y: 160), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
        "截图文字识别".draw(at: CGPoint(x: 40, y: 70), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        guard let image = bitmap.cgImage else { return false }
        do {
            let text = try TextRecognition.recognize(image)
            guard text.contains("SnapNest"), text.contains("123"), text.contains("截图文字识别") else {
                print("FAIL OCR fixture: \(text)"); return false
            }
            print("OCR verified: real Vision recognizes English, digits and Chinese locally")
        } catch { print("FAIL OCR: \(error)"); return false }
        let before = PinnedImages.shared.panels.count
        let panel = PinnedImages.shared.show(image, near: CGRect(x: 100, y: 100, width: 400, height: 200))
        guard panel.isVisible, panel.level == .floating, panel.styleMask.contains(.resizable),
              !panel.hidesOnDeactivate, PinnedImages.shared.panels.count == before + 1 else { return false }
        panel.close()
        guard PinnedImages.shared.panels.count == before else { return false }
        print("Pin verified: floating resizable window, independent lifetime, close cleanup")
        return true
    }
}
