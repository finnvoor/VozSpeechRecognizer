// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VozSpeechRecognizer",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "VozSpeechRecognizer", targets: ["VozSpeechRecognizer"])
    ],
    dependencies: [
        .package(url: "https://github.com/mattt/AnySpeechRecognizer", from: "0.1.0"),
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core", from: "4.2.1"),
    ],
    targets: [
        .target(
            name: "VozSpeechRecognizer",
            dependencies: [
                "AnySpeechRecognizer",
                .product(name: "Voz", package: "desert-ant-core"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
