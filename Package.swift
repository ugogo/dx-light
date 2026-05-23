// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DXLight",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DXLightCore", targets: ["DXLightCore"]),
        .executable(name: "dx-light-cli", targets: ["DXLightCLI"]),
        .executable(name: "DXLight", targets: ["DXLightApp"]),
    ],
    targets: [
        .target(
            name: "DXLightCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .executableTarget(
            name: "DXLightCLI",
            dependencies: ["DXLightCore"]
        ),
        .executableTarget(
            name: "DXLightApp",
            dependencies: ["DXLightCore"]
        ),
        .testTarget(
            name: "DXLightCoreTests",
            dependencies: ["DXLightCore"]
        ),
    ]
)
