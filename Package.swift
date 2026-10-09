// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Agora", platforms: [.macOS(.v14)],
    products: [.executable(name: "Agora", targets: ["AgoraMac"]), .executable(name: "AgoraMCP", targets: ["AgoraMCP"])],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
        .package(url: "https://github.com/apple/swift-log.git", exact: "1.16.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0")
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "AgoraCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "AgoraMac", dependencies: ["AgoraCore", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.copy("Resources/Outlook")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "AgoraMCP", dependencies: ["AgoraCore", .product(name: "MCP", package: "swift-sdk"), .product(name: "Logging", package: "swift-log")]),
        .testTarget(name: "AgoraCoreTests", dependencies: ["AgoraCore"])
    ], swiftLanguageModes: [.v5]
)
