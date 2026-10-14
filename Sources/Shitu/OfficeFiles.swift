import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OfficeReference: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var url: URL
    var bookmark: Data?
    init(url: URL, title: String? = nil) throws {
        guard url.isFileURL || (["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil && url.user == nil && url.password == nil) else {
            throw OfficeError.message("只支持文件、文件夹、应用和 HTTP(S) 网页。")
        }
        self.url = url
        self.title = title ?? (url.isFileURL ? url.lastPathComponent : url.host ?? url.absoluteString)
        if url.isFileURL {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }
}
enum OfficeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Retains security scopes while references are displayed or handed to a drag session.
@MainActor final class OfficeAccess {
    private var active: [UUID: URL] = [:]
    func resolve(_ reference: OfficeReference) throws -> URL {
        if let cached = active[reference.id] {
            if FileManager.default.fileExists(atPath: cached.path) { return cached }
            release(reference.id)
        }
        guard reference.url.isFileURL else { return reference.url }
        var stale = false
        let url: URL
        if let data = reference.bookmark {
            url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        } else { url = reference.url }
        let scoped = url.startAccessingSecurityScopedResource()
        guard FileManager.default.fileExists(atPath: url.path) else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw OfficeError.message("文件已移动、删除或不可访问：\(reference.title)。请重新添加。")
        }
        if scoped { active[reference.id] = url }
        return url
    }
    func release(_ id: UUID) { active.removeValue(forKey: id)?.stopAccessingSecurityScopedResource() }
    deinit { for url in active.values { url.stopAccessingSecurityScopedResource() } }
}

@MainActor enum OfficeDisk {
    nonisolated static var root: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QingyuOffice", isDirectory: true) }
    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
    static func load<T: Decodable>(_ type: T.Type, from url: URL, empty: T) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else { return empty }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
    static func pick(multiple: Bool = true, completion: @escaping ([URL]) -> Void) {
        let picker = NSOpenPanel()
        picker.canChooseFiles = true; picker.canChooseDirectories = true
        picker.allowsMultipleSelection = multiple
        if let window = NSApp.keyWindow {
            picker.beginSheetModal(for: window) { if $0 == .OK { completion(picker.urls) } }
        } else if picker.runModal() == .OK { completion(picker.urls) }
    }
}

@MainActor final class FileShelfStore: ObservableObject {
    @Published private(set) var items: [OfficeReference] = []
    @Published var message: String?
    let access = OfficeAccess()
    private let file: URL
    private let canUse: @MainActor () -> Bool
    private var loadFailed = false
    init(root: URL = OfficeDisk.root, canUse: @escaping @MainActor () -> Bool = { ProStore.shared.isPro }) {
        file = root.appendingPathComponent("shelf.json"); self.canUse = canUse
        do { items = try OfficeDisk.load([OfficeReference].self, from: file, empty: []) }
        catch { loadFailed = true; message = "暂存篮读取失败，未覆盖原数据：\(error.localizedDescription)" }
    }
    private func allowed() -> Bool {
        guard !loadFailed else { message = "请先恢复暂存篮数据文件，当前仅供查看。"; return false }
        guard canUse() else { message = "此功能需要轻屿 Pro。"; return false }; return true
    }
    func add(_ urls: [URL]) {
        guard allowed() else { return }
        var next = items; var errors: [String] = []
        for url in urls where url.isFileURL && !next.contains(where: { $0.url == url }) {
            do {
                guard next.count < 200 else { throw OfficeError.message("暂存篮最多保存 200 项，请先移除已处理项目。") }
                next.append(try OfficeReference(url: url))
            } catch { errors.append(error.localizedDescription) }
        }
        do { try OfficeDisk.save(next, to: file); items = next; message = errors.isEmpty ? nil : errors.joined(separator: "\n") }
        catch { message = error.localizedDescription }
    }
    func remove(_ ids: Set<UUID>) {
        guard allowed() else { return }
        let next = items.filter { !ids.contains($0.id) }
        do { try OfficeDisk.save(next, to: file); items = next; ids.forEach { access.release($0) }; message = "已移除引用，原文件未改变。" }
        catch { message = error.localizedDescription }
    }
    func resolved(_ ids: Set<UUID>) -> [URL] {
        guard allowed() else { return [] }
        var urls: [URL] = []; var errors: [String] = []
        for item in items where ids.contains(item.id) {
            do { urls.append(try access.resolve(item)) } catch { errors.append(error.localizedDescription) }
        }
        if !errors.isEmpty { message = errors.joined(separator: "\n") }
        return urls
    }
    func copy(_ ids: Set<UUID>) {
        let urls = resolved(ids); guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
        message = "已复制 \(urls.count) 个文件引用，可到 Finder 或邮件中粘贴。"
    }
    func reveal(_ item: OfficeReference) {
        do { NSWorkspace.shared.activateFileViewerSelecting([try access.resolve(item)]) } catch { message = error.localizedDescription }
    }
}

