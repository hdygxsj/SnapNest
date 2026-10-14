import AppKit
import SwiftUI
import Combine
import ShituCore

struct EditorCanvas: NSViewRepresentable {
    @ObservedObject var document: EditorDocument
    var cancel: (() -> Void)? = nil
    var save: (() -> Void)? = nil
    var copy: (() -> Void)? = nil
    func makeNSView(context: Context) -> CanvasView { CanvasView(document: document) }
    func updateNSView(_ view: CanvasView, context: Context) { view.document = document; view.cancel = cancel; view.save = save; view.copy = copy; view.needsDisplay = true }
}

@MainActor
final class CanvasView: NSView {
    var document: EditorDocument
    var cancel: (() -> Void)?
    var save: (() -> Void)?
    var copy: (() -> Void)?
    private var draft: Annotation?
    private var pendingText: DispatchWorkItem?
    private var firstClickHistory: EditHistory<EditorSnapshot>?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(document: EditorDocument) { self.document = document; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func resetCursorRects() { addCursorRect(bounds, cursor: document.tool == .text ? .iBeam : .crosshair) }
    private func point(_ event: NSEvent) -> CGPoint {
        let location = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(CGFloat(document.image.width), max(0, location.x * CGFloat(document.image.width) / max(1, bounds.width))),
                       y: min(CGFloat(document.image.height), max(0, location.y * CGFloat(document.image.height) / max(1, bounds.height))))
    }
    override func mouseDown(with event: NSEvent) {
        pendingText?.cancel()
        pendingText = nil
        if event.clickCount == 2 {
            if let firstClickHistory { document.history = firstClickHistory }
            firstClickHistory = nil
            draft = nil
            needsDisplay = true
            copy?()
            return
        }
        firstClickHistory = document.history
        window?.makeFirstResponder(self)
        let p = point(event)
        var annotation = Annotation(tool: document.tool, points: [p], color: NSColor(document.color), lineWidth: document.lineWidth)
        if document.tool == .text {
            // Let a second click copy the screenshot before opening a text dialog.
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.window?.isVisible == true, self.document.tool == .text else { return }
                self.pendingText = nil
                let alert = NSAlert()
                alert.messageText = "添加文字"
                alert.informativeText = "输入标注文字；字号随工具栏中的粗细调整。"
                let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 26))
                input.placeholderString = "在这里输入文字"
                alert.accessoryView = input
                alert.addButton(withTitle: "添加"); alert.addButton(withTitle: "取消")
                alert.window.initialFirstResponder = input
                if alert.runModal() == .alertFirstButtonReturn, !input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    annotation.text = input.stringValue
                    self.document.add(annotation)
                }
            }
            pendingText = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
        } else if document.tool == .number {
            document.add(annotation)
            needsDisplay = true
        } else { draft = annotation; needsDisplay = true }
    }
    override func mouseDragged(with event: NSEvent) {
        guard var annotation = draft else { return }
        if annotation.tool == .pen { annotation.points.append(point(event)) }
        else { annotation.points = [annotation.points[0], point(event)] }
        draft = annotation; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard var annotation = draft else { return }
        draft = nil
        if annotation.tool == .crop { document.crop(annotation.rect) }
        else if annotation.tool == .mosaic {
            if annotation.rect.width >= 3 && annotation.rect.height >= 3 {
                annotation.patch = document.pixelated(annotation.rect)
                if annotation.patch != nil { document.add(annotation) }
            }
        } else if annotation.tool == .pen || annotation.rect.width + annotation.rect.height > 3 { document.add(annotation) }
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        firstClickHistory = nil
        if event.keyCode == 53 {
            pendingText?.cancel(); pendingText = nil
            if draft != nil { draft = nil; needsDisplay = true } else { cancel?() }
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" { copy?(); return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "s" { save?(); return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            if event.modifierFlags.contains(.shift) { document.redo() } else { document.undo() }
        } else { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        NSImage(cgImage: document.image, size: NSSize(width: document.image.width, height: document.image.height))
            .draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); context.scaleBy(x: bounds.width / CGFloat(document.image.width), y: bounds.height / CGFloat(document.image.height))
        for annotation in document.history.current.annotations { EditorDocument.draw(annotation, in: context) }
        if let draft { EditorDocument.draw(draft, in: context) }
        context.restoreGState()
    }
}

