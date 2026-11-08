// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "monitorer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "monitorer", targets: ["monitorer"])
    ],
    targets: [
        .target(
            name: "MonitorerCore",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(name: "monitorer", dependencies: ["MonitorerCore"]),
        .testTarget(name: "MonitorerCoreTests", dependencies: ["MonitorerCore"]),
    ]
)
