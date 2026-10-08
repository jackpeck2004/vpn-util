// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VPNUtility",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "VPNUtility", targets: ["VPNUtility"])],
    targets: [
        .target(name: "VPNCore"),
        .executableTarget(name: "VPNUtility", dependencies: ["VPNCore"]),
        .executableTarget(name: "VPNCoreChecks", dependencies: ["VPNCore"], path: "Tests/VPNCoreTests")
    ]
)
