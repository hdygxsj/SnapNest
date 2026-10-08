import AppKit
import SwiftUI

@MainActor
enum ToolbarVerification {
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
