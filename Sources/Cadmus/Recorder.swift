// The tap block is typed `@Sendable` but the buffer it hands over is not, and
// there is no version of this that satisfies the checker: the audio thread owns
// that buffer for the length of the call and nothing else can see it.
@preconcurrency import AVFoundation

/// Captures the microphone into the exact buffer the model wants: 16 kHz, mono,
/// float, and cuts it into phrases. Nothing is ever written to disk.
///
/// Two threads touch this: the main thread starts and stops it, the audio
/// thread appends to it. The lock is what makes that safe, so the promise to
/// the compiler is one I actually keep.
final class Recorder: @unchecked Sendable {
  /// Whisper is trained on 16 kHz audio and resamples anything else itself.
  /// Converting here means it never has to.
  static let sampleRate: Double = 16_000

  /// One finished phrase, and what was measured while it was said.
  ///
  /// The numbers are free: they are the same ones that decided where the phrase
  /// ended. Nothing here is computed for the journal, it is only kept instead
  /// of thrown away.
  struct Take {
    let samples: [Float]
    /// Seconds that were actually speech, not the length of the recording.
    let speech: Double
    let seconds: Double
    /// Gaps long enough to notice but too short to end the phrase. This is
    /// hesitation, which is the thing worth practising away.
    let hesitations: Int
  }

  /// Called with one finished phrase, from the audio thread. The caller has to
  /// get itself somewhere else before doing anything slow with it.
  var onSegment: ((Take) -> Void)?

  /// Called once, when the first real audio arrives.
  ///
  /// Starting the engine and hearing something are not the same moment. A
  /// Bluetooth headset has to change profile before its microphone exists, and
  /// that takes a noticeable while, so this is what tells me it is safe to
  /// talk instead of me guessing.
  var onReady: (() -> Void)?
  private var ready = false

  /// A new engine for every take, and none between them. Holding one open keeps
  /// the input device open with it, and a device nobody is using is a device
  /// that is free to go back to whatever profile it prefers.
  private var engine: AVAudioEngine?
  private var converter: AVAudioConverter?
  private var current: [Float] = []
  private var voiced: Double = 0
  private var silence: Double = 0
  private var hesitations = 0
  private var countedThisGap = false
  private let lock = NSLock()

  private(set) var isRecording = false

