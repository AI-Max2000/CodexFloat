import AppKit
import ApplicationServices

enum ManualResetNavigationResult: Equatable {
  case selectionRequested, accessibilityRequired, tabNotFound, openFailed
}

/// Only opens settings and selects its usage navigation item. Never presses a
/// reset/redeem control. Accessibility is used only after an explicit click.
@MainActor
struct ManualResetNavigator {
  // Current Codex deep-link allowlist drops /usage and falls back to General.
  static let usageURL = URL(string: "codex://settings")!
  var openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }
  var selectUsageTab: () async -> ManualResetNavigationResult = {
    await CodexUsageTabLocator.select()
  }

  @discardableResult
  func open() -> Bool { openURL(Self.usageURL) }

  func openAndLocate() async -> ManualResetNavigationResult {
    guard open() else { return .openFailed }
    return await selectUsageTab()
  }
}

enum UsageSettingsTabMatch {
  static let labels: Set<String> = [
    "使用情况和计费", "使用情況和計費", "使用情況與計費", "用量和计费", "用量與計費",
    "Usage and billing", "Usage & billing", "用量", "使用情况", "使用情況", "Usage",
  ]

  static func matches(role: String, label: String, frame: CGRect, window: CGRect) -> Bool {
    ["AXButton", "AXLink", "AXRadioButton", "AXRow"].contains(role)
      && labels.contains(label.trimmingCharacters(in: .whitespacesAndNewlines))
      && window.contains(frame) && frame.width > 0 && frame.height > 0
      && frame.maxX <= window.minX + min(420, window.width * 0.45)
  }
}

@MainActor
private enum CodexUsageTabLocator {
  static func select() async -> ManualResetNavigationResult {
    guard AXIsProcessTrusted() else { return .accessibilityRequired }
    // Bounded retries for settings navigation/rendering. Only the foreground
    // Codex window is eligible; switching applications cancels the operation.
    var hasSeenCodex = false
    for _ in 0..<12 {
      do { try await Task.sleep(for: .milliseconds(200)) }
      catch { return .tabNotFound }
      guard let app = NSWorkspace.shared.frontmostApplication,
        app.bundleIdentifier == "com.openai.codex" else {
        if hasSeenCodex { return .tabNotFound }
        continue
      }
      hasSeenCodex = true
      let root = AXUIElementCreateApplication(app.processIdentifier)
      AXUIElementSetMessagingTimeout(root, 0.1)
      guard let rawWindow = value(root, kAXFocusedWindowAttribute),
        CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else { continue }
      let window = rawWindow as! AXUIElement
      guard let bounds = frame(window) else { continue }
      let deadline = Date().addingTimeInterval(0.15)
      var queue = [window]
      var visited = 0
      var hasSettingsBack = false
      var candidate: AXUIElement?
      while !queue.isEmpty && visited < 250 && Date() < deadline {
        let node = queue.removeFirst()
        visited += 1
        let role = value(node, kAXRoleAttribute) as? String ?? ""
        let rect = frame(node)
        // Do not inspect the content pane, account details, or conversation text.
        if let rect, rect.minX > bounds.minX + min(420, bounds.width * 0.45) { continue }
        if let rect, ["AXButton", "AXLink", "AXRadioButton", "AXRow"].contains(role) {
          let label = [value(node, kAXTitleAttribute) as? String,
                       value(node, kAXDescriptionAttribute) as? String]
            .compactMap { $0 }.first(where: { !$0.isEmpty }) ?? ""
          if ["返回应用", "返回應用", "返回應用程式", "Back to app"].contains(label),
            rect.maxX <= bounds.minX + min(420, bounds.width * 0.45) {
            hasSettingsBack = true
          }
          if UsageSettingsTabMatch.matches(role: role, label: label, frame: rect, window: bounds),
            NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            candidate = node
          }
        }
        if hasSettingsBack, let candidate {
          guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
            let focused = value(root, kAXFocusedWindowAttribute), CFEqual(focused, window)
          else { return .tabNotFound }
          return AXUIElementPerformAction(candidate, kAXPressAction as CFString) == .success
            ? .selectionRequested : .tabNotFound
        }
        // Editable fields and static text cannot contain the navigation target.
        if ["AXTextField", "AXTextArea", "AXStaticText"].contains(role) { continue }
        queue.append(contentsOf: value(node, kAXChildrenAttribute) as? [AXUIElement] ?? [])
      }
    }
    return .tabNotFound
  }

  private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
    return result
  }

  private static func frame(_ element: AXUIElement) -> CGRect? {
    guard let rawPosition = value(element, kAXPositionAttribute),
      let rawSize = value(element, kAXSizeAttribute),
      CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position),
      AXValueGetValue(rawSize as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: position, size: size)
  }
}
