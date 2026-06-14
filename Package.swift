// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Swisp",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Swisp", targets: ["Swisp"]),
        .executable(name: "SwispCLI", targets: ["SwispCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.4.0"),
    ],
    targets: [
        .target(name: "Swisp", dependencies: [
            .product(name: "BigInt", package: "BigInt"),
        ], resources: [.process("init.lisp"), .process("backquote.lisp")]),
        .executableTarget(name: "SwispCLI", dependencies: [
            "Swisp",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
    ]
)
