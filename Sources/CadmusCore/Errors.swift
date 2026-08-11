import Foundation

public enum CadmusError: LocalizedError {
  case noInputDevice
  case hotkeyFailed(OSStatus)
  case hotkeyTaken(OSStatus)
  case modelMissing(String)
  case modelFailedToLoad(String)
  case transcriptionFailed(Int32)

  public var errorDescription: String? {
    switch self {
    case .noInputDevice:
      return "No microphone available."
    case .hotkeyFailed(let status):
      return "Could not install the hotkey handler (\(status))."
    case .hotkeyTaken(let status):
      return "Could not register the hotkey (\(status)). Something else probably owns it."
    case .modelMissing(let path):
      return "No model at \(path). Run `make model` to download it."
    case .modelFailedToLoad(let path):
      return "The model at \(path) failed to load."
    case .transcriptionFailed(let code):
      return "Transcription failed (\(code))."
    }
  }
}
