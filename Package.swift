// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Symboard",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Symboard", targets: ["Symboard"]),
    ],
    dependencies: [
        // 1.11.2 에 읽기 작업이 쌓이는 문제를 고친 사본(Vendor/SwiftTerm/PATCHES.md).
        .package(path: "Vendor/SwiftTerm"),
    ],
    targets: [
        .target(name: "SymboardCore"),
        .executableTarget(
            name: "Symboard",
            dependencies: ["SymboardCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "SymboardCoreTests", dependencies: ["SymboardCore"]),
    ]
)
