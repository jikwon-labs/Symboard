// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Symboard",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Symboard", targets: ["Symboard"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.11.2"),
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
