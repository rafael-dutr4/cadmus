// The tap block is typed `@Sendable` but the buffer it hands over is not, and
// there is no version of this that satisfies the checker: the audio thread owns
// that buffer for the length of the call and nothing else can see it.
@preconcurrency import AVFoundation

/// Captures the microphone into the exact buffer the model wants: 16 kHz, mono,
/// float. Nothing is ever written to disk.
///
/// Two threads touch this: the main thread starts and stops it, the audio
/// thread appends to it. The lock is what makes that safe, so the promise to
/// the compiler is one I actually keep.
final class Recorder: @unchecked Sendable {
  /// Whisper is trained on 16 kHz audio and resamples anything else itself.
  /// Converting here means it never has to.
  static let sampleRate: Double = 16_000

  private let engine = AVAudioEngine()
  private var converter: AVAudioConverter?
  private var samples: [Float] = []
  private let lock = NSLock()

  private(set) var isRecording = false

  /// The format the tap produces, and the only format the rest of the program
  /// knows about.
  private let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: Recorder.sampleRate,
    channels: 1,
    interleaved: false
  )!

  func start() throws {
    guard !isRecording else { return }

    lock.withLock { samples.removeAll(keepingCapacity: true) }

    let input = engine.inputNode
    // The hardware picks this, not me. It is usually 48 kHz stereo.
    let inputFormat = input.inputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0 else {
      throw KadmosError.noInputDevice
    }
    converter = AVAudioConverter(from: inputFormat, to: targetFormat)

    input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
      self?.append(buffer)
    }

    engine.prepare()
    try engine.start()
    isRecording = true
  }

  /// Stops the engine and hands over everything captured.
  @discardableResult
  func stop() -> [Float] {
    guard isRecording else { return [] }
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    isRecording = false
    return lock.withLock { samples }
  }

  private func append(_ buffer: AVAudioPCMBuffer) {
    guard let converter else { return }

    let ratio = targetFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
    guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
      return
    }

    // The converter pulls: it asks for input until it has enough to fill the
    // output buffer. This block has one buffer to give and says so after.
    // The flag is a reference because the block is typed as escaping even
    // though the converter calls it before returning.
    let given = Flag()
    var error: NSError?
    converter.convert(to: out, error: &error) { _, status in
      if given.value {
        status.pointee = .noDataNow
        return nil
      }
      given.value = true
      status.pointee = .haveData
      return buffer
    }

    guard error == nil, out.frameLength > 0, let channel = out.floatChannelData?[0] else {
      return
    }
    let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
    lock.withLock { samples.append(contentsOf: chunk) }
  }
}

/// A mutable bool that survives being captured by an escaping closure.
private final class Flag: @unchecked Sendable {
  var value = false
}

extension Array where Element == Float {
  /// Root mean square, the cheap measure of how loud the take was. This is
  /// what keeps silence away from the model: given silence Whisper does not
  /// return nothing, it returns a confident sentence it made up.
  var rms: Float {
    guard !isEmpty else { return 0 }
    let sum = reduce(Float(0)) { $0 + $1 * $1 }
    return (sum / Float(count)).squareRoot()
  }

  var seconds: Double {
    Double(count) / Recorder.sampleRate
  }
}
