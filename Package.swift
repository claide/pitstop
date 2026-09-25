// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pitstop",
    platforms: [.macOS(.v14)],
    targets: [
        // Shared logic: accounts, providers, quota check, ticket log.
        .target(name: "PitstopCore", path: "Sources/PitstopCore"),
        // The menu bar app.
        .executableTarget(
            name: "Pitstop", dependencies: ["PitstopCore"], path: "Sources/Pitstop",
            resources: [.process("Resources")]
        ),
        // The `pitstop` command used by execute-jira. Bundled as Contents/Helpers/pitstop.
        .executableTarget(name: "PitstopCLI", dependencies: ["PitstopCore"], path: "Sources/PitstopCLI"),
    ]
)
