import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct TutorialStep: Codable, Identifiable {
    var id = UUID()
    var imageFile: String
    var caption = ""
}
struct TutorialProject: Codable, Identifiable {
    var id = UUID()
    var title: String
    var steps: [TutorialStep] = []
}

@MainActor final class TutorialStore: ObservableObject {
    @Published private(set) var projects: [TutorialProject] = []
    @Published var selectedID: UUID?
    @Published var message: String?
    var requestCapture: (() -> Void)?
    /// The host can suspend its outside-click monitor while native pickers are open.
    var panelActivity: ((Bool) -> Void)?
    private var captureTarget: UUID?
    private var loadFailed = false
    let root: URL
    var selected: TutorialProject? { projects.first { $0.id == selectedID } }
    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QingyuOffice/Tutorials")) {
        self.root = root
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("projects.json")
            if FileManager.default.fileExists(atPath: file.path) { projects = try JSONDecoder().decode([TutorialProject].self, from: Data(contentsOf: file)) }
            selectedID = projects.first?.id
        } catch { loadFailed = true; message = "无法读取教程：\(error.localizedDescription)" }
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "Tutorial", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private func commit(_ next: [TutorialProject]) throws {
        guard !loadFailed else { throw failure("教程数据读取失败；请先备份并修复 projects.json 后重启，避免覆盖原数据。") }
        try JSONEncoder().encode(next).write(to: root.appendingPathComponent("projects.json"), options: .atomic)
        projects = next
    }
    @discardableResult func create(title: String = "新教程") throws -> UUID {
        let project = TutorialProject(title: String(title.prefix(120)))
        try commit(projects + [project]); selectedID = project.id; return project.id
    }
    func rename(_ id: UUID, title: String) throws {
        var next = projects; guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        next[index].title = String(title.prefix(120)); try commit(next)
    }
    func removeProject(_ id: UUID) throws {
        let files = projects.first(where: { $0.id == id })?.steps.map(\.imageFile) ?? []
        try commit(projects.filter { $0.id != id })
        if selectedID == id { selectedID = projects.first?.id }
        if captureTarget == id { cancelCapture() }
        for file in files { removeOwned(file) }
    }
    func caption(_ project: UUID, step: UUID, text: String) throws {
        try update(project) { value in
            guard let i = value.steps.firstIndex(where: { $0.id == step }) else { return }
            value.steps[i].caption = String(text.prefix(500))
        }
    }
    func move(_ project: UUID, step: UUID, offset: Int) throws {
        try update(project) { value in
            guard let i = value.steps.firstIndex(where: { $0.id == step }), value.steps.indices.contains(i + offset) else { return }
            value.steps.swapAt(i, i + offset)
        }
    }
    func remove(_ project: UUID, step: UUID) throws {
        let file = projects.first(where: { $0.id == project })?.steps.first(where: { $0.id == step })?.imageFile
        try update(project) { $0.steps.removeAll { $0.id == step } }
        if let file { removeOwned(file) }
    }
    private func update(_ id: UUID, body: (inout TutorialProject) throws -> Void) throws {
        var next = projects
        guard let i = next.firstIndex(where: { $0.id == id }) else { throw failure("教程已不存在。") }
        try body(&next[i]); try commit(next)
    }
    private func ownedURL(_ file: String) -> URL? {
        guard file == (file as NSString).lastPathComponent, UUID(uuidString: String(file.dropLast(4))) != nil, file.hasSuffix(".png") else { return nil }
        return root.appendingPathComponent(file)
    }
    private func removeOwned(_ file: String) { if let url = ownedURL(file) { try? FileManager.default.removeItem(at: url) } }
    func image(_ step: TutorialStep) -> CGImage? {
        guard let url = ownedURL(step.imageFile), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 4096, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
    }
    func importImage(_ url: URL, project: UUID, replacing: UUID? = nil) throws {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 4096, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw failure("无法读取所选图片。") }
        try add(image, project: project, replacing: replacing)
    }
    func add(_ image: CGImage, project: UUID, replacing: UUID? = nil) throws {
        guard let value = projects.first(where: { $0.id == project }) else { throw failure("教程已不存在。") }
        guard replacing != nil || value.steps.count < 100 else { throw failure("每个教程最多 100 步。") }
        if let replacing, !value.steps.contains(where: { $0.id == replacing }) { throw failure("步骤已不存在。") }
        let filename = UUID().uuidString + ".png", url = root.appendingPathComponent(filename)
        let scale = min(1, 4096 / Double(max(image.width, image.height)))
        guard let context = CGContext(data: nil, width: max(1, Int(Double(image.width) * scale)), height: max(1, Int(Double(image.height) * scale)), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw failure("图片过大，无法分配内存。") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        guard let bounded = context.makeImage() else { throw failure("无法处理图片。") }
        try Self.writePNG(bounded, to: url)
        var old: String?
        do {
            try update(project) { value in
                if let replacing, let i = value.steps.firstIndex(where: { $0.id == replacing }) { old = value.steps[i].imageFile; value.steps[i].imageFile = filename }
                else { value.steps.append(TutorialStep(imageFile: filename)) }
            }
        } catch { try? FileManager.default.removeItem(at: url); throw error }
        if let old { removeOwned(old) }
    }
    func beginCapture() {
        do { guard let id = selectedID, projects.contains(where: { $0.id == id }) else { throw failure("请先创建教程。") }; guard let requestCapture else { throw failure("截图入口暂不可用。") }; captureTarget = id; requestCapture() }
        catch { message = error.localizedDescription }
    }
    func cancelCapture() { captureTarget = nil }
    func acceptCapture(_ image: CGImage) {
        guard let id = captureTarget else { return }; captureTarget = nil
        perform { try add(image, project: id) }
    }
    func perform(_ operation: () throws -> Void) { do { try operation(); message = nil } catch { message = error.localizedDescription } }
    static func writePNG(_ image: CGImage, to url: URL) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw NSError(domain: "Tutorial", code: 2) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "Tutorial", code: 3) }
        try (data as Data).write(to: url, options: .atomic)
    }
    func export(_ id: UUID, to url: URL, pdf: Bool) throws {
        guard let project = projects.first(where: { $0.id == id }), !project.steps.isEmpty else { throw failure("请先添加教程步骤。") }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
        let titleBounds = (project.title as NSString).boundingRect(with: CGSize(width: pdf ? 539 : 1144, height: 100000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        guard titleBounds.height <= 32 else { throw failure("教程标题过长或换行过多，请缩短后导出。") }
        for (index, step) in project.steps.enumerated() {
            let text = "\(index + 1). \(step.caption)" as NSString
            let bounds = text.boundingRect(with: CGSize(width: pdf ? 539 : 1144, height: 100000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: pdf ? 12 : 20), .paragraphStyle: paragraph])
            guard bounds.height <= (pdf ? 235 : 265) else { throw failure("第 \(index + 1) 步说明过长或换行过多，请精简后导出。") }
        }
        if pdf {
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".tutorial-\(UUID()).pdf")
            defer { try? FileManager.default.removeItem(at: temporary) }
            var box = CGRect(x: 0, y: 0, width: 595, height: 842)
            guard let consumer = CGDataConsumer(url: temporary as CFURL), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw failure("无法创建 PDF。") }
            for (index, step) in project.steps.enumerated() {
                guard let image = image(step) else { throw failure("第 \(index + 1) 步图片丢失。") }
                context.beginPDFPage(nil)
                draw(context, image: image, title: project.title, caption: "\(index + 1). \(step.caption)", rect: box)
                context.endPDFPage()
            }
            context.closePDF()
            if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary) }
            else { try FileManager.default.moveItem(at: temporary, to: url) }
        } else {
            let width = 1200
            var heights: [Int] = []
            for step in project.steps {
                guard let image = image(step) else { throw failure("教程中有图片丢失。") }
                heights.append(Int(Double(image.height) * 1120 / Double(image.width)) + 400)
            }
            let height = heights.reduce(0, +)
            guard height <= 20000, width * height <= 24_000_000 else { throw failure("长图超过 1200 × 20000 像素限制，请拆分教程或导出 PDF。") }
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw failure("无法分配长图内存，请导出 PDF。") }
            var y = height
            for (index, step) in project.steps.enumerated() {
                guard let image = image(step) else { throw failure("步骤图片丢失。") }; y -= heights[index]
                draw(context, image: image, title: project.title, caption: "\(index + 1). \(step.caption)", rect: CGRect(x: 0, y: y, width: width, height: heights[index]))
            }
            guard let result = context.makeImage() else { throw failure("无法创建长图。") }; try Self.writePNG(result, to: url)
        }
    }
    private func draw(_ context: CGContext, image: CGImage, title: String, caption: String, rect: CGRect) {
        context.saveGState(); defer { context.restoreGState() }
        context.setFillColor(NSColor.white.cgColor); context.fill(rect)
        let margin: CGFloat = 28, captionHeight: CGFloat = rect.width > 600 ? 270 : 240
        let available = CGRect(x: rect.minX + margin, y: rect.minY + captionHeight + margin, width: rect.width - margin * 2, height: rect.height - captionHeight - 100)
        let scale = min(available.width / CGFloat(image.width), available.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.draw(image, in: CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2, width: size.width, height: size.height))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
        (title as NSString).draw(in: CGRect(x: rect.minX + margin, y: rect.maxY - 58, width: rect.width - margin * 2, height: 32), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.black])
        (caption as NSString).draw(in: CGRect(x: rect.minX + margin, y: rect.minY + margin, width: rect.width - margin * 2, height: captionHeight), withAttributes: [.font: NSFont.systemFont(ofSize: rect.width > 600 ? 20 : 12), .foregroundColor: NSColor.black, .paragraphStyle: paragraph])
        NSGraphicsContext.restoreGraphicsState()
    }
}
