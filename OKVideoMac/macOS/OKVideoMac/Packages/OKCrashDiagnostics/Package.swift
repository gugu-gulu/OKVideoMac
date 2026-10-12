// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OKCrashDiagnostics",
    platforms: [.macOS(.v12)],
    products: [.library(name: "OKCrashDiagnostics", targets: ["OKCrashDiagnostics"])],
    targets: [
        .binaryTarget(name: "CrashReporter", path: "Vendor/CrashReporter.xcframework"),
        .target(name: "OKCrashDiagnostics", dependencies: ["CrashReporter"],
                resources: [.copy("Resources/PrivacyInfo.xcprivacy"), .copy("Resources/PLCrashReporter-LICENSE.txt")]),
    ],
    swiftLanguageVersions: [.v5]
)
