// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Shitu", platforms: [.macOS(.v15)],
    products: [.executable(name: "Shitu", targets: ["Shitu"])],
    targets: [
        .target(name: "ShituCore"),
        .executableTarget(name: "Shitu", dependencies: ["ShituCore"]),
        .executableTarget(name: "ShituCoreChecks", dependencies: ["ShituCore"], path: "Tests/ShituCoreTests")
    ], swiftLanguageModes: [.v5]
)
