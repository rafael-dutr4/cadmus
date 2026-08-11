import Foundation

/// What I said, and how I said it, one line per phrase.
///
/// Cadmus does not coach me and it is not going to. It is a keyboard, and a
/// keyboard that told me my grammar was wrong would be a different program with
/// a different rule. What it can do is keep the record, and the record is the
/// thing an agent can read later and answer questions about: what am I getting
/// wrong, which words keep coming out unclear, am I getting faster.
///
/// Every number here is one the recorder already computed to decide where the
/// phrase ended, and the confidences come from the model's own output. Nothing
/// is measured for the journal, it is only kept instead of thrown away.
///
/// The audio is still never written. This is text, and it is only ever on this
/// machine.
public enum Journal {
  /// Whose journal this is. Cadmus keeps one of everything I dictate;
  /// Fabulinus keeps one of everything I practised. Same shape, same reader,
  /// different question, so they are different files.
  nonisolated(unsafe) public static var name = "cadmus"

  private static var directory: URL {
    FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/share/\(name)")
  }

  /// On unless told otherwise. Everything I dictate ends up here, which is
  /// worth knowing: CADMUS_JOURNAL=0 turns it off.
  private static let enabled = ProcessInfo.processInfo.environment["CADMUS_JOURNAL"] != "0"

  /// Words that are not wrong but are what I say while deciding what to say.
  private static let fillers = [
    "uh", "um", "erm", "ah", "hmm", "like", "you know", "I mean", "kind of",
    "sort of", "basically", "actually",
  ]

  /// One file per day, one JSON object per line. A line is appended and never
  /// revisited, so a crash costs the phrase being written and not the day.
  public static func record(_ take: Recorder.Take, as transcription: Transcriber.Transcription) {
    guard enabled, !transcription.text.isEmpty else { return }

    let words = transcription.text.split(whereSeparator: { $0.isWhitespace }).count
    // Words per minute of talking, not of recording. Counting the pauses would
    // make a thoughtful sentence look like a slow one.
    let pace = take.speech > 0 ? Double(words) / take.speech * 60 : 0

    let entry: [String: Any] = [
      "at": ISO8601DateFormatter().string(from: Date()),
      "said": transcription.text,
      "unsure": transcription.unsure,
      "words": words,
      "speech": (take.speech * 10).rounded() / 10,
      "seconds": (take.seconds * 10).rounded() / 10,
      "wpm": Int(pace.rounded()),
      "hesitations": take.hesitations,
      "fillers": countFillers(in: transcription.text),
    ]

    guard
      let line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
      var data = String(data: line, encoding: .utf8)?.data(using: .utf8)
    else { return }
    data.append(0x0A)

    append(data)
  }

  private static func countFillers(in text: String) -> Int {
    let lower = text.lowercased()
    return fillers.reduce(0) { total, filler in
      // Bounded, so "like" in "I would like" counts and "like" inside
      // "unlikely" does not.
      let pattern = "\\b\(NSRegularExpression.escapedPattern(for: filler))\\b"
      guard let regex = try? NSRegularExpression(pattern: pattern) else { return total }
      return total
        + regex.numberOfMatches(in: lower, range: NSRange(lower.startIndex..., in: lower))
    }
  }

  private static func append(_ data: Data) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let file = directory.appending(path: "\(formatter.string(from: Date())).jsonl")

    if let handle = try? FileHandle(forWritingTo: file) {
      defer { try? handle.close() }
      do {
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
      } catch {
        Log.say("could not write the journal: \(error.localizedDescription)")
      }
    } else {
      // First phrase of the day, so there is no file to append to yet.
      do {
        try data.write(to: file, options: .atomic)
      } catch {
        Log.say("could not write the journal: \(error.localizedDescription)")
      }
    }
  }
}
