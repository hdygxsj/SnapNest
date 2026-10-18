import AppKit
import ImageIO

@MainActor enum TutorialVerification {
    static func run() throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QingyuTutorialCheck-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "TutorialVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let context = CGContext(data: nil, width: 160, height: 90, bitsPerComponent: 8, bytesPerRow: 640, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
        let image = context.makeImage()!
        let store = TutorialStore(root: root)
        let first = try store.create(title: "教程一")
        try store.add(image, project: first); try store.add(image, project: first)
        let step = store.selected!.steps[0]
        try store.caption(first, step: step.id, text: "检查文字")
        try store.move(first, step: step.id, offset: 1)
        try check(store.selected!.steps[1].id == step.id, "Reordering lost step identity")
        var captureRequested = false
        store.requestCapture = { captureRequested = true }
        store.beginCapture()
        let second = try store.create(title: "教程二")
        store.acceptCapture(image)
        try check(captureRequested && store.projects.first!.steps.count == 3 && store.selectedID == second, "Capture target changed with selection")
        store.selectedID = first
        store.beginCapture(); store.cancelCapture(); store.acceptCapture(image)
        try check(store.projects.first!.steps.count == 3, "Cancelled capture added a step")
        let reload = TutorialStore(root: root)
        try check(reload.projects.count == 2 && reload.projects[0].steps[1].caption == "检查文字", "Persistence failed")
        let png = root.appendingPathComponent("result.png"), pdf = root.appendingPathComponent("result.pdf")
        try store.export(first, to: png, pdf: false); try store.export(first, to: pdf, pdf: true)
        try check(CGImageSourceCreateWithURL(png as CFURL, nil) != nil, "PNG export invalid")
        try check(CGPDFDocument(pdf as CFURL)?.numberOfPages == 3, "PDF page count invalid")
        var denied = false
        try store.remove(first, step: step.id)
        try check(!FileManager.default.fileExists(atPath: root.appendingPathComponent(step.imageFile).path), "Removed image leaked")
        let remaining = store.projects[0].steps[0]
        try store.caption(first, step: remaining.id, text: String(repeating: "换行\n", count: 100))
        denied = false
        do { try store.export(first, to: pdf, pdf: true) } catch { denied = true }
        try check(denied, "Overflowing caption silently clipped")
        try store.caption(first, step: remaining.id, text: "")
        let missingStep = store.projects[0].steps[0]
        try FileManager.default.removeItem(at: root.appendingPathComponent(missingStep.imageFile))
        denied = false
        do { try store.export(first, to: pdf, pdf: true) } catch { denied = true }
        try check(denied, "Missing image silently exported")
        // A nearly flat image must still receive a positive image drawing region.
        let stripContext = CGContext(data: nil, width: 1200, height: 1, bitsPerComponent: 8, bytesPerRow: 4800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        stripContext.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        stripContext.fill(CGRect(x: 0, y: 0, width: 1200, height: 1))
        let stripProject = try store.create(title: "Thin strip")
        try store.add(stripContext.makeImage()!, project: stripProject)
        let stripURL = root.appendingPathComponent("strip.png")
        try store.export(stripProject, to: stripURL, pdf: false)
        let stripSource = CGImageSourceCreateWithURL(stripURL as CFURL, nil)!
        let exportedStrip = CGImageSourceCreateImageAtIndex(stripSource, 0, nil)!
        var rgba = [UInt8](repeating: 0, count: exportedStrip.width * exportedStrip.height * 4)
        rgba.withUnsafeMutableBytes { bytes in
            let decoded = CGContext(data: bytes.baseAddress, width: exportedStrip.width, height: exportedStrip.height, bitsPerComponent: 8, bytesPerRow: exportedStrip.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            decoded.draw(exportedStrip, in: CGRect(x: 0, y: 0, width: exportedStrip.width, height: exportedStrip.height))
        }
        let coloredPixels = stride(from: 0, to: rgba.count, by: 4).filter { rgba[$0] > 180 && rgba[$0 + 1] < 180 && rgba[$0 + 2] < 180 }.count
        try check(coloredPixels > 500, "Thin image strip disappeared from PNG export")
        let pngBeforeOverflow = try Data(contentsOf: png)
        let pdfBeforeOverflow = try Data(contentsOf: pdf)
        try store.rename(stripProject, title: String(repeating: "Title line\n", count: 8))
        for (destination, isPDF, original) in [(png, false, pngBeforeOverflow), (pdf, true, pdfBeforeOverflow)] {
            denied = false
            do { try store.export(stripProject, to: destination, pdf: isPDF) } catch { denied = true }
            let retained = try Data(contentsOf: destination)
            try check(denied && retained == original, "Overflowing title exported or replaced existing output")
        }
        let corrupt = root.appendingPathComponent("corrupt")
        try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
        let metadata = corrupt.appendingPathComponent("projects.json")
        let invalid = Data("invalid JSON".utf8)
        try invalid.write(to: metadata)
        let broken = TutorialStore(root: corrupt)
        denied = false
        do { _ = try broken.create() } catch { denied = true }
        let preserved = try Data(contentsOf: metadata)
        try check(denied && preserved == invalid, "Corrupt metadata overwritten")
        return "tutorial: persistence, ordering, capture routing/cancel, PNG/PDF, thin strips, title overflow preservation, free export and missing-image checks passed"
    }
}
