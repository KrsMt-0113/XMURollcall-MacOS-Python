// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "XMURollcall",
    platforms: [.macOS(.v26)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "XMURollcall",
            dependencies: [],
            resources: [
                .copy("Resources/python_scripts")
            ]
        ),
        .testTarget(
            name: "XMURollcallTests",
            dependencies: ["XMURollcall"]
        )
    ]
)
