// SnapNest 2.0 private additions.
import AppKit
import SwiftUI
import Combine

enum IslandPage { case launcher, tasks, capture, settings }

@MainActor final class TaskIslandController: ObservableObject {
    @Published var expanded = false
    @Published var page: IslandPage = .launcher
    let captureContent: AnyView?
    let settingsContent: AnyView?
    private let model: TaskCenterModel
    private let launcher: QuickLauncherController
    private let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var suppressed = false
    private var subscriptions: Set<AnyCancellable> = []
    private var screenObserver: NSObjectProtocol?
    private var outsideMonitor: Any?
    private var escapeMonitor: Any?
    init(model: TaskCenterModel, launcher: QuickLauncherController, captureContent: AnyView? = nil, settingsContent: AnyView? = nil, preview: Bool = false) {
        self.model = model; self.launcher = launcher
        self.captureContent = captureContent; self.settingsContent = settingsContent
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
                guard let self, self.panel.attachedSheet == nil else { return }
                self.collapse()
            }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.type != .keyDown {
                if let self, event.window !== self.panel, self.panel.attachedSheet == nil { self.collapse() }
                return event
            }
            guard let self, event.window === self.panel, event.keyCode == 53,
                  self.panel.attachedSheet == nil else { return event }
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
        guard expanded, panel.attachedSheet == nil else { return }
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
        let size = expanded ? NSSize(width: 600, height: 570) : NSSize(width: 192, height: 38)
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
    @Environment(\.colorScheme) private var colorScheme
    private var mint: Color { colorScheme == .dark ? Color(red: 0.62, green: 0.92, blue: 0.77) : Color(red: 0.08, green: 0.42, blue: 0.31) }
    var body: some View {
        Group {
            if controller.expanded {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "viewfinder").foregroundStyle(mint).padding(.trailing, 8)
                        tab("截图", page: .capture, icon: "viewfinder")
                        tab("快捷启动", page: .launcher, icon: "command")
                        tab("待办", page: .tasks, icon: "checklist")
                        tab("设置", page: .settings, icon: "slider.horizontal.3")
                        Spacer()
                        Button { controller.collapse() } label: { Image(systemName: "chevron.up").padding(8) }.help("收起 · Esc")
                    }.padding(.horizontal, 16).frame(height: 66).fixedSize(horizontal: false, vertical: true)
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                    if controller.page == .launcher { QuickLauncherView(model: launcher).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else if controller.page == .tasks { TaskCenterView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else if controller.page == .capture { controller.captureContent ?? AnyView(Text("截图工具")) }
                    else { controller.settingsContent ?? AnyView(Text("跟随系统外观")) }
                }
            } else {
                Button { controller.expand(.tasks) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "command").foregroundStyle(mint)
                        Rectangle().fill(Color.primary.opacity(0.2)).frame(width: 1, height: 14)
                        Image(systemName: "checklist").foregroundStyle(mint)
                        Text(model.connected && model.dataAvailable ? "\(model.unfinishedCount)" : "—")
                            .font(.system(size: 12, weight: .medium))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .buttonStyle(.plain).tint(mint).foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: controller.expanded ? 22 : 19))
        .overlay(RoundedRectangle(cornerRadius: controller.expanded ? 22 : 19).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
    private func tab(_ title: String, page: IslandPage, icon: String) -> some View {
        Button { controller.expand(page) } label: {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14).frame(height: 34)
                .foregroundStyle(controller.page == page ? mint : Color.secondary)
                .background(controller.page == page ? mint.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
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