struct FileShelfWorkspace: View {
    @ObservedObject var store: FileShelfStore
    @State private var selection: Set<UUID> = []
    @State private var targeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("文件暂存篮").font(.title3.bold()); Spacer()
                Button("添加文件") { OfficeDisk.pick { store.add($0) } }
                Button("复制所选") { store.copy(selection) }.disabled(selection.isEmpty)
                Button("移出所选") { store.remove(selection); selection = [] }.disabled(selection.isEmpty)
            }
            Text("拖入文件集中整理，原文件不移动。拖文件到主屏顶部中央可展开；选中多项后从下方一起拖出。").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.items) { item in
                        HStack {
                            Toggle(isOn: Binding(get: { selection.contains(item.id) }, set: { if $0 { selection.insert(item.id) } else { selection.remove(item.id) } })) { EmptyView() }.toggleStyle(.checkbox).labelsHidden()
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 26, height: 26)
                            VStack(alignment: .leading) {
                                Text(item.title).lineLimit(1)
                                Text(item.url.deletingLastPathComponent().path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                if (try? store.access.resolve(item)) == nil { Text("文件不可访问，请重新添加").font(.caption2).foregroundStyle(.orange) }
                            }
                            Spacer(); Button("定位") { store.reveal(item) }
                        }.padding(9).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if store.items.isEmpty { Text("把文件拖到这里，或点击「添加文件」").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 180) }
                }
            }.background(targeted ? Color.accentColor.opacity(0.12) : .clear)
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
                    for provider in providers {
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, _ in
                            let url = (value as? URL) ?? (value as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                            if let url { Task { @MainActor in store.add([url]) } }
                        }
                    }
                    return !providers.isEmpty
                }
            OfficeFileDrag(title: "拖动发送所选 \(selection.count) 项", urls: { store.resolved(selection) }).frame(height: 36).opacity(selection.isEmpty ? 0.45 : 1)
            if let message = store.message { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }.onChange(of: store.items) { _, items in selection.formIntersection(Set(items.map(\.id))) }
    }
}

struct OfficeFileDrag: NSViewRepresentable {
    var title: String
    var urls: () -> [URL]
    func makeNSView(context: Context) -> OfficeDragView { OfficeDragView() }
    func updateNSView(_ view: OfficeDragView, context: Context) { view.title = title; view.urls = urls; view.needsDisplay = true }
}
final class OfficeDragView: NSView, NSDraggingSource {
    var title = ""
    var urls: () -> [URL] = { [] }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill(); NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        let text = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor])
        text.draw(at: NSPoint(x: 12, y: (bounds.height - text.size().height) / 2))
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let items = urls().enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(NSRect(x: point.x + CGFloat(index % 5) * 5, y: point.y, width: 32, height: 32), contents: NSWorkspace.shared.icon(forFile: url.path)); return item
        }
        guard !items.isEmpty else { return }
        beginDraggingSession(with: items, event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
