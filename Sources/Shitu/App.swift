import AppKit
import SwiftUI
import Combine
import Carbon

@main
struct ShituApp {
    @MainActor static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-v2"), CommandLine.arguments.count > index + 1 {
            exit(TaskCenterPreview.render(to: CommandLine.arguments[index + 1]) ? 0 : 1)
        }
        if CommandLine.arguments.contains("--verify-v2") {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            Task { exit(await TaskCenterVerification.run() ? 0 : 1) }
            app.run()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-hud"), CommandLine.arguments.count > index + 1 {
            exit(ToolbarVerification.renderHUD(to: CommandLine.arguments[index + 1]) ? 0 : 1)
        }
        if CommandLine.arguments.contains("--verify-recording") {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            Task { exit(await RecordingVerification.run() ? 0 : 1) }
            app.run()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-color-loupe"), CommandLine.arguments.count > index + 1 {
            exit(PixelLoupe.render(to: CommandLine.arguments[index + 1]) ? 0 : 1)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-toolbar"), CommandLine.arguments.count > index + 1 {
            exit(ToolbarVerification.render(to: CommandLine.arguments[index + 1]) ? 0 : 1)
        }
        if CommandLine.arguments.contains("--verify-productivity") { exit(ProductivityVerification.run() ? 0 : 1) }
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
    private let launcherKey = HotKey()
    private let taskKey = HotKey()
    private let launcher = QuickLauncherController.shared
    private let taskCenter = TaskCenterController()
    private let selectedText = SelectedTextCapture()
    private var launcherShortcutAvailable = false
    private let updates = UpdateController()
    private var contextMenu: NSMenu?
    private var updateSubscription: AnyCancellable?
    private var hud: NSPanel?
    private var statusItem: NSStatusItem!
    private var subscription: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        model.presentEditor = { [weak self] image, kind, region in
            guard let self else { return }
            self.editor.show(image: image, region: region, automaticallyCopy: self.model.copyAfterCapture, save: { [weak self] image in
                self?.model.saveEdited(image, kind: kind) ?? false
            }, switchMode: { [weak self] mode, region in
                guard let region else { return }
                self?.model.switchFromEditor(mode, region: region)
            }, closed: { [weak self] in self?.model.closeEditor() })
        }
        editor.regionChanged = { [weak self] in self?.model.rememberRegion($0) }
        model.openLauncher = { [weak self] in self?.showLauncher() }
        model.openTasks = { [weak self] in self?.showTasks() }
        model.openSelectionSettings = { [weak self] in self?.selectionPreferences() }
        selectedText.canCapture = { [weak self] in self?.model.busy == false }
        selectedText.addTask = { [weak self] text in self?.taskCenter.showComposer(text: text) }
        selectedText.start()
        taskCenter.captureContent = AnyView(CaptureWorkspace(model: model))
        taskCenter.settingsContent = AnyView(WorkspaceSettings(model: model, selectedText: selectedText))
        taskCenter.start()
        launcherKey.action = { [weak self] in self?.showLauncher() }
        launcherShortcutAvailable = launcherKey.register(keyCode: UInt32(kVK_Space), identifier: 2)
        launcher.shortcutAvailable = launcherShortcutAvailable
        taskKey.action = { [weak self] in self?.selectedText.capture() }
        if !taskKey.register(keyCode: UInt32(kVK_ANSI_T), identifier: 3) {
            selectedText.shortcutMessage = "⌘⇧T 被其他应用占用。可开启划词按钮，或从菜单栏添加待办。"
        }
        launcher.canLaunchApplication = { [weak self] in self?.model.busy == false }
        launcher.startApplicationShortcuts()
        model.checkForUpdates = { [weak self] in self?.checkUpdates() }
        model.showMain = { [weak self] in self?.showWindow() }
        model.hideMain = { NSApp.hide(nil) }
        model.showHUD = { [weak self] in self?.showHUD() }
        model.hideHUD = { [weak self] in self?.hud?.orderOut(nil) }
        hotKey.action = { [weak self] in self?.model.hotKeyPressed() }
        model.shortcutAvailable = hotKey.register()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "SnapNest")
        statusItem.button?.toolTip = "SnapNest：点击展开快捷面板，右键打开菜单"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleQuickPanel)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateSubscription = updates.$release.sink { [weak self] _ in
            DispatchQueue.main.async { guard let self else { return }; self.updateMenu(self.model.phase) }
        }
        subscription = model.$phase.sink { [weak self] phase in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateMenu(phase)
                self.taskCenter.setCaptureActive(phase != .idle)
                if phase != .idle { self.launcher.hide(); self.selectedText.dismiss() }
            }
        }
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); mainMenu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于SnapNest", action: #selector(about), keyEquivalent: "")
        let updateItem = appMenu.addItem(withTitle: "检查更新…", action: #selector(checkUpdates), keyEquivalent: "")
        updateItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出SnapNest", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = mainMenu
        showWindow()
        updates.checkOnLaunch()
        if CommandLine.arguments.contains("--demo-editor") { model.openDemoEditor() }
    }
    private func updateMenu(_ phase: AppModel.Phase) {
        let active = phase == .recording || phase == .paused || phase == .scrolling
        statusItem.button?.title = phase == .paused ? " SnapNest Ⅱ" : (active ? " SnapNest ●" : (updates.asset == nil ? " SnapNest" : " SnapNest ↑"))
        let menu = NSMenu()
        add("打开SnapNest", action: #selector(showWindow), to: menu)
        add(launcherShortcutAvailable ? "快捷启动  ⌘⇧空格" : "快捷启动（快捷键被占用）", action: #selector(showLauncher), to: menu, enabled: !model.busy)
        add("待办与灵动岛", action: #selector(showTasks), to: menu, enabled: !model.busy)
        add("新增待办…", action: #selector(newTask), to: menu, enabled: !model.busy)
        add("划词添加设置…", action: #selector(selectionPreferences), to: menu, enabled: !model.busy)
        menu.addItem(.separator())
        if active {
            if model.isRecordingSession { add(phase == .paused ? "继续录制" : "暂停录制", action: #selector(toggleRecordingPause), to: menu, enabled: model.canToggleRecording) }
            add(phase == .scrolling ? "结束并编辑  ⌘⇧X" : "结束并保存  ⌘⇧X", action: #selector(stop), to: menu)
        }
        else {
            for (title, action) in [("区域截图  ⌘⇧X", #selector(area)), ("窗口截图", #selector(windowCapture)), ("全屏截图", #selector(full)), ("滚动长截图", #selector(long)), ("全屏录制", #selector(record)), ("区域录制", #selector(regionRecord)), ("GIF 录制", #selector(gif))] {
                add(title, action: action, to: menu, enabled: phase == .idle)
            }
            add("再次截取上次区域", action: #selector(repeatCapture), to: menu, enabled: model.canRepeatCapture)
        }
        menu.addItem(.separator())
        add(updates.asset == nil ? "检查更新…" : "下载新版本…", action: #selector(checkUpdates), to: menu, enabled: !model.busy)
        add("退出SnapNest", action: #selector(quit), to: menu)
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
            statusItem.menu = contextMenu
            button.performClick(nil)
            statusItem.menu = nil
        } else { showWindow() }
    }
    @objc private func showLauncher() {
        guard !model.busy else { return }
        launcher.show()
    }
    @objc private func showTasks() {
        guard !model.busy else { return }
        taskCenter.showTasks()
    }
    @objc private func newTask() {
        guard !model.busy else { return }
        taskCenter.showComposer(text: "")
    }
    @objc private func selectionPreferences() {
        guard !model.busy else { return }
        taskCenter.showPage(.settings)
    }
    @objc private func checkUpdates() {
        guard !model.busy else { return }
        taskCenter.showPage(.settings)
    }
    @objc private func showWindow() {
        if model.phase == .editing { editor.reveal(); return }
        NSApp.setActivationPolicy(.regular)
        taskCenter.showPage(.capture) }
    @objc private func area() { model.begin(.area) }
    @objc private func repeatCapture() { model.begin(.repeatArea) }
    @objc private func windowCapture() { model.begin(.window) }
    @objc private func full() { model.begin(.full) }
    @objc private func long() { model.begin(.long) }
    @objc private func record() { model.begin(.record) }
    @objc private func regionRecord() { model.begin(.regionRecord) }
    @objc private func gif() { model.begin(.gif) }
    @objc private func stop() { model.stop() }
    @objc private func toggleRecordingPause() { model.toggleRecordingPause() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func about() { taskCenter.showPage(.settings) }
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
