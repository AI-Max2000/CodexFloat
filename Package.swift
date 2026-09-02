// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CodexFloat",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "CodexFloat", targets: ["CodexFloat"]),
    .library(name: "CodexQuotaCore", targets: ["CodexQuotaCore"]),
    .library(name: "TiboFeedCore", targets: ["TiboFeedCore"]),
    .library(name: "ActivityClassifier", targets: ["ActivityClassifier"]),
    .library(name: "LocalStore", targets: ["LocalStore"]),
  ],
  targets: [
    .target(name: "CodexQuotaCore"),
    .target(name: "ActivityClassifier", dependencies: ["CodexQuotaCore"]),
    .target(
      name: "TiboFeedCore",
      dependencies: ["CodexQuotaCore", "ActivityClassifier"]
    ),
    .target(
      name: "LocalStore",
      dependencies: ["CodexQuotaCore", "ActivityClassifier", "TiboFeedCore"],
      linkerSettings: [.linkedLibrary("sqlite3")]
    ),
    .executableTarget(
      name: "CodexFloat",
      dependencies: ["CodexQuotaCore", "TiboFeedCore", "ActivityClassifier", "LocalStore"],
      linkerSettings: [
        .linkedFramework("AppKit"), .linkedFramework("UserNotifications"),
        .linkedFramework("Network"), .linkedFramework("Carbon"),
        .linkedFramework("ApplicationServices"),
      ]
    ),
    .testTarget(
      name: "CodexFloatTests",
      dependencies: [
        "CodexFloat", "CodexQuotaCore", "TiboFeedCore", "ActivityClassifier", "LocalStore",
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
