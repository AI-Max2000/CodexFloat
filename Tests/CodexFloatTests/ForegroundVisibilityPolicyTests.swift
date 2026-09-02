import Foundation
import Testing

@testable import CodexFloat

@Suite("Foreground visibility")
struct ForegroundVisibilityPolicyTests {
  @Test func recognizesSupportedChatGPTBundleIdentifiers() {
    #expect(ForegroundVisibilityPolicy.isChatGPT(bundleIdentifier: "com.openai.codex"))
    #expect(ForegroundVisibilityPolicy.isChatGPT(bundleIdentifier: "com.openai.chat"))
    #expect(ForegroundVisibilityPolicy.isChatGPT(bundleIdentifier: "com.openai.chatgpt"))
    #expect(!ForegroundVisibilityPolicy.isChatGPT(bundleIdentifier: "com.apple.finder"))
    #expect(!ForegroundVisibilityPolicy.isChatGPT(bundleIdentifier: nil))
  }

  @Test func hidesOutsideChatGPTAndRestoresWhenItReturns() {
    #expect(
      ForegroundVisibilityPolicy.shouldShow(
        userWantsVisible: true,
        onlyWhenChatGPTIsFrontmost: true,
        frontmostBundleIdentifier: "com.openai.codex"
      ))
    #expect(
      !ForegroundVisibilityPolicy.shouldShow(
        userWantsVisible: true,
        onlyWhenChatGPTIsFrontmost: true,
        frontmostBundleIdentifier: "com.apple.finder"
      ))
  }

  @Test func disabledPolicyShowsOverOtherApps() {
    #expect(
      ForegroundVisibilityPolicy.shouldShow(
        userWantsVisible: true,
        onlyWhenChatGPTIsFrontmost: false,
        frontmostBundleIdentifier: "com.apple.finder"
      ))
  }

  @Test func menuBarQuotaStaysVisibleOutsideChatGPTEvenWithFrontmostOnlyEnabled() {
    #expect(
      ForegroundVisibilityPolicy.shouldShow(
        displayMode: .menuBar,
        userWantsVisible: true,
        onlyWhenChatGPTIsFrontmost: true,
        frontmostBundleIdentifier: "com.apple.finder"
      ))
    #expect(
      !ForegroundVisibilityPolicy.shouldShow(
        displayMode: .standard,
        userWantsVisible: true,
        onlyWhenChatGPTIsFrontmost: true,
        frontmostBundleIdentifier: "com.apple.finder"
      ))
  }

  @Test func manualHideAlwaysWins() {
    #expect(
      !ForegroundVisibilityPolicy.shouldShow(
        userWantsVisible: false,
        onlyWhenChatGPTIsFrontmost: false,
        frontmostBundleIdentifier: "com.openai.codex"
      ))
  }
}

@Suite("Foreground visibility settings")
@MainActor
struct ForegroundVisibilitySettingsTests {
  @Test func frontmostOnlyIsEnabledByDefault() {
    let suiteName = "ForegroundVisibilitySettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)

    #expect(settings.showOnlyWhenChatGPTIsFrontmost)
  }

  @Test func notificationSchedulingSettingsNotifyImmediately() {
    let suiteName = "NotificationSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)
    var changeCount = 0
    settings.onNotificationSettingsChange = { changeCount += 1 }

    settings.notificationsEnabled = false
    settings.notifyFiveHoursBeforeReset = false

    #expect(changeCount == 2)
  }
}
