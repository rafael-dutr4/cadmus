import Foundation

/// A line per thing that happens, on stderr.
///
/// Cadmus fails silently by design: a take that produces nothing looks the same
/// whether the microphone was closed, the phrase never ended, the model
/// returned an empty string, or the keystrokes went nowhere. Those are four
/// different bugs and guessing between them cost more than this file.
public enum Log {
  private static let start = Date()

  public static func say(_ message: String) {
    let elapsed = String(format: "%7.2fs", Date().timeIntervalSince(start))
    FileHandle.standardError.write(Data("[\(elapsed)] \(message)\n".utf8))
  }
}
