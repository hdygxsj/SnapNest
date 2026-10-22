// Qingyu (SnapNest) 2.0 — MIT License.
import AppKit
import SwiftUI
import Combine

enum IslandPage { case launcher, tasks, capture, office, settings }

@MainActor final class TaskIslandController: NSObject, ObservableObject, NSWindowDelegate {
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
    private var presentingWorkspace = false
    private var changingFrame = false
    private let defaults: UserDefaults
    private var workspaceFrame: NSRect?
    private static let frameKey = "qingyu.workspace.frame.v1"
    private var escapeMonitor: Any?
    init(model: TaskCenterModel, launcher: QuickLauncherController, captureContent: AnyView? = nil, settingsContent: AnyView? = nil, officeContent: AnyView? = nil, preview: Bool = false, defaults: UserDefaults = .standard) {
        self.model = model; self.launcher = launcher; self.defaults = defaults
        if let value = defaults.string(forKey: Self.frameKey) { workspaceFrame = NSRectFromString(value) }
        self.captureContent = captureContent; self.settingsContent = settingsContent; self.officeContent = officeContent
        super.init()
        if preview { return }
        panel.delegate = self
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: UnifiedIslandView(controller: self, model: model, launcher: launcher))
        launcher.presentationRequested = { [weak self] in self?.expand(.launcher) }
        launcher.dismissalRequested = { [weak self] in self?.collapse() }
        model.objectWillChange.sink { [weak self] _ in Task { @MainActor in self?.update() } }.store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.update(constrain: true) }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
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
        self.page = page; expanded = true; update(constrain: true)
        NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true)
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        panel.makeKeyAndOrderFront(nil)
        if page == .launcher { launcher.activate(in: panel) }
    }
    func collapse() {
        guard expanded, panel.attachedSheet == nil, !modalActivity else { return }
        saveWorkspaceFrame()
        launcher.deactivate(); expanded = false; panel.resignKey(); update()
    }
    func setCaptureActive(_ active: Bool) {
        if active { saveWorkspaceFrame() }
        suppressed = active
        if active {
            launcher.deactivate(); expanded = false
            if let sheet = panel.attachedSheet { panel.endSheet(sheet, returnCode: .cancel); sheet.orderOut(nil) }
        }
        update()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        collapse()
        return false
    }
    func windowDidMove(_ notification: Notification) { saveWorkspaceFrame() }
    func windowDidResize(_ notification: Notification) { saveWorkspaceFrame() }
    private func saveWorkspaceFrame() {
        guard presentingWorkspace, !changingFrame, !panel.isMiniaturized else { return }
        workspaceFrame = panel.frame
        defaults.set(NSStringFromRect(panel.frame), forKey: Self.frameKey)
    }
    private func update(constrain: Bool = false) {
        guard !suppressed, expanded || model.islandEnabled, let screen = NSScreen.screens.first else { panel.orderOut(nil); return }
        changingFrame = true
        defer { changingFrame = false }
        if expanded {
            if !presentingWorkspace {
                panel.orderOut(nil)
                panel.styleMask = [.titled, .closable, .miniaturizable, .resizable]
                panel.title = "轻屿"
                panel.titleVisibility = .visible
                panel.isMovable = true
                panel.isMovableByWindowBackground = false
                panel.level = .normal
                panel.isFloatingPanel = false
                panel.collectionBehavior = [.fullScreenPrimary]
                panel.minSize = NSSize(width: min(800, screen.visibleFrame.width), height: min(622, screen.visibleFrame.height))
                presentingWorkspace = true
                if let frame = WorkspacePlacement.frame(saved: workspaceFrame, screens: NSScreen.screens.map(\.visibleFrame)) { panel.setFrame(frame, display: true) }
            } else if constrain, let frame = WorkspacePlacement.frame(saved: panel.frame, screens: NSScreen.screens.map(\.visibleFrame)) {
                panel.setFrame(frame, display: true)
            }
        } else {
            if presentingWorkspace { panel.orderOut(nil) }
            panel.styleMask = [.borderless, .nonactivatingPanel]
            panel.minSize = .zero
            panel.level = .floating; panel.isFloatingPanel = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            presentingWorkspace = false
            let frame = screen.visibleFrame
            panel.setFrame(NSRect(x: frame.midX - 96, y: frame.maxY - 46, width: 192, height: 38), display: true)
        }
        if !panel.isVisible && !panel.isMiniaturized { panel.orderFront(nil) }
    }
    static func verifyLifecycle(model: TaskCenterModel, defaults: UserDefaults) -> Bool {
        let controller = TaskIslandController(model: model, launcher: QuickLauncherController(), defaults: defaults)
        defer { controller.panel.orderOut(nil) }
        controller.expand(.capture)
        guard controller.panel.styleMask.contains(.resizable), controller.panel.level == .normal else { return false }
        let original = controller.panel.frame
        let changed = original.offsetBy(dx: 25, dy: -20)
        controller.panel.setFrame(changed, display: true)
        controller.saveWorkspaceFrame()
        controller.expand(.office)
        let expected = WorkspacePlacement.frame(saved: changed, screens: NSScreen.screens.map(\.visibleFrame))!
        guard controller.panel.frame == expected else { return false }
        controller.collapse()
        guard !controller.panel.isVisible else { return false }
        controller.expand(.capture)
        guard controller.panel.frame == expected else { return false }
        controller.panel.performClose(nil)
        guard !controller.panel.isVisible, !controller.expanded else { return false }
        model.islandEnabled = true
        controller.update()
        guard controller.panel.frame.width == 192, controller.panel.level == .floating else { return false }
        controller.expand(.office)
        guard controller.panel.frame == expected else { return false }
        controller.setCaptureActive(true)
        guard !controller.panel.isVisible else { return false }
        controller.setCaptureActive(false)
        controller.expand(.capture)
        guard controller.panel.frame == expected else { return false }
        let restored = TaskIslandController(model: model, launcher: QuickLauncherController(), defaults: defaults)
        defer { restored.panel.orderOut(nil) }
        restored.expand(.capture)
        return restored.panel.frame == expected
    }
    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
    }

}
private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { styleMask.contains(.titled) }
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
