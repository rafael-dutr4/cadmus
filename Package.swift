// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Kadmos",
  // Follows Homebrew. The whisper dylib it installs is built for the running
  // system, so anything older here only produces a linker warning about a
  // compatibility this build does not actually have.
  platforms: [.macOS("26.0")],
  targets: [
    // whisper.cpp exposes a plain C header, so it is a system library and
    // not a wrapper. See Sources/CWhisper/module.modulemap.
    .systemLibrary(name: "CWhisper", path: "Sources/CWhisper"),
    .executableTarget(
      name: "Kadmos",
      dependencies: ["CWhisper"],
      swiftSettings: [.unsafeFlags(["-I/opt/homebrew/include"])],
      linkerSettings: [.unsafeFlags(["-L/opt/homebrew/lib"])]
    ),
  ]
)
