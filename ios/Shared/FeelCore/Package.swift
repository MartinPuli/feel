// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "FeelCore", platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "FeelCore", targets: ["FeelCore"]), .executable(name: "feel-replay", targets: ["FeelReplay"])],
    targets: [.target(name: "FeelCore"), .executableTarget(name: "FeelReplay", dependencies: ["FeelCore"]), .testTarget(name: "FeelCoreTests", dependencies: ["FeelCore"])])
