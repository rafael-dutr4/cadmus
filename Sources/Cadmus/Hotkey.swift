import Carbon.HIToolbox

/// One system wide hotkey.
///
/// This is the old Carbon API and it is deprecated, and it is still the only way
/// to ask the system for a key combination without watching every keystroke the
/// machine produces. The modern alternative is an event tap, which means seeing
/// everything I type in every application in order to notice one chord. For a
/// program that also holds a microphone, the smaller permission is worth the
/// older API.
final class Hotkey {
  private var ref: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private let action: () -> Void

  /// Carbon calls back into C, which cannot carry context, so the instance is
  /// parked here for the callback to find. Unchecked because the compiler
  /// cannot see what is true here: the handler is installed on the
  /// application event target, so it is only ever written and read on the main
  /// thread, by the run loop that owns the hotkey.
  nonisolated(unsafe) private static var current: Hotkey?

  init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) throws {
    self.action = action
    Hotkey.current = self

    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    let installed = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, _ in
        Hotkey.current?.action()
        return noErr
      },
      1,
      &spec,
      nil,
      &handler
    )
    guard installed == noErr else { throw CadmusError.hotkeyFailed(installed) }

    let id = EventHotKeyID(signature: OSType(0x4B44_4D53), id: 1)  // 'KDMS'
    let registered = RegisterEventHotKey(
      keyCode,
      modifiers,
      id,
      GetApplicationEventTarget(),
      0,
      &ref
    )
    guard registered == noErr else { throw CadmusError.hotkeyTaken(registered) }
  }

  deinit {
    if let ref { UnregisterEventHotKey(ref) }
    if let handler { RemoveEventHandler(handler) }
  }
}
