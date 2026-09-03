import AppKit

/// Navigation only. No reset-credit IDs, redemption RPCs, accessibility clicks,
/// or account content are needed. The user confirms redemption inside Codex.
@MainActor
struct ManualResetNavigator {
  // Verified against the installed Codex settings route. There is no stable
  // reset-section fragment in this client: do not invent #resets or claim focus.
  static let usageURL = URL(string: "codex://settings/usage")!
  var openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }

  @discardableResult
  func open() -> Bool { openURL(Self.usageURL) }
}
