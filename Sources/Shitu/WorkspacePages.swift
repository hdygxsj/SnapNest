import AppKit
import SwiftUI
import ShituCore
import QuickLookThumbnailing

struct CaptureWorkspace: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var showAll = false
    @ObservedObject private var quality = CaptureQualityPreferences.shared
    private var dark: Bool { scheme == .dark }
    private var accent: Color { WorkspaceTheme.accent(scheme) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 22) {
                        Image(systemName: "viewfinder").font(.system(size: 62, weight: .light)).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text("区域截图").font(.system(size: 27, weight: .bold)); Keycap(text: "⌘ ⇧ X") }
                            Text("拖动选择区域，松开即可截取").font(.system(size: 14)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(quality.prefersHD ? "高清画质" : "标准画质") { model.showQualitySettings?() }
                            .font(.caption).foregroundStyle(accent)
                    }.padding(.vertical, 8)
                    HStack(spacing: 12) {
                        captureButton(.area, "区域截图", "viewfinder", large: true)
                        captureButton(.window, "窗口截图", "macwindow", large: true)
                        captureButton(.full, "全屏截图", "rectangle.dashed", large: true)
                        captureButton(.regionRecord, "区域录屏", "video", large: true)
                    }.disabled(model.busy)
                HStack(spacing: 18) {
                        Button { model.begin(.long) } label: { Label("长截图", systemImage: "rectangle.portrait") }
                        Button { model.begin(.gif) } label: { Label("录制 GIF", systemImage: "sparkles.tv") }
                    Button { model.begin(.repeatArea) } label: { Label("再次截取", systemImage: "arrow.counterclockwise") }.disabled(!model.canRepeatCapture)
                    Button { model.begin(.record) } label: { Label("全屏录制", systemImage: "record.circle") }
                    Spacer()
                }.font(.system(size: 12)).foregroundStyle(.secondary).disabled(model.busy)
                if !model.permission {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield").foregroundStyle(accent)
                        Text("首次使用需开启屏幕录制权限").font(.caption)
                        Spacer()
                        Button("前往设置") { model.openPrivacySettings() }
                        Button("刷新") { model.refreshPermission() }
                    }.font(.caption).padding(10).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                }
                if let error = model.error { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
                Divider().opacity(0.6)
                HStack {
                    Text("最近捕捉").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button(showAll ? "收起" : "查看全部") { showAll.toggle() }.font(.caption).foregroundStyle(.secondary)
                    Button { model.revealFolder() } label: { Image(systemName: "folder") }.help("打开保存文件夹")
                }
                if model.items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 28)).foregroundStyle(.tertiary)
                        Text("你的下一次灵感，从这里开始").font(.callout).foregroundStyle(.secondary)
                        Text("截图与录制会显示在这里").font(.caption).foregroundStyle(.tertiary)
                    }.frame(maxWidth: .infinity).frame(height: 155)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 16) {
                        ForEach(showAll ? model.items : Array(model.items.prefix(3))) { item in captureCard(item, height: 112) }
                    }
                }
            }.padding(24)
        }.onAppear { model.refreshPermission() }
    }
    private func captureButton(_ mode: CaptureMode, _ title: String, _ icon: String, large: Bool = false) -> some View {
        Button { model.begin(mode) } label: {
            (large ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 6))) {
                Image(systemName: icon).font(.system(size: large ? 26 : 17, weight: .regular))
                Text(title).font(.system(size: large ? 13 : 12, weight: .medium)).fixedSize()
            }.frame(maxWidth: .infinity).frame(height: large ? 80 : 48)
                .foregroundStyle(mode == .area ? accent : Color.primary)
                .background(mode == .area ? accent.opacity(dark ? 0.22 : 0.08) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(mode == .area ? accent.opacity(0.5) : .clear, lineWidth: 1))
        }
    }
    private func captureCard(_ item: CaptureItem, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { model.preview(item) } label: {
                CaptureThumbnail(url: item.url).frame(height: height).frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            }.help("预览\(item.kind)")
            HStack(spacing: 8) {
                Text(item.kind).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if item.url.pathExtension == "png" { Button { model.editExisting(item) } label: { Image(systemName: "pencil.tip") }.help("编辑") }
                if !item.isVideo { Button { model.copy(item) } label: { Image(systemName: "doc.on.doc") }.help("复制") }
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

struct CaptureThumbnail: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image { Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped() }
                else { Image(systemName: "photo").font(.title).foregroundStyle(.tertiary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }.task(id: url) {
            image = nil
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 700, height: 440), scale: 1, representationTypes: .thumbnail)
            let result = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            if !Task.isCancelled { image = result?.nsImage }
        }
    }
}

struct WorkspaceSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var selectedText: SelectedTextCapture
    @ObservedObject private var launcher = QuickLauncherController.shared
    @ObservedObject private var theme = WorkspaceTheme.shared
    @StateObject private var login = LoginItemController(service: NativeLoginItemService())
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("设置").font(.title2.bold())
                CaptureQualitySettings(store: CaptureQualityPreferences.shared)
                VStack(alignment: .leading, spacing: 12) {
                    Label("外观", systemImage: "circle.lefthalf.filled").font(.headline)
                    Picker("主题", selection: $theme.selection) {
                        ForEach(WorkspaceAppearance.allCases) { appearance in Text(appearance.title).tag(appearance) }
                    }.pickerStyle(.segmented)
                    Text("布局保持一致，深浅外观随心切换").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("全局快捷键").font(.headline)
                    HStack { Text("快捷启动"); Spacer(); Text("⌘ ⇧ 空格") }
                    HStack { Text("截图 / 结束录制"); Spacer(); Text("⌘ ⇧ X") }
                    HStack { Text("选中文字添加待办"); Spacer(); Text("⌘ ⇧ T") }
                    if !launcher.shortcutAvailable { Text("快捷启动快捷键注册失败，可能被其他应用占用。关闭冲突应用后重新启动 轻屿。").font(.caption).foregroundStyle(.orange) }
                }.font(.callout)
                Divider()
                Toggle("登录时自动启动", isOn: Binding(get: { login.isRegistered }, set: { enabled in
                    Task { await login.setEnabled(enabled) }
                })).disabled(login.isChanging)
                if login.status == .requiresApproval { Button("打开登录项设置") { login.openSettings() } }
                if login.status == .notFound { Text("请从完整应用包启动后设置登录项。").font(.caption).foregroundStyle(.orange) }
                if let error = login.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
                Toggle("截图自动复制到剪贴板", isOn: $model.copyAfterCapture)
                Toggle("录屏包含系统声音", isOn: $model.audio)
                HStack { Text("保存位置"); Spacer(); Button("选择文件夹") { model.chooseFolder() } }.buttonStyle(.bordered)
                Text(model.saveFolder.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Divider()
                SelectedTextSettings(capture: selectedText)
                Divider()
                Text("轻屿 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0") · 私有版").font(.headline)
                Text("尚未配置私有更新渠道，更新请使用开发者提供的安装包。").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }.onAppear { selectedText.refreshAccess(); login.refresh() }
    }
}
