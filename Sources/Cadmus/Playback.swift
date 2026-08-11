import AppKit
import CoreAudio

/// Pausing whatever is playing while Cadmus listens, and starting it again
/// after.
///
/// This exists for Bluetooth. A headset cannot carry good audio out and a
/// microphone in at the same time: while music plays it is in the stereo
/// profile, which has no microphone at all, so recording gets silence. Stopping
/// the music frees the device to switch to the profile that has a microphone.
///
/// The alternative was to record from the built in microphone and leave the
/// music alone. That is a better idea on paper and it does not work: pointing
/// the engine at another device after the node exists leaves it running at the
/// old rate, and it delivers about a tenth of the audio.
enum Playback {
  /// Play/pause. It is a toggle, which is the whole reason for the check below.
  private static let playPauseKey: Int32 = 16

  /// Pauses only if something is actually playing, and says whether it did.
  ///
  /// The check is not politeness, it is correctness: the media key is a toggle,
  /// so pressing it while nothing plays would start the last thing I listened
  /// to. Recording has to be able to fail without turning on music.
  static func pauseIfPlaying() -> Bool {
    guard isPlaying() else { return false }
    press(playPauseKey)
    return true
  }

  static func resume() {
    press(playPauseKey)
  }

  /// Whether the default output device is being driven by anybody. This asks
  /// the device rather than any application, so it is true for a browser tab
  /// and a music player alike, and it needs no permission over either.
  private static func isPlaying() -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var running: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard
      AudioObjectGetPropertyData(defaultOutput(), &address, 0, nil, &size, &running) == noErr
    else { return false }
    return running != 0
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
