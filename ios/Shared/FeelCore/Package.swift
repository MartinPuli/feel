// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "FeelCore", platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "FeelCore", targets: ["FeelCore"]), .executable(name: "feel-replay", targets: ["FeelReplay"])],
    targets: [.target(name: "FeelCore"), .target(name: "FeelSim", dependencies: ["FeelCore"]),
              .executableTarget(name: "FeelReplay", dependencies: ["FeelCore", "FeelSim"]),
              .testTarget(name: "FeelCoreTests", dependencies: ["FeelCore"]),
              .testTarget(name: "FeelSimTests", dependencies: ["FeelCore", "FeelSim"])])
