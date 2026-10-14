import AppKit

/// A transparent hole keeps the selected pixels undimmed, including after cropping.
final class EditorBackdropView: NSView {
    var selection: CGRect = .zero { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        let path = NSBezierPath(rect: bounds)
        let hole = bounds.intersection(selection)
        if !hole.isNull && !hole.isEmpty { path.appendRect(hole) }
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.36).setFill()
        path.fill()
    }
}

@MainActor
final class EditorBackdrop {
    private var windows: [NSPanel] = []
    func show(selection: CGRect) {
        if windows.isEmpty {
            for screen in NSScreen.screens {
                let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.title = "轻屿 · 编辑遮罩"
                panel.isReleasedWhenClosed = false
                panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.hidesOnDeactivate = false
                panel.ignoresMouseEvents = true // Existing outside-click monitors dismiss without swallowing the click.
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.contentView = EditorBackdropView(frame: CGRect(origin: .zero, size: screen.frame.size))
                windows.append(panel)
            }
        }
        update(selection: selection)
        windows.forEach { $0.orderFrontRegardless() }
    }
    func update(selection: CGRect) {
        for window in windows {
            (window.contentView as? EditorBackdropView)?.selection = selection.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
        }
    }
    func hide() { windows.forEach { $0.orderOut(nil) } }
    func dismiss() { hide(); windows.removeAll() }
}
