// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "flutter_linkme_sdk",
  platforms: [
    .macOS(.v10_15)
  ],
  products: [
    .library(
      name: "flutter-linkme-sdk",
      targets: ["flutter_linkme_sdk"]
    )
  ],
  dependencies: [
    // Flutter creates this sibling package in the example app's ephemeral
    // SwiftPM directory when it generates the plugin registrant.
    .package(name: "FlutterFramework", path: "../FlutterFramework"),
    .package(
      url: "https://github.com/r-dev-limited/li-nk.me-ios-sdk.git",
      exact: "0.2.14"
    )
  ],
  targets: [
    .target(
      name: "flutter_linkme_sdk",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework"),
        .product(name: "LinkMeKit", package: "li-nk.me-ios-sdk")
      ],
      resources: [
        .process("PrivacyInfo.xcprivacy")
      ]
    )
  ]
)
