import AppKit
import Foundation

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let background = CGPath(roundedRect: CGRect(x: 32, y: 32, width: 960, height: 960), cornerWidth: 220, cornerHeight: 220, transform: nil)
        context.addPath(background)
        context.setFillColor(CGColor(red: 0.19, green: 0.34, blue: 0.84, alpha: 1)); context.fillPath()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let configuration = NSImage.SymbolConfiguration(pointSize: 550, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let symbol = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "轻屿")?.withSymbolConfiguration(configuration) {
            symbol.draw(in: CGRect(x: 240, y: 240, width: 544, height: 544))
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSBitmapImageRep(cgImage: context.makeImage()!)
        let suffix = scale == 2 ? "@2x" : ""
        try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(destination)/icon_\(size)x\(size)\(suffix).png"))
    }
}
