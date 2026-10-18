import AppKit
import SwiftUI
import ShituCore

struct WorkScene: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var targets: [OfficeReference] = []
}
@MainActor final class WorkSceneStore: ObservableObject {
    @Published private(set) var scenes: [WorkScene] = []
    @Published var selectedID: UUID?
    @Published var message: String?
    @Published private(set) var opening = false
    private let file: URL
    let access = OfficeAccess()
    private var loadFailed = false
    var current: WorkScene? { scenes.first { $0.id == selectedID } }
    init(root: URL = OfficeDisk.root) {
        file = root.appendingPathComponent("scenes.json")
        do { scenes = try OfficeDisk.load([WorkScene].self, from: file, empty: []); selectedID = scenes.first?.id }
        catch { loadFailed = true; message = "工作现场读取失败，原数据未覆盖：\(error.localizedDescription)" }
    }
    private func allowed() -> Bool {
        guard !loadFailed else { return false }
        return true
    }
    private func persist(_ next: [WorkScene]) -> Bool {
        do { try OfficeDisk.save(next, to: file); scenes = next; return true }
        catch { message = error.localizedDescription; return false }
    }
    func create(_ title: String) {
        guard allowed(), scenes.count < 50 else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { message = "请先填写现场名称。"; return }
        let scene = WorkScene(title: String(name.prefix(100)))
        if persist(scenes + [scene]) { selectedID = scene.id; message = nil }
    }
    func rename(_ title: String) {
        guard allowed(), let index = scenes.firstIndex(where: { $0.id == selectedID }) else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { return }
        var next = scenes; next[index].title = String(name.prefix(100)); _ = persist(next)
    }
    func remove() {
        guard allowed(), let scene = current else { return }
        if persist(scenes.filter { $0.id != scene.id }) { scene.targets.forEach { access.release($0.id) }; selectedID = scenes.first?.id }
    }
    func add(_ urls: [URL], to id: UUID? = nil) {
        guard allowed(), let index = scenes.firstIndex(where: { $0.id == (id ?? selectedID) }) else { return }
        var next = scenes; var errors: [String] = []
        for url in urls where !next[index].targets.contains(where: { $0.url == url }) {
            do {
                guard next[index].targets.count < 40 else { throw OfficeError.message("每个现场最多保存 40 个目标。") }
                next[index].targets.append(try OfficeReference(url: url))
            } catch { errors.append(error.localizedDescription) }
        }
        if persist(next) { message = errors.isEmpty ? nil : errors.joined(separator: "\n") }
    }
    func captureRunningApps() {
        let urls = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }.compactMap(\.bundleURL)
        add(urls); if message == nil { message = "已添加正在运行的应用。文件夹和网页请手动加入；不会恢复窗口位置或浏览器标签。" }
    }
    func removeTarget(_ id: UUID) {
        guard allowed(), let index = scenes.firstIndex(where: { $0.id == selectedID }) else { return }
        var next = scenes; next[index].targets.removeAll { $0.id == id }
        if persist(next) { access.release(id) }
    }
    func open() {
        guard allowed(), !opening, let scene = current, !scene.targets.isEmpty else { return }
        opening = true; message = "正在打开“\(scene.title)”…"
        // Snapshot avoids a changing selection redirecting an in-progress launch.
        Task {
            var failures: [String] = []; var count = 0
            for reference in scene.targets {
                do {
                    let url = try access.resolve(reference)
                    if url.isFileURL && url.pathExtension.lowercased() == "app" {
                        let config = NSWorkspace.OpenConfiguration(); config.activates = false
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                            }
                        }
                    } else if !NSWorkspace.shared.open(url) { throw OfficeError.message("无法打开 \(reference.title)") }
                    count += 1
                } catch { failures.append("\(reference.title)：\(error.localizedDescription)") }
            }
            opening = false
            message = "已打开 \(count)/\(scene.targets.count) 项。" + (failures.isEmpty ? "" : "\n" + failures.joined(separator: "\n"))
        }
    }
}

struct WorkScenesWorkspace: View {
    @ObservedObject var store: WorkSceneStore
    @State private var title = ""
    @State private var web = ""
    @State private var confirmDelete = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("工作现场").font(.title3.bold()); Spacer(); Text("应用 · 文件夹 · 网页").font(.caption).foregroundStyle(.secondary) }
            HStack {
                TextField("现场名称，例如：周报整理", text: $title)
                Button("新建") { store.create(title) }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("重命名") { store.rename(title) }.disabled(store.current == nil || title.isEmpty)
            }
            if !store.scenes.isEmpty {
                HStack {
                    Picker("现场", selection: $store.selectedID) { ForEach(store.scenes) { Text($0.title).tag(Optional($0.id)) } }.labelsHidden()
                    Button(store.opening ? "正在打开…" : "一键打开") { store.open() }.buttonStyle(.borderedProminent).disabled(store.opening || store.current?.targets.isEmpty != false)
                    Button("删除") { confirmDelete = true }.disabled(store.current == nil || store.opening)
                }
                HStack {
                    Button("加入当前应用") { store.captureRunningApps() }
                    Button("添加应用 / 文件夹") { let id = store.selectedID; OfficeDisk.pick { store.add($0, to: id) } }
                }
                HStack {
                    TextField("https:// 网页地址", text: $web)
                    Button("添加网页") {
                        if let url = LauncherSearch.webURL(web) { store.add([url]); web = "" }
                        else { store.message = "请输入有效的 HTTP(S) 网页地址，不含用户名或密码。" }
                    }.disabled(web.isEmpty)
                }
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(store.current?.targets ?? []) { item in
                            HStack {
                                Image(systemName: item.url.isFileURL ? "folder" : "globe")
                                VStack(alignment: .leading) { Text(item.title); Text(item.url.isFileURL ? item.url.path : item.url.absoluteString).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                Spacer(); Button("移除") { store.removeTarget(item.id) }
                            }.padding(8).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            } else { Text("创建一个现场，把这个项目常用的应用、目录和网页放在一起。").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            if let message = store.message { Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(5).textSelection(.enabled) }
            Text("只打开已保存的目标，不关闭其他应用，也不恢复未保存文档和窗口布局。").font(.caption2).foregroundStyle(.secondary)
        }.onChange(of: store.selectedID) { _, _ in title = store.current?.title ?? "" }
            .confirmationDialog("删除这个工作现场？原文件和应用不会被删除。", isPresented: $confirmDelete) { Button("删除现场", role: .destructive) { store.remove() } }
    }
}
