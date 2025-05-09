// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_mapbox_navigation",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "flutter-mapbox-navigation", targets: ["flutter_mapbox_navigation"])
    ],
    dependencies: [
        .package(url: "https://github.com/mapbox/mapbox-navigation-ios.git", from: "3.7.0")
        .package(url: "https://github.com/mapbox/mapbox-maps-ios.git", from: "11.0.0")
    ],
    targets: [
        .target(
            name: "flutter_mapbox_navigation",
            dependencies: [
                .product(name: "MapboxNavigationCore", package: "mapbox-navigation-ios"),
                .product(name: "MapboxNavigationUIKit", package: "mapbox-navigation-ios")
                .product(name: "MapboxMaps", package: "mapbox-maps-ios")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)