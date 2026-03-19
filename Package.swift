// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TodoApp-iPad",
    platforms: [.iOS(.v17)],
    products: [],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "12.10.0"),
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "9.1.0"),
    ],
    targets: []
)
