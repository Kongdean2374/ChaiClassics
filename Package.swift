// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "ChaiCore", platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "ChaiCore", targets: ["ChaiCore"])],
    targets: [
        .target(name: "ChaiCore", path: "Core", resources: [.process("Resources")]),
        .testTarget(name: "ChaiCoreTests", dependencies: ["ChaiCore"], path: "Tests/ChaiCoreTests", resources: [.copy("Fixtures")])
    ]
)
