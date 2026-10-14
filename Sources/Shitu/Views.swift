import SwiftUI
import AppKit
import ShituCore

private let canvas = Color(red: 0.055, green: 0.07, blue: 0.09)
private let panel = Color(red: 0.09, green: 0.11, blue: 0.135)
private let mint = Color(red: 0.62, green: 0.92, blue: 0.77)

struct MainView: View {
    @ObservedObject var model: AppModel
    @StateObject private var loginItems = LoginItemController(service: NativeLoginItemService())
    @State private var page = "工作台"
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    if let error = model.error { errorBanner(error) }
                    if !model.permission { permissionBanner }
                    if page == "偏好设置" { settings }
                    else if page == "捕捉记录" { history }
                    else { workspace; history }
                }.padding(32)
            }
        }
        .background(canvas).foregroundStyle(Color.white.opacity(0.92))
        .preferredColorScheme(.dark)
        .frame(minWidth: 900, minHeight: 680)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshPermission(); loginItems.refresh() }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 10) {
                Image(systemName: "viewfinder").font(.system(size: 27, weight: .medium)).foregroundStyle(mint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SnapNest").font(.system(size: 23, weight: .semibold))
                    Text("SNAPNEST").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.7).foregroundStyle(.secondary)
                }
            }.padding(.top, 18)
            VStack(spacing: 8) {
                nav("工作台", icon: "square.grid.2x2")
                nav("捕捉记录", icon: "clock.arrow.circlepath")
                nav("偏好设置", icon: "slider.horizontal.3")
                Divider()
                Button { model.openLauncher?() } label: { Label("快捷启动", systemImage: "command").frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                Button { model.openTasks?() } label: { Label("待办与灵动岛", systemImage: "checklist").frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                Button { model.openSelectionSettings?() } label: { Label("划词添加", systemImage: "text.cursor").frame(maxWidth: .infinity, alignment: .leading).padding(12) }
            }.buttonStyle(.plain).disabled(model.busy)
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "command").font(.system(size: 20)).foregroundStyle(mint)
                Text("灵感，随手拾起。") .font(.system(size: 12, weight: .medium))
                Text("按下 ⌘ ⇧ X\n即刻框选屏幕区域")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(panel, in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 6) {
                Circle().fill(model.permission ? mint : .orange).frame(width: 5, height: 5)
                Text(model.permission ? "本地保存 · 准备就绪" : "等待屏幕录制授权")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.bottom, 12)
        }.padding(.horizontal, 20).frame(width: 180)
            .background(Color.white.opacity(0.025))
            .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.06)).frame(width: 1) }
    }
    private func nav(_ title: String, icon: String) -> some View {
        Button { page = title } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).frame(width: 18)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                if page == title { Circle().fill(mint).frame(width: 5, height: 5) }
            }.padding(12).foregroundStyle(page == title ? mint : Color.secondary)
                .background(page == title ? mint.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(page == "工作台" ? "CAPTURE YOUR MOMENT" : "YOUR PERSONAL SPACE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2.5).foregroundStyle(mint)
                Text(page == "工作台" ? "每一屏，都值得留住。" : page)
                    .font(.system(size: 28, weight: .semibold))
                Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.revealFolder() } label: {
                Image(systemName: "folder").font(.system(size: 17)).padding(12)
                    .background(panel, in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).help("打开保存文件夹")
        }
    }
    private var workspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { model.begin(.area) } label: {
                HStack(spacing: 22) {
                    Image(systemName: "viewfinder").font(.system(size: 42, weight: .ultraLight))
                        .frame(width: 76, height: 76).background(.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                    VStack(alignment: .leading, spacing: 7) {
                        Text("区域截图").font(.system(size: 23, weight: .semibold))
                        Text("拖动框选截图，单击取色，悬停查看像素。") .font(.system(size: 12)).opacity(0.65)
                        HStack(spacing: 5) { key("⌘"); key("⇧"); key("X") }.padding(.top, 5)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 22, weight: .light))
                }.padding(25).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(Color(red: 0.07, green: 0.18, blue: 0.14))
                    .background(LinearGradient(colors: [mint, Color(red: 0.77, green: 0.95, blue: 0.84)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).disabled(model.busy)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                modeCard(.repeatArea, icon: "arrow.clockwise", subtitle: "直接截取上次区域，无需框选", badge: "PNG").disabled(!model.canRepeatCapture)
                modeCard(.window, icon: "macwindow", subtitle: "悬停锁定窗口，单击截图", badge: "PNG")
                modeCard(.full, icon: "rectangle.inset.filled", subtitle: "完整记录当前显示器", badge: "PNG")
                modeCard(.long, icon: "arrow.down.to.line", subtitle: "滚动页面，自动拼接", badge: "长图")
                modeCard(.record, icon: "record.circle", subtitle: "记录屏幕上的每个瞬间", badge: "MP4")
                modeCard(.regionRecord, icon: "viewfinder.rectangular", subtitle: "只录制你关注的区域", badge: "MP4")
            }.disabled(model.busy)
            modeCard(.gif, icon: "livephoto", subtitle: "框选区域录制动图 · 10 fps · 最长 30 秒", badge: "GIF").disabled(model.busy)
            HStack(spacing: 8) {
                Image(systemName: "lock.shield").foregroundStyle(mint.opacity(0.7))
                Text("所有截图与录屏仅保存于本机")
                Spacer()
                Text("PNG / MP4 / GIF").font(.system(size: 9, design: .monospaced))
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 3)
            if model.busy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(model.status).font(.system(size: 12))
                    Spacer()
                    if model.isRecordingSession {
                        Button(model.phase == .paused ? "继续录制" : "暂停") { model.toggleRecordingPause() }.disabled(!model.canToggleRecording)
                    }
                    if model.isRecordingSession || model.phase == .scrolling {
                        Button(model.phase == .scrolling ? "结束并编辑" : "结束并保存") { model.stop() }.tint(mint)
                    }
                }.padding(12).background(panel, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    private func key(_ value: String) -> some View {
        Text(value).font(.system(size: 11, weight: .medium)).frame(width: 25, height: 24)
            .background(.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))
    }
    private func modeCard(_ mode: CaptureMode, icon: String, subtitle: String, badge: String) -> some View {
        Button { model.begin(mode) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon).font(.system(size: 23, weight: .light)).foregroundStyle(mint)
                    Spacer()
                    Text(badge).font(.system(size: 8, weight: .medium, design: .monospaced))
                        .tracking(1).foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.1)))
                }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode.rawValue).font(.system(size: 14, weight: .semibold))
                        Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(panel, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.055)))
        }.buttonStyle(.plain)
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("最近捕捉").font(.system(size: 14, weight: .semibold))
                Text(String(format: "%02d", model.items.count)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button("打开文件夹 ↗") { model.revealFolder() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(mint)
            }
            if model.items.isEmpty {
                HStack(spacing: 13) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 25, weight: .ultraLight)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("第一张精彩，等你捕捉").font(.system(size: 12))
                        Text("截图和录屏会出现在这里，点击即可预览。") .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(22).frame(maxWidth: .infinity).background(panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(page == "工作台" ? Array(model.items.prefix(3)) : model.items) { item in
                    HStack(spacing: 12) {
                        Button { model.preview(item) } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.06))
                                if !item.isVideo, let image = NSImage(contentsOf: item.url) {
                                    Image(nsImage: image).resizable().scaledToFit().padding(3)
                                } else { Image(systemName: "play.rectangle").foregroundStyle(mint) }
                            }.frame(width: 64, height: 44)
                        }.buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.kind).font(.system(size: 12, weight: .medium))
                            Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.url.pathExtension == "png" { Button { model.editExisting(item) } label: { Image(systemName: "pencil") }.help("编辑图片") }
                        if !item.isVideo { Button { model.copy(item) } label: { Image(systemName: "doc.on.doc") }.help("复制图片") }
                        Button { model.preview(item) } label: { Image(systemName: "arrow.up.right.square") }.help("预览")
                        Button { model.reveal(item) } label: { Image(systemName: "folder") }.help("在 Finder 中显示")
                    }.buttonStyle(.borderless).padding(10).background(panel, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("版本更新").font(.headline)
                    Text("当前版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("检查更新…") { model.checkForUpdates?() }
            }
            Text("关闭主窗口后，SnapNest会留在顶部菜单栏。点击菜单栏“SnapNest”可展开快捷面板。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            Text("启动设置").font(.headline)
            Toggle("登录时自动启动", isOn: Binding(get: { loginItems.isRegistered }, set: { enabled in
                Task { await loginItems.setEnabled(enabled) }
            })).disabled(loginItems.isChanging)
            Text("登录 Mac 后自动打开SnapNest，可随时使用 ⌘⇧X 截图。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if loginItems.status == .requiresApproval {
                HStack {
                    Text("已添加登录项，等待系统允许。").font(.system(size: 11)).foregroundStyle(.orange)
                    Button("打开登录项设置") { loginItems.openSettings() }
                }
            }
            if loginItems.status == .notFound {
                Text("请从完整的SnapNest.app 启动后设置登录项。")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            if let error = loginItems.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled)
            }
            Divider()
            Text("捕捉偏好").font(.headline)
            Toggle("截图后自动复制到剪贴板", isOn: $model.copyAfterCapture)
            Toggle("录屏时包含系统声音", isOn: $model.audio)
            Text("录制不包含麦克风。视频使用 H.264 / MP4，30 fps，最高 3840 × 2160。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text("GIF 无声音，10 fps，最长 30 秒，最长边 960 像素。截图后可在编辑器沿用原选区切换录屏、长截图或 GIF。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("保存位置").font(.system(size: 13, weight: .medium))
                    Text(model.saveFolder.path).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button("更改…") { model.chooseFolder() }
            }
            Divider()
            HStack {
                Text("全局快捷键")
                Spacer()
                Text("⌘ ⇧ X").font(.system(size: 14, design: .monospaced)).foregroundStyle(mint)
            }
            Text(model.shortcutAvailable ? "空闲时框选截图；长截图时完成拼接，录屏时结束并保存。" : "快捷键注册失败，可能被其他应用占用。请关闭冲突应用后重启SnapNest。")
                .font(.system(size: 11)).foregroundStyle(model.shortcutAvailable ? Color.secondary : Color.orange)
            Divider()
            HStack {
                Button("打开系统录屏权限设置") { model.openPrivacySettings() }
                Button(model.checkingPermission ? "检查中…" : "检查实际捕获权限") { model.checkPermission() }.disabled(model.checkingPermission)
                Button("定位当前应用") { model.revealApplication() }
            }
        }.toggleStyle(.switch).tint(mint).padding(24).background(panel, in: RoundedRectangle(cornerRadius: 16)).disabled(model.busy)
    }
    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "lock.rectangle").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.permissionNeedsRecovery ? "系统拒绝了当前版本的屏幕捕获" : "为当前版本的SnapNest开启屏幕录制权限")
                        .font(.system(size: 12, weight: .semibold))
                    Text("授权开关已打开仍报错时，请关闭再开启，然后退出并重新打开SnapNest。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack {
                Button(model.permissionNeedsRecovery ? "打开权限设置" : "请求授权") {
                    if model.permissionNeedsRecovery { model.openPrivacySettings() } else { model.requestPermission() }
                }
                Button(model.checkingPermission ? "检查中…" : "检查权限") { model.checkPermission() }
                    .disabled(model.checkingPermission || model.busy)
                Button("退出SnapNest") { model.quitForPermission() }.disabled(model.busy)
                Spacer()
                Button("定位当前应用") { model.revealApplication() }.buttonStyle(.plain).foregroundStyle(mint)
            }.font(.system(size: 11))
            Text("当前应用：\(model.applicationPath)").font(.system(size: 9)).foregroundStyle(.secondary).textSelection(.enabled)
        }.padding(16).background(mint.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
    private func errorBanner(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            Text(error).font(.system(size: 11)).textSelection(.enabled)
            Spacer()
            Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }.padding(14).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct CaptureHUD: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(model.phase == .recording ? Color.red : mint).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 4) {
                if model.startedAt != nil {
                    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                        let seconds = Int(model.recordedSeconds)
                        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).font(.system(size: 16, weight: .medium, design: .monospaced))
                    }
                } else { Text(model.phase == .scrolling ? "长截图 · \(model.pixelHeight) px" : "SnapNest").font(.system(size: 13, weight: .semibold)) }
                Text(model.status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if model.isRecordingSession {
                Button { model.toggleRecordingPause() } label: {
                    Image(systemName: model.phase == .paused ? "play.fill" : "pause.fill").font(.system(size: 13)).padding(11)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).disabled(!model.canToggleRecording).help(model.phase == .paused ? "继续录制" : "暂停录制")
            }
            Button { model.stop() } label: {
                Image(systemName: "stop.fill").font(.system(size: 13)).padding(11)
                    .background(Color.red.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain).disabled(model.phase == .stopping).help("结束并保存 · ⌘⇧X")
        }.padding(16).frame(width: 350).background(panel).foregroundStyle(.white).preferredColorScheme(.dark)
    }
}
