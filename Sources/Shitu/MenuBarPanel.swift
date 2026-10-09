import AppKit
import SwiftUI

/// Closing the workspace hides it; the status item and global shortcut stay alive.
@MainActor
final class ResidentWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }
}

struct MenuBarPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateController
    var capture: (CaptureMode) -> Void
    var open: () -> Void
    var checkUpdates: () -> Void
    var quit: () -> Void
    var stop: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "viewfinder").foregroundStyle(.mint)
                Text("拾图 SnapNest").font(.headline)
                Spacer()
                Text("⌘⇧X").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text(model.busy ? model.status : "已在菜单栏运行，随时可以截图")
                .font(.caption).foregroundStyle(.secondary)
            if model.phase == .recording || model.phase == .scrolling || model.phase == .capturing {
                Button("结束捕捉") { stop() }.buttonStyle(.borderedProminent).tint(.mint)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach([CaptureMode.area, .full, .regionRecord, .gif, .long, .record], id: \.self) { mode in
                    Button(mode.rawValue) { capture(mode) }.frame(maxWidth: .infinity)
                        .buttonStyle(.bordered).disabled(model.busy)
                }
            }
            Divider()
            HStack {
                Button("打开主界面", action: open)
                Spacer()
                Button(updates.asset == nil ? "检查更新" : "发现新版本 ↑", action: checkUpdates).disabled(model.busy)
            }
            HStack {
                Text("关闭主窗口不会退出").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("退出拾图", action: quit).disabled(model.busy)
            }
        }.padding(18).frame(width: 330)
    }
}
