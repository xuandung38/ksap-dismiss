// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KSAPDismiss",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "KSAPDismiss", targets: ["KSAPDismiss"]),
        .executable(name: "KSAPDismissApp", targets: ["KSAPDismissApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        // Library target containing all app code (testable)
        // Named "KSAPDismiss" to match Xcode module name
        .target(
            name: "KSAPDismiss",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "KSAPDismiss",
            exclude: ["Info.plist", "KSAPDismiss.entitlements"],
            resources: [
                .copy("Resources")
            ]
        ),
        // Executable target with app entry point
        .executableTarget(
            name: "KSAPDismissApp",
            dependencies: ["KSAPDismiss"],
            path: "App",
            sources: ["main.swift"]
        ),
        .testTarget(
            name: "KSAPDismissTests",
            dependencies: ["KSAPDismiss"],
            path: "Tests"
        )
    ]
)
