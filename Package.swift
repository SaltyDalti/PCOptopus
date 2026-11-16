// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PCOptopus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PCOptopusKit", targets: [
            "Model", "Store", "Sensors", "Policy", "Apply", "Coach"
        ]),
        .executable(name: "PCOptopus", targets: ["PCOptopusApp"]),
        .executable(name: "PCOptopusHelper", targets: ["PCOptopusHelper"]),
        .executable(name: "PCOptopusVerification", targets: ["PCOptopusVerification"])
    ],
    targets: [
        .target(
            name: "Model",
            path: "Packages/PCOptopusKit/Sources/Model"
        ),
        .target(
            name: "Store",
            dependencies: ["Model"],
            path: "Packages/PCOptopusKit/Sources/Store"
        ),
        .target(
            name: "Sensors",
            dependencies: ["Model"],
            path: "Packages/PCOptopusKit/Sources/Sensors"
        ),
        .target(
            name: "Policy",
            dependencies: ["Model", "Store", "Apply"],
            path: "Packages/PCOptopusKit/Sources/Policy"
        ),
        .target(
            name: "Apply",
            dependencies: ["Model"],
            path: "Packages/PCOptopusKit/Sources/Apply"
        ),
        .target(
            name: "Coach",
            dependencies: ["Model", "Policy"],
            path: "Packages/PCOptopusKit/Sources/Coach"
        ),
        // AppKit menu-bar app (runs with Command Line Tools).
        // SwiftUI sources live in App/SwiftUI for Xcode once installed.
        .executableTarget(
            name: "PCOptopusApp",
            dependencies: ["Model", "Store", "Sensors", "Policy", "Apply", "Coach"],
            path: "App/Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Cocoa")
            ]
        ),
        .executableTarget(
            name: "PCOptopusHelper",
            dependencies: ["Model", "Apply"],
            path: "Helper/Sources"
        ),
        // Primary verification on Command Line Tools (no XCTest framework).
        .executableTarget(
            name: "PCOptopusVerification",
            dependencies: ["Model", "Store", "Sensors", "Policy", "Apply", "Coach"],
            path: "Packages/PCOptopusKit/Sources/Verification"
        )
        // XCTest suites live under Packages/PCOptopusKit/Tests for full Xcode.
    ]
)
