import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotKeyRecorderView: NSViewRepresentable {
  @Binding var configuration: HotKeyConfiguration
  let language: AppLanguage

  func makeCoordinator() -> Coordinator { Coordinator(configuration: $configuration) }

  func makeNSView(context: Context) -> HotKeyRecorderButton {
    let button = HotKeyRecorderButton()
    button.setLanguage(language)
    button.setConfiguration(configuration)
    button.onConfigurationChange = { [weak coordinator = context.coordinator] newValue in
      coordinator?.configuration.wrappedValue = newValue
    }
    return button
  }

  func updateNSView(_ button: HotKeyRecorderButton, context: Context) {
    context.coordinator.configuration = $configuration
    button.setLanguage(language)
    button.setConfiguration(configuration)
  }

  final class Coordinator {
    var configuration: Binding<HotKeyConfiguration>
    init(configuration: Binding<HotKeyConfiguration>) { self.configuration = configuration }
  }
}

final class HotKeyRecorderButton: NSButton {
  var onConfigurationChange: ((HotKeyConfiguration) -> Void)?

  private var configuration = HotKeyConfiguration.default
  private var isRecording = false
  private var language = AppLanguage.simplifiedChinese
  private var strings: AppStrings { AppStrings(language: language) }

  override var acceptsFirstResponder: Bool { true }

  init() {
    super.init(frame: .zero)
    bezelStyle = .rounded
    controlSize = .regular
    setButtonType(.momentaryPushIn)
    target = self
    action = #selector(beginRecording)
    toolTip = strings.text(.shortcutButtonHelp)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func setConfiguration(_ value: HotKeyConfiguration) {
    configuration = value
    if !isRecording { title = value.displayName }
  }

  func setLanguage(_ value: AppLanguage) {
    language = value
    toolTip = strings.text(.shortcutButtonHelp)
    if isRecording {
      title = strings.text(.pressNewShortcut)
    } else {
      title = configuration.displayName
    }
  }

  @objc private func beginRecording() {
    isRecording = true
    title = strings.text(.pressNewShortcut)
    window?.makeFirstResponder(self)
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == UInt16(kVK_Escape) {
      finishRecording()
      return
    }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    var modifiers: UInt32 = 0
    if flags.contains(.control) { modifiers |= UInt32(controlKey) }
    if flags.contains(.option) { modifiers |= UInt32(optionKey) }
    if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
    if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
    let newValue = HotKeyConfiguration(keyCode: UInt32(event.keyCode), modifiers: modifiers)

    guard newValue.isValid else {
      NSSound.beep()
      title = strings.text(.shortcutNeedsModifier)
      return
    }

    configuration = newValue
    onConfigurationChange?(newValue)
    finishRecording()
  }

  override func resignFirstResponder() -> Bool {
    let result = super.resignFirstResponder()
    if result, isRecording {
      isRecording = false
      title = configuration.displayName
    }
    return result
  }

  private func finishRecording() {
    isRecording = false
    title = configuration.displayName
    window?.makeFirstResponder(nil)
  }
}
