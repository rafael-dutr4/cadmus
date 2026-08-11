import CWhisper
import Foundation

/// Turns the recorded samples into text.
///
/// The model is loaded once and kept. Loading it costs about as much as a short
/// transcription, and paying that on every phrase would be the whole latency
/// budget spent on nothing.
///
/// One take at a time. The hotkey is free to start a new recording while the
/// last one is still transcribing, and two calls into the same whisper context
/// at once would corrupt its state, so the queue serializes them.
final class Transcriber: @unchecked Sendable {
  private let context: OpaquePointer
  private let threads: Int32
  private let queue = DispatchQueue(label: "br.dutra.cadmus.transcriber")

  /// Below this the model was guessing. Not a measurement of anything, a line
  /// drawn across a probability, and it is here to be moved once I have seen a
  /// week of what falls under it.
  private static let sureEnough: Float = 0.6

  /// The Homebrew build of ggml is split: the library that whisper links is a
  /// loader, and the backends that do the arithmetic (Metal, BLAS, and one CPU
  /// build per chip generation) are separate files it opens at runtime. Loading
  /// them is the caller's job and whisper does not do it, so a program that
  /// skips this gets a context with zero devices and dies on an assert inside
  /// the library. `whisper-cli` calls this in its own `main` for the same
  /// reason. The search path is compiled into the loader, so it takes no
  /// argument here.
  private static let backends: Void = ggml_backend_load_all()

  init(modelPath: String) throws {
    guard FileManager.default.fileExists(atPath: modelPath) else {
      throw CadmusError.modelMissing(modelPath)
    }
    _ = Transcriber.backends

    var params = whisper_context_default_params()
    params.use_gpu = true  // Metal. Without it this is several times slower.

    guard let context = whisper_init_from_file_with_params(modelPath, params) else {
      throw CadmusError.modelFailedToLoad(modelPath)
    }
    self.context = context

    // The efficiency cores make a batch like this slower, not faster, so
    // only the performance cores are asked for.
    let cores = ProcessInfo.processInfo.activeProcessorCount
    self.threads = Int32(max(1, min(8, cores - 2)))
  }

  deinit {
    whisper_free(context)
  }

  /// What the model returned, and how sure it was of it.
  struct Transcription {
    let text: String
    /// The words the model was least sure about. A word it hedged on is
    /// usually a word that was said unclearly, which is the only measurement
    /// of my own pronunciation available without another model.
    let unsure: [String]
  }

  func transcribe(_ samples: [Float]) throws -> Transcription {
    try queue.sync { try run(samples) }
  }

  private func run(_ samples: [Float]) throws -> Transcription {
    var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
    params.n_threads = threads
    params.translate = false
    params.no_timestamps = true
    params.print_progress = false
    params.print_realtime = false
    params.print_special = false
    params.print_timestamps = false
    // Every press is its own thought. Carrying the previous transcription in
    // as context is what makes Whisper repeat a sentence it already wrote.
    params.no_context = true
    params.suppress_blank = true

    // Both strings have to outlive the call, which is why this nests instead of
    // assigning. A Swift string handed to C does not keep its buffer alive past
    // the expression that produced it.
    let status = "en".withCString { language -> Int32 in
      params.language = language
      return (Vocabulary.prompt ?? "").withCString { prompt -> Int32 in
        if Vocabulary.prompt != nil { params.initial_prompt = prompt }
        return samples.withUnsafeBufferPointer { buffer in
          whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
        }
      }
    }
    guard status == 0 else { throw CadmusError.transcriptionFailed(status) }

    var text = ""
    var unsure: [String] = []
    for segment in 0..<whisper_full_n_segments(context) {
      guard let contents = whisper_full_get_segment_text(context, segment) else { continue }
      text += String(cString: contents)
      unsure += hedgedWords(in: segment)
    }
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)

    // Handed audio with no speech in it, the model does not return nothing. It
    // returns its own name for nothing, and that is not text I want typed.
    guard Vocabulary.isSpeech(text) else { return Transcription(text: "", unsure: []) }
    return Transcription(text: Vocabulary.correct(text), unsure: unsure)
  }

  /// The words the model hedged on.
  ///
  /// Whisper reports a probability per token, and a token is often a piece of a
  /// word, so the pieces are joined back up before being judged. Punctuation is
  /// skipped: the model is frequently unsure where a comma goes and that says
  /// nothing about how anything was said.
  private func hedgedWords(in segment: Int32) -> [String] {
    var words: [(text: String, worst: Float)] = []

    for index in 0..<whisper_full_n_tokens(context, segment) {
      guard let raw = whisper_full_get_token_text(context, segment, index) else { continue }
      let piece = String(cString: raw)
      // Timestamps and the rest of the model's own markers.
      guard !piece.hasPrefix("[_") else { continue }

      let probability = whisper_full_get_token_p(context, segment, index)
      // A piece that does not start a new word belongs to the previous one, and
      // a word is only as certain as its least certain piece.
      if piece.hasPrefix(" ") || words.isEmpty {
        words.append((piece, probability))
      } else {
        words[words.count - 1].text += piece
        words[words.count - 1].worst = min(words[words.count - 1].worst, probability)
      }
    }

    return
      words
      .map { (word: $0.text.trimmingCharacters(in: .whitespaces), worst: $0.worst) }
      .filter { $0.worst < Transcriber.sureEnough }
      .map { $0.word.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'")) }
      .filter { $0.count > 1 }
  }
}
