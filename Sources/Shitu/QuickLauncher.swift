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
    @Published var shortcutAvailable = false
    @Published fileprivate var editingShortcut: LauncherItem?
    let appShortcuts = AppShortcutStore()
    var canLaunchApplication: (() -> Bool)?
    @Published fileprivate var addingURL = false
    @Published fileprivate var focusGeneration = 0
    private weak var panel: NSPanel?
    var presentationRequested: (() -> Void)?
    var dismissalRequested: (() -> Void)?
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

    func startApplicationShortcuts() {
        appShortcuts.launch = { [weak self] binding in
            guard let self, self.canLaunchApplication?() != false else { return }
            let item = LauncherItem(url: binding.url, title: binding.title)
            self.open(item, fromShortcut: true)
        }
        appShortcuts.start()
    }

    fileprivate var results: [LauncherItem] {
        let bound = appShortcuts.bindings.map { LauncherItem(url: $0.url, title: $0.title) }
        var seen = Set<String>()
        return (favorites + bound + applications).filter { seen.insert($0.id).inserted }
            .filter { LauncherSearch.matches(title: $0.title, query: query) }
    }

    static func appearancePreview() -> QuickLauncherController {
        let model = QuickLauncherController()
        model.applications = [
            LauncherItem(url: URL(fileURLWithPath: "/System/Applications/Notes.app"), title: "备忘录"),
            LauncherItem(url: URL(fileURLWithPath: "/System/Applications/Calendar.app"), title: "日历"),
            LauncherItem(url: URL(fileURLWithPath: "/System/Applications/Mail.app"), title: "邮件"),
            LauncherItem(url: URL(fileURLWithPath: "/System/Applications/Reminders.app"), title: "提醒事项")
        ]
        model.favorites = Array(model.applications.prefix(3))
        model.selectedID = model.applications.first?.id
        return model
    }

    func show() { presentationRequested?() }

    func activate(in window: NSPanel) {
        launchGeneration += 1
        panel = window
        selectedID = results.first?.id
        focusGeneration += 1
        installKeys()
        scanApplications()
    }
    func deactivate() {
        launchGeneration += 1
        removeKeys()
    }
    func hide() { deactivate(); dismissalRequested?() }

    func windowWillClose(_ notification: Notification) {
        launchGeneration += 1
        removeKeys()
    }

    private func installKeys() {
        removeKeys()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, self.panel?.attachedSheet == nil, !self.addingURL, self.editingShortcut == nil else { return event }
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

    fileprivate func open(_ item: LauncherItem, fromShortcut: Bool = false) {
        launchGeneration += 1
        let generation = launchGeneration
        error = nil
        if item.url.isFileURL && !FileManager.default.fileExists(atPath: item.url.path) {
            error = "目标已移动或删除：\(item.title)"; if fromShortcut { show() }; return
        }
        if item.url.pathExtension.lowercased() == "app" && item.url.isFileURL {
            NSWorkspace.shared.openApplication(at: item.url, configuration: .init()) { [weak self] _, failure in
                Task { @MainActor in
                    guard let self, self.launchGeneration == generation else { return }
                    if let failure { self.error = "无法打开：\(failure.localizedDescription)"; if fromShortcut { self.show() } }
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

struct QuickLauncherView: View {
    @ObservedObject var model: QuickLauncherController
    @ObservedObject private var shortcuts: AppShortcutStore
    init(model: QuickLauncherController) { self.model = model; self.shortcuts = model.appShortcuts }
    @Environment(\.colorScheme) private var scheme
    @FocusState private var searchFocused: Bool
    var body: some View {
        Group {
            if let item = model.editingShortcut {
                AppShortcutEditor(store: shortcuts, url: item.url, title: item.title) { model.editingShortcut = nil; searchFocused = true }
            }
            else if model.addingURL { LauncherURLSheet(model: model) }
            else { launcherContent }
        }
    }
    @State private var hoveredID: String?
    private var accent: Color { WorkspaceTheme.accent(scheme) }
    private var searching: Bool { !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var launcherContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("快捷启动").font(.system(size: 23, weight: .semibold))
                    Text("应用、文件夹与网址，随手打开").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("收藏应用或文件夹", action: model.addFileFavorite)
                    Button("收藏网址") { model.addingURL = true }
                } label: {
                    Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                        .frame(width: 32, height: 32)
                }.menuStyle(.borderlessButton).fixedSize().help("添加收藏")
                    .accessibilityLabel("添加收藏")
            }
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(accent)
                TextField("搜索应用或收藏", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 16)).focused($searchFocused)
                    .accessibilityLabel("搜索应用或收藏，支持拼音")
                if !model.query.isEmpty {
                    Button { model.query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .help("清空搜索").accessibilityLabel("清空搜索")
                }
                Text("⌘ ⇧ Space").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).frame(height: 52)
                .background(scheme == .dark ? Color.white.opacity(0.045) : Color.white, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(searchFocused ? accent.opacity(0.45) : Color.primary.opacity(0.09), lineWidth: 1))
            if !searching && !model.favorites.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("收藏", count: model.favorites.count)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.favorites) { item in
                                Button { model.open(item) } label: {
                                    VStack(spacing: 9) {
                                        appIcon(item, size: 36)
                                        Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    }.frame(width: 94, height: 86)
                                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                                }.help("打开 " + item.title)
                                    .contextMenu {
                                        if item.url.isFileURL && item.url.pathExtension.lowercased() == "app" {
                                            Button("设置快捷键") { model.editingShortcut = item }
                                        }
                                        Button("移除收藏") { model.toggleFavorite(item) }
                                    }
                            }
                        }
                    }.frame(height: 88)
                }
            }
            VStack(spacing: 8) {
                sectionLabel(searching ? "搜索结果" : "全部应用与收藏", count: model.results.count)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(model.results) { item in
                                resultRow(item).id(item.id)
                            }
                            if model.results.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: model.scanning ? "app.dashed" : "magnifyingglass").font(.system(size: 28)).foregroundStyle(.tertiary)
                                    Text(model.scanning ? "正在查找已安装应用…" : "没有找到匹配项").font(.system(size: 14, weight: .medium))
                                    Text("支持应用名称和拼音搜索").font(.system(size: 12)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity).padding(.vertical, 36)
                            }
                        }
                    }.onChange(of: model.selectedID) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }.frame(maxHeight: .infinity)
            if let error = shortcuts.error { Text(error).font(.caption).foregroundStyle(.red) }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack(spacing: 14) {
                Label("选择", systemImage: "arrow.up.arrow.down")
                Label("打开", systemImage: "return")
                Spacer()
                Text("双击列表打开 · 点击键盘设置快捷键")
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }.buttonStyle(.plain).padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear { searchFocused = true }
            .onChange(of: model.focusGeneration) { _, _ in searchFocused = true }
            .onChange(of: model.query) { _, _ in model.resetSelection() }
    }
    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack(spacing: 7) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text("\(count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            Spacer()
            if model.scanning { ProgressView().controlSize(.mini) }
        }.foregroundStyle(.secondary)
    }
    private func appIcon(_ item: LauncherItem, size: CGFloat) -> some View {
        Group {
            if item.url.isFileURL { Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().scaledToFit() }
            else { Image(systemName: "globe").resizable().scaledToFit().padding(5).foregroundStyle(accent) }
        }.frame(width: size, height: size)
    }
    private func resultRow(_ item: LauncherItem) -> some View {
        let selected = model.selectedID == item.id
        let active = selected || hoveredID == item.id
        let binding = shortcuts.bindings.first(where: { $0.id == item.id })
        let favorite = model.favorites.contains(where: { $0.id == item.id })
        return HStack(spacing: 12) {
            appIcon(item, size: 32)
            Text(item.title).font(.system(size: 13, weight: selected ? .medium : .regular)).lineLimit(1)
            if item.isWeb { Text(item.url.host ?? "").font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1) }
            Spacer(minLength: 12)
            if item.url.isFileURL && item.url.pathExtension.lowercased() == "app" {
                Button { model.editingShortcut = item } label: {
                    Group {
                        if let binding { Text(binding.chord.label).font(.system(size: 11, design: .monospaced)) }
                        else { Image(systemName: "keyboard").font(.system(size: 14)) }
                    }.padding(.horizontal, 9).frame(height: 26)
                        .foregroundStyle(active ? accent : .secondary)
                        .background(Color.primary.opacity(active ? 0.055 : 0.025), in: RoundedRectangle(cornerRadius: 6))
                }.help(shortcuts.failures[item.id] ?? "设置此应用的全局启动快捷键")
                    .accessibilityLabel("设置 " + item.title + " 的快捷键")
                    .opacity(binding != nil || active ? 1 : 0.3)
                if shortcuts.failures[item.id] != nil { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            Button { model.toggleFavorite(item) } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .foregroundStyle(favorite ? accent : Color.secondary.opacity(active ? 1 : 0.35))
                    .frame(width: 26, height: 28)
            }.help(favorite ? "移除收藏" : "添加收藏")
                .accessibilityLabel((favorite ? "移除收藏 " : "收藏 ") + item.title)
        }.padding(.horizontal, 12).frame(height: 50)
            .background(selected ? accent.opacity(scheme == .dark ? 0.19 : 0.08) : Color.primary.opacity(hoveredID == item.id ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? accent.opacity(0.15) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.open(item) }
            .onTapGesture { model.selectedID = item.id }
            .onHover { hovering in hoveredID = hovering ? item.id : nil }
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
