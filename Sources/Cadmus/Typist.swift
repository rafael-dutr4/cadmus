import AppKit
import CoreGraphics

/// Puts text into whatever application has focus, and never presses Enter.
///
/// Two ways to do this and they fail differently, so both are here and the
/// config picks. Synthesizing the characters is indistinguishable from me
/// typing, which is what a terminal UI expects. Pasting is faster and cannot
/// drop a character, but an application is free to treat a paste as an
/// attachment instead of as input (the Claude Code prompt collapses a large one
/// into `[Pasted text]`, which hides the words I am supposed to be checking).
enum Typist {
  enum Method: String {
    case keystrokes
    case paste
  }

  static func insert(_ text: String, using method: Method) {
    guard !text.isEmpty else { return }
    switch method {
    case .keystrokes: typeUnicode(text)
    case .paste: pasteAndRestore(text)
    }
  }

  /// macOS grants the right to post events per binary path, so this is false
  /// until the binary sitting at this exact path is ticked in System Settings.
  static func hasAccessibilityPermission(prompting: Bool) -> Bool {
    // The constant behind this key is a mutable global in the C header, so
    // the string is written out instead of read from the SDK.
    let options = ["AXTrustedCheckOptionPrompt": prompting] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  // MARK: - Keystrokes

  private static func typeUnicode(_ text: String) {
    guard let source = CGEventSource(stateID: .hidSystemState) else { return }
    // A key event carries its own string, so the layout of the physical
    // keyboard is irrelevant and a keycode never has to be looked up.
    // The buffer behind it is small, hence the chunking.
    for chunk in text.chunked(by: 16) {
      var utf16 = Array(chunk.utf16)
      for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
        else { continue }
        event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        event.post(tap: .cghidEventTap)
      }
      // Fast typing, but typing. Without this a TUI redrawing on every
      // keystroke can fall behind and lose the tail.
      usleep(1_500)
    }
  }

  // MARK: - Paste

  private static func pasteAndRestore(_ text: String) {
    let pasteboard = NSPasteboard.general
    // Only the string is saved. Restoring every representation of an
    // arbitrary clipboard (a file, an image, a promise) is not something I
    // can do correctly, so the honest scope is text.
    let saved = pasteboard.string(forType: .string)

    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)

    guard let source = CGEventSource(stateID: .hidSystemState) else { return }
    let v: CGKeyCode = 9
    for down in [true, false] {
      let event = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: down)
      event?.flags = .maskCommand
      event?.post(tap: .cghidEventTap)
    }

    // The paste has to be read before the clipboard changes under it.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      guard let saved else { return }
      pasteboard.clearContents()
      pasteboard.setString(saved, forType: .string)
    }
  }
}

extension String {
  func chunked(by size: Int) -> [String] {
    var result: [String] = []
    var index = startIndex
    while index < endIndex {
      let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
      result.append(String(self[index..<end]))
      index = end
    }
    return result
  }
}
