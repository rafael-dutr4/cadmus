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

  func transcribe(_ samples: [Float]) throws -> String {
    try queue.sync { try run(samples) }
  }

  private func run(_ samples: [Float]) throws -> String {
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

    let status = "en".withCString { language -> Int32 in
      params.language = language
      return samples.withUnsafeBufferPointer { buffer in
        whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
      }
    }
    guard status == 0 else { throw CadmusError.transcriptionFailed(status) }

    var text = ""
    for index in 0..<whisper_full_n_segments(context) {
      guard let segment = whisper_full_get_segment_text(context, index) else { continue }
      text += String(cString: segment)
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
