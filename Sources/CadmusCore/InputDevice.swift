import CoreAudio

/// Recording from the built in microphone without asking the audio engine to
/// change devices.
///
/// A Bluetooth headset has two profiles and only one of them has a microphone.
/// Opening its microphone forces the switch, which wrecks whatever is playing,
/// and closing it switches back, so the next recording opens a device that has
/// no microphone at all and captures nothing. That flapping was the bug where
/// dictation worked once and then stopped.
///
/// The way out is to never open the headset's microphone. What does not work is
/// pointing the engine at another device after its input node exists: the node
/// keeps running at the old rate and delivers about a tenth of the audio.
/// Changing which device is the default, before the engine is built, works and
/// keeps working across takes.
///
/// It is a system wide setting, so it is put back the moment recording stops.
public enum InputDevice {
  nonisolated(unsafe) private static var previous: AudioDeviceID?

  /// Makes the built in microphone the default input, and remembers what was
  /// there. Does nothing when the built in microphone is already the default,
  /// or when the machine has none.
  public static func useBuiltIn() {
    guard previous == nil, let builtIn = builtInInput() else { return }
    let current = defaultInput()
    guard current != builtIn else { return }
    previous = current
    setDefaultInput(builtIn)
  }

  public static func restore() {
    guard let previous else { return }
    setDefaultInput(previous)
    InputDevice.previous = nil
  }

  private static func builtInInput() -> AudioDeviceID? {
    for id in allDevices() where transport(of: id) == kAudioDeviceTransportTypeBuiltIn {
      if hasInput(id) { return id }
    }
    return nil
  }

  private static func allDevices() -> [AudioDeviceID] {
    var address = global(kAudioHardwarePropertyDevices)
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
    var address = global(kAudioDevicePropertyTransportType)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return 0 }
    return value
  }

  /// A device is an input if it publishes at least one input buffer. The built
  /// in speakers and the built in microphone are separate devices with the same
  /// transport, so this is what tells them apart.
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

  private static func defaultInput() -> AudioDeviceID {
    var address = global(kAudioHardwarePropertyDefaultInputDevice)
    var id: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
    return id
  }

  private static func setDefaultInput(_ id: AudioDeviceID) {
    var address = global(kAudioHardwarePropertyDefaultInputDevice)
    var id = id
    AudioObjectSetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
      UInt32(MemoryLayout<AudioDeviceID>.size), &id)
  }

  private static func global(_ selector: AudioObjectPropertySelector)
    -> AudioObjectPropertyAddress
  {
    AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
  }
}
