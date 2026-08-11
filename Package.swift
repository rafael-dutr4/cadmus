// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Cadmus",
  // Follows Homebrew. The whisper dylib it installs is built for the running
  // system, so anything older here only produces a linker warning about a
  // compatibility this build does not actually have.
  platforms: [.macOS("26.0")],
  targets: [
    // whisper.cpp exposes a plain C header, so it is a system library and
    // not a wrapper. See Sources/CWhisper/module.modulemap.
    .systemLibrary(name: "CWhisper", path: "Sources/CWhisper"),
    .executableTarget(
      name: "Cadmus",
      dependencies: ["CWhisper"],
      swiftSettings: [.unsafeFlags(["-I/opt/homebrew/include"])],
      linkerSettings: [
        .unsafeFlags(["-L/opt/homebrew/lib"]),
        // whisper pulls itself in through the module map. ggml is named here
        // because the backend loader lives in it and nothing else references
        // it, so the linker has no reason to look.
        .linkedLibrary("ggml"),
      ]
    ),
  ]
)
