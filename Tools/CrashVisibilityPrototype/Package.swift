// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrashVisibilityPrototype",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "CrashVisibilityPrototype", targets: ["CrashVisibilityApp"])],
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", exact: "9.30.1"),
    ],
    targets: [
        .target(name: "HandlerProbe"),
        .binaryTarget(name: "CrashReporter", path: "build/Vendor/CrashReporter.xcframework"),
        .target(name: "CrashVisibilityCore", dependencies: [
            "CrashReporter",
            "HandlerProbe",
            .product(name: "Sentry", package: "sentry-cocoa"),
        ]),
        .executableTarget(name: "CrashVisibilityApp", dependencies: ["CrashVisibilityCore"]),
        .testTarget(name: "CrashVisibilityCoreTests", dependencies: ["CrashVisibilityCore"]),
    ],
    swiftLanguageModes: [.v5]
)
