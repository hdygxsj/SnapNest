import Foundation
import ShituCore

func checkUpdates() throws {
    func release(_ version: String, prerelease: Bool = false, draft: Bool = false, host: String = "github.com", name: String = "SnapNest-v1.10.0-macos-universal.zip") throws -> AppRelease {
        let json: [String: Any] = ["tag_name": version, "html_url": "https://github.com/hdygxsj/SnapNest/releases/tag/\(version)", "body": "更新说明", "draft": draft, "prerelease": prerelease,
            "assets": [["name": name, "size": 123, "browser_download_url": "https://\(host)/hdygxsj/SnapNest/releases/download/\(version)/\(name)"]]]
        return try JSONDecoder().decode(AppRelease.self, from: JSONSerialization.data(withJSONObject: json))
    }
    XCTAssertEqual(try release("v1.10.0").updateAsset(currentVersion: "1.9.0") != nil, true)
    XCTAssertNil(try release("v1.10.0").updateAsset(currentVersion: "1.10.0"))
    XCTAssertNil(try release("v1.9.0").updateAsset(currentVersion: "1.10.0"))
    XCTAssertNil(try release("v1.10.0", prerelease: true).updateAsset(currentVersion: "1.0.0"))
    XCTAssertNil(try release("v1.10.0", draft: true).updateAsset(currentVersion: "1.0.0"))
    XCTAssertNil(try release("v1.10.0", host: "example.com").updateAsset(currentVersion: "1.0.0"))
    XCTAssertNil(try release("v1.10.0", name: "source.zip").updateAsset(currentVersion: "1.0.0"))
    XCTAssertNil(try release("v1.10.0-beta").updateAsset(currentVersion: "1.0.0"))
    XCTAssertNil(try release("v1.10.0").updateAsset(currentVersion: "unknown"))
}
