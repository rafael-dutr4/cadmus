import Foundation

/// Teaching the model my words, and cleaning up after it.
///
/// This is the part macOS dictation cannot do, and the reason the project is
/// worth building. It is two mechanisms and they work at different ends.
///
/// Before: Whisper accepts a prompt that biases the decoder toward the words in
/// it. It is not a dictionary and not a rule, it moves probabilities, so it
/// helps and it does not guarantee.
///
/// After: what the prompt does not fix gets replaced in the text. Both live in
/// files rather than in code, because a word I get wrong today should be
/// fixable by editing a line, the way the rules file works in Aerarium.
enum Vocabulary {
  private static let directory = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".config/cadmus")

  private static var vocabularyFile: URL { directory.appending(path: "vocabulary.txt") }
  private static var replacementsFile: URL { directory.appending(path: "replacements.txt") }

  /// Loaded once. Editing the files means restarting Cadmus, which is honest:
  /// a prompt that changed halfway through a take would make two phrases of the
  /// same sentence disagree.
  static let prompt: String? = loadPrompt()
  static let replacements: [(String, String)] = loadReplacements()

  /// Whisper's own name for a stretch of nothing, and its cousins. It writes
  /// these when handed audio with no speech in it, and they are not text I ever
  /// want typed into a prompt.
  private static let notSpeech = [
    "[BLANK_AUDIO]", "[SILENCE]", "(silence)", "[MUSIC]", "[Music]",
    "(upbeat music)", "[SOUND]", "[NOISE]", "[INAUDIBLE]", "you",
  ]

  /// Whether the model returned something worth typing.
  ///
  /// A bare "you" is on the list because it is what this model returns for a
  /// second of room tone, which happens more often than anybody says the word
  /// alone.
  static func isSpeech(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    let bare = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".,!? "))
    return !notSpeech.contains { $0.caseInsensitiveCompare(bare) == .orderedSame }
  }

  /// Applies every replacement, in the order they are written.
  static func correct(_ text: String) -> String {
    replacements.reduce(text) { result, pair in
      result.replacingOccurrences(
        of: pair.0, with: pair.1, options: [.caseInsensitive, .diacriticInsensitive])
    }
  }

  // MARK: - The files

  private static func loadPrompt() -> String? {
    writeDefaultsIfMissing()
    guard let contents = try? String(contentsOf: vocabularyFile, encoding: .utf8) else {
      return nil
    }
    let words =
      contents
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    guard !words.isEmpty else { return nil }
    // Written as a sentence rather than a list. The prompt is read as text that
    // came before mine, so words sitting in prose bias better than a column of
    // them would.
    return words.joined(separator: ", ") + "."
  }

  private static func loadReplacements() -> [(String, String)] {
    writeDefaultsIfMissing()
    guard let contents = try? String(contentsOf: replacementsFile, encoding: .utf8) else {
      return []
    }
    return contents.split(separator: "\n").compactMap { line in
      let line = line.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
      let parts = line.components(separatedBy: "=>")
      guard parts.count == 2 else { return nil }
      let wrong = parts[0].trimmingCharacters(in: .whitespaces)
      let right = parts[1].trimmingCharacters(in: .whitespaces)
      guard !wrong.isEmpty else { return nil }
      return (wrong, right)
    }
  }

  private static func writeDefaultsIfMissing() {
    try? FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true)

    if !FileManager.default.fileExists(atPath: vocabularyFile.path) {
      try? """
      # Words Whisper does not expect. One per line, # for a comment.
      # These are pushed at the model before every phrase, so it reaches for
      # them instead of for whatever sounds closest.
      Cadmus
      Aerarium
      Obsidian
      Claude Code
      whisper.cpp
      ggml
      Swift
      macOS
      Homebrew
      TOML
      JSON
      wikilink
      repository
      commit
      """.write(to: vocabularyFile, atomically: true, encoding: .utf8)
    }

    if !FileManager.default.fileExists(atPath: replacementsFile.path) {
      try? """
      # What the prompt does not fix. One per line: wrong => right.
      # Applied in order, ignoring case and accents.
      Cadence => Cadmus
      Cadmos => Cadmus
      Kadmos => Cadmus
      """.write(to: replacementsFile, atomically: true, encoding: .utf8)
    }
  }
}
