import AppKit
import SwiftUI
import ApplicationServices

/// Reads only an explicit selection. Never synthesizes Copy or replaces the clipboard.
@MainActor
final class SelectedTextCapture: ObservableObject {
    @Published var bubbleEnabled = UserDefaults.standard.bool(forKey: "v2.selectionBubble") {
        didSet { UserDefaults.standard.set(bubbleEnabled, forKey: "v2.selectionBubble"); if !bubbleEnabled { dismiss() } }
    }
    @Published private(set) var hasAccess = AXIsProcessTrusted()
    @Published var shortcutMessage = "⌘⇧T：选中文字后添加待办"
    var addTask: ((String) -> Void)?
    var canCapture: () -> Bool = { true }
    private var monitor: Any?
    private var downMonitor: Any?
    private var activation: NSObjectProtocol?
    private var pending: Task<Void, Never>?
    private var bubble: NSPanel?
    private var settings: NSWindow?
    private var generation = 0

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in self?.selectionEnded() }
        }
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        activation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    func capture() {
        guard canCapture() else { return }
        let text = readSelection()?.text ?? ""
        dismiss()
        hasAccess = AXIsProcessTrusted()
        // Empty composer offers explicit Paste; inaccessible text is never silently substituted.
        addTask?(text)
    }

    func dismiss() {
        generation += 1
        pending?.cancel()
        pending = nil
        bubble?.orderOut(nil)
    }

    private func selectionEnded() {
        dismiss()
        guard bubbleEnabled, canCapture(), AXIsProcessTrusted() else { return }
        let token = generation
        let appPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, let self, self.generation == token, self.canCapture(),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == appPID,
                  let selection = self.readSelection() else { return }
            let mouse = NSEvent.mouseLocation
            if let bounds = selection.bounds, !bounds.insetBy(dx: -50, dy: -50).contains(mouse) { return }
            self.showBubble(text: selection.text, at: mouse)
        }
    }

    private func readSelection() -> (text: String, bounds: CGRect?)? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        guard (subrole as? String) != kAXSecureTextFieldSubrole else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let raw = selected as? String else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var range: CFTypeRef?
        var rectValue: CFTypeRef?
        var bounds: CGRect?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
           let range, AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &rectValue) == .success,
           let rectValue, CFGetTypeID(rectValue) == AXValueGetTypeID() {
            let value = unsafeBitCast(rectValue, to: AXValue.self)
            var rect = CGRect.zero
            if AXValueGetType(value) == .cgRect, AXValueGetValue(value, .cgRect, &rect), rect.width > 0, rect.height > 0 {
                let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
                bounds = CGRect(x: rect.minX, y: desktopTop - rect.maxY, width: rect.width, height: rect.height)
            }
        }
        return (text, bounds)
    }

    private func showBubble(text: String, at point: NSPoint) {
        let panel = bubble ?? NSPanel(contentRect: NSRect(x: 0, y: 0, width: 134, height: 36), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView:
            Button { [weak self] in
                guard let self, self.canCapture() else { return }
                self.dismiss(); self.addTask?(text)
            } label: {
                Label("添加待办", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .medium)).frame(width: 134, height: 36)
                    .background(.regularMaterial, in: Capsule())
            }.buttonStyle(.plain))
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        let frame = screen?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: max(frame.minX, min(point.x + 8, frame.maxX - 134)), y: max(frame.minY, min(point.y - 44, frame.maxY - 36))))
        bubble = panel
        panel.orderFrontRegardless()
    }

    func showPreferences() {
        hasAccess = AXIsProcessTrusted()
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "划词添加待办"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SelectedTextSettings(capture: self))
            window.center(); settings = window
        }
        NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func refreshAccess() { hasAccess = AXIsProcessTrusted() }
}

private struct SelectedTextSettings: View {
    @ObservedObject var capture: SelectedTextCapture
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选中文字，随手记下来").font(.title3.bold())
            Text(capture.shortcutMessage).font(.callout)
            Toggle("选中文字后显示「添加待办」按钮", isOn: $capture.bubbleEnabled)
            Text("需要辅助功能权限才能读取其他应用的选中文字。仅处理选区，不模拟复制；不支持读取的应用可在待办窗口点击「粘贴」。")
                .font(.caption).foregroundStyle(.secondary)
            Label(capture.hasAccess ? "辅助功能已授权" : "尚未授权辅助功能", systemImage: capture.hasAccess ? "checkmark.circle" : "info.circle")
            HStack {
                Button("打开辅助功能设置") { capture.openAccessibilitySettings() }
                Button("重新检查") { capture.refreshAccess() }
            }
        }.padding(24).frame(width: 430, height: 300)
    }
}
