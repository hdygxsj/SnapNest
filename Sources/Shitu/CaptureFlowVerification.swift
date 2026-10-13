import AppKit

@MainActor
enum CaptureFlowVerification {
    static func run() -> Bool {
        _ = NSApplication.shared
        guard WindowSelectionVerification.run() else { print("FAIL window selection gestures"); return false }
        let board = NSPasteboard.general
        let original = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            board.clearContents()
            let items = original.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            board.writeObjects(items)
        }
        board.clearContents()
        let editor = EditorController()
        var closedCount = 0
        editor.show(image: EditorVerification.fixture(), region: nil, save: { _ in true }, switchMode: { _, _ in }, closed: { closedCount += 1 })
        guard NSImage(pasteboard: board) != nil else {
            print("FAIL screenshot must be on clipboard before Save or Copy")
            return false
        }
        let masks = NSApp.windows.filter { $0.title == "拾图 · 编辑遮罩" && $0.isVisible }
        guard masks.count == NSScreen.screens.count, !masks.isEmpty else {
            print("FAIL editor must dim every display outside the selection"); return false
        }
        guard let canvasWindow = NSApp.windows.first(where: { $0.title == "拾图 · 选区" }) else { return false }
        canvasWindow.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        func findCanvas(_ view: NSView) -> CanvasView? {
            if let canvas = view as? CanvasView { return canvas }
            return view.subviews.compactMap(findCanvas).first
        }
        guard let root = canvasWindow.contentView, let canvas = findCanvas(root) else {
            print("FAIL missing editor canvas"); return false
        }
        editor.handleOutsideClick(at: CGPoint(x: canvasWindow.frame.midX, y: canvasWindow.frame.midY))
        guard closedCount == 0 else { print("FAIL inside click dismissed editor"); return false }
        if let toolbar = NSApp.windows.first(where: { $0.title == "拾图 · 选区工具条" }) {
            editor.handleOutsideClick(at: CGPoint(x: toolbar.frame.midX, y: toolbar.frame.midY))
            guard closedCount == 0 else { print("FAIL toolbar click dismissed editor"); return false }
        }
        canvas.document.crop(CGRect(x: 10, y: 10, width: 120, height: 90))
        editor.handleOutsideClick(at: CGPoint(x: -100000, y: -100000))
        guard masks.allSatisfy({ !$0.isVisible }) else { print("FAIL editor masks remain after dismissal"); return false }
        let copied = NSImage(pasteboard: board)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        guard closedCount == 1, copied?.width == 120, copied?.height == 90, !canvasWindow.isVisible else {
            print("FAIL outside click must close and copy the latest edited image"); return false
        }
        editor.handleOutsideClick(at: .zero)
        guard closedCount == 1 else { print("FAIL repeated completion"); return false }
        board.clearContents()
        board.setString("keep clipboard", forType: .string)
        editor.show(image: EditorVerification.fixture(), region: nil, automaticallyCopy: false,
                    save: { _ in true }, switchMode: { _, _ in }, closed: {})
        editor.handleOutsideClick(at: CGPoint(x: -100000, y: -100000))
        guard board.string(forType: .string) == "keep clipboard" else {
            print("FAIL explicit automatic-copy preference was ignored"); return false
        }
        // Double-click is an explicit Copy, even when automatic clipboard copy is disabled.
        editor.show(image: EditorVerification.fixture(), region: nil, automaticallyCopy: false,
                    save: { _ in true }, switchMode: { _, _ in }, closed: { closedCount += 1 })
        guard let doubleWindow = NSApp.windows.first(where: { $0.title == "拾图 · 选区" && $0.isVisible }),
              let doubleRoot = doubleWindow.contentView else { return false }
        doubleRoot.layoutSubtreeIfNeeded()
        guard let doubleCanvas = findCanvas(doubleRoot) else { return false }
        doubleCanvas.document.crop(CGRect(x: 10, y: 10, width: 100, height: 80))
        doubleCanvas.document.tool = .text
        let countBeforeDouble = closedCount
        let doubleEvent = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 20, y: 20),
            modifierFlags: [], timestamp: 0, windowNumber: doubleWindow.windowNumber, context: nil,
            eventNumber: 0, clickCount: 2, pressure: 1)!
        let firstEvent = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 20, y: 20),
            modifierFlags: [], timestamp: 0, windowNumber: doubleWindow.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1)!
        doubleCanvas.mouseDown(with: firstEvent)
        doubleCanvas.mouseUp(with: firstEvent)
        doubleCanvas.mouseDown(with: doubleEvent)
        RunLoop.current.run(until: Date().addingTimeInterval(NSEvent.doubleClickInterval + 0.05))
        let doubleImage = NSImage(pasteboard: board)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        guard !doubleWindow.isVisible, closedCount == countBeforeDouble + 1,
              doubleImage?.width == 100, doubleImage?.height == 80 else {
            print("FAIL double-click must copy edited screenshot and dismiss"); return false
        }
        print("Double-click verified: copies latest crop, closes editor, works with automatic copy disabled")
        let numberedDocument = EditorDocument(image: EditorVerification.fixture(width: 400, height: 400))
        numberedDocument.tool = .number
        let numberedCanvas = CanvasView(document: numberedDocument)
        numberedCanvas.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        var numberCopied = false
        numberedCanvas.copy = { numberCopied = true }
        numberedCanvas.mouseDown(with: firstEvent)
        numberedCanvas.mouseUp(with: firstEvent)
        guard numberedDocument.history.current.annotations.last?.text == "1" else { print("FAIL number must appear immediately"); return false }
        numberedCanvas.mouseDown(with: firstEvent)
        numberedCanvas.mouseUp(with: firstEvent)
        guard numberedDocument.history.current.annotations.map(\.text) == ["1", "2"] else { print("FAIL rapid number clicks lost"); return false }
        numberedCanvas.mouseDown(with: doubleEvent)
        guard numberCopied, numberedDocument.history.current.annotations.map(\.text) == ["1"] else { print("FAIL double-click added an unwanted number"); return false }
        print("Number gestures verified: immediate marking, rapid clicks, clean double-click copy")
        numberedDocument.tool = .pen
        numberedCanvas.mouseDown(with: firstEvent)
        numberedCanvas.mouseUp(with: firstEvent)
        guard numberedDocument.history.current.annotations.count == 2 else { return false }
        numberedCanvas.mouseDown(with: doubleEvent)
        guard numberedDocument.history.current.annotations.count == 1 else { print("FAIL double-click retained first-click pen dot"); return false }
        let backdropView = EditorBackdropView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        backdropView.selection = CGRect(x: 20, y: 20, width: 40, height: 40)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        backdropView.draw(backdropView.bounds)
        NSGraphicsContext.restoreGraphicsState()
        guard let outside = bitmap.colorAt(x: 5, y: 5), let inside = bitmap.colorAt(x: 40, y: 40),
              abs(outside.alphaComponent - 0.36) < 0.02, inside.alphaComponent == 0 else {
            print("FAIL mask must dim outside pixels and keep selection transparent"); return false
        }
        let model = AppModel()
        let previousRegion = UserDefaults.standard.data(forKey: "lastCaptureRegion.v1")
        defer {
            if let previousRegion { UserDefaults.standard.set(previousRegion, forKey: "lastCaptureRegion.v1") }
            else { UserDefaults.standard.removeObject(forKey: "lastCaptureRegion.v1") }
        }
        if let screen = NSScreen.main, let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let rect = CGRect(x: screen.frame.minX + 20, y: screen.frame.minY + 30, width: 120, height: 80)
            model.rememberRegion(CaptureRegion(displayID: number.uint32Value, screenFrame: screen.frame, rect: rect, scale: screen.backingScaleFactor))
            let relaunched = AppModel()
            guard relaunched.canRepeatCapture, relaunched.lastCapture?.rect(on: screen.frame) == rect else { print("FAIL last region not restored"); return false }
            relaunched.phase = .recording
            guard !relaunched.canRepeatCapture else { print("FAIL repeat enabled while recording"); return false }
            print("Repeat capture verified: saved display/local region, restored after relaunch, disabled while busy")
        }
        var mainShown = false
        model.showMain = { mainShown = true }
        model.phase = .editing
        model.closeEditor()
        guard model.phase == .idle, !mainShown else {
            print("FAIL closing editor must not reopen main window")
            return false
        }
        let savedHistory = UserDefaults.standard.data(forKey: "history")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SnapNest-Flow-\(UUID().uuidString)")
        defer {
            if let savedHistory { UserDefaults.standard.set(savedHistory, forKey: "history") }
            else { UserDefaults.standard.removeObject(forKey: "history") }
            try? FileManager.default.removeItem(at: folder)
        }
        model.saveFolder = folder
        model.phase = .editing
        guard model.saveEdited(EditorVerification.fixture(), kind: "验证"), !mainShown,
              model.phase == .idle, let item = model.items.first,
              FileManager.default.fileExists(atPath: item.url.path) else {
            print("FAIL save must write image without reopening main window"); return false
        }
        let resident = ResidentWindowDelegate()
        let workspace = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 300, height: 200),
                                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
        workspace.isReleasedWhenClosed = false
        workspace.delegate = resident
        NSApp.setActivationPolicy(.regular)
        workspace.makeKeyAndOrderFront(nil)
        workspace.performClose(nil)
        guard !workspace.isVisible, NSApp.activationPolicy() == .accessory else {
            print("FAIL closing workspace must hide to menu bar"); return false
        }
        NSApp.setActivationPolicy(.regular)
        workspace.makeKeyAndOrderFront(nil)
        guard workspace.isVisible else { print("FAIL workspace cannot reopen"); return false }
        workspace.orderOut(nil)
        print("Resident window checks passed: close hides to menu bar, workspace reopens")
        print("Capture flow checks passed: immediate clipboard, multi-display mask lifecycle/alpha, outside dismissal, latest crop, toolbar/inside clicks, copy preference, no main window on close/save")
        return true
    }
}