/// Only the controls live in this panel; the image stays over its original screen region.
struct FloatingEditorToolbar: View {
    @ObservedObject var document: EditorDocument
    let canSwitch: Bool
    var save: () -> Void
    var copy: () -> Void
    var switchMode: (CaptureMode) -> Void
    var close: () -> Void
    var pin: () -> Void = {}
    var recognize: () -> Void = {}
    var adjust: () -> Void = {}
    static let size = CGSize(width: 520, height: 88)
    private let colors: [(String, Color)] = [("红色", .red), ("橙色", .orange), ("黄色", .yellow), ("绿色", .green), ("蓝色", .blue), ("白色", .white), ("黑色", .black)]
    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                ForEach(EditorTool.allCases, id: \.self) { tool in
                    Button { document.tool = tool } label: {
                        Group {
                            if tool == .text { Text("T").font(.system(size: 16, weight: .semibold, design: .serif)) }
                            else { Image(systemName: tool.icon).font(.system(size: 14)) }
                        }.frame(width: 28, height: 28)
                            .foregroundStyle(document.tool == tool ? Color.mint : Color.primary)
                            .background(document.tool == tool ? Color.mint.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain).help(tool.rawValue).accessibilityLabel(tool.rawValue)
                }
                Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 18).padding(.horizontal, 4)
                Menu {
                    ForEach(colors, id: \.0) { name, color in
                        Button(name) { document.color = color }
                    }
                } label: {
                    Image(systemName: "circle.fill").foregroundStyle(document.color).font(.system(size: 15))
                        .frame(width: 28, height: 28)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 28)
                    .overlay(Circle().fill(document.color).frame(width: 14, height: 14).allowsHitTesting(false)).help("标注颜色").accessibilityLabel("标注颜色")
                Menu {
                    Button("细 · 2 px") { document.lineWidth = 2 }
                    Button("中 · 4 px") { document.lineWidth = 4 }
                    Button("粗 · 8 px") { document.lineWidth = 8 }
                } label: {
                    Image(systemName: "line.3.horizontal").font(.system(size: 14))
                        .frame(width: 28, height: 28)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 28).help("线条粗细").accessibilityLabel("线条粗细")
                iconButton("arrow.uturn.backward", help: "撤销 ⌘Z", action: document.undo)
                    .disabled(!document.history.canUndo).keyboardShortcut("z", modifiers: .command)
                iconButton("arrow.uturn.forward", help: "重做 ⌘⇧Z", action: document.redo)
                    .disabled(!document.history.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
                Spacer(minLength: 0)
                Text("\(document.image.width) × \(document.image.height)")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8).frame(width: 76, alignment: .trailing)
            }.frame(height: 28)
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            HStack(spacing: 6) {
                if canSwitch {
                    actionButton("录屏", icon: "record.circle", width: 66) { switchMode(.regionRecord) }.help("继续录制原选区")
                    actionButton("GIF", icon: "livephoto", width: 62) { switchMode(.gif) }.help("继续录制原选区为 GIF")
                    actionButton("长截图", icon: "arrow.down.to.line", width: 78) { switchMode(.long) }.help("继续拼接原选区")
                } else {
                    iconButton("minus.magnifyingglass", help: "缩小") { document.zoom = max(0.05, document.zoom / 1.25) }
                    iconButton("plus.magnifyingglass", help: "放大") { document.zoom = min(3, document.zoom * 1.25) }
                }
                Spacer(minLength: 0)
                iconButton("pin", help: "钉在屏幕上", action: pin)
                iconButton("text.viewfinder", help: document.isRecognizing ? "正在识别文字…" : "识别文字", action: recognize).disabled(document.isRecognizing)
                if canSwitch { iconButton("arrow.up.left.and.arrow.down.right", help: "调整选区", action: adjust) }
                iconButton("xmark", help: "取消 Esc", action: close).keyboardShortcut(.cancelAction)
                actionButton("复制", icon: "doc.on.doc", width: 62, action: copy).keyboardShortcut("c", modifiers: .command)
                actionButton("保存", icon: "checkmark", width: 62, prominent: true, action: save).keyboardShortcut("s", modifiers: .command)
            }.frame(height: 28)
        }.padding(.horizontal, 10).padding(.vertical, 10)
            .frame(width: Self.size.width, height: Self.size.height)
            .background(Color(red: 0.12, green: 0.14, blue: 0.16), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.16)))
            .preferredColorScheme(.dark)
    }
    private func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13)).frame(width: 28, height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
    private func actionButton(_ title: String, icon: String, width: CGFloat, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) { Image(systemName: icon); Text(title).lineLimit(1).fixedSize() }
                .font(.system(size: 11, weight: .medium)).frame(width: width, height: 28)
                .foregroundStyle(prominent ? Color.black : Color.primary)
                .background(prominent ? Color.mint : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain)
    }
}

