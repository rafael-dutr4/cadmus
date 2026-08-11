import AVFoundation
import AppKit
import Carbon.HIToolbox

/// Ctrl+Option+D. One key to start, the same key to stop. Not hold to talk: a
/// prompt is half a minute of speech and holding a key down that long is
/// miserable.
private let hotkeyCode = UInt32(kVK_ANSI_D)
private let hotkeyModifiers = UInt32(controlKey | optionKey)

/// Everything here runs on the main thread, which is not a preference: the
/// menu bar, the hotkey handler and the event posting all belong to it. The one
/// piece that must not is the model, and it is the one piece sent away.
@MainActor
final class Cadmus: NSObject, NSApplicationDelegate {
  private let recorder = Recorder()
  private var transcriber: Transcriber?
  private var hotkey: Hotkey?
  private var statusItem: NSStatusItem!

  /// Phrases are transcribed and typed here, one after another. It has to be
  /// serial: the words have to reach the window in the order I said them, and
  /// a queue that runs two phrases at once would sometimes type the second one
  /// first.
  private let worker = DispatchQueue(label: "br.dutra.cadmus.worker")

  /// How many phrases are still in the worker. Only there to tell an idle
  /// Cadmus apart from one that is still catching up after I stopped talking.
  private var pending = 0

  /// Whether Cadmus is the one who paused the music. Only what Cadmus stopped
  /// is ever started again: if I had already paused it myself, it stays paused.
  private var pausedPlayback = false

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

    // The audio thread hands over a finished phrase. Nothing slow can happen
    // there, so it goes straight to the worker.
    recorder.onSegment = { [weak self] samples in
      Task { @MainActor in self?.enqueue(samples) }
    }

    // The sound means the microphone is live, not that the hotkey was seen.
    // With a Bluetooth headset those are a second apart, and anything said in
    // between is gone.
    recorder.onReady = {
      Task { @MainActor in NSSound(named: "Tink")?.play() }
    }

    do {
      transcriber = try Transcriber(modelPath: modelPath)
      hotkey = try Hotkey(keyCode: hotkeyCode, modifiers: hotkeyModifiers) { [weak self] in
        self?.toggle()
      }
    } catch {
      fail(error)
    }
    redraw()
  }

  private func toggle() {
    recorder.isRecording ? finish() : begin()
  }

  private func begin() {
    // Before the microphone, not after. A Bluetooth headset playing music has
    // no microphone at all, so the music has to stop for one to exist.
    pausedPlayback = Playback.pauseIfPlaying()
    do {
      try recorder.start()
      redraw()
    } catch {
      if pausedPlayback { Playback.resume() }
      pausedPlayback = false
      fail(error)
    }
  }

  /// Stopping only closes the microphone. Everything said before it is already
  /// on its way, or already typed.
  private func finish() {
    recorder.stop()
    if pausedPlayback {
      pausedPlayback = false
      Playback.resume()
    }
    redraw()
  }

  private func enqueue(_ samples: [Float]) {
    guard let transcriber else { return }
    pending += 1
    redraw()

    let method = self.method
    worker.async {
      let text = (try? transcriber.transcribe(samples)) ?? ""
      DispatchQueue.main.async {
        self.pending -= 1
        self.redraw()
        guard !text.isEmpty else { return }
        // A space after, so the next phrase does not weld itself to this one.
        // Still no Enter, ever: I read it and I send it.
        Typist.insert(text + " ", using: method)
      }
    }
  }

  /// `●` listening, `…` catching up, `○` idle. Recording and transcribing
  /// overlap now, so the icon shows the microphone first: knowing whether it is
  /// listening matters more than knowing it is busy.
  private func redraw() {
    if recorder.isRecording {
      statusItem.button?.title = "●"
    } else {
      statusItem.button?.title = pending > 0 ? "…" : "○"
    }
  }

  private func fail(_ error: Error) {
    redraw()
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
