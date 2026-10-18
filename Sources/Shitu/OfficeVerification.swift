import AppKit
import SwiftUI
import ImageIO

@MainActor enum OfficeVerification {
    static func run() -> Bool {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QingyuOfficeCheck-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        func check(_ value: Bool, _ message: String) throws { if !value { throw OfficeError.message(message) } }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("original.txt")
            try Data("original".utf8).write(to: file)
            let shelf = FileShelfStore(root: root)
            shelf.add([file, file]); try check(shelf.items.count == 1, "Shelf deduplication")
            let reload = FileShelfStore(root: root)
            try check(reload.items.count == 1, "Shelf persistence")
            let id = shelf.items[0].id
            try check(shelf.resolved([id]).count == 1, "Bookmark resolution")
            shelf.remove([id]); try check(shelf.items.isEmpty && FileManager.default.fileExists(atPath: file.path), "Shelf removed original")
            shelf.add([file]); let reference = shelf.items[0]
            _ = try shelf.access.resolve(reference)
            try FileManager.default.removeItem(at: file)
            try check((try? shelf.access.resolve(reference)) == nil, "Stale cached path accepted")
            let scenes = WorkSceneStore(root: root)
            scenes.create("工作"); scenes.add([URL(string: "https://example.com")!, URL(string: "https://example.com")!])
            scenes.add([URL(string: "javascript:alert(1)")!])
            try check(scenes.current?.targets.count == 1, "Scene URL validation/deduplication")
            let scenesReloaded = WorkSceneStore(root: root)
            try check(scenesReloaded.current?.title == "工作" && scenesReloaded.current?.targets.count == 1, "Scene persistence")
            let corruptRoot = root.appendingPathComponent("corrupt")
            try FileManager.default.createDirectory(at: corruptRoot, withIntermediateDirectories: true)
            let corrupt = Data("not json".utf8)
            try corrupt.write(to: corruptRoot.appendingPathComponent("shelf.json"))
            let broken = FileShelfStore(root: corruptRoot); broken.add([root])
            try check(try Data(contentsOf: corruptRoot.appendingPathComponent("shelf.json")) == corrupt, "Corrupt data overwritten")
            let a = fixture(width: 80, height: 60, change: false), b = fixture(width: 80, height: 60, change: true)
            let identical = try ComparisonPixels.difference(a, a, threshold: 0)
            try check(identical.1 == 0, "Identical images differ")
            let different = try ComparisonPixels.difference(a, b, threshold: 0)
            try check(abs(different.1 - 0.25) < 0.001, "Difference pixel ratio")
            try check(try ComparisonPixels.difference(a, b, threshold: 255).1 == 0, "Threshold ignored")
            var rejected = false
            do { _ = try ComparisonPixels.difference(a, fixture(width: 40, height: 40, change: false), threshold: 0) } catch { rejected = true }
            try check(rejected, "Mismatched image dimensions accepted")
            let first = root.appendingPathComponent("first.png"), second = root.appendingPathComponent("second.png")
            try NSBitmapImageRep(cgImage: a).representation(using: .png, properties: [:])!.write(to: first)
            try NSBitmapImageRep(cgImage: b).representation(using: .png, properties: [:])!.write(to: second)
            let comparison = ComparisonStore(); comparison.load(first, first: true); comparison.load(second, first: false)
            comparison.note = "确认差异并检查布局。"
            let report = try comparison.report(); try check(CGImageSourceCreateWithData(report as CFData, nil) != nil, "Invalid report PNG")
            comparison.note = String(repeating: "换行\n", count: 80)
            rejected = false; do { _ = try comparison.report() } catch { rejected = true }; try check(rejected, "Clipped note exported")
            print(try TutorialVerification.run())
            print("Office checks passed: file references, bookmarks, persistence, missing files, original preservation, scene URL validation, free access, pixel difference, threshold, report export and overflow")
            return true
        } catch { print("Office verification failed: \(error)"); return false }
    }
    static func fixture(width: Int = 640, height: Int = 400, change: Bool) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if change { context.setFillColor(NSColor.systemBlue.cgColor); context.fill(CGRect(x: 0, y: 0, width: width/2, height: height/2)) }
        return context.makeImage()!
    }
    static func render(to directory: String) -> Bool {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OfficePreview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let tutorial = TutorialStore(root: root.appendingPathComponent("tutorial"))
            let project = try tutorial.create(title: "报销系统操作教程")
            try tutorial.add(fixture(change: true), project: project)
            try tutorial.caption(project, step: tutorial.selected!.steps[0].id, text: "打开申请页面，检查信息后提交。")
            let shelf = FileShelfStore(root: root)
            let sample = root.appendingPathComponent("报销说明.txt"); try Data("示例资料".utf8).write(to: sample); shelf.add([sample])
            let scenes = WorkSceneStore(root: root); scenes.create("整理周报"); scenes.add([URL(string: "https://example.com")!, root])
            let comparison = ComparisonStore()
            let first = root.appendingPathComponent("修改前.png"), second = root.appendingPathComponent("修改后.png")
            try NSBitmapImageRep(cgImage: fixture(change: false)).representation(using: .png, properties: [:])!.write(to: first)
            try NSBitmapImageRep(cgImage: fixture(change: true)).representation(using: .png, properties: [:])!.write(to: second)
            comparison.load(first, first: true); comparison.load(second, first: false); comparison.note = "检查布局变化。"
            let views: [(String, AnyView)] = [("tutorial", AnyView(TutorialWorkspace(store: tutorial))), ("shelf", AnyView(FileShelfWorkspace(store: shelf))), ("scenes", AnyView(WorkScenesWorkspace(store: scenes))), ("comparison", AnyView(ComparisonWorkspace(store: comparison)))]
            for (name, view) in views { for dark in [false, true] {
                let host = NSHostingView(rootView: view.padding(22).frame(width: 800, height: 500).background(WorkspaceTheme.surface(dark ? .dark : .light)).environment(\.colorScheme, dark ? .dark : .light))
                host.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
                let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw OfficeError.message("Preview bitmap unavailable") }
                host.cacheDisplay(in: host.bounds, to: rep)
                guard let data = rep.representation(using: .png, properties: [:]) else { throw OfficeError.message("Preview PNG unavailable") }
                try data.write(to: output.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            } }
            return true
        } catch { print(error); return false }
    }
}
