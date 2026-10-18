// swift-tools-version:5.9
// SwiftTerm 1.11.2 (b1262db5) 를 그대로 옮기고 라이브러리 대상만 남겼다. 고친 곳은 PATCHES.md.
import PackageDescription

let package = Package(
    name: "SwiftTerm",
    platforms: [.macOS(.v13)],
    products: [.library(name: "SwiftTerm", targets: ["SwiftTerm"])],
    targets: [
        .target(name: "SwiftTerm", path: "Sources/SwiftTerm", exclude: ["Mac/README.md"]),
    ],
    swiftLanguageVersions: [.v5]
)
