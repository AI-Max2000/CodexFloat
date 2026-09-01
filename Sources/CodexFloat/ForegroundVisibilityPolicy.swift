import Foundation

enum ForegroundVisibilityPolicy {
  private static let chatGPTBundleIdentifiers: Set<String> = [
    "com.openai.codex",
    "com.openai.chat",
    "com.openai.chatgpt",
  ]

  static func isChatGPT(bundleIdentifier: String?) -> Bool {
    guard let bundleIdentifier else { return false }
    return chatGPTBundleIdentifiers.contains(bundleIdentifier.lowercased())
  }

  static func shouldShow(
    displayMode: QuotaDisplayMode = .standard,
    userWantsVisible: Bool,
    onlyWhenChatGPTIsFrontmost: Bool,
    frontmostBundleIdentifier: String?
  ) -> Bool {
    guard userWantsVisible else { return false }
    if displayMode == .menuBar { return true }
    return !onlyWhenChatGPTIsFrontmost || isChatGPT(bundleIdentifier: frontmostBundleIdentifier)
  }
}