  private let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: Recorder.sampleRate,
    channels: 1,
    interleaved: false
  )!

  // MARK: - Where a phrase ends
  //
  // The cut is a pause, not a clock. Whisper reads a whole phrase at once and
  // guesses badly at half of one, so cutting mid word to be quick would buy
  // latency with the accuracy that is the point of the project.
  //
  // A pause is also the only cut that never has to be taken back. The text goes
  // into somebody else's window, where nothing can be retracted, so a phrase is
  // only typed once it is finished.

  /// What counts as speech is measured, not decided in advance.
  ///
  /// A fixed number was wrong the moment anything changed. Set for a headset
  /// against my mouth it was twice my voice on the built in microphone, so
  /// nothing crossed it, no pause was ever found, and the only text that came
  /// out was whatever stopping flushed. It would have been wrong again in a
  /// louder room, or on a different machine.
  ///
  /// So Cadmus tracks how quiet the room is and calls speech anything a few
  /// times louder than that. A number can still be forced with
  /// CADMUS_VOICE_FLOOR, which is now for arguing with it rather than for
  /// making it work.
  private let forcedFloor: Float? =
    ProcessInfo.processInfo.environment["CADMUS_VOICE_FLOOR"].flatMap(Float.init)

  /// The running estimate of the room with nobody talking in it.
  private var background: Float = 0

  /// How far above the room something has to be to be a voice. Speech is
  /// several times louder than the noise it sits in, so this does not have to
  /// be precise, only on the right side of the gap.
  private let overRoom: Float = 3.5

  /// Below this nothing is speech, whatever the room says. It stops a silent
  /// room from making the threshold so small that its own hiss becomes a voice.
  private let quietestPossibleVoice: Float = 0.002

  private var voiceFloor: Float {
    if let forcedFloor { return forcedFloor }
    return max(quietestPossibleVoice, background * overRoom)
  }

  /// How long the quiet has to last to count as the end of a phrase.
  ///
  /// This was 0.7s, which is a pause between sentences for someone reading
  /// aloud and a pause in the middle of one for someone thinking. Dictating a
  /// prompt is the second thing, so it cut me into fragments like "True" and
  /// "speak." and handed each one to the model with no sentence around it.
  ///
  /// The cost of raising it is that text appears later. That is the right way
  /// to spend it: a whole sentence transcribed a second later beats half a
  /// sentence transcribed now, because the half sentence is also wrong.
  private let pause: Double =
    ProcessInfo.processInfo.environment["CADMUS_PAUSE"].flatMap(Double.init) ?? 1.4

  /// Below this there is no phrase, only a noise that crossed the floor.
  private let shortestPhrase: Double = 0.5

  /// A gap long enough to hear as a hesitation, short enough that the sentence
  /// is still going.
  private let hesitation: Double = 0.35

  /// If I never pause, the phrase is cut anyway. Whisper's window is 30
  /// seconds and anything past it is dropped without a word about it.
  private let longestPhrase: Double = 20

  func start() throws {
    guard !isRecording else { return }
    reset()

    // Before the engine exists, because the engine reads the device once and
    // keeps it. Changing it afterwards leaves the node running at the old rate.
    InputDevice.useBuiltIn()

    let (engine, inputFormat): (AVAudioEngine, AVAudioFormat)
    do {
      (engine, inputFormat) = try openInput()
    } catch {
      InputDevice.restore()
      throw error
    }
    self.engine = engine

    let input = engine.inputNode
    converter = AVAudioConverter(from: inputFormat, to: targetFormat)

    input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
      self?.append(buffer)
    }

    engine.prepare()
    do {
      try engine.start()
    } catch {
      self.engine = nil
      InputDevice.restore()
      throw error
    }
    isRecording = true
  }

  /// Stops the engine and flushes whatever phrase was still open. The engine is
  /// dropped rather than kept, so the microphone is actually released.
  func stop() {
    guard isRecording else { return }
    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()
    engine = nil
    converter = nil
    isRecording = false
    InputDevice.restore()
    emitIfWorthIt()
  }

  /// An engine pointed at a device that is actually ready.
  ///
  /// Changing the default input takes effect when it takes effect, not when the
  /// call returns, and an engine built a moment too early reports a sample rate
  /// of zero and records nothing. The engine reads the device once, at the
  /// moment its input node is created, so waiting means building a new one
  /// rather than asking the same one again.
  ///
  /// It almost always succeeds on the first try. The waiting is for the take
  /// that comes right after the previous one put the device back.
  private func openInput() throws -> (AVAudioEngine, AVAudioFormat) {
    for _ in 0..<20 {
      let engine = AVAudioEngine()
      let format = engine.inputNode.inputFormat(forBus: 0)
      if format.sampleRate > 0 { return (engine, format) }
      Thread.sleep(forTimeInterval: 0.05)
    }
    throw CadmusError.noInputDevice
  }

  /// Follows the quiet down quickly and the loud up slowly.
  ///
  /// The asymmetry is the whole trick. Falling fast means the estimate settles
  /// on the room within a moment of starting, and rising slowly means a long
  /// sentence never drags the threshold up behind it until my own voice counts
  /// as background and the phrase never ends.
  private func learnTheRoom(_ level: Float) {
    if background == 0 {
      background = level
    } else if level < background {
      background += (level - background) * 0.3
    } else {
      background += (level - background) * 0.002
    }
  }

  private func reset() {
    ready = false
    background = 0
    lock.withLock {
      current.removeAll(keepingCapacity: true)
      voiced = 0
      silence = 0
    }
  }

  private func append(_ buffer: AVAudioPCMBuffer) {
    guard let converter else { return }

    if !ready, buffer.frameLength > 0 {
      ready = true
      onReady?()
    }

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
    accumulate(Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength))))
  }

  private func accumulate(_ chunk: [Float]) {
    let level = chunk.rms
    learnTheRoom(level)
    let loud = level >= voiceFloor
    let length = chunk.seconds

    let ended: Bool = lock.withLock {
      // Quiet before a single word has been said is not a pause, it is the wait
      // before I start. Dropping it keeps the buffer from growing all day, and
      // keeps a phrase from opening with a minute of nothing in front of it.
      if !loud && voiced == 0 {
        current.removeAll(keepingCapacity: true)
        return false
      }

      current.append(contentsOf: chunk)
      if loud {
        voiced += length
        silence = 0
        countedThisGap = false
      } else {
        silence += length
        // Counted once per gap, and only for gaps that are noticeable without
        // being the end of the phrase.
        if !countedThisGap, silence >= hesitation, silence < pause {
          hesitations += 1
          countedThisGap = true
        }
      }

      let paused = silence >= pause && voiced >= shortestPhrase
      return paused || current.seconds >= longestPhrase
    }

    if ended { emitIfWorthIt() }
  }

  private func emitIfWorthIt() {
    let heard = lock.withLock { (voiced, current.seconds, current.rms) }
    Log.say(
      String(
        format: "phrase ended: %.1fs of speech in %.1fs of audio, loudness %.4f (floor %.4f)",
        heard.0, heard.1, heard.2, voiceFloor))

    let take: Take? = lock.withLock {
      defer {
        current.removeAll(keepingCapacity: true)
        voiced = 0
        silence = 0
        hesitations = 0
        countedThisGap = false
      }
      guard voiced >= shortestPhrase else { return nil }
      return Take(
        samples: current,
        speech: voiced,
        seconds: current.seconds,
        hesitations: hesitations
      )
    }
    if let take { onSegment?(take) }
  }
}

/// A mutable bool that survives being captured by an escaping closure.
private final class Flag: @unchecked Sendable {
  var value = false
}

extension Array where Element == Float {
  /// Root mean square, the cheap measure of how loud a piece of audio is. This
  /// is what finds the pauses, and what keeps silence away from the model:
  /// given silence Whisper does not return nothing, it returns a confident
  /// sentence it made up.
  var rms: Float {
    guard !isEmpty else { return 0 }
    let sum = reduce(Float(0)) { $0 + $1 * $1 }
    return (sum / Float(count)).squareRoot()
  }

  var seconds: Double {
    Double(count) / Recorder.sampleRate
  }
}
