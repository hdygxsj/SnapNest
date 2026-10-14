// SnapNest 2.0 private additions. Local development only.
import AppKit
import SwiftUI
import ShituCore

private struct LauncherItem: Identifiable, Codable, Equatable, Sendable {
    let url: URL
    let title: String
    var id: String { url.absoluteString }
    var isWeb: Bool { ["https", "http"].contains(url.scheme?.lowercased() ?? "") }
}

@MainActor
final class QuickLauncherController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = QuickLauncherController()
    @Published fileprivate var query = ""
    @Published fileprivate var applications: [LauncherItem] = []
    @Published fileprivate var favorites: [LauncherItem] = []
    @Published fileprivate var selectedID: String?
    @Published fileprivate var error: String?
    @Published fileprivate var scanning = false
    @Published fileprivate var addingURL = false
    @Published fileprivate var focusGeneration = 0
    private var panel: LauncherPanel?
    private var keyMonitor: Any?
    private var launchGeneration = 0
    private let favoritesKey = "snapnest.v2.launcher.favorites"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: favoritesKey) {
            do {
                favorites = try JSONDecoder().decode([LauncherItem].self, from: data).filter {
                    $0.url.isFileURL || LauncherSearch.webURL($0.url.absoluteString) != nil
                }
            } catch { self.error = "无法读取收藏：\(error.localizedDescription)" }
        }
    }

    fileprivate var results: [LauncherItem] {
        let favoriteIDs = Set(favorites.map(\.id))
        return (favorites + applications.filter { !favoriteIDs.contains($0.id) })
            .filter { LauncherSearch.matches(title: $0.title, query: query) }
    }

    func show() {
        launchGeneration += 1
        if panel == nil {
            let window = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                                       styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "SnapNest · 快速启动"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.hidesOnDeactivate = false
            window.isMovableByWindowBackground = true
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.delegate = self
            window.contentView = NSHostingView(rootView: QuickLauncherView(model: self))
            panel = window
        }
        query = ""
        selectedID = results.first?.id
        panel?.center()
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        focusGeneration += 1
        installKeys()
        scanApplications()
    }

    func hide() {
        launchGeneration += 1
        panel?.orderOut(nil)
        removeKeys()
    }

    func windowWillClose(_ notification: Notification) {
        launchGeneration += 1
        removeKeys()
    }

    private func installKeys() {
        removeKeys()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, self.panel?.attachedSheet == nil, !self.addingURL else { return event }
            // Candidate navigation, commit and cancellation belong to the input method.
            if let editor = self.panel?.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            switch event.keyCode {
            case 53: self.hide(); return nil
            case 125: self.moveSelection(1); return nil
            case 126: self.moveSelection(-1); return nil
            case 36, 76: self.openSelection(); return nil
            default: return event
            }
        }
    }

    private func removeKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    fileprivate func resetSelection() { selectedID = results.first?.id }

    private func moveSelection(_ delta: Int) {
        let items = results
        guard !items.isEmpty else { selectedID = nil; return }
        let current = items.firstIndex { $0.id == selectedID } ?? 0
        selectedID = items[min(max(current + delta, 0), items.count - 1)].id
    }

    fileprivate func openSelection() {
        guard let item = results.first(where: { $0.id == selectedID }) ?? results.first else { return }
        open(item)
    }

    fileprivate func open(_ item: LauncherItem) {
        launchGeneration += 1
        let generation = launchGeneration
        error = nil
        if item.url.isFileURL && !FileManager.default.fileExists(atPath: item.url.path) {
            error = "目标已移动或删除：\(item.title)"; return
        }
        if item.url.pathExtension.lowercased() == "app" && item.url.isFileURL {
            NSWorkspace.shared.openApplication(at: item.url, configuration: .init()) { [weak self] _, failure in
                Task { @MainActor in
                    guard let self, self.launchGeneration == generation else { return }
                    if let failure { self.error = "无法打开：\(failure.localizedDescription)" }
                    else { self.hide() }
                }
            }
        } else if NSWorkspace.shared.open(item.url) { hide() }
        else { error = "无法打开“\(item.title)”，请检查目标或默认应用。" }
    }

    fileprivate func toggleFavorite(_ item: LauncherItem) {
        if favorites.contains(where: { $0.id == item.id }) { favorites.removeAll { $0.id == item.id } }
        else { favorites.append(item) }
        persist()
        if !results.contains(where: { $0.id == selectedID }) { resetSelection() }
    }

    private func persist() {
        do { UserDefaults.standard.set(try JSONEncoder().encode(favorites), forKey: favoritesKey) }
        catch { self.error = "保存收藏失败：\(error.localizedDescription)" }
    }

    fileprivate func addFileFavorite() {
        guard let panel else { return }
        let picker = NSOpenPanel()
        picker.title = "收藏应用或文件夹"
        picker.canChooseDirectories = true
        picker.canChooseFiles = true
        picker.allowsMultipleSelection = false
        picker.beginSheetModal(for: panel) { [weak self] response in
            guard response == .OK, let url = picker.url, let self else { return }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                self.error = "请选择应用（.app）或文件夹。"; return
            }
            let item = LauncherItem(url: url, title: FileManager.default.displayName(atPath: url.path))
            if !self.favorites.contains(where: { $0.id == item.id }) { self.favorites.append(item); self.persist() }
            self.selectedID = item.id
        }
    }

    fileprivate func addWebFavorite(title: String, address: String) -> Bool {
        guard let url = LauncherSearch.webURL(address) else { return false }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = LauncherItem(url: url, title: name.isEmpty ? (url.host ?? address) : name)
        if !favorites.contains(where: { $0.id == item.id }) { favorites.append(item); persist() }
        selectedID = item.id
        return true
    }

    private func scanApplications() {
        guard !scanning else { return }
        scanning = true
        Task { [weak self] in
            let items = await Task.detached(priority: .userInitiated) {
                scanLauncherApplications()
            }.value
            guard let self else { return }
            self.applications = items
            self.scanning = false
            if !self.results.contains(where: { $0.id == self.selectedID }) { self.resetSelection() }
        }
    }
}

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct QuickLauncherView: View {
    @ObservedObject var model: QuickLauncherController
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("搜索应用与收藏 · 支持拼音", text: $model.query)
                    .textFieldStyle(.plain).font(.title3).focused($searchFocused)
                Text("⌘ ⇧ Space").font(.caption).foregroundStyle(.secondary)
            }.padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Text("快速启动").font(.headline)
                if model.scanning { ProgressView().controlSize(.small) }
                Spacer()
                Button("收藏应用/文件夹", action: model.addFileFavorite)
                Button("收藏网址") { model.addingURL = true }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(model.results) { item in
                            HStack(spacing: 10) {
                                Image(systemName: item.isWeb ? "globe" : (item.url.pathExtension.lowercased() == "app" ? "app" : "folder"))
                                    .frame(width: 26).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).lineLimit(1)
                                    Text(item.isWeb ? item.url.absoluteString : item.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Button { model.toggleFavorite(item) } label: {
                                    Image(systemName: model.favorites.contains(where: { $0.id == item.id }) ? "star.fill" : "star")
                                }.buttonStyle(.borderless).help("添加或移除收藏")
                            }.padding(9)
                                .background(model.selectedID == item.id ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { model.open(item) }
                                .onTapGesture { model.selectedID = item.id }
                                .id(item.id)
                        }
                        if model.results.isEmpty { Text(model.scanning ? "正在扫描已安装应用…" : "没有匹配的应用或收藏").foregroundStyle(.secondary).padding(30) }
                    }
                }.onChange(of: model.selectedID) { _, id in if let id { proxy.scrollTo(id) } }
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                Text("↑ ↓ 选择    ↩ 打开    Esc 关闭").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("打开", action: model.openSelection).disabled(model.results.isEmpty)
            }
        }.padding(18).padding(.top, 20).frame(width: 560, height: 470)
            .onAppear { searchFocused = true }
            .onChange(of: model.focusGeneration) { _, _ in searchFocused = true }
            .onChange(of: model.query) { _, _ in model.resetSelection() }
            .sheet(isPresented: $model.addingURL) { LauncherURLSheet(model: model) }
    }
}

