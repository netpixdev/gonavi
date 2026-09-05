// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Gonavi",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Gonavi", targets: ["Gonavi"]),
               .library(name: "GonaviCore", targets: ["GonaviCore"])],
    targets: [
        .target(name: "GonaviCore"),
        .executableTarget(name: "Gonavi", dependencies: ["GonaviCore"]),
        .testTarget(name: "GonaviCoreTests", dependencies: ["GonaviCore"])
    ]
)
