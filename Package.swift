// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PickleKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "PickleKit", targets: ["PickleKit"]),
    ],
    dependencies: [
        // Kumi (組) — the report/spec HTML is assembled with this owned,
        // zero-dependency builder instead of hand-written tag strings.
        .package(url: "https://github.com/alleato-llc/kumi.git", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "PickleKit",
            dependencies: [.product(name: "Kumi", package: "kumi")],
            path: "Sources/PickleKit"
        ),
        .testTarget(
            name: "PickleKitTests",
            dependencies: ["PickleKit"],
            path: "Tests/PickleKitTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
