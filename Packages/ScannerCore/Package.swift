// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScannerCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScannerCore", targets: ["ScannerCore"]),
        .executable(name: "scan-cli", targets: ["scan-cli"])
    ],
    targets: [
        .target(name: "ScannerCore"),
        .executableTarget(
            name: "scan-cli",
            dependencies: ["ScannerCore"]
        ),
        .testTarget(
            name: "ScannerCoreTests",
            dependencies: ["ScannerCore"]
        )
    ]
)
