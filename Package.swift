// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Symboard",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Symboard", targets: ["Symboard"]),
        .executable(name: "symboard-mcp", targets: ["SymboardMCP"]),
        .executable(name: "symboard-agentd", targets: ["SymboardAgentd"]),
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
        // claude 콘솔에 붙이는 stdio MCP 서버(8차). 앱 번들 Contents/MacOS 에 함께 넣는다.
        .executableTarget(name: "SymboardMCP", dependencies: ["SymboardCore"]),
        // 콘솔을 앱 밖에서 들고 있는 백그라운드 프로그램(13차). 앱을 꺼도 콘솔이 계속 돈다.
        .executableTarget(
            name: "SymboardAgentd",
            dependencies: ["SymboardCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "SymboardCoreTests", dependencies: ["SymboardCore"]),
    ]
)
