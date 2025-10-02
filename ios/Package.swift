// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "flutter_linkme_sdk",
  platforms: [
    .iOS(.v14)
  ],
  products: [
    .library(
      name: "flutter_linkme_sdk",
      targets: ["flutter_linkme_sdk"]
    )
  ],
  dependencies: [
    .package(
      url: "https://github.com/r-dev-limited/li-nk.me-ios-sdk.git", .upToNextMajor(from: "0.1.0"))
  ],
  targets: [
    .target(
      name: "flutter_linkme_sdk",
      dependencies: ["LinkMeKit"],
      path: "Classes"
    )
  ]
)
