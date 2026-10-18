import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct ComparisonImage {
    let image: CGImage
    let name: String
    let sourceWidth: Int
    let sourceHeight: Int
    static func load(_ url: URL) throws -> Self {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else {
            throw OfficeError.message("无法读取图片，请选择 PNG、JPEG 或其他受支持的静态图片。")
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let rotated = (5...8).contains(orientation)
        return Self(image: image, name: url.lastPathComponent, sourceWidth: rotated ? height : width, sourceHeight: rotated ? width : height)
    }
}

enum ComparisonPixels {
    static func difference(_ first: CGImage, _ second: CGImage, threshold: Int) throws -> (CGImage, Double) {
        guard first.width == second.width, first.height == second.height else { throw OfficeError.message("差异分析需要两张图片尺寸一致，请先裁剪到相同尺寸。") }
        let w = first.width, h = first.height
        guard w > 0, h > 0, w <= 4096, h <= 4096 else { throw OfficeError.message("图片尺寸过大。") }
        let color = CGColorSpaceCreateDeviceRGB()
        func pixels(_ image: CGImage) throws -> [UInt8] {
            var bytes = [UInt8](repeating: 255, count: w * h * 4)
            let drawn = bytes.withUnsafeMutableBytes { ptr -> Bool in
                guard let context = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: color, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: w, height: h))
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h)); return true
            }
            guard drawn else { throw OfficeError.message("无法创建差异分析缓冲区。") }; return bytes
        }
        let a = try pixels(first), b = try pixels(second)
        var output = b, changed = 0
        for i in stride(from: 0, to: output.count, by: 4) {
            let delta = (0..<3).map { abs(Int(a[i + $0]) - Int(b[i + $0])) }.max() ?? 0
            if delta > max(0, min(255, threshold)) {
                output[i] = 255; output[i+1] = 45; output[i+2] = 90; changed += 1
            } else {
                let gray = UInt8((Int(b[i]) + Int(b[i+1]) + Int(b[i+2])) / 6 + 127)
                output[i] = gray; output[i+1] = gray; output[i+2] = gray
            }
            output[i+3] = 255
        }
        guard let provider = CGDataProvider(data: Data(output) as CFData), let result = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: color, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw OfficeError.message("无法生成差异图。") }
        return (result, Double(changed) / Double(w * h))
    }
}

@MainActor final class ComparisonStore: ObservableObject {
    @Published private(set) var before: ComparisonImage?
    @Published private(set) var after: ComparisonImage?
    @Published private(set) var difference: CGImage?
    @Published private(set) var ratio: Double?
    @Published var message: String?
    @Published var note = ""
    @Published var threshold = 20.0
    @Published private(set) var analyzing = false
    private var generation = 0
    func load(_ url: URL, first: Bool) {
        do {
            let image = try ComparisonImage.load(url)
            if first { before = image } else { after = image }
            generation += 1; difference = nil; ratio = nil; analyzing = false; message = nil
        } catch { message = error.localizedDescription }
    }
    func pick(first: Bool) {
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.image]
        if let window = NSApp.keyWindow { picker.beginSheetModal(for: window) { if $0 == .OK, let url = picker.url { self.load(url, first: first) } } }
        else if picker.runModal() == .OK, let url = picker.url { load(url, first: first) }
    }
    func analyze() {
        guard let before, let after else { return }
        guard before.sourceWidth == after.sourceWidth, before.sourceHeight == after.sourceHeight else { message = "原图尺寸不同，不能直接分析像素差异。左右对照仍可使用。"; return }
        generation += 1; let token = generation; let threshold = Int(threshold)
        difference = nil; ratio = nil; analyzing = true; message = nil
        Task {
            let result = await Task.detached { Result { try ComparisonPixels.difference(before.image, after.image, threshold: threshold) } }.value
            guard token == generation else { return }
            analyzing = false
            switch result {
            case .success(let value): difference = value.0; ratio = value.1
            case .failure(let error): message = error.localizedDescription
            }
        }
    }
    func invalidateAnalysis() { generation += 1; difference = nil; ratio = nil; analyzing = false }
    func report() throws -> Data {
        guard let before, let after else { throw OfficeError.message("请先选择两张图片。") }
        let noteBounds = ("验收意见\n" + note as NSString).boundingRect(with: NSSize(width: 740, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 20)])
        guard noteBounds.height <= 400 else { throw OfficeError.message("验收意见过长，请减少文字或换行后导出。") }
        guard let context = CGContext(data: nil, width: 1600, height: 1200, bitsPerComponent: 8, bytesPerRow: 6400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw OfficeError.message("无法创建报告画布。") }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1600, height: 1200).fill()
        func text(_ value: String, _ rect: NSRect, _ size: CGFloat) {
            (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black])
        }
        text("轻屿 · 截图对比", NSRect(x: 40, y: 1130, width: 1520, height: 40), 28)
        func draw(_ source: CGImage, into box: NSRect) {
            let scale = min(box.width / CGFloat(source.width), box.height / CGFloat(source.height))
            let size = NSSize(width: CGFloat(source.width) * scale, height: CGFloat(source.height) * scale)
            NSImage(cgImage: source, size: .zero).draw(in: NSRect(x: box.midX - size.width/2, y: box.midY - size.height/2, width: size.width, height: size.height))
        }
        text("修改前：\(before.name)", NSRect(x: 40, y: 1080, width: 740, height: 30), 18)
        text("修改后：\(after.name)", NSRect(x: 820, y: 1080, width: 740, height: 30), 18)
        draw(before.image, into: NSRect(x: 40, y: 580, width: 740, height: 480))
        draw(after.image, into: NSRect(x: 820, y: 580, width: 740, height: 480))
        if let difference {
            draw(difference, into: NSRect(x: 40, y: 80, width: 740, height: 460))
            text("差异像素：\(String(format: "%.2f", (ratio ?? 0) * 100))%（预览分辨率）", NSRect(x: 820, y: 500, width: 740, height: 35), 20)
        }
        text("验收意见\n\(note)", NSRect(x: 820, y: 80, width: 740, height: 400), 20)
        guard let cg = context.makeImage(), let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw OfficeError.message("导出图片失败。") }
        return data
    }
    func export() {
        let picker = NSSavePanel(); picker.allowedContentTypes = [.png]; picker.nameFieldStringValue = "轻屿-截图对比.png"
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = picker.url else { return }
            do { try self.report().write(to: url, options: .atomic); self.message = "对比报告已导出。" } catch { self.message = error.localizedDescription }
        }
        if let window = NSApp.keyWindow { picker.beginSheetModal(for: window, completionHandler: finish) } else { finish(picker.runModal()) }
    }
}

