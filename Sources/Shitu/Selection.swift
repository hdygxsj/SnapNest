import AppKit

struct CaptureRegion {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let rect: CGRect // AppKit global coordinates, bottom-left origin
    let scale: CGFloat
}

@MainActor
final class SelectionController {
    private var windows: [NSWindow] = []
    private var completion: ((CaptureRegion?) -> Void)?

    func select(instruction: String = "拖动选择区域 · Esc 取消", completion: @escaping (CaptureRegion?) -> Void) {
        guard self.completion == nil else { return }
        self.completion = completion
        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.instruction = instruction
            view.finished = { [weak self] localRect in
                guard let rect = localRect,
                      let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                    self?.finish(nil); return
                }
                self?.finish(CaptureRegion(displayID: number.uint32Value, screenFrame: screen.frame,
                    rect: rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY), scale: screen.backingScaleFactor))
            }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            windows.append(window)
        }
    }
    func cancel() { finish(nil) }
    private func finish(_ region: CaptureRegion?) {
        let callback = completion
        completion = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        callback?(region)
    }
}

private final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var instruction = "拖动选择区域 · Esc 取消"
    var finished: ((CGRect?) -> Void)?
    private var start: NSPoint?
    private var selection: CGRect = .zero
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = .zero
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        if selection.width >= 8 && selection.height >= 8 { finished?(selection) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finished?(nil) }
    }
    override func rightMouseDown(with event: NSEvent) { finished?(nil) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.34).setFill()
        bounds.fill()
        if !selection.isEmpty {
            NSColor.clear.setFill()
            selection.fill(using: .copy)
            NSColor.systemMint.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 2
            border.stroke()
        }
        let text = selection.isEmpty ? instruction : "\(Int(selection.width)) × \(Int(selection.height)) pt · 松开完成"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attributes)
        let box = CGRect(x: (bounds.width - size.width) / 2 - 20, y: bounds.height - 100, width: size.width + 40, height: 44)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
        text.draw(at: CGPoint(x: box.minX + 20, y: box.minY + 13), withAttributes: attributes)
    }
}
