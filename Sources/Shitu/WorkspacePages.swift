import AppKit
import SwiftUI
import ShituCore

struct CaptureWorkspace: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("截图与录制").font(.title2.bold()); Spacer(); Text("⌘⇧X").foregroundStyle(.secondary) }
                Text(model.status).font(.callout).foregroundStyle(.secondary)
                if let error = model.error { Text(error).foregroundStyle(.red).font(.caption) }
                if !model.permission {
                    Text("截图与录屏需要屏幕录制权限").font(.callout)
                    HStack {
                        Button("打开权限设置") { model.openPrivacySettings() }
                        Button("检查权限") { model.refreshPermission() }
                    }.buttonStyle(.bordered)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        Button { model.begin(mode) } label: {
                            Text(mode.rawValue).frame(maxWidth: .infinity).padding(14)
                                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                        }.disabled(model.busy || (mode == .repeatArea && !model.canRepeatCapture))
                    }
                }
                HStack { Text("最近捕捉").font(.headline); Spacer(); Button("打开文件夹") { model.revealFolder() } }
                ForEach(model.items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.kind)
                            Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.url.pathExtension == "png" { Button("编辑") { model.editExisting(item) } }
                        if !item.isVideo { Button("复制") { model.copy(item) } }
                        Button("预览") { model.preview(item) }
                    }.font(.callout).padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
                if model.items.isEmpty { Text("截图和录屏会保存在这里").foregroundStyle(.secondary) }
            }.padding(22)
        }.onAppear { model.refreshPermission() }
    }
}

struct WorkspaceSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var selectedText: SelectedTextCapture
    @ObservedObject private var launcher = QuickLauncherController.shared
    @StateObject private var login = LoginItemController(service: NativeLoginItemService())
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("设置").font(.title2.bold())
                Text("外观随 macOS 自动切换深浅模式").foregroundStyle(.secondary).font(.callout)
                VStack(alignment: .leading, spacing: 8) {
                    Text("全局快捷键").font(.headline)
                    HStack { Text("快捷启动"); Spacer(); Text("⌘ ⇧ 空格") }
                    HStack { Text("截图 / 结束录制"); Spacer(); Text("⌘ ⇧ X") }
                    HStack { Text("选中文字添加待办"); Spacer(); Text("⌘ ⇧ T") }
                    if !launcher.shortcutAvailable { Text("快捷启动快捷键注册失败，可能被其他应用占用。关闭冲突应用后重新启动 SnapNest。").font(.caption).foregroundStyle(.orange) }
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
                Text("SnapNest \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0") · 私有版").font(.headline)
                Text("尚未配置私有更新渠道，更新请使用开发者提供的安装包。").font(.caption).foregroundStyle(.secondary)
            }.padding(22)
        }.onAppear { selectedText.refreshAccess(); login.refresh() }
    }
}
