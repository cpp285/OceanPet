// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OceanPet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OceanPet", targets: ["OceanPet"])
    ],
    targets: [
        .executableTarget(
            name: "OceanPet",
            path: "Sources/OceanPet",
            resources: [.copy("Resources")],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Speech"),
                .linkedFramework("SpriteKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "OceanPetTests",
            dependencies: ["OceanPet"],
            path: "Tests/OceanPetTests"
        )
    ]
)
