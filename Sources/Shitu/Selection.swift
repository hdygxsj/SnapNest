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

    func select(initialRegion: CaptureRegion? = nil, windowOnly: Bool = false, snapshots: [CGDirectDisplayID: CGImage] = [:], colorPicked: ((String) -> Void)? = nil, instruction: String = "拖动选择区域 · Esc 取消", completion: @escaping (CaptureRegion?) -> Void) {
        guard self.completion == nil else { return }
        self.completion = completion
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let targets: [WindowTarget] = windowOnly ? info.compactMap { item in
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
            if let initialRegion,
               (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value != initialRegion.displayID { continue }
            let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            if let initialRegion {
                view.adjusting = true
                view.adjustmentScale = screen.backingScaleFactor
                view.setSelection(initialRegion.rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY))
            }
            view.instruction = windowOnly ? "移到窗口上，单击截取 · Esc 取消" : instruction
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               let image = snapshots[number.uint32Value] {
                view.snapshot = image
                view.pixels = ScreenPixels(image: image)
            }
            view.colorFinished = { [weak self] color in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(color.hex, forType: .string)
                self?.finish(nil)
                colorPicked?(color.hex)
            }
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
        if windows.isEmpty { finish(nil) }
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
    var snapshot: CGImage?
    var pixels: ScreenPixels?
    var colorFinished: ((PixelColor) -> Void)?
    var adjusting = false
    var adjustmentScale: CGFloat = 1
    private var resizeEdges = 0
    private var dragOriginal = CGRect.zero
    func setSelection(_ rect: CGRect) { selection = SelectionAdjustment.fit(rect, inside: bounds); needsDisplay = true }
    private var pointer: CGPoint = .zero
    private var hovered: WindowTarget?
    private var dragged = false
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    func refreshHover() {
        if adjusting { needsDisplay = true; return }
        pointer = CGPoint(x: NSEvent.mouseLocation.x - screenOrigin.x, y: NSEvent.mouseLocation.y - screenOrigin.y)
        hovered = WindowTarget.hit(at: NSEvent.mouseLocation, in: targets)
        selection = hovered?.frame.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y) ?? .zero
        needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) { if start == nil { refreshHover() } }
    override func mouseEntered(with event: NSEvent) { if start == nil { refreshHover() } }
    override func mouseExited(with event: NSEvent) {
        if adjusting { return }
        if start == nil { hovered = nil; selection = .zero; pointer = CGPoint(x: -1, y: -1); needsDisplay = true }
    }
    private var start: NSPoint?
    private var selection: CGRect = .zero
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        dragged = false
        if adjusting, let start {
            window?.makeFirstResponder(self)
            dragOriginal = selection
            resizeEdges = 0
            if abs(start.x - selection.minX) <= 8 { resizeEdges |= 1 }
            else if abs(start.x - selection.maxX) <= 8 { resizeEdges |= 2 }
            if abs(start.y - selection.minY) <= 8 { resizeEdges |= 4 }
            else if abs(start.y - selection.maxY) <= 8 { resizeEdges |= 8 }
            if !selection.insetBy(dx: -8, dy: -8).contains(start) { self.start = nil }
            return
        }
        refreshHover()
    }
    override func mouseDragged(with event: NSEvent) {
        guard !windowOnly, let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        if adjusting {
            selection = SelectionAdjustment.drag(dragOriginal, delta: CGPoint(x: end.x-start.x, y: end.y-start.y), edges: resizeEdges, bounds: bounds)
            needsDisplay = true; return
        }
        guard dragged || hypot(end.x - start.x, end.y - start.y) >= 4 else { return }
        dragged = true
        hovered = nil
        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        if adjusting { start = nil; return }
        if !dragged, !windowOnly, let pixels,
           let p = pixels.pixel(at: convert(event.locationInWindow, from: nil), in: bounds),
           let color = pixels.color(x: Int(p.x), y: Int(p.y)) {
            colorFinished?(color); return
        }
        if !dragged, let hovered { windowFinished?(hovered); return }
        start = nil
        if !windowOnly && dragged && selection.width >= 8 && selection.height >= 8 { finished?(selection) }
        else { dragged = false; refreshHover() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finished?(nil); return }
        guard adjusting else { return }
        if event.keyCode == 36 { finished?(selection); return }
        if event.charactersIgnoringModifiers?.lowercased() == "d" { enterDimensions(); return }
        let step: CGFloat = (event.modifierFlags.contains(.shift) ? 10 : 1) / adjustmentScale
        let offset: CGPoint
        switch event.keyCode {
        case 123: offset = CGPoint(x: -step, y: 0)
        case 124: offset = CGPoint(x: step, y: 0)
        case 125: offset = CGPoint(x: 0, y: -step)
        case 126: offset = CGPoint(x: 0, y: step)
        default: return
        }
        setSelection(selection.offsetBy(dx: offset.x, dy: offset.y))
    }
    private func enterDimensions() {
        let alert = NSAlert(); alert.messageText = "选区尺寸（像素）"
        alert.informativeText = "输入宽和高，尺寸会限制在当前显示器内。"
        let width = NSTextField(string: String(Int(selection.width * adjustmentScale)))
        let height = NSTextField(string: String(Int(selection.height * adjustmentScale)))
        let stack = NSStackView(views: [NSTextField(labelWithString: "宽"), width, NSTextField(labelWithString: "高"), height])
        stack.frame = CGRect(x: 0, y: 0, width: 300, height: 28)
        alert.accessoryView = stack
        alert.addButton(withTitle: "应用"); alert.addButton(withTitle: "取消")
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        if alert.runModal() == .alertFirstButtonReturn, let w = Double(width.stringValue), let h = Double(height.stringValue),
           w.isFinite, h.isFinite, w > 0, h > 0 {
            setSelection(CGRect(origin: selection.origin, size: CGSize(width: w / adjustmentScale, height: h / adjustmentScale)))
        }
    }
    override func rightMouseDown(with event: NSEvent) { finished?(nil) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        if let snapshot {
            NSImage(cgImage: snapshot, size: bounds.size).draw(in: bounds)
        }
        NSColor.black.withAlphaComponent(0.34).setFill()
        bounds.fill()
        if !selection.isEmpty {
            if let snapshot {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: selection).addClip()
                NSImage(cgImage: snapshot, size: bounds.size).draw(in: bounds)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                NSColor.clear.setFill()
                selection.fill(using: .copy)
            }
            NSColor.systemMint.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 2
            border.stroke()
        }
        if adjusting {
            NSColor.systemMint.setFill()
            for x in [selection.minX, selection.midX, selection.maxX] {
                for y in [selection.minY, selection.midY, selection.maxY] where x != selection.midX || y != selection.midY {
                    CGRect(x: x-3, y: y-3, width: 6, height: 6).fill()
                }
            }
        }
        if !adjusting, !dragged, let pixels, bounds.contains(pointer) { PixelLoupe.draw(pixels: pixels, pointer: pointer, bounds: bounds) }
        let text = adjusting ? "\(Int(selection.width * adjustmentScale)) × \(Int(selection.height * adjustmentScale)) px · 拖动边角/内部 · 方向键微调 · D 尺寸 · 回车确认 · Esc 返回" : hovered.map { "\($0.name) · 单击截取窗口" + (windowOnly ? " · Esc 取消" : " · 拖动框选 · Esc 取消") } ?? (selection.isEmpty ? instruction : "\(Int(selection.width)) × \(Int(selection.height)) pt · 松开完成")
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
        view.windowOnly = true
        view.mouseDown(with: event(.leftMouseDown, 20, 20))
        view.mouseUp(with: event(.leftMouseUp, 21, 21))
        guard windowID == 42, region == nil else { return false }
        windowID = nil
        view.windowOnly = false
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
        view.windowOnly = false
        view.targets = []
        view.pixels = ScreenPixels(image: EditorVerification.fixture())
        var picked: PixelColor?
        view.colorFinished = { picked = $0 }
        windowID = nil; region = nil
        view.mouseDown(with: event(.leftMouseDown, 20, 20))
        view.mouseUp(with: event(.leftMouseUp, 20, 20))
        guard picked != nil, region == nil, windowID == nil else { return false }
        picked = nil
        view.mouseDown(with: event(.leftMouseDown, 20, 20))
        view.mouseUp(with: event(.leftMouseUp, 120, 100))
        guard picked == nil, region != nil else { return false }
        print("Color selection verified: click picks color, drag captures region")
        print("Window selection verified: click snaps, drag selects, window-only mode, cancellation")
        let adjustment = SelectionView(frame: view.bounds)
        adjustment.adjusting = true
        adjustment.adjustmentScale = 2
        adjustment.setSelection(CGRect(x: 50, y: 50, width: 100, height: 80))
        var confirmed: CGRect?
        var completed = false
        adjustment.finished = { confirmed = $0; completed = true }
        adjustment.mouseDown(with: event(.leftMouseDown, 150, 130))
        adjustment.mouseDragged(with: event(.leftMouseDragged, 180, 150))
        adjustment.mouseUp(with: event(.leftMouseUp, 180, 150))
        guard !completed else { return false }
        func key(_ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: code)!
        }
        adjustment.keyDown(with: key(124))
        adjustment.keyDown(with: key(36))
        guard confirmed == CGRect(x: 50.5, y: 50, width: 130, height: 100) else { return false }
        completed = false
        adjustment.keyDown(with: key(53))
        guard completed, confirmed == nil else { return false }
        print("Selection adjustment verified: corner resize, Retina pixel movement, Enter confirmation, Escape cancellation")
        return true
    }
}
