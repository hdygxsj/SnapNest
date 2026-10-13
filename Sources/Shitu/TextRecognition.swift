import AppKit
import Vision

enum TextRecognition {
    static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
    @MainActor static func present(_ text: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = text.isEmpty ? "未识别到文字" : "识别文字"
        alert.informativeText = text.isEmpty ? "试试更清晰的截图或更大的文字。" : "已在本机识别，可修改后复制。"
        if text.isEmpty { alert.addButton(withTitle: "关闭"); alert.runModal(); return false }
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 480, height: 280))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let field = NSTextView(frame: scroll.bounds)
        field.string = text; field.font = .systemFont(ofSize: 15)
        field.isRichText = false; field.isVerticallyResizable = true
        field.textContainer?.widthTracksTextView = true
        scroll.documentView = field
        alert.accessoryView = scroll
        alert.addButton(withTitle: "复制文字"); alert.addButton(withTitle: "返回截图")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(field.string, forType: .string)
            return true
        }
        return false
    }
}
