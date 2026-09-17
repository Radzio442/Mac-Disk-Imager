// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacDiskImager",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacDiskImager", targets: ["MacDiskImager"]),
        .executable(name: "MacDiskImagerHelper", targets: ["MacDiskImagerHelper"])
    ],
    targets: [
        .executableTarget(name: "MacDiskImager", path: "Sources/MacDiskImager"),
        .executableTarget(name: "MacDiskImagerHelper", path: "Sources/MacDiskImagerHelper")
    ]
)
