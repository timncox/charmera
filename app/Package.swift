// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Charmera",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CharmeraCore",
            path: "CharmeraCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Charmera",
            dependencies: ["CharmeraCore"],
            path: "Charmera",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
