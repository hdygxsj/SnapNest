import AppKit
import SwiftUI

@MainActor
final class PinnedImages: NSObject, NSWindowDelegate {
    static let shared = PinnedImages()
    private(set) var panels: [NSPanel] = []
    @discardableResult func show(_ image: CGImage, near frame: CGRect) -> NSPanel {
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        let available = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 700)
        let ratio = min(1, min((available.width - 40) / CGFloat(image.width), (available.height - 80) / CGFloat(image.height)))
        let size = CGSize(width: max(220, CGFloat(image.width) * ratio), height: max(140, CGFloat(image.height) * ratio + 36))
        let panel = NSPanel(contentRect: CGRect(origin: CGPoint(x: max(available.minX, min(frame.minX, available.maxX - size.width)),
            y: max(available.minY, min(frame.minY, available.maxY - size.height))), size: size),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "SnapNest · 钉图"
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = CGSize(width: 220, height: 140)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: PinnedImageView(image: NSImage(cgImage: image, size: .zero),
            opacityChanged: { [weak panel] in panel?.alphaValue = $0 }, close: { [weak panel] in panel?.close() }))
        panels.append(panel); NSApp.unhide(nil); panel.orderFrontRegardless()
        return panel
    }
    func windowWillClose(_ notification: Notification) {
        panels.removeAll { $0 === notification.object as? NSWindow }
    }
}
private struct PinnedImageView: View {
    let image: NSImage
    var opacityChanged: (Double) -> Void
    var close: () -> Void
    @State private var opacity = 1.0
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image]) } label: { Image(systemName: "doc.on.doc") }.help("复制图片")
                Text("透明度").font(.caption)
                Slider(value: $opacity, in: 0.2...1).onChange(of: opacity) { _, value in opacityChanged(value) }
                Button(action: close) { Image(systemName: "xmark") }.help("关闭钉图")
            }.padding(8)
            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(Color.black.opacity(0.08))
    }
}
