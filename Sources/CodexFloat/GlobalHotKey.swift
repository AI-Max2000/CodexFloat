import Carbon.HIToolbox
import Foundation

struct HotKeyConfiguration: Codable, Equatable, Sendable {
  let keyCode: UInt32
  let modifiers: UInt32

  static let `default` = HotKeyConfiguration(
    keyCode: UInt32(kVK_ANSI_C),
    modifiers: UInt32(controlKey | optionKey)
  )

  var isValid: Bool {
    modifiers & UInt32(controlKey | optionKey | cmdKey) != 0
  }

  var displayName: String {
    var result = ""
    if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
    return result + Self.keyName(for: keyCode)
  }

  private static func keyName(for keyCode: UInt32) -> String {
    let names: [UInt32: String] = [
      UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
      UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
      UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
      UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
      UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
      UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
      UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
      UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
      UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
      UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
      UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
      UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
      UInt32(kVK_ANSI_9): "9", UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩",
      UInt32(kVK_Tab): "⇥", UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦",
      UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→", UInt32(kVK_UpArrow): "↑",
      UInt32(kVK_DownArrow): "↓", UInt32(kVK_Home): "Home", UInt32(kVK_End): "End",
      UInt32(kVK_PageUp): "Page Up", UInt32(kVK_PageDown): "Page Down",
      UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
      UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
      UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
      UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
    ]
    return names[keyCode] ?? "Key \(keyCode)"
  }
}

enum GlobalHotKeyError: LocalizedError {
  case invalidConfiguration
  case installFailed(OSStatus)
  case registrationFailed(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration:
      "快捷键至少需要包含 Control、Option 或 Command"
    case .installFailed(let status):
      "无法安装全局快捷键处理器（\(status)）"
    case .registrationFailed(let status):
      "无法注册全局快捷键（\(status)）"
    }
  }

  func message(language: AppLanguage) -> String {
    switch (language, self) {
    case (.simplifiedChinese, _): return errorDescription ?? "快捷键不可用"
    case (.traditionalChinese, .invalidConfiguration):
      return "快捷鍵至少需要包含 Control、Option 或 Command"
    case (.traditionalChinese, .installFailed(let status)):
      return "無法安裝全域快捷鍵處理程式（\(status)）"
    case (.traditionalChinese, .registrationFailed(let status)):
      return "無法註冊全域快捷鍵（\(status)）"
    case (.english, .invalidConfiguration):
      return "The shortcut must include Control, Option, or Command"
    case (.english, .installFailed(let status)):
      return "Could not install the global shortcut handler (\(status))"
    case (.english, .registrationFailed(let status)):
      return "Could not register the global shortcut (\(status))"
    }
  }
}

@MainActor
protocol GlobalHotKeySystem: AnyObject {
  func installHandler(
    userData: UnsafeMutableRawPointer,
    reference: inout EventHandlerRef?
  ) -> OSStatus
  func register(
    configuration: HotKeyConfiguration,
    reference: inout EventHotKeyRef?
  ) -> OSStatus
  func unregister(_ reference: EventHotKeyRef) -> OSStatus
  func removeHandler(_ reference: EventHandlerRef) -> OSStatus
}

@MainActor
final class CarbonGlobalHotKeySystem: GlobalHotKeySystem {
  static let shared = CarbonGlobalHotKeySystem()

  private init() {}

  func installHandler(
    userData: UnsafeMutableRawPointer,
    reference: inout EventHandlerRef?
  ) -> OSStatus {
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    return InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, userData in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
        MainActor.assumeIsolated { hotKey.performAction() }
        return noErr
      },
      1,
      &eventType,
      userData,
      &reference
    )
  }

  func register(
    configuration: HotKeyConfiguration,
    reference: inout EventHotKeyRef?
  ) -> OSStatus {
    let hotKeyID = EventHotKeyID(signature: OSType(0x4344_5846), id: 1)  // CDXF
    return RegisterEventHotKey(
      configuration.keyCode,
      configuration.modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &reference
    )
  }

  func unregister(_ reference: EventHotKeyRef) -> OSStatus {
    UnregisterEventHotKey(reference)
  }

  func removeHandler(_ reference: EventHandlerRef) -> OSStatus {
    RemoveEventHandler(reference)
  }
}

@MainActor
final class GlobalHotKey {
  private var hotKeyReference: EventHotKeyRef?
  private var eventHandlerReference: EventHandlerRef?
  private let system: any GlobalHotKeySystem
  private let action: @MainActor () -> Void

  init(
    configuration: HotKeyConfiguration,
    system: any GlobalHotKeySystem = CarbonGlobalHotKeySystem.shared,
    action: @escaping @MainActor () -> Void
  ) throws {
    guard configuration.isValid else { throw GlobalHotKeyError.invalidConfiguration }
    self.system = system
    self.action = action

    let handlerStatus = system.installHandler(
      userData: Unmanaged.passUnretained(self).toOpaque(),
      reference: &eventHandlerReference
    )
    guard handlerStatus == noErr else { throw GlobalHotKeyError.installFailed(handlerStatus) }

    let registrationStatus = system.register(
      configuration: configuration,
      reference: &hotKeyReference
    )
    guard registrationStatus == noErr else {
      if let eventHandlerReference { _ = system.removeHandler(eventHandlerReference) }
      eventHandlerReference = nil
      throw GlobalHotKeyError.registrationFailed(registrationStatus)
    }
  }

  func performAction() {
    action()
  }

  func invalidate() {
    if let hotKeyReference {
      _ = system.unregister(hotKeyReference)
      self.hotKeyReference = nil
    }
    if let eventHandlerReference {
      _ = system.removeHandler(eventHandlerReference)
      self.eventHandlerReference = nil
    }
  }
}
