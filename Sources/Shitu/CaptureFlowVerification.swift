import AppKit

@MainActor
enum CaptureFlowVerification {
    static func run() -> Bool {
        _ = NSApplication.shared
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
        editor.show(image: EditorVerification.fixture(), region: nil, save: { _ in true }, switchMode: { _ in }, closed: { closedCount += 1 })
        guard NSImage(pasteboard: board) != nil else {
            print("FAIL screenshot must be on clipboard before Save or Copy")
            return false
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
        let copied = NSImage(pasteboard: board)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        guard closedCount == 1, copied?.width == 120, copied?.height == 90, !canvasWindow.isVisible else {
            print("FAIL outside click must close and copy the latest edited image"); return false
        }
        editor.handleOutsideClick(at: .zero)
        guard closedCount == 1 else { print("FAIL repeated completion"); return false }
        board.clearContents()
        board.setString("keep clipboard", forType: .string)
        editor.show(image: EditorVerification.fixture(), region: nil, automaticallyCopy: false,
                    save: { _ in true }, switchMode: { _ in }, closed: {})
        editor.handleOutsideClick(at: CGPoint(x: -100000, y: -100000))
        guard board.string(forType: .string) == "keep clipboard" else {
            print("FAIL explicit automatic-copy preference was ignored"); return false
        }
        let model = AppModel()
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
        print("Capture flow checks passed: immediate clipboard, outside dismissal, latest crop, toolbar/inside clicks, copy preference, no main window on close/save")
        return true
    }
}
