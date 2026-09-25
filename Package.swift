// swift-tools-version:5.9
import PackageDescription

// Every target excludes .DS_Store: if Finder ever drops one inside Sources/, SwiftPM
// treats it as an unhandled resource and auto-generates a Bundle.module accessor that
// expects a resource bundle we never build or ship, crashing the app on launch with
// "could not load resource bundle". Excluding it here makes that impossible regardless
// of what Finder does on any given Mac.
let noFinderCruft: [String] = [".DS_Store"]

let package = Package(
    name: "Pitstop",
    platforms: [.macOS(.v14)],
    targets: [
        // Shared logic: accounts, providers, quota check, ticket log.
        .target(name: "PitstopCore", path: "Sources/PitstopCore", exclude: noFinderCruft),
        // The menu bar app.
        .executableTarget(
            name: "Pitstop",
            dependencies: ["PitstopCore"],
            path: "Sources/Pitstop",
            exclude: noFinderCruft,
            resources: [.process("Resources")]
        ),
        // The `pitstop` command used by execute-jira. Bundled as Contents/Helpers/pitstop.
        .executableTarget(name: "PitstopCLI", dependencies: ["PitstopCore"], path: "Sources/PitstopCLI", exclude: noFinderCruft),
    ]
)
