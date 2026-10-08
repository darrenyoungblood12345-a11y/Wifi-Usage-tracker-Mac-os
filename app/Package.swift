// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "WiFiTracker",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "WiFiTracker", targets: ["WiFiTracker"]),
  ],
  targets: [
    .target(name: "WiFiTrackerCore"),
    .executableTarget(
      name: "WiFiTracker",
      dependencies: ["WiFiTrackerCore"]
    ),
    .testTarget(
      name: "WiFiTrackerCoreTests",
      dependencies: ["WiFiTrackerCore"]
    ),
    .testTarget(
      name: "WiFiTrackerTests",
      dependencies: ["WiFiTracker"]
    ),
  ]
)
