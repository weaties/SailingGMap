// swift-tools-version: 6.3
//
// SailingCore — the mathematics of SailingGMap, with no UI dependency.
//
// Keeping the math in its own package is what makes it testable: `swift test`
// runs the whole suite headless in a few seconds, with no app host and no
// window server. AGENTS.md § "Architecture principles" treats the absence of
// SwiftUI/AppKit imports here as an invariant, and scripts/lint.sh enforces it.
//
// Dependency note: GeneralizedMap 0.1.0 ships a `swift-tools-version: 6.4`
// manifest that no released toolchain can parse. The requirement below is the
// honest one; scripts/bootstrap-dependency.sh produces a locally-patched 0.1.1
// tag that satisfies it. See docs/toolchain.md.
//
import PackageDescription

let package = Package(
    name: "SailingCore",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "SailingCore", targets: ["SailingCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/SinanKarasu/GeneralizedMap.git", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "SailingCore",
            dependencies: [
                .product(name: "GeneralizedMap", package: "GeneralizedMap")
            ]
        ),
        .testTarget(
            name: "SailingCoreTests",
            dependencies: ["SailingCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
