import AVFoundation
import AppKit
import CadmusCore
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

  /// Whether the microphone is actually delivering audio yet, which on a
  /// Bluetooth headset is a moment after the hotkey.
  private var micLive = false

  private let method: Typist.Method = {
    // The open question of the project, so it is switchable without a
    // rebuild: CADMUS_INSERT=paste.
    Typist.Method(rawValue: ProcessInfo.processInfo.environment["CADMUS_INSERT"] ?? "")
      ?? .keystrokes
  }()

  private let quiet = ProcessInfo.processInfo.environment["CADMUS_QUIET"] != "0"

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
    //
    // Both are reported because both fail silently. Typing without the
    // accessibility right posts events that go nowhere and returns no error,
    // which is indistinguishable from a transcription that came back empty.
    let trusted = Typist.hasAccessibilityPermission(prompting: true)
    Log.say("accessibility (the right to type): \(trusted ? "granted" : "DENIED")")
    if !trusted {
      Log.say("  nothing will be typed until this binary is ticked in")
      Log.say("  System Settings > Privacy & Security > Accessibility")
      Log.say("  the grant follows the binary, so a rebuild can lose it")
    }

    let mic = AVCaptureDevice.authorizationStatus(for: .audio)
    Log.say("microphone: \(mic == .authorized ? "granted" : "\(mic.rawValue), not authorized")")
    AVCaptureDevice.requestAccess(for: .audio) { granted in
      Log.say("microphone after asking: \(granted ? "granted" : "DENIED")")
    }

    // The audio thread hands over a finished phrase. Nothing slow can happen
    // there, so it goes straight to the worker.
    recorder.onSegment = { [weak self] take in
      Task { @MainActor in self?.enqueue(take) }
    }

    // The microphone becoming live is not the same moment as the hotkey. With
    // a Bluetooth headset they are a moment apart, and anything said in between
    // is gone, so the icon has to tell them apart. It cannot be a sound any
    // more, because by then the machine is muted.
    recorder.onReady = { [weak self] in
      Task { @MainActor in
        Log.say("the microphone is live, talk now")
        self?.micLive = true
        self?.redraw()
      }
    }

    // A Cadmus that dies holding the mute leaves the machine silent with no
    // sign of why, which is a worse bug than the one muting solves. Quitting
    // goes through the delegate, and every way of dying that can still run code
    // goes through these. The crash signals are on the list because a crash is
    // exactly when nobody is left to clean up.
    for killed in [SIGTERM, SIGINT, SIGHUP, SIGSEGV, SIGABRT, SIGILL, SIGBUS, SIGFPE] {
      signal(killed) { _ in
        Playback.restore()
        InputDevice.restore()
        exit(1)
      }
    }

    // Touched here so the files exist before the first phrase rather than
    // appearing halfway through one.
    Log.say(
      "vocabulary: \(Vocabulary.prompt == nil ? "none" : "loaded"), "
        + "\(Vocabulary.replacements.count) replacements, from ~/.config/cadmus")

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

  func applicationWillTerminate(_ notification: Notification) {
    Playback.restore()
    InputDevice.restore()
  }

  private func toggle() {
    recorder.isRecording ? finish() : begin()
  }

  private func begin() {
    // The machine goes quiet while I dictate. This is no longer needed to
    // protect the audio, now that the headset microphone is never opened: it is
    // here so that nothing playing gets recorded along with me, and because I
    // would rather not be talked at while talking. CADMUS_QUIET=0 turns it off.
    micLive = false
    if quiet { Playback.silence() }
    do {
      try recorder.start()
      Log.say("recording")
      redraw()
    } catch {
      Log.say("could not start recording: \(error.localizedDescription)")
      Playback.restore()
      fail(error)
    }
  }

  /// Stopping closes the microphone and gives the machine its sound back.
  /// Everything said before it is already on its way, or already typed.
  private func finish() {
    recorder.stop()
    Log.say("stopped")
    micLive = false
    Playback.restore()
    redraw()
  }

  private func enqueue(_ take: Recorder.Take) {
    guard let transcriber else { return }
    pending += 1
    redraw()

    let method = self.method
    Log.say(String(format: "phrase of %.1fs handed to the model", take.seconds))
    worker.async {
      let transcription: Transcriber.Transcription
      do {
        transcription = try transcriber.transcribe(take.samples)
      } catch {
        Log.say("the model failed: \(error.localizedDescription)")
        transcription = Transcriber.Transcription(text: "", unsure: [])
      }

      // Written here rather than after typing, so what I said is kept even if
      // the keystrokes go nowhere.
      Journal.record(take, as: transcription)

      let text = transcription.text
      DispatchQueue.main.async {
        self.pending -= 1
        self.redraw()
        Log.say("the model said: \(text.isEmpty ? "(nothing)" : "\"\(text)\"")")
        if !transcription.unsure.isEmpty {
          Log.say("unsure about: \(transcription.unsure.joined(separator: ", "))")
        }
        guard !text.isEmpty else { return }
        Log.say("typing it with \(method.rawValue)")
        // A space after, so the next phrase does not weld itself to this one.
        // Still no Enter, ever: I read it and I send it.
        Typist.insert(text + " ", using: method)
      }
    }
  }

  /// `◌` opening the microphone, `●` listening, `…` catching up, `○` idle.
  ///
  /// The first two used to be one state and a sound. They are separate now
  /// because the machine is muted while I dictate, so the icon is the only
  /// thing left that can tell me when it is safe to talk.
  private func redraw() {
    if recorder.isRecording {
      statusItem.button?.title = micLive ? "●" : "◌"
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
