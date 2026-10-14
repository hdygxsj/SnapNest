import AppKit
import SwiftUI
import ShituCore
import CryptoKit

@MainActor
final class UpdateController: ObservableObject {
    static let isPrivateEdition = true
    static let releasesURL = URL(string: "https://github.com/hdygxsj/SnapNest/releases")!
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0"
    @Published var automaticallyCheck = UserDefaults.standard.object(forKey: "automaticallyCheckUpdates") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automaticallyCheck, forKey: "automaticallyCheckUpdates") }
    }
    @Published private(set) var status = "2.0 私有版本，尚未配置更新渠道。"
    @Published private(set) var busy = false
    @Published private(set) var release: AppRelease?
    @Published private(set) var downloadedURL: URL?
    private var window: NSWindow?
    var asset: AppRelease.Asset? { release?.updateAsset(currentVersion: currentVersion) }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "拾图 · 版本更新"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: UpdateView(updates: self))
            window.center()
            self.window = window
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    func checkManually() {
        show()
        Task { await check() }
    }
    func checkOnLaunch() {
        guard !Self.isPrivateEdition, automaticallyCheck,
              Date().timeIntervalSince(UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast) > 86400 else { return }
        Task { await check() }
    }
    func check() async {
        guard !Self.isPrivateEdition else { status = "2.0 私有版本，更新由开发者提供安装包。"; return }
        guard !busy else { return }
        busy = true
        status = "正在检查更新…"
        defer { busy = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/hdygxsj/SnapNest/releases/latest")!)
            request.timeoutInterval = 20
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("SnapNest/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode
            guard code == 200 else {
                if code == 403 || code == 429 { throw CaptureFailure(message: "检查频率受限，请稍后重试，或打开发布页查看。") }
                throw CaptureFailure(message: "暂时无法获取版本信息，请重试或打开发布页。")
            }
            let result = try JSONDecoder().decode(AppRelease.self, from: data)
            release = result
            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
            if result.isNewer(than: currentVersion) {
                status = asset != nil ? "发现新版本 \(result.version)" : "发现新版本 \(result.version)，请到发布页下载安装。"
            } else { status = "当前没有可用更新（\(currentVersion)）。" }
        } catch { status = "检查更新失败：\(error.localizedDescription)" }
    }
    func download() async {
        guard !Self.isPrivateEdition, !busy, let asset else { return }
        busy = true
        status = "正在下载新版，请稍候…"
        defer { busy = false }
        do {
            var request = URLRequest(url: asset.browser_download_url)
            request.timeoutInterval = 120
            let (temporary, response) = try await URLSession.shared.download(for: request)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CaptureFailure(message: "下载失败，请重试。") }
            let data = try Data(contentsOf: temporary, options: .mappedIfSafe)
            guard data.count == asset.size else { throw CaptureFailure(message: "安装包不完整，请重新下载。") }
            if let digest = asset.digest, digest.hasPrefix("sha256:") {
                let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard "sha256:\(actual)" == digest.lowercased() else { throw CaptureFailure(message: "安装包校验失败，请重新下载。") }
            }
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            let folder = downloads.appendingPathComponent("SnapNest-\(UUID().uuidString.prefix(8))", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(asset.name)
            try FileManager.default.moveItem(at: temporary, to: destination)
            downloadedURL = destination
            status = "下载完成。解压后退出拾图，将新版拖入“应用程序”替换旧版，再重新打开。"
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch { status = "下载失败：\(error.localizedDescription)" }
    }
}

struct UpdateView: View {
    @ObservedObject var updates: UpdateController
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SnapNest · 拾图").font(.title2.bold())
            Text("当前版本 \(updates.currentVersion)").foregroundStyle(.secondary)
            if !UpdateController.isPrivateEdition { Toggle("启动时自动检查更新", isOn: $updates.automaticallyCheck) }
            Text(updates.status).font(.callout).textSelection(.enabled)
            if updates.busy { ProgressView().controlSize(.small) }
            ScrollView {
                Text(updates.release?.body ?? "当前版本不连接 GitHub / Gitee 更新渠道。请使用开发者提供的新版安装包更新。")
                    .font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("检查更新") { Task { await updates.check() } }.disabled(updates.busy)
                if !UpdateController.isPrivateEdition { Button("发布页") { NSWorkspace.shared.open(UpdateController.releasesURL) } }
                Spacer()
                if let url = updates.downloadedURL {
                    Button("显示安装包") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                if updates.asset != nil {
                    Button("下载新版") { Task { await updates.download() } }.disabled(updates.busy)
                }
            }
        }.padding(24).frame(width: 480, height: 420)
    }
}
