import AppKit
import SwiftUI

@MainActor
enum ToolbarVerification {
    static func renderHUD(to path: String) -> Bool {
        _ = NSApplication.shared
        let model = AppModel()
        model.phase = .paused; model.startedAt = Date(); model.status = "已暂停 · 可继续或结束保存"
        let view = NSHostingView(rootView: CaptureHUD(model: model))
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 382, height: 78), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        view.frame = CGRect(x: 0, y: 0, width: 382, height: 78)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: URL(fileURLWithPath: path)); return true } catch { print(error); return false }
    }
    static func render(to path: String) -> Bool {
        _ = NSApplication.shared
        let document = EditorDocument(image: EditorVerification.fixture())
        let view = NSHostingView(rootView: FloatingEditorToolbar(document: document, canSwitch: true,
            save: {}, copy: {}, switchMode: { _ in }, close: {}))
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 520, height: 88), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        view.frame = CGRect(x: 0, y: 0, width: 520, height: 88)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: URL(fileURLWithPath: path)); print("Toolbar rendered: \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)"); return true }
        catch { print(error); return false }
    }
}
