import AppKit
import SwiftUI
import ShituCore
import UniformTypeIdentifiers

struct CaptureItem: Identifiable, Codable {
    let id: UUID
    let url: URL
    let date: Date
    let kind: String
    var isVideo: Bool { url.pathExtension == "mp4" }
}

enum CaptureMode: String, CaseIterable {
    case area = "区域截图", full = "全屏截图", long = "滚动长截图", record = "全屏录制", regionRecord = "区域录制", gif = "GIF 录制"
}

@MainActor
final class AppModel: ObservableObject {
    enum Phase { case idle, selecting, capturing, scrolling, recording, stopping, editing }
    @Published var phase: Phase = .idle
    @Published var status = "随时捕捉，留住每一处细节。"
    @Published var error: String?
    @Published var audio = UserDefaults.standard.object(forKey: "audio") as? Bool ?? true {
        didSet { UserDefaults.standard.set(audio, forKey: "audio") }
    }
    @Published var copyAfterCapture = UserDefaults.standard.object(forKey: "copyAfterCapture") as? Bool ?? true {
        didSet { UserDefaults.standard.set(copyAfterCapture, forKey: "copyAfterCapture") }
    }
    @Published private var access = ScreenCaptureAccess(preflight: CGPreflightScreenCaptureAccess())
    @Published var checkingPermission = false
    var permission: Bool { access.isAllowed }
    var permissionNeedsRecovery: Bool { access.needsRecovery }
    let permissionInstructions = "macOS 尚未允许当前版本捕获屏幕。请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中，关闭再开启拾图，然后完全退出并重新打开。若仍失败，移除列表中的旧拾图，再添加当前应用。"
    var applicationPath: String { Bundle.main.bundleURL.path }
    @Published var shortcutAvailable = false
    @Published var items: [CaptureItem] = []
    @Published var saveFolder: URL
    @Published var startedAt: Date?
    @Published var frameCount = 0
    @Published var pixelHeight = 0
    var presentEditor: ((CGImage, String, CaptureRegion?) -> Void)?
    var checkForUpdates: (() -> Void)?
    var showMain: (() -> Void)?
    var hideMain: (() -> Void)?
    var showHUD: (() -> Void)?
    var hideHUD: (() -> Void)?
    private let selector = SelectionController()
    private let engine = CaptureEngine()
    private var longCapture: LongCapture?
    private var longTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var gifStopTask: Task<Void, Never>?
    private var recordingURL: URL?
    var busy: Bool { phase != .idle }

