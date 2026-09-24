// swift-tools-version: 6.2
import PackageDescription

// NorthKit holds what every Khepri surface shares: the design tokens today,
// and the generated API client and models as the contract grows. The iOS app
// and its widgets link it now; watchOS and macOS will link the same package.
let package = Package(
    name: "NorthKit",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "NorthKit", targets: ["NorthKit"]),
    ],
    targets: [
        .target(
            name: "NorthKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "NorthKitTests",
            dependencies: ["NorthKit"]
        ),
    ]
)
