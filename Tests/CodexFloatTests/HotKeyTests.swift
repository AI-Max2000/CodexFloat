import Carbon.HIToolbox
import Testing

@testable import CodexFloat

@Suite("Global hot key")
struct HotKeyTests {
  @Test func defaultShortcutIsControlOptionC() {
    let shortcut = HotKeyConfiguration.default

    #expect(shortcut.keyCode == UInt32(kVK_ANSI_C))
    #expect(shortcut.modifiers == UInt32(controlKey | optionKey))
    #expect(shortcut.displayName == "⌃⌥C")
    #expect(shortcut.isValid)
  }

  @Test func shortcutRequiresARegistrationModifier() {
    let plainKey = HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_K), modifiers: 0)
    let shiftOnly = HotKeyConfiguration(
      keyCode: UInt32(kVK_ANSI_K),
      modifiers: UInt32(shiftKey)
    )

    #expect(!plainKey.isValid)
    #expect(!shiftOnly.isValid)
  }

  @Test @MainActor func registrationLifecycleCleansUpExactlyOnce() throws {
    let system = FakeGlobalHotKeySystem()
    var actionCount = 0
    let hotKey = try GlobalHotKey(configuration: .default, system: system) {
      actionCount += 1
    }

    #expect(system.installCount == 1)
    #expect(system.registerCount == 1)
    system.invokeInstalledAction()
    #expect(actionCount == 1)

    hotKey.invalidate()
    hotKey.invalidate()
    #expect(system.unregisterCount == 1)
    #expect(system.removeHandlerCount == 1)
  }

  @Test @MainActor func registrationFailureRemovesInstalledHandler() {
    let system = FakeGlobalHotKeySystem()
    system.registrationStatus = OSStatus(eventHotKeyExistsErr)

    #expect(throws: GlobalHotKeyError.self) {
      _ = try GlobalHotKey(configuration: .default, system: system) {}
    }
    #expect(system.installCount == 1)
    #expect(system.registerCount == 1)
    #expect(system.unregisterCount == 0)
    #expect(system.removeHandlerCount == 1)
  }

  @Test @MainActor func installFailureDoesNotAttemptRegistration() {
    let system = FakeGlobalHotKeySystem()
    system.installStatus = OSStatus(eventInternalErr)

    #expect(throws: GlobalHotKeyError.self) {
      _ = try GlobalHotKey(configuration: .default, system: system) {}
    }
    #expect(system.installCount == 1)
    #expect(system.registerCount == 0)
    #expect(system.removeHandlerCount == 0)
  }
}

@MainActor
private final class FakeGlobalHotKeySystem: GlobalHotKeySystem {
  var installStatus = OSStatus(noErr)
  var registrationStatus = OSStatus(noErr)
  var installCount = 0
  var registerCount = 0
  var unregisterCount = 0
  var removeHandlerCount = 0
  private var installedUserData: UnsafeMutableRawPointer?

  func installHandler(
    userData: UnsafeMutableRawPointer,
    reference: inout EventHandlerRef?
  ) -> OSStatus {
    installCount += 1
    guard installStatus == noErr else { return installStatus }
    installedUserData = userData
    reference = EventHandlerRef(bitPattern: 1)
    return noErr
  }

  func register(
    configuration: HotKeyConfiguration,
    reference: inout EventHotKeyRef?
  ) -> OSStatus {
    registerCount += 1
    guard registrationStatus == noErr else { return registrationStatus }
    reference = EventHotKeyRef(bitPattern: 2)
    return noErr
  }

  func unregister(_ reference: EventHotKeyRef) -> OSStatus {
    unregisterCount += 1
    return noErr
  }

  func removeHandler(_ reference: EventHandlerRef) -> OSStatus {
    removeHandlerCount += 1
    return noErr
  }

  func invokeInstalledAction() {
    guard let installedUserData else { return }
    let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(installedUserData).takeUnretainedValue()
    hotKey.performAction()
  }
}
