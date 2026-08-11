import AVFoundation
import AppKit
import Carbon.HIToolbox

/// Ctrl+Option+D. One key to start, the same key to stop. Not hold to talk: a
/// prompt is half a minute of speech and holding a key down that long is
/// miserable.
private let hotkeyCode = UInt32(kVK_ANSI_D)
private let hotkeyModifiers = UInt32(controlKey | optionKey)

/// A take shorter or quieter than this never reaches the model. Given silence
/// Whisper does not return nothing, it returns a confident sentence out of its
/// training data.
private let silenceFloor: Float = 0.005
private let shortestTake: Double = 0.4

/// Everything here runs on the main thread, which is not a preference: the
/// menu bar, the hotkey handler and the event posting all belong to it. The one
/// piece that must not is the model, and it is the one piece sent away.
@MainActor
final class Cadmus: NSObject, NSApplicationDelegate {
  private let recorder = Recorder()
  private var transcriber: Transcriber?
  private var hotkey: Hotkey?
  private var statusItem: NSStatusItem!

  private let method: Typist.Method = {
    // The open question of the project, so it is switchable without a
    // rebuild: CADMUS_INSERT=paste.
    Typist.Method(rawValue: ProcessInfo.processInfo.environment["CADMUS_INSERT"] ?? "")
      ?? .keystrokes
  }()

  private var modelPath: String {
    if let override = ProcessInfo.processInfo.environment["CADMUS_MODEL"] { return override }
    return FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "personal/cadmus/models/ggml-small.en.bin").path
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.title = "○"
    let menu = NSMenu()
    menu.addItem(
      NSMenuItem(title: "Cadmus (ctrl option D)", action: nil, keyEquivalent: ""))
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    statusItem.menu = menu

    // Asked for now rather than at the moment I first speak, because the
    // dialog steals focus and the focused window is where the text goes.
    _ = Typist.hasAccessibilityPermission(prompting: true)
    AVCaptureDevice.requestAccess(for: .audio) { _ in }

    do {
      transcriber = try Transcriber(modelPath: modelPath)
      hotkey = try Hotkey(keyCode: hotkeyCode, modifiers: hotkeyModifiers) { [weak self] in
        self?.toggle()
      }
    } catch {
      fail(error)
    }
    setIdle()
  }

  private func toggle() {
    recorder.isRecording ? finish() : begin()
  }

  private func begin() {
    do {
      try recorder.start()
      statusItem.button?.title = "●"
      NSSound(named: "Tink")?.play()
    } catch {
      fail(error)
    }
  }

  private func finish() {
    let samples = recorder.stop()
    statusItem.button?.title = "…"

    guard samples.seconds >= shortestTake, samples.rms >= silenceFloor else {
      setIdle()
      return
    }

    guard let transcriber else { return }
    let method = self.method

    // Off the main thread: the model holds the CPU for a second or so and
    // the menu bar has to keep drawing.
    Task.detached(priority: .userInitiated) {
      do {
        let text = try transcriber.transcribe(samples)
        await MainActor.run {
          self.setIdle()
          guard !text.isEmpty else { return }
          // A space after, so the next phrase does not weld itself to
          // this one. Still no Enter, ever: I read it and I send it.
          Typist.insert(text + " ", using: method)
        }
      } catch {
        await MainActor.run { self.fail(error) }
      }
    }
  }

  private func setIdle() {
    statusItem.button?.title = "○"
  }

  private func fail(_ error: Error) {
    setIdle()
    FileHandle.standardError.write(Data("cadmus: \(error.localizedDescription)\n".utf8))
    let alert = NSAlert()
    alert.messageText = "Cadmus"
    alert.informativeText = error.localizedDescription
    alert.runModal()
  }
}

let app = NSApplication.shared
let delegate = Cadmus()
app.delegate = delegate
// No dock icon and no window. The menu bar is the whole interface.
app.setActivationPolicy(.accessory)
app.run()
