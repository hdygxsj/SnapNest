import AppKit
import ShituCore

@MainActor
enum PixelLoupe {
    static func render(to path: String) -> Bool {
        _ = NSApplication.shared
        let image = EditorVerification.fixture()
        guard let pixels = ScreenPixels(image: image),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 360,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 360)
        NSImage(cgImage: image, size: bounds.size).draw(in: bounds)
        draw(pixels: pixels, pointer: CGPoint(x: 280, y: 180), bounds: bounds)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: URL(fileURLWithPath: path)); return true } catch { return false }
    }
    static func draw(pixels: ScreenPixels, pointer: CGPoint, bounds: CGRect) {
        guard let pixel = pixels.pixel(at: pointer, in: bounds),
              let color = pixels.color(x: Int(pixel.x), y: Int(pixel.y)) else { return }
        let size = CGSize(width: 174, height: 202)
        let x = pointer.x + size.width + 24 < bounds.maxX ? pointer.x + 24 : pointer.x - size.width - 24
        let y = pointer.y - size.height - 24 >= bounds.minY ? pointer.y - size.height - 24 : pointer.y + 24
        let box = CGRect(x: max(bounds.minX + 4, min(x, bounds.maxX - size.width - 4)),
                         y: max(bounds.minY + 4, min(y, bounds.maxY - size.height - 4)), width: size.width, height: size.height)
        NSColor(white: 0.08, alpha: 1).setFill()
        NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
        let grid = CGPoint(x: box.minX + 10, y: box.maxY - 164)
        for row in 0..<11 { for column in 0..<11 {
            let c = pixels.color(x: Int(pixel.x) + column - 5, y: Int(pixel.y) + row - 5)
            (c.map { NSColor(srgbRed: CGFloat($0.red)/255, green: CGFloat($0.green)/255, blue: CGFloat($0.blue)/255, alpha: 1) } ?? .darkGray).setFill()
            let cell = CGRect(x: grid.x + CGFloat(column)*14, y: grid.y + CGFloat(10-row)*14, width: 14, height: 14)
            cell.fill()
            NSColor.black.withAlphaComponent(0.15).setStroke()
            NSBezierPath(rect: cell).stroke()
        } }
        let center = CGRect(x: grid.x + 70, y: grid.y + 70, width: 14, height: 14)
        NSColor.black.setStroke(); let outer = NSBezierPath(rect: center.insetBy(dx: -1, dy: -1)); outer.lineWidth = 3; outer.stroke()
        NSColor.white.setStroke(); let inner = NSBezierPath(rect: center); inner.lineWidth = 1; inner.stroke()
        color.hex.draw(at: CGPoint(x: box.minX + 10, y: box.minY + 21), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.white])
        color.rgb.draw(at: CGPoint(x: box.minX + 10, y: box.minY + 6), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.lightGray])
    }
}