private struct LauncherURLSheet: View {
    @ObservedObject var model: QuickLauncherController
    @State private var title = ""
    @State private var address = ""
    @State private var invalid = false
    @FocusState private var addressFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("收藏网址").font(.headline)
            TextField("https://example.com", text: $address).focused($addressFocused)
            TextField("名称（可选）", text: $title)
            if invalid { Text("请输入有效的 http:// 或 https:// 网址（不含用户名或密码）。").font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { model.addingURL = false }.keyboardShortcut(.cancelAction)
                Button("收藏") {
                    if model.addWebFavorite(title: title, address: address) { model.addingURL = false }
                    else { invalid = true }
                }.keyboardShortcut(.defaultAction)
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 430)
            .onAppear { addressFocused = true }
    }
}

private func scanLauncherApplications() -> [LauncherItem] {
                let manager = FileManager.default
                let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
                             manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
                var found: [String: LauncherItem] = [:]
                for root in roots {
                    guard let walker = manager.enumerator(at: root, includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                    for case let url as URL in walker where url.pathExtension.lowercased() == "app" {
                        walker.skipDescendants()
                        let resolved = url.resolvingSymlinksInPath()
                        found[resolved.path] = LauncherItem(url: resolved, title: manager.displayName(atPath: resolved.path)
                            .replacingOccurrences(of: ".app", with: "", options: [.anchored, .backwards]))
                    }
                }
                return found.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
}
