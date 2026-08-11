import CoreAudio

/// Picking the microphone instead of taking the default one.
///
/// The default input is whatever macOS decided, and when that is a Bluetooth
/// headset it is the wrong answer twice. A headset cannot carry good audio out
/// and a microphone in at the same time: playing music puts it in the stereo
/// profile, which has no microphone at all, and opening the microphone drags
/// the whole device down to the hands free profile, which wrecks the music.
///
/// So Cadmus records from the built in microphone on purpose. The music keeps
/// playing on the headset, untouched, and the microphone array in the machine
/// is better for speech than a headset in hands free mode anyway.
enum AudioDevice {
  static func builtInInput() -> AudioDeviceID? {
    for id in allDevices() where transport(of: id) == kAudioDeviceTransportTypeBuiltIn {
      if hasInput(id) { return id }
    }
    return nil
  }

  private static func allDevices() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
    else { return [] }

    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
    else { return [] }
    return ids
  }

  private static func transport(of id: AudioDeviceID) -> UInt32 {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return 0 }
    return value
  }

  /// A device is an input if it publishes at least one input buffer. The
  /// built in speakers and the built in microphone are separate devices with
  /// the same transport, so this is what tells them apart.
  private static func hasInput(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
      return false
    }

    let raw = UnsafeMutableRawPointer.allocate(
      byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else {
      return false
    }
    return raw.assumingMemoryBound(to: AudioBufferList.self).pointee.mNumberBuffers > 0
  }
}