private final class FloatingCanvasWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class EditorController {
    var regionChanged: ((CaptureRegion) -> Void)?
    private let backdrop = EditorBackdrop()
    private let adjustmentSelector = SelectionController()
    private var adjustmentActive = false
    private var canvasWindow: NSWindow?
    private var toolbarPanel: NSPanel?
    private var layoutSubscription: AnyCancellable?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var automaticallyCopy = true
    private var onClose: (() -> Void)?
    private var document: EditorDocument?
    private var originalRegion: CaptureRegion?
    private var originalFrame: CGRect = .zero
    private var visibleScreen: CGRect = .zero

    func show(image: CGImage, region: CaptureRegion?, automaticallyCopy: Bool = true, save: @escaping (CGImage) -> Bool,
              switchMode: @escaping (CaptureMode, CaptureRegion?) -> Void, closed: @escaping () -> Void) {
        dismiss()
        let document = EditorDocument(image: image)
        self.document = document
        self.automaticallyCopy = automaticallyCopy
        if automaticallyCopy { copyToClipboard(image) }
        originalRegion = region // Immutable screen capture target; never derive it from toolbar/canvas windows.
        onClose = closed
        let screen = NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return id.uint32Value == region?.displayID
        } ?? NSScreen.main
        visibleScreen = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        if let region {
            originalFrame = region.rect
            document.zoom = region.rect.width / CGFloat(image.width)
        } else {
            let width: CGFloat = min(CGFloat(image.width) * CGFloat(document.zoom), visibleScreen.width - 80)
            let height: CGFloat = min(CGFloat(image.height) * CGFloat(document.zoom), visibleScreen.height - 160)
            originalFrame = CGRect(x: visibleScreen.midX - width / 2, y: visibleScreen.midY - height / 2 + 40, width: width, height: height)
        }
        let finish: () -> Void = { [weak self] in
            guard let self, let rendered = document.render() else { return }
            // Close the editor without bringing the app window back.
            self.backdrop.hide()
            self.canvasWindow?.orderOut(nil); self.toolbarPanel?.orderOut(nil)
            if save(rendered) { self.dismiss() } else { self.reveal() }
        }
        let copy: () -> Void = { [weak self] in
            guard let self, let rendered = document.render() else { return }
            self.copyToClipboard(rendered)
            self.cancel()
        }
        let close: () -> Void = { [weak self] in self?.cancel() }
        let canvas = FloatingCanvasWindow(contentRect: originalFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        canvas.title = "SnapNest · 选区"
        canvas.isReleasedWhenClosed = false
        canvas.level = .floating
        canvas.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        canvas.isMovable = false
        canvas.hasShadow = false
        if region != nil {
            canvas.contentView = NSHostingView(rootView: EditorCanvas(document: document, cancel: close, save: finish, copy: copy)
                .overlay(Rectangle().stroke(Color.mint, lineWidth: 1).allowsHitTesting(false)))
        } else {
            canvas.contentView = NSHostingView(rootView: ScrollView([.horizontal, .vertical]) {
                EditorCanvas(document: document, cancel: close, save: finish, copy: copy)
                    .frame(width: Double(document.image.width) * document.zoom, height: Double(document.image.height) * document.zoom)
            })
        }
        canvasWindow = canvas
        let toolbar = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        toolbar.title = "SnapNest · 选区工具条"
        toolbar.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        toolbar.hidesOnDeactivate = false
        toolbar.isFloatingPanel = true
        toolbar.isMovableByWindowBackground = true
        toolbar.isOpaque = false; toolbar.backgroundColor = .clear
        toolbar.hasShadow = true
        toolbar.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let toolbarHost = NSHostingView(rootView: FloatingEditorToolbar(document: document, canSwitch: region != nil,
            save: finish, copy: copy, switchMode: { [weak self] mode in
                let target = self?.originalRegion
                self?.dismiss()
                switchMode(mode, target)
            }, close: close, pin: { [weak self] in
                guard let self, let image = document.render() else { return }
                let frame = self.canvasWindow?.frame ?? .zero
                self.cancel()
                PinnedImages.shared.show(image, near: frame)
            }, recognize: { [weak self] in self?.recognizeText() }, adjust: { [weak self] in
                self?.adjustSelection(save: save, switchMode: switchMode, closed: closed)
            }))
        toolbarHost.sizingOptions = []
        toolbarHost.frame = CGRect(origin: .zero, size: FloatingEditorToolbar.size)
        toolbar.contentView = toolbarHost
        toolbarPanel = toolbar
        layoutSubscription = document.$history.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.updateLayout() }
        }
        updateLayout()
        reveal()
        installOutsideClickMonitors()
    }
    private func updateLayout() {
        guard let document, let canvasWindow else { return }
        if originalRegion != nil {
            let crop = CGRect(origin: document.history.current.cropOrigin, size: CGSize(width: document.image.width, height: document.image.height))
            let frame = FloatingEditorLayout.canvas(selection: originalFrame,
                originalPixels: CGSize(width: document.initialWidth, height: document.initialHeight), crop: crop)
            canvasWindow.setFrame(frame, display: true)
        }
        backdrop.update(selection: canvasWindow.frame)
        toolbarPanel?.setFrame(FloatingEditorLayout.toolbar(selection: canvasWindow.frame, visibleScreen: visibleScreen, size: FloatingEditorToolbar.size), display: true)
    }
    func reveal() {
        NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true)
        if let canvasWindow { backdrop.show(selection: canvasWindow.frame) }
        canvasWindow?.makeKeyAndOrderFront(nil)
        toolbarPanel?.orderFrontRegardless()
    }
    private func recognizeText() {
        guard let document, !document.isRecognizing, let image = document.render() else { return }
        document.isRecognizing = true
        Task { [weak self] in
            do {
                let text = try await Task.detached(priority: .userInitiated) { try TextRecognition.recognize(image) }.value
                guard let self, self.document === document else { return }
                document.isRecognizing = false
                if TextRecognition.present(text) {
                    let callback = self.onClose
                    self.dismiss()
                    callback?()
                }
            } catch {
                guard let self, self.document === document else { return }
                document.isRecognizing = false
                let alert = NSAlert(); alert.messageText = "文字识别失败"
                alert.informativeText = error.localizedDescription; alert.runModal()
            }
        }
    }
    private func adjustSelection(save: @escaping (CGImage) -> Bool,
        switchMode: @escaping (CaptureMode, CaptureRegion?) -> Void, closed: @escaping () -> Void) {
        guard let region = originalRegion, !adjustmentActive else { return }
        if let document, document.history.canUndo {
            let alert = NSAlert(); alert.messageText = "重新调整截图区域？"
            alert.informativeText = "确认后会重新截图，替换当前标注和裁剪；取消调整可返回当前截图。"
            alert.addButton(withTitle: "调整选区"); alert.addButton(withTitle: "返回")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        adjustmentActive = true
        backdrop.hide(); canvasWindow?.orderOut(nil); toolbarPanel?.orderOut(nil)
        adjustmentSelector.select(initialRegion: region) { [weak self] target in
            guard let self else { return }
            guard let target else { self.adjustmentActive = false; self.reveal(); return }
            Task { [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(200))
                    let image = try await CaptureEngine().screenshot(target)
                    guard let self else { return }
                    self.adjustmentActive = false
                    self.regionChanged?(target)
                    self.show(image: image, region: target, automaticallyCopy: self.automaticallyCopy,
                              save: save, switchMode: switchMode, closed: closed)
                } catch {
                    guard let self else { return }
                    self.adjustmentActive = false; self.reveal()
                    let alert = NSAlert(); alert.messageText = "无法重新截图"; alert.informativeText = error.localizedDescription; alert.runModal()
                }
            }
        }
    }
    private func copyToClipboard(_ image: CGImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: .zero)])
    }
    private func installOutsideClickMonitors() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.handleOutsideClick(at: NSEvent.mouseLocation)
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, NSApp.modalWindow == nil else { return event }
            // Menus and annotation dialogs belong to the editing session, even outside the selection.
            if let window = event.window,
               window === self.canvasWindow || window === self.toolbarPanel || window.level >= .popUpMenu {
                return event
            }
            self.handleOutsideClick(at: NSEvent.mouseLocation)
            return event
        }
    }
    func handleOutsideClick(at point: CGPoint) {
        guard !adjustmentActive, let canvasWindow, let toolbarPanel, NSApp.modalWindow == nil,
              !canvasWindow.frame.contains(point), !toolbarPanel.frame.contains(point) else { return }
        cancel()
    }
    private func cancel() {
        if automaticallyCopy, let rendered = document?.render() { copyToClipboard(rendered) }
        let callback = onClose
        dismiss()
        callback?()
    }
    private func dismiss() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        outsideClickMonitor = nil; localClickMonitor = nil
        layoutSubscription = nil
        backdrop.dismiss()
        canvasWindow?.orderOut(nil); toolbarPanel?.orderOut(nil)
        canvasWindow = nil; toolbarPanel = nil; document = nil
        onClose = nil; originalRegion = nil
    }
}
