// swift-tools-version: 6.2
import PackageDescription

// Two targets, and the line between them is the rule of the project.
//
// CadmusCore is voice becoming text: the microphone, the model, my vocabulary,
// and getting out of the way of whatever is playing. None of it knows what the
// text is for.
//
// Cadmus is the keyboard: a hotkey, and typing the result into whatever has
// focus. That is the part another program would not want.
//
// The split exists because Fabulinus, which drills my English, needs the first
// half and none of the second. It is also the honest shape: everything in the
// core was already written without knowing where the words were going.
let package = Package(
  name: "Cadmus",
  // Follows Homebrew. The whisper dylib it installs is built for the running
  // system, so anything older here only produces a linker warning about a
  // compatibility this build does not actually have.
  platforms: [.macOS("26.0")],
  products: [
    .library(name: "CadmusCore", targets: ["CadmusCore"])
  ],
  targets: [
    // whisper.cpp exposes a plain C header, so it is a system library and
    // not a wrapper. See Sources/CWhisper/module.modulemap.
    .systemLibrary(name: "CWhisper", path: "Sources/CWhisper"),
    .target(
      name: "CadmusCore",
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
    .executableTarget(
      name: "Cadmus",
      dependencies: ["CadmusCore"]
    ),
  ]
)
