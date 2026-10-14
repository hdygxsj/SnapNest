// SnapNest 2.0 private additions.
import AppKit
import SwiftUI
import Combine

enum IslandPage { case launcher, tasks, capture, office, settings }

@MainActor final class TaskIslandController: ObservableObject {
    @Published var expanded = false
    @Published var page: IslandPage = .launcher
    let captureContent: AnyView?
    let settingsContent: AnyView?
    let officeContent: AnyView?
    var modalActivity = false
    private let model: TaskCenterModel
    private let launcher: QuickLauncherController
    private let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var suppressed = false
    private var subscriptions: Set<AnyCancellable> = []
    private var screenObserver: NSObjectProtocol?
    private var outsideMonitor: Any?
    private var escapeMonitor: Any?
    init(model: TaskCenterModel, launcher: QuickLauncherController, captureContent: AnyView? = nil, settingsContent: AnyView? = nil, officeContent: AnyView? = nil, preview: Bool = false) {
        self.model = model; self.launcher = launcher
        self.captureContent = captureContent; self.settingsContent = settingsContent; self.officeContent = officeContent
        if preview { return }
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: UnifiedIslandView(controller: self, model: model, launcher: launcher))
        launcher.presentationRequested = { [weak self] in self?.expand(.launcher) }
        launcher.dismissalRequested = { [weak self] in self?.collapse() }
        model.objectWillChange.sink { [weak self] _ in Task { @MainActor in self?.update() } }.store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel.attachedSheet == nil, !self.modalActivity else { return }
                self.collapse()
            }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.type != .keyDown {
                if let self, event.window !== self.panel, self.panel.attachedSheet == nil, !self.modalActivity { self.collapse() }
                return event
            }
            guard let self, event.window === self.panel, event.keyCode == 53,
                  self.panel.attachedSheet == nil, !self.modalActivity else { return event }
            if let editor = self.panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            self.collapse(); return nil
        }
        update()
    }
    func expand(_ page: IslandPage) {
        guard !suppressed else { return }
        launcher.deactivate()
        self.page = page; expanded = true; update()
        NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if page == .launcher { launcher.activate(in: panel) }
    }
    func collapse() {
        guard expanded, panel.attachedSheet == nil, !modalActivity else { return }
        launcher.deactivate(); expanded = false; panel.resignKey(); update()
    }
    func setCaptureActive(_ active: Bool) {
        suppressed = active
        if active {
            launcher.deactivate(); expanded = false
            if let sheet = panel.attachedSheet { panel.endSheet(sheet, returnCode: .cancel); sheet.orderOut(nil) }
        }
        update()
    }
    private func update() {
        guard !suppressed, expanded || model.islandEnabled, let screen = NSScreen.screens.first else { panel.orderOut(nil); return }
        let frame = screen.visibleFrame
        let size = expanded ? NSSize(width: 800, height: 600) : NSSize(width: 192, height: 38)
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 8, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }
}
private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct UnifiedIslandView: View {
    @ObservedObject var controller: TaskIslandController
    @ObservedObject var model: TaskCenterModel
    @ObservedObject var launcher: QuickLauncherController
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }
    private var accent: Color { WorkspaceTheme.accent(scheme) }
    var body: some View {
        Group {
            if controller.expanded {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        navigation
                        content.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    HStack(spacing: 8) {
                        Text("轻屿").font(.system(size: 11, weight: .semibold))
                        Text("·").foregroundStyle(.tertiary)
                        Text(controller.page == .launcher ? "搜索应用 · 设置独立快捷键" : "随手捕捉，轻松有序").foregroundStyle(.secondary)
                        Spacer()
                        Keycap(text: "esc"); Text("收起").foregroundStyle(.secondary)
                    }.font(.system(size: 11)).padding(.horizontal, 22).frame(height: 42)
                        .overlay(alignment: .top) { Divider().opacity(0.5) }
                }
            } else {
                Button { controller.expand(.tasks) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checklist").foregroundStyle(accent)
                        Text(model.connected && model.dataAvailable ? "\(model.unfinishedCount)" : "—").font(.system(size: 12, weight: .semibold))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }.buttonStyle(.plain).tint(accent).foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WorkspaceTheme.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: controller.expanded ? 18 : 19))
            .overlay(RoundedRectangle(cornerRadius: controller.expanded ? 18 : 19).stroke(Color.primary.opacity(0.09), lineWidth: 1))
    }
    private var navigation: some View {
        HStack(spacing: 8) {
            Button { controller.collapse() } label: {
                Image(systemName: "leaf.fill").font(.system(size: 19, weight: .medium)).foregroundStyle(accent)
                    .frame(width: 42, height: 36)
            }.help("轻屿 · 收起")
            tab("截图", page: .capture, icon: "viewfinder")
            tab("启动", page: .launcher, icon: "square.grid.2x2")
            tab("待办", page: .tasks, icon: "checkmark.square")
            tab("办公", page: .office, icon: "briefcase")
            tab("设置", page: .settings, icon: "gearshape")
            Spacer(minLength: 0)
            Button { controller.collapse() } label: { Image(systemName: "chevron.up").padding(12) }.help("收起 · Esc")
        }.padding(14).frame(height: 66)
            .background(dark ? Color.white.opacity(0.025) : Color.white.opacity(0.35))
            .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }
    @ViewBuilder private var content: some View {
        switch controller.page {
        case .launcher: QuickLauncherView(model: launcher)
        case .tasks: TaskCenterView(model: model)
        case .capture: controller.captureContent ?? AnyView(Text("截图工具"))
        case .office: controller.officeContent ?? AnyView(Text("办公工具"))
        case .settings: controller.settingsContent ?? AnyView(Text("外观设置"))
        }
    }
    private func tab(_ title: String, page: IslandPage, icon: String) -> some View {
        Button { controller.expand(page) } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium))
                Text(title).font(.system(size: 13, weight: controller.page == page ? .semibold : .medium))
            }.frame(width: 88, height: 38)
                .foregroundStyle(controller.page == page ? (dark ? Color.white : accent) : Color.secondary)
                .background(controller.page == page ? accent.opacity(dark ? 0.34 : 0.09) : .clear, in: RoundedRectangle(cornerRadius: 11))
        }
    }
}

struct TaskIslandView: View {
    @ObservedObject var model: TaskCenterModel
    let open: () -> Void
    var body: some View {
        Button(action: open) { Label(model.connected && model.dataAvailable ? "\(model.unfinishedCount)" : "—", systemImage: "checklist").padding(10) }
            .buttonStyle(.plain).foregroundStyle(Color.primary).background(Color(nsColor: .windowBackgroundColor), in: Capsule())
    }
}
