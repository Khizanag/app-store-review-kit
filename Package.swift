// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AppStoreReviewKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "AppStoreReviewKit",
            targets: ["AppStoreReviewKit"],
        ),
        .executable(
            name: "asrk",
            targets: ["asrk"],
        ),
    ],
    targets: [
        .target(name: "AppStoreReviewKit"),
        .executableTarget(
            name: "asrk",
            dependencies: ["AppStoreReviewKit"],
        ),
        .testTarget(
            name: "AppStoreReviewKitTests",
            dependencies: ["AppStoreReviewKit"],
        ),
    ],
    swiftLanguageModes: [.v6]
)
