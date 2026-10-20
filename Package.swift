// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "HABar",
    platforms: [.macOS(.v26)],
    targets: [.executableTarget(name: "HABar", path: "Sources", swiftSettings: [.swiftLanguageMode(.v5)])]
)
