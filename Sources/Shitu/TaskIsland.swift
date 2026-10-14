// SnapNest v2 private additions. Original project MIT notices remain in LICENSE.
import AppKit
import SwiftUI
import Combine

@MainActor final class TaskIslandController {
    private let model: TaskCenterModel
    private let panel: NSPanel
    private var suppressed = false
    private var subscriptions: Set<AnyCancellable> = []
    private var screenObserver: NSObjectProtocol?
    init(model: TaskCenterModel, open: @escaping () -> Void) {
        self.model = model
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 168, height: 36), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: TaskIslandView(model: model, open: open))
        model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.update() }
        }.store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
        update()
    }
    func setCaptureActive(_ active: Bool) { suppressed = active; update() }
    private func update() {
        guard !suppressed, model.islandEnabled, model.connected, model.dataAvailable, model.boundList != nil,
              let screen = NSScreen.screens.first else { panel.orderOut(nil); return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 8))
        panel.orderFrontRegardless()
    }
}
struct TaskIslandView: View {
    @ObservedObject var model: TaskCenterModel
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                Text("\(model.unfinishedCount) 项待办").font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }.foregroundStyle(.white).frame(width: 168, height: 36).background(.black.opacity(0.9), in: Capsule())
        }.buttonStyle(.plain).accessibilityLabel("打开任务，\(model.unfinishedCount) 项未完成")
    }
}
