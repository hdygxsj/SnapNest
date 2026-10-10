import AppKit
import ShituCore

struct CaptureRegion {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let rect: CGRect // AppKit global coordinates, bottom-left origin
    let scale: CGFloat
    var windowID: CGWindowID? = nil
}

@MainActor
final class SelectionController {
    private var windows: [NSWindow] = []
    private var completion: ((CaptureRegion?) -> Void)?

    func select(windowOnly: Bool = false, snapWindows: Bool = false, instruction: String = "拖动选择区域 · Esc 取消", completion: @escaping (CaptureRegion?) -> Void) {
        guard self.completion == nil else { return }
        self.completion = completion
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let targets: [WindowTarget] = (snapWindows || windowOnly) ? info.compactMap { item in
            guard let pid = item[kCGWindowOwnerPID as String] as? Int32,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  (item[kCGWindowLayer as String] as? Int) == 0,
                  (item[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = item[kCGWindowNumber as String] as? UInt32,
                  let dictionary = item[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: dictionary),
                  frame.width >= 8, frame.height >= 8 else { return nil }
            return WindowTarget(id: id, quartzFrame: frame, primaryHeight: primaryHeight,
                                name: item[kCGWindowOwnerName as String] as? String ?? "应用窗口")
        } : []
        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.instruction = windowOnly ? "移到窗口上，单击截取 · Esc 取消" : instruction
            view.targets = targets
            view.windowOnly = windowOnly
            view.screenOrigin = screen.frame.origin
            window.acceptsMouseMovedEvents = true
            view.windowFinished = { [weak self] target in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { self?.finish(nil); return }
                self?.finish(CaptureRegion(displayID: number.uint32Value, screenFrame: screen.frame,
                    rect: target.frame, scale: screen.backingScaleFactor, windowID: target.id))
            }
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
            view.refreshHover()
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
    var targets: [WindowTarget] = []
    var windowOnly = false
    var screenOrigin: CGPoint = .zero
    var windowFinished: ((WindowTarget) -> Void)?
    private var hovered: WindowTarget?
    private var dragged = false
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    func refreshHover() {
        hovered = WindowTarget.hit(at: NSEvent.mouseLocation, in: targets)
        selection = hovered?.frame.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y) ?? .zero
        needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) { if start == nil { refreshHover() } }
    override func mouseEntered(with event: NSEvent) { if start == nil { refreshHover() } }
    override func mouseExited(with event: NSEvent) {
        if start == nil { hovered = nil; selection = .zero; needsDisplay = true }
    }
    private var start: NSPoint?
    private var selection: CGRect = .zero
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        dragged = false
        refreshHover()
    }
    override func mouseDragged(with event: NSEvent) {
        guard !windowOnly, let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        guard dragged || hypot(end.x - start.x, end.y - start.y) >= 4 else { return }
        dragged = true
        hovered = nil
        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        if !dragged, let hovered { windowFinished?(hovered); return }
        start = nil
        if !windowOnly && dragged && selection.width >= 8 && selection.height >= 8 { finished?(selection) }
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
        let text = hovered.map { "\($0.name) · 单击截取窗口" + (windowOnly ? " · Esc 取消" : " · 拖动框选 · Esc 取消") } ?? (selection.isEmpty ? instruction : "\(Int(selection.width)) × \(Int(selection.height)) pt · 松开完成")
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attributes)
        let box = CGRect(x: (bounds.width - size.width) / 2 - 20, y: bounds.height - 100, width: size.width + 40, height: 44)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
        text.draw(at: CGPoint(x: box.minX + 20, y: box.minY + 13), withAttributes: attributes)
    }
}

@MainActor
enum WindowSelectionVerification {
    static func run() -> Bool {
        let mouse = NSEvent.mouseLocation
        let view = SelectionView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.targets = [WindowTarget(id: 42,
            quartzFrame: CGRect(x: mouse.x - 100, y: -mouse.y - 100, width: 200, height: 200),
            primaryHeight: 0, name: "Fixture")]
        var windowID: CGWindowID?
        var region: CGRect?
        var cancelled = false
        view.windowFinished = { windowID = $0.id }
        view.finished = { region = $0; cancelled = $0 == nil }
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: event(.leftMouseDown, 20, 20))
        view.mouseUp(with: event(.leftMouseUp, 21, 21))
        guard windowID == 42, region == nil else { return false }
        windowID = nil
        view.mouseDown(with: event(.leftMouseDown, 20, 20))
        view.mouseDragged(with: event(.leftMouseDragged, 120, 100))
        view.mouseUp(with: event(.leftMouseUp, 120, 100))
        guard windowID == nil, region == CGRect(x: 20, y: 20, width: 100, height: 80) else { return false }
        region = nil
        view.windowOnly = true
        view.mouseDown(with: event(.leftMouseDown, 20, 20))
        view.mouseUp(with: event(.leftMouseUp, 120, 100))
        guard windowID == 42, region == nil else { return false }
        view.rightMouseDown(with: event(.rightMouseDown, 0, 0))
        guard cancelled else { return false }
        print("Window selection verified: click snaps, drag selects, window-only mode, cancellation")
        return true
    }
}
