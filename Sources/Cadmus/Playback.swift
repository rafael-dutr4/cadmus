import AppKit
import CoreAudio

/// Silencing the machine while Cadmus listens, and putting it back after.
///
/// This exists for Bluetooth. A headset cannot carry good audio out and a
/// microphone in at the same time. Opening the microphone drags the device into
/// the hands free profile, and everything that keeps playing through it comes
/// out sounding broken, so anything still making noise while I dictate is noise
/// I would want to stop anyway.
///
/// Two mechanisms, because one is not enough. Pausing asks whatever is playing
/// to stop and keeps my place in it, and it only reaches an application that
/// listens to the media keys. Muting the output device catches everything else:
/// a video, a notification, a tab I forgot about, a sound that starts after I
/// began talking.
///
/// The alternative was to record from the built in microphone and leave the
/// audio alone. That is a better idea on paper and it does not work: pointing
/// the engine at another device after the input node exists leaves it running
/// at the old rate, and it delivers about a tenth of the audio.
enum Playback {
  /// Play/pause. It is a toggle, which is the whole reason for the check below.
  private static let playPauseKey: Int32 = 16

  /// What was true before Cadmus touched anything. Nothing is restored that
  /// Cadmus did not change: leaving the machine louder than I set it is worse
  /// than leaving it quiet.
  nonisolated(unsafe) private static var previousMute: UInt32?
  nonisolated(unsafe) private static var previousVolume: Float32?
  nonisolated(unsafe) private static var paused = false

  // MARK: - Going quiet

  /// Pauses what is playing and mutes the output for the length of a take.
  static func silence() {
    paused = pauseIfPlaying()
    mute()
  }

  /// Puts back exactly what was changed, in the reverse order. Unmuting first
  /// means the music never restarts into a muted machine.
  static func restore() {
    unmute()
    if paused {
      paused = false
      press(playPauseKey)
    }
  }

  /// Pauses only if something is actually playing, and says whether it did.
  ///
  /// The check is not politeness, it is correctness: the media key is a toggle,
  /// so pressing it while nothing plays would start the last thing I listened
  /// to. Recording has to be able to fail without turning on music.
  private static func pauseIfPlaying() -> Bool {
    guard isPlaying() else { return false }
    press(playPauseKey)
    return true
  }

  // MARK: - The output device

  private static func mute() {
    let device = defaultOutput()

    // Master mute is the clean way and most devices have it. The ones that do
    // not still have a volume, so the fallback is to take it to zero and
    // remember where it was.
    if let current = readFlag(device, kAudioDevicePropertyMute) {
      previousMute = current
      writeFlag(device, kAudioDevicePropertyMute, 1)
      return
    }
    if let current = readVolume(device) {
      previousVolume = current
      writeVolume(device, 0)
    }
  }

  private static func unmute() {
    let device = defaultOutput()
    if let previous = previousMute {
      writeFlag(device, kAudioDevicePropertyMute, previous)
      previousMute = nil
    }
    if let previous = previousVolume {
      writeVolume(device, previous)
      previousVolume = nil
    }
  }

  /// Whether the default output device is being driven by anybody. This asks
  /// the device rather than any application, so it is true for a browser tab
  /// and a music player alike, and it needs no permission over either.
  private static func isPlaying() -> Bool {
    (readFlag(defaultOutput(), kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0) != 0
  }

  private static func defaultOutput() -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var id: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
    return id
  }

  private static func address(_ selector: AudioObjectPropertySelector)
    -> AudioObjectPropertyAddress
  {
    AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  // Concrete rather than generic on purpose. These properties are plain C
  // numbers, and a generic version would compile for types that cannot be
  // copied to a device this way.

  private static func readFlag(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector)
    -> UInt32?
  {
    var property = address(selector)
    guard AudioObjectHasProperty(device, &property) else { return nil }
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else {
      return nil
    }
    return value
  }

  private static func writeFlag(
    _ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ value: UInt32
  ) {
    var property = address(selector)
    var value = value
    AudioObjectSetPropertyData(
      device, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
  }

  private static func readVolume(_ device: AudioDeviceID) -> Float32? {
    var property = address(kAudioDevicePropertyVolumeScalar)
    guard AudioObjectHasProperty(device, &property) else { return nil }
    var value: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else {
      return nil
    }
    return value
  }

  private static func writeVolume(_ device: AudioDeviceID, _ value: Float32) {
    var property = address(kAudioDevicePropertyVolumeScalar)
    var value = value
    AudioObjectSetPropertyData(
      device, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
  }

  // MARK: - Media keys

  /// The media keys are not keyboard events. They are system defined events
  /// carrying the key in `data1`, which is why this cannot go through the same
  /// path as the typing in Typist.
  private static func press(_ key: Int32) {
    for down in [true, false] {
      let state: Int32 = down ? 0xA : 0xB
      let event = NSEvent.otherEvent(
        with: .systemDefined,
        location: .zero,
        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        subtype: 8,
        data1: Int((key << 16) | (state << 8)),
        data2: -1
      )
      event?.cgEvent?.post(tap: .cghidEventTap)
    }
  }
}
