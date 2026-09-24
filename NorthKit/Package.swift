// swift-tools-version: 6.2
import PackageDescription

// NorthKit holds what every Khepri surface shares. The iOS app and its widgets
// link it now; watchOS and macOS will link the same package.
//
//   NorthKit  design tokens: colours, fonts, radii
//   NorthAPI  the /api/v1 client, generated at build time from openapi.yaml
let package = Package(
    name: "NorthKit",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "NorthKit", targets: ["NorthKit"]),
        .library(name: "NorthAPI", targets: ["NorthAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "NorthKit",
            resources: [.process("Resources")]
        ),
        .target(
            name: "NorthAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
        .testTarget(
            name: "NorthKitTests",
            dependencies: ["NorthKit"],
            resources: [.copy("ArtFixtures")]
        ),
        .testTarget(
            name: "NorthAPITests",
            dependencies: ["NorthAPI"],
            resources: [.copy("Contract")]
        ),
    ]
)
