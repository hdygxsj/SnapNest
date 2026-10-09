import Foundation

public struct AppRelease: Decodable {
    public struct Asset: Decodable {
        public let name: String
        public let browser_download_url: URL
        public let size: Int
        public let digest: String?
    }
    public let tag_name: String
    public let html_url: URL
    public let body: String?
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]
    public var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    public func isNewer(than currentVersion: String) -> Bool {
        let pattern = #"^\d+\.\d+\.\d+$"#
        guard !draft, !prerelease,
              version.range(of: pattern, options: .regularExpression) != nil,
              currentVersion.range(of: pattern, options: .regularExpression) != nil else { return false }
        return version.compare(currentVersion, options: .numeric) == .orderedDescending
    }
    public func updateAsset(currentVersion: String) -> Asset? {
        guard isNewer(than: currentVersion) else { return nil }
        return assets.first {
            $0.name == "SnapNest-v\(version)-macos-universal.zip" && $0.size > 0 &&
            $0.browser_download_url.scheme == "https" && $0.browser_download_url.host == "github.com" &&
            $0.browser_download_url.path == "/hdygxsj/SnapNest/releases/download/\(tag_name)/\($0.name)"
        }
    }
}
