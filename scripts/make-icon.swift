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
        context.setFillColor(CGColor(red: 0.065, green: 0.095, blue: 0.11, alpha: 1)); context.fillPath()
        context.setStrokeColor(CGColor(red: 0.62, green: 0.92, blue: 0.77, alpha: 1))
        context.setLineWidth(52); context.setLineCap(.round); context.setLineJoin(.round)
        for (x, y, dx, dy) in [(260.0, 260.0, 1.0, 1.0), (764, 260, -1, 1), (260, 764, 1, -1), (764, 764, -1, -1)] {
            context.move(to: CGPoint(x: x, y: y + dy * 132))
            context.addLine(to: CGPoint(x: x, y: y))
            context.addLine(to: CGPoint(x: x + dx * 132, y: y)); context.strokePath()
        }
        context.setFillColor(CGColor(red: 0.79, green: 0.96, blue: 0.86, alpha: 1))
        context.fillEllipse(in: CGRect(x: 426, y: 426, width: 172, height: 172))
        let image = NSBitmapImageRep(cgImage: context.makeImage()!)
        let suffix = scale == 2 ? "@2x" : ""
        try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(destination)/icon_\(size)x\(size)\(suffix).png"))
    }
}
