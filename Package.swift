// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuakeKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "QuakeRuntime", targets: ["QuakeRuntime"]),
        .library(name: "QuakePluginAPI", targets: ["QuakePluginAPI"]),
        .library(name: "QuakeHID", targets: ["QuakeHID"]),
        .executable(name: "quake-probe", targets: ["QuakeProbe"]),
        .executable(name: "quake-test", targets: ["QuakeTest"]),
        .executable(name: "quake-panel", targets: ["QuakePanelHost"])
    ],
    targets: [
        .target(
            name: "QuakePluginAPI"
        ),
        .target(
            name: "QuakeRuntime",
            dependencies: ["QuakePluginAPI"]
        ),
        .target(
            name: "QuakeHID",
            dependencies: ["QuakeRuntime"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .executableTarget(
            name: "QuakeProbe",
            dependencies: ["QuakeHID", "QuakePluginAPI", "QuakeRuntime"]
        ),
        .executableTarget(
            name: "QuakePanelHost",
            dependencies: ["QuakeHID", "QuakeRuntime"],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "QuakeTest",
            dependencies: ["QuakeHID", "QuakePluginAPI", "QuakeRuntime"]
        ),
        .testTarget(
            name: "QuakeKitTests",
            dependencies: ["QuakeHID", "QuakeRuntime"]
        )
    ]
)
