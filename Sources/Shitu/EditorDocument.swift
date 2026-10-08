import AppKit
import SwiftUI
import ShituCore

enum EditorTool: String, CaseIterable {
    case rectangle = "矩形", ellipse = "椭圆", arrow = "箭头", pen = "画笔", text = "文字", mosaic = "马赛克", crop = "裁剪"
    var icon: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .mosaic: return "square.grid.3x3.fill"
        case .crop: return "crop"
        }
    }
}
struct Annotation {
    var tool: EditorTool
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat
    var text = ""
    var patch: CGImage?
    var rect: CGRect {
        guard let start = points.first, let end = points.last else { return .zero }
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}
struct EditorSnapshot {
    var image: CGImage
    var annotations: [Annotation] = []
    var cropOrigin: CGPoint = .zero
}

@MainActor
final class EditorDocument: ObservableObject {
    @Published var history: EditHistory<EditorSnapshot>
    @Published var tool: EditorTool = .rectangle
    @Published var color: Color = .red
    @Published var lineWidth: Double = 4
    @Published var zoom: Double = 1
    @Published var message = "拖动添加标注；文字工具点击输入。⌘Z 撤销，⌘⇧Z 重做。"
    let initialWidth: Int
    let initialHeight: Int
    init(image: CGImage) {
        history = EditHistory(EditorSnapshot(image: image))
        initialWidth = image.width; initialHeight = image.height
        zoom = min(1, min(900 / Double(image.width), 540 / Double(image.height)))
        zoom = max(0.08, zoom)
    }
    var image: CGImage { history.current.image }
    func add(_ annotation: Annotation) {
        var state = history.current
        state.annotations.append(annotation)
        history.commit(state)
    }
    func undo() { history.undo() }
    func redo() { history.redo() }
    func crop(_ rect: CGRect) {
        let clipped = rect.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard clipped.width >= 8, clipped.height >= 8, let rendered = render(), let cropped = rendered.cropping(to: clipped) else { return }
        let oldOrigin = history.current.cropOrigin
        history.commit(EditorSnapshot(image: cropped, cropOrigin: CGPoint(x: oldOrigin.x + clipped.minX, y: oldOrigin.y + clipped.minY)))
        message = "已裁剪到 \(cropped.width) × \(cropped.height)；可撤销。切换录制仍使用原始屏幕选区。"
    }
    func pixelated(_ rect: CGRect) -> CGImage? {
        guard let image = render()?.cropping(to: rect.integral), image.width > 0, image.height > 0 else { return nil }
        let w = max(1, image.width / 18), h = max(1, image.height / 18)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }
    func render() -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.translateBy(x: 0, y: CGFloat(image.height)); context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for annotation in history.current.annotations { Self.draw(annotation, in: context) }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
    static func draw(_ annotation: Annotation, in context: CGContext) {
        guard let first = annotation.points.first, let last = annotation.points.last else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(annotation.color.cgColor)
        context.setFillColor(annotation.color.cgColor)
        context.setLineWidth(annotation.lineWidth)
        context.setLineCap(.round); context.setLineJoin(.round)
        switch annotation.tool {
        case .rectangle: context.stroke(annotation.rect)
        case .ellipse: context.strokeEllipse(in: annotation.rect)
        case .pen:
            context.move(to: first)
            for point in annotation.points.dropFirst() { context.addLine(to: point) }
            if annotation.points.count == 1 { context.addLine(to: CGPoint(x: first.x + 0.1, y: first.y)) }
            context.strokePath()
        case .arrow:
            context.move(to: first); context.addLine(to: last); context.strokePath()
            let angle = atan2(last.y - first.y, last.x - first.x)
            let length = max(15, annotation.lineWidth * 4)
            context.move(to: CGPoint(x: last.x - length * cos(angle - .pi / 6), y: last.y - length * sin(angle - .pi / 6)))
            context.addLine(to: last)
            context.addLine(to: CGPoint(x: last.x - length * cos(angle + .pi / 6), y: last.y - length * sin(angle + .pi / 6)))
            context.strokePath()
        case .text:
            let font = NSFont.systemFont(ofSize: max(18, annotation.lineWidth * 5), weight: .semibold)
            (annotation.text as NSString).draw(at: first, withAttributes: [.font: font, .foregroundColor: annotation.color])
        case .mosaic:
            if let patch = annotation.patch {
                context.interpolationQuality = .none
                context.translateBy(x: annotation.rect.minX, y: annotation.rect.maxY)
                context.scaleBy(x: 1, y: -1)
                context.draw(patch, in: CGRect(origin: .zero, size: annotation.rect.size))
            } else { context.setFillColor(NSColor.gray.withAlphaComponent(0.5).cgColor); context.fill(annotation.rect) }
        case .crop:
            context.setStrokeColor(NSColor.systemMint.cgColor)
            context.setLineDash(phase: 0, lengths: [8, 5]); context.stroke(annotation.rect)
        }
    }
}
