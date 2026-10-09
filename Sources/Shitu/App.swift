import AppKit
import SwiftUI
import Combine

@main
struct ShituApp {
    @MainActor static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-toolbar"), CommandLine.arguments.count > index + 1 {
            exit(ToolbarVerification.render(to: CommandLine.arguments[index + 1]) ? 0 : 1)
        }
        if CommandLine.arguments.contains("--verify-capture-flow") {
            exit(CaptureFlowVerification.run() ? 0 : 1)
        }
        if CommandLine.arguments.contains("--verify-editor") {
            exit(EditorVerification.run() ? 0 : 1)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let editor = EditorController()
    private let hotKey = HotKey()
    private let residentWindowDelegate = ResidentWindowDelegate()
    private let updates = UpdateController()
    private let quickPanel = NSPopover()
    private var contextMenu: NSMenu?
    private var updateSubscription: AnyCancellable?
    private var window: NSWindow!
    private var hud: NSPanel?
    private var statusItem: NSStatusItem!
    private var subscription: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 810), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "拾图"
        window.delegate = residentWindowDelegate
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainView(model: model).padding(.top, 22).background(Color(red: 0.055, green: 0.07, blue: 0.09)))
        window.minSize = NSSize(width: 900, height: 720)
        window.center()
        window.setFrameAutosaveName("ShituMainWindow")
        model.presentEditor = { [weak self] image, kind, region in
            guard let self else { return }
            self.editor.show(image: image, region: region, automaticallyCopy: self.model.copyAfterCapture, save: { [weak self] image in
                self?.model.saveEdited(image, kind: kind) ?? false
            }, switchMode: { [weak self] mode in
                guard let region else { return }
                self?.model.switchFromEditor(mode, region: region)
            }, closed: { [weak self] in self?.model.closeEditor() })
        }
        model.checkForUpdates = { [weak self] in self?.checkUpdates() }
        model.showMain = { [weak self] in self?.showWindow() }
        model.hideMain = { [weak self] in self?.window.orderOut(nil); NSApp.hide(nil) }
        model.showHUD = { [weak self] in self?.showHUD() }
        model.hideHUD = { [weak self] in self?.hud?.orderOut(nil) }
        hotKey.action = { [weak self] in self?.model.hotKeyPressed() }
        model.shortcutAvailable = hotKey.register()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "拾图")
        statusItem.button?.toolTip = "拾图：点击展开快捷面板，右键打开菜单"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleQuickPanel)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        quickPanel.behavior = .transient
        quickPanel.contentViewController = NSHostingController(rootView: MenuBarPanel(model: model, updates: updates,
            capture: { [weak self] mode in self?.quickPanel.performClose(nil); self?.model.begin(mode) },
            open: { [weak self] in self?.quickPanel.performClose(nil); self?.showWindow() },
            checkUpdates: { [weak self] in self?.quickPanel.performClose(nil); self?.checkUpdates() },
            quit: { [weak self] in self?.quit() },
            stop: { [weak self] in self?.quickPanel.performClose(nil); self?.model.stop() }))
        updateSubscription = updates.$release.sink { [weak self] _ in
            DispatchQueue.main.async { guard let self else { return }; self.updateMenu(self.model.phase) }
        }
        subscription = model.$phase.sink { [weak self] phase in
            DispatchQueue.main.async { self?.updateMenu(phase) }
        }
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); mainMenu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于拾图", action: #selector(about), keyEquivalent: "")
        let updateItem = appMenu.addItem(withTitle: "检查更新…", action: #selector(checkUpdates), keyEquivalent: "")
        updateItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出拾图", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = mainMenu
        showWindow()
        updates.checkOnLaunch()
        if CommandLine.arguments.contains("--demo-editor") { model.openDemoEditor() }
    }
    private func updateMenu(_ phase: AppModel.Phase) {
        let active = phase == .recording || phase == .scrolling
        statusItem.button?.title = active ? " 拾图 ●" : (updates.asset == nil ? " 拾图" : " 拾图 ↑")
        let menu = NSMenu()
        add("打开拾图", action: #selector(showWindow), to: menu)
        menu.addItem(.separator())
        if active { add(phase == .scrolling ? "结束并编辑  ⌘⇧X" : "结束并保存  ⌘⇧X", action: #selector(stop), to: menu) }
        else {
            for (title, action) in [("区域截图  ⌘⇧X", #selector(area)), ("全屏截图", #selector(full)), ("滚动长截图", #selector(long)), ("全屏录制", #selector(record)), ("区域录制", #selector(regionRecord)), ("GIF 录制", #selector(gif))] {
                add(title, action: action, to: menu, enabled: phase == .idle)
            }
        }
        menu.addItem(.separator())
        add(updates.asset == nil ? "检查更新…" : "下载新版本…", action: #selector(checkUpdates), to: menu, enabled: !model.busy)
        add("退出拾图", action: #selector(quit), to: menu)
        contextMenu = menu
    }
    private func add(_ title: String, action: Selector, to menu: NSMenu, enabled: Bool = true) {
        menu.autoenablesItems = false
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.isEnabled = enabled; menu.addItem(item)
    }
    private func showHUD() {
        NSApp.unhide(nil)
        if hud == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 382, height: 78), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.contentView = NSHostingView(rootView: CaptureHUD(model: model).clipShape(RoundedRectangle(cornerRadius: 14)))
            hud = panel
        }
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            hud?.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 410, y: screen.visibleFrame.minY + 28))
        }
        hud?.orderFrontRegardless()
    }
    @objc private func toggleQuickPanel() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            quickPanel.performClose(nil)
            statusItem.menu = contextMenu
            button.performClick(nil)
            statusItem.menu = nil
        } else if quickPanel.isShown { quickPanel.performClose(nil) }
        else { quickPanel.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    @objc private func checkUpdates() {
        guard !model.busy else { return }
        updates.checkManually()
    }
    @objc private func showWindow() {
        if model.phase == .editing { editor.reveal(); return }
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    @objc private func area() { model.begin(.area) }
    @objc private func full() { model.begin(.full) }
    @objc private func long() { model.begin(.long) }
    @objc private func record() { model.begin(.record) }
    @objc private func regionRecord() { model.begin(.regionRecord) }
    @objc private func gif() { model.begin(.gif) }
    @objc private func stop() { model.stop() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "拾图", .applicationVersion: updates.currentVersion, .credits: NSAttributedString(string: "截图 · 长截图 · 录屏\n所有内容仅保存在本机")]) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.busy {
            let alert = NSAlert()
            alert.messageText = "正在捕捉中"
            alert.informativeText = "请先保存或关闭截图编辑器、结束录屏或长截图；框选时按 Esc 取消。"
            alert.addButton(withTitle: "继续捕捉")
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }
}