struct ComparisonWorkspace: View {
    @ObservedObject var store: ComparisonStore
    @State private var mode = 0
    @State private var split = 0.5
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("截图对比").font(.title3.bold()); Spacer()
                Button("选择修改前") { store.pick(first: true) }; Button("选择修改后") { store.pick(first: false) }
                Button("导出报告") { store.export() }.disabled(store.before == nil || store.after == nil)
            }
            Picker("对比方式", selection: $mode) { Text("左右对照").tag(0); Text("滑动对照").tag(1); Text("差异高亮").tag(2) }.pickerStyle(.segmented)
            GeometryReader { geometry in
                if let before = store.before, let after = store.after {
                    if mode == 0 {
                        HStack(spacing: 10) { picture(before.image).overlay(alignment: .topLeading) { Text("修改前").padding(5).background(.regularMaterial) }; picture(after.image).overlay(alignment: .topLeading) { Text("修改后").padding(5).background(.regularMaterial) } }
                    } else if mode == 1 {
                        ZStack(alignment: .leading) {
                            picture(after.image)
                            picture(before.image).mask(alignment: .leading) { Rectangle().frame(width: geometry.size.width * split) }
                            Rectangle().fill(.orange).frame(width: 2).offset(x: geometry.size.width * split)
                        }
                    } else if let difference = store.difference { picture(difference) }
                    else { Text(store.analyzing ? "正在分析…" : "点击下方「分析差异」生成高亮图").frame(maxWidth: .infinity, maxHeight: .infinity) }
                } else { ContentUnavailableView("选择两张截图开始", systemImage: "rectangle.on.rectangle", description: Text("图片仅在本地处理，不上传服务器。")) }
            }.frame(minHeight: 140).background(Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 10))
            if mode == 1 { HStack { Text("修改前"); Slider(value: $split, in: 0...1); Text("修改后") }.font(.caption) }
            if mode == 2 {
                HStack { Text("容差 \(Int(store.threshold))"); Slider(value: $store.threshold, in: 0...100, step: 1).onChange(of: store.threshold) { _, _ in store.invalidateAnalysis() }; Button("分析差异") { store.analyze() }.disabled(store.analyzing || store.before == nil || store.after == nil); if let ratio = store.ratio { Text(String(format: "%.2f%%", ratio * 100)) } }.font(.caption)
            }
            TextField("验收意见（最多 600 字，随报告导出）", text: $store.note, axis: .vertical).lineLimit(2...3).onChange(of: store.note) { _, value in if value.count > 600 { store.note = String(value.prefix(600)) } }
            if let message = store.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            Text("大图按最长边 2048 像素分析；高亮表示像素变化，不代表语义错误。切换办公页面保留当前对比，退出应用后不保存。 ").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func picture(_ image: CGImage) -> some View { Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
}