    init() {
        if let path = UserDefaults.standard.string(forKey: "saveFolder") {
            saveFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            saveFolder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("拾图", isDirectory: true)
        }
        if let data = UserDefaults.standard.data(forKey: "history"), let saved = try? JSONDecoder().decode([CaptureItem].self, from: data) {
            items = saved.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        }
    }
    func requestPermission() {
        access.updatePreflight(CGRequestScreenCaptureAccess())
        if access.preflight { checkPermission() }
        else { error = permissionInstructions; openPrivacySettings() }
    }
    func checkPermission() {
        guard !checkingPermission, !busy else { return }
        checkingPermission = true
        Task {
            defer { checkingPermission = false }
            guard CGPreflightScreenCaptureAccess() else {
                access.updatePreflight(false)
                error = permissionInstructions
                status = "屏幕录制尚未授权"
                return
            }
            do {
                try await engine.verifyPermission()
                access.verified()
                error = nil
                status = "权限检查通过，可以开始截图或录屏"
            } catch { fail(error) }
        }
    }
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
    func revealApplication() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    func quitForPermission() { guard !busy else { return }; NSApp.terminate(nil) }
    func refreshPermission() { access.updatePreflight(CGPreflightScreenCaptureAccess()) }
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "保存到这里"
        if panel.runModal() == .OK, let url = panel.url {
            saveFolder = url
            UserDefaults.standard.set(url.path, forKey: "saveFolder")
        }
    }
    func revealFolder() {
        do { try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true); NSWorkspace.shared.open(saveFolder) }
        catch { fail(error) }
    }
    func hotKeyPressed() {
        if phase == .scrolling || phase == .recording { stop() }
        else if !busy { begin(.area) }
    }
    func begin(_ mode: CaptureMode) {
        guard !busy, !checkingPermission else { return }
        refreshPermission()
        guard permission else {
            showMain?()
            error = permissionInstructions
            if permissionNeedsRecovery { openPrivacySettings() } else { requestPermission() }
            return
        }
        error = nil
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        hideMain?()
        if mode == .full || mode == .record {
            guard let screen, let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                fail(CaptureFailure(message: "没有可用的显示器。")); return
            }
            launch(mode, region: CaptureRegion(displayID: number.uint32Value, screenFrame: screen.frame, rect: screen.frame, scale: screen.backingScaleFactor))
        } else {
            phase = .selecting
            status = "拖动框选区域，Esc 取消"
            selector.select(instruction: mode == .long ? "框选滚动正文，避开固定栏 · 缓慢下滚 · ⌘⇧X 保存" : "拖动选择区域 · Esc 取消") { [weak self] region in
                guard let self else { return }
                guard let region else { self.reset(); self.hideMain?(); return }
                self.launch(mode, region: region)
            }
        }
    }
    private func launch(_ mode: CaptureMode, region: CaptureRegion) {
        phase = .capturing
        captureTask = Task {
            do {
                // Let selection and app windows leave the compositor before capture.
                try await Task.sleep(for: .milliseconds(250))
                if mode == .record || mode == .regionRecord || mode == .gif {
                    status = "即将开始录屏…"
                    showHUD?()
                    for second in (1...3).reversed() {
                        status = "\(second) 秒后开始录屏"
                        try await Task.sleep(for: .seconds(1))
                    }
                    let url = mode == .gif
                        ? FileManager.default.temporaryDirectory.appendingPathComponent("Shitu-GIF-\(UUID().uuidString).mp4")
                        : try destination(extension: "mp4")
                    recordingURL = url
                    engine.recordingFinished = { [weak self] result in
                        guard let self else { return }
                        self.gifStopTask?.cancel(); self.gifStopTask = nil
                        self.recordingURL = nil
                        switch result {
                        case .success:
                            guard FileManager.default.fileExists(atPath: url.path) else {
                                self.fail(CaptureFailure(message: "录屏文件未生成，请重试。")); return
                            }
                            if mode == .gif {
                                self.phase = .stopping; self.status = "正在导出 GIF…"
                                Task {
                                    defer { try? FileManager.default.removeItem(at: url) }
                                    do {
                                        let output = try self.destination(extension: "gif")
                                        try await GIFExporter.export(video: url, to: output) { [weak self] progress in
                                            Task { @MainActor in
                                                if self?.phase == .stopping { self?.status = "正在导出 GIF · \(Int(progress * 100))%" }
                                            }
                                        }
                                        self.addItem(output, kind: "GIF 录制")
                                        self.status = "GIF 已保存"
                                        self.reset(keepStatus: true); self.showMain?()
                                    } catch { self.fail(error) }
                                }
                            } else {
                                self.addItem(url, kind: mode.rawValue)
                                self.status = "录屏已保存"
                                self.reset(keepStatus: true); self.showMain?()
                            }
                        case .failure(let error):
                            if mode == .gif { try? FileManager.default.removeItem(at: url) }
                            self.fail(error)
                        }
                    }
                    try await engine.startRecording(region, audio: mode == .gif ? false : audio, to: url, gif: mode == .gif)
                    if Task.isCancelled {
                        phase = .stopping
                        try await engine.stopRecording()
                        return
                    }
                    guard recordingURL != nil, phase == .capturing else { return }
                    phase = .recording; startedAt = Date()
                    status = mode == .gif ? "GIF · 最长 30 秒 · ⌘⇧X 结束" : "正在录屏 · ⌘⇧X 结束"
                    if mode == .gif {
                        gifStopTask = Task { [weak self] in
                            do { try await Task.sleep(for: .seconds(GIFExporter.maximumDuration)) }
                            catch { return }
                            if self?.phase == .recording { self?.stop() }
                        }
                    }
                } else if mode == .long {
                    let session = LongCapture()
                    longCapture = session
                    let first = try await engine.screenshot(region)
                    try Task.checkCancellation()
                    _ = try await session.append(first)
                    phase = .scrolling; frameCount = 1; pixelHeight = first.height
                    status = "缓慢向下滚动，每次不超过半屏"
                    showHUD?()
                    longTask = Task { [weak self] in
                        guard let self else { return }
                        while !Task.isCancelled && self.phase == .scrolling {
                            do {
                                try await Task.sleep(for: .milliseconds(850))
                                let image = try await self.engine.screenshot(region)
                                guard !Task.isCancelled else { break }
                                let result = try await session.append(image)
                                guard self.phase == .scrolling else { break }
                                switch result {
                                case .added(let count, let height):
                                    self.frameCount = count; self.pixelHeight = height
                                    self.status = "已拼接 \(count) 帧 · \(height) px"
                                case .duplicate: break
                                case .unmatched: self.status = "未对齐：请稍向上回滚，再缓慢向下"
                                case .limit: self.status = "达到长度上限，正在保存"; self.stop(); return
                                }
                            } catch is CancellationError { break }
                            catch { self.fail(error); break }
                        }
                    }
                } else {
                    let image = try await engine.screenshot(region)
                    try Task.checkCancellation()
                    edit(image, kind: mode.rawValue, region: region)
                }
            } catch is CancellationError { reset(); hideMain?() }
            catch { fail(error) }
        }
    }
    func stop() {
        if phase == .capturing { captureTask?.cancel(); return }
        guard phase == .recording || phase == .scrolling else { return }
        let wasRecording = phase == .recording
        phase = .stopping; status = "正在保存，请稍候…"
        if wasRecording {
            Task {
                do { try await engine.stopRecording() }
                catch { fail(error) }
            }
        } else {
            let task = longTask
            task?.cancel()
            let session = longCapture
            Task {
                await task?.value
                do {
                    guard let session else { throw CaptureFailure(message: "没有可保存的长截图。") }
                    let image = try await session.result()
                    longCapture = nil; longTask = nil
                    hideHUD?()
                    edit(image, kind: "滚动长截图", region: nil)
                } catch { fail(error) }
            }
        }
    }
    func openDemoEditor() {
        guard let screen = NSScreen.main, let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        hideMain?()
        let demoRect = CGRect(x: screen.frame.midX - 300, y: screen.frame.midY - 180, width: 600, height: 360)
        let region = CaptureRegion(displayID: id.uint32Value, screenFrame: screen.frame, rect: demoRect, scale: screen.backingScaleFactor)
        edit(EditorVerification.fixture(), kind: "编辑器示例", region: region)
    }
    private func edit(_ image: CGImage, kind: String, region: CaptureRegion?) {
        phase = .editing
        status = "编辑截图，或使用同一区域继续捕捉"
        presentEditor?(image, kind, region)
    }
    func saveEdited(_ image: CGImage, kind: String) -> Bool {
        do {
            try saveImage(image, kind: kind)
            reset(keepStatus: true); hideMain?()
            return true
        } catch { self.error = error.localizedDescription; showMain?(); return false }
    }
    func closeEditor() { reset(); hideMain?() }
    func switchFromEditor(_ mode: CaptureMode, region: CaptureRegion) {
        guard phase == .editing else { return }
        refreshPermission()
        guard permission else {
            reset()
            error = "请先在系统设置中授权屏幕录制，再开始捕捉。"
            showMain?(); return
        }
        hideMain?()
        launch(mode, region: region)
    }
    private func destination(extension suffix: String) throws -> URL {
        try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return saveFolder.appendingPathComponent("拾图_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(4)).\(suffix)")
    }
    private func saveImage(_ image: CGImage, kind: String) throws {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CaptureFailure(message: "PNG 编码失败。") }
        let url = try destination(extension: "png")
        try data.write(to: url, options: .atomic)
        if copyAfterCapture {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: .zero)])
        }
        addItem(url, kind: kind)
        status = copyAfterCapture ? "截图已保存，并复制到剪贴板" : "截图已保存"
    }
    private func addItem(_ url: URL, kind: String) {
        items.insert(CaptureItem(id: UUID(), url: url, date: Date(), kind: kind), at: 0)
        items = Array(items.prefix(30))
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: "history") }
    }
    func editExisting(_ item: CaptureItem) {
        guard !busy, item.url.pathExtension == "png", let image = NSImage(contentsOf: item.url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        hideMain?()
        edit(image, kind: "编辑截图", region: nil)
    }
    func copy(_ item: CaptureItem) {
        guard !item.isVideo, let image = NSImage(contentsOf: item.url) else { return }
        NSPasteboard.general.clearContents()
        if item.url.pathExtension == "gif", let data = try? Data(contentsOf: item.url) {
            NSPasteboard.general.writeObjects([item.url as NSURL])
            NSPasteboard.general.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
        } else { NSPasteboard.general.writeObjects([image]) }
        status = "已复制到剪贴板"
    }
    func reveal(_ item: CaptureItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
    func preview(_ item: CaptureItem) { NSWorkspace.shared.open(item.url) }
    private func reset(keepStatus: Bool = false) {
        phase = .idle; startedAt = nil
        hideHUD?()
        if !keepStatus { status = "随时捕捉，留住每一处细节。" }
    }
    private func fail(_ error: Error) {
        gifStopTask?.cancel(); gifStopTask = nil
        longTask?.cancel(); longTask = nil; longCapture = nil
        if ScreenCaptureAccess.isPermissionError(error) {
            access.denied()
            self.error = permissionInstructions
            status = "屏幕捕获权限被系统拒绝，需要重新授权"
        } else {
            self.error = error.localizedDescription
            status = "操作未完成，请查看提示"
        }
        reset(keepStatus: true); showMain?()
    }
}
