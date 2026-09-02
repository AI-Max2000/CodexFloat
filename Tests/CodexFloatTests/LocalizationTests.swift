import AppKit
import Foundation
import Testing

@testable import CodexFloat

@Suite("Application localization")
struct LocalizationTests {
  @Test func everyLanguageContainsEveryVisibleString() {
    for language in AppLanguage.allCases {
      let strings = AppStrings(language: language)
      for key in LocalizedTextKey.allCases {
        #expect(strings.text(key) != key.rawValue, "Missing \(language.rawValue): \(key.rawValue)")
      }
    }
  }

  @Test func resetStatusUsesClearChineseCopy() {
    let simplified = AppStrings(language: .simplifiedChinese)
    let traditional = AppStrings(language: .traditionalChinese)

    #expect(simplified.format(.resetCountHeader, 1) == "1 次额外重置")
    #expect(simplified.text(.updatedJustNow) == "刚刚更新")
    #expect(!simplified.format(.resetCountHeader, 1).contains("Reset"))
    #expect(simplified.format(.remainingQuota, 86) == "剩余 86%")
    #expect(!simplified.format(.remainingQuota, 86).contains("已用"))
    #expect(traditional.format(.resetCountHeader, 1) == "1 次額外重置")
  }

  @Test func announcementTimesFollowTheLanguageTimeZone() throws {
    let instant = try #require(
      ISO8601DateFormatter().date(from: "2026-08-31T02:34:00Z"))
    let simplified = AppStrings(language: .simplifiedChinese)
    let traditional = AppStrings(language: .traditionalChinese)
    let english = AppStrings(language: .english)

    #expect(simplified.zonedShortDateTime(instant).contains("8月31日 10:34"))
    #expect(simplified.zonedShortDateTime(instant).hasSuffix("北京时间"))
    #expect(traditional.zonedShortDateTime(instant).contains("8月31日"))
    #expect(traditional.zonedShortDateTime(instant).contains("10:34"))
    #expect(traditional.zonedShortDateTime(instant).hasSuffix("北京時間"))
    #expect(english.zonedShortDateTime(instant).contains("Aug 30"))
    #expect(english.zonedShortDateTime(instant).contains("7:34"))
    #expect(english.zonedShortDateTime(instant).contains("PM"))
    #expect(english.zonedShortDateTime(instant).hasSuffix("PT"))
  }

  @Test func resetForecastRefreshesEveryFiveMinutesWithoutCheckTimeCopy() {
    let simplified = AppStrings(language: .simplifiedChinese)

    #expect(ResetForecastRefreshPolicy.interval == 300)
    #expect(simplified.text(.resetProbabilityHelp).contains("每 5 分钟"))
    #expect(simplified.format(.resetProbability48Hours, 63).contains("63%"))
  }
}

@Suite("Language setting")
@MainActor
struct LanguageSettingTests {
  @Test func simplifiedChineseIsTheDefault() {
    let suiteName = "LanguageSettingTests.default.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(AppSettings(defaults: defaults).appLanguage == .simplifiedChinese)
  }

  @Test func selectedLanguagePersistsAndNotifies() {
    let suiteName = "LanguageSettingTests.persist.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)
    var changes = 0
    settings.onLanguageChange = { changes += 1 }

    settings.appLanguage = .english

    #expect(changes == 1)
    #expect(AppSettings(defaults: defaults).appLanguage == .english)
  }

  @Test func minimalCollapsedStylePersistsAndEnablesHoverExpansion() {
    let suiteName = "LanguageSettingTests.minimalStyle.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)
    settings.hoverExpansionEnabled = false

    settings.quotaDisplayMode = .minimal

    #expect(settings.hoverExpansionEnabled)
    #expect(AppSettings(defaults: defaults).quotaDisplayMode == .minimal)

    defaults.set(false, forKey: "hoverExpansionEnabled")
    let repairedSettings = AppSettings(defaults: defaults)
    #expect(repairedSettings.hoverExpansionEnabled)
  }

  @Test func allThreeDisplayModesPersist() {
    let suiteName = "LanguageSettingTests.displayModes.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)
    var changes = 0
    settings.onDisplayModeChange = { changes += 1 }

    for mode in QuotaDisplayMode.allCases {
      settings.quotaDisplayMode = mode
      #expect(AppSettings(defaults: defaults).quotaDisplayMode == mode)
    }
    #expect(changes == QuotaDisplayMode.allCases.count)
  }

  @Test func menuBarCountdownUsesCompactLocalizedUnits() {
    let now = Date(timeIntervalSince1970: 1_000)
    let interval: TimeInterval = 518_400 + 39_600 + 2_520
    let reset = now.addingTimeInterval(interval)

    #expect(
      AppStrings(language: .simplifiedChinese).menuBarCountdown(to: reset, now: now)
        == "6天11时")
    #expect(AppStrings(language: .english).menuBarCountdown(to: reset, now: now) == "6d 11h")
    #expect(
      AppStrings(language: .simplifiedChinese).menuBarBadgeCountdown(to: reset, now: now)
        == "6天")
    #expect(
      AppStrings(language: .traditionalChinese).menuBarBadgeCountdown(to: reset, now: now)
        == "6天")
    #expect(AppStrings(language: .english).menuBarBadgeCountdown(to: reset, now: now) == "6d")
    #expect(
      AppStrings(language: .simplifiedChinese).format(.menuBarQuotaTitle, 89, "6天11时")
        == "89%·6天11时")
  }

  @Test func menuBarModeExplainsNativeSystemPlacement() {
    let simplified = AppStrings(language: .simplifiedChinese)
    let traditional = AppStrings(language: .traditionalChinese)
    let english = AppStrings(language: .english)

    #expect(simplified.text(.menuBarDisplayHelp).contains("系统状态栏"))
    #expect(traditional.text(.menuBarDisplayHelp).contains("系統狀態列"))
    #expect(english.text(.menuBarDisplayHelp).contains("native item"))
  }

  @Test func quotaRefreshDefaultsToThirtySecondsAndPersists() {
    let suiteName = "LanguageSettingTests.refreshInterval.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)
    var changes = 0
    settings.onQuotaRefreshSettingsChange = { changes += 1 }

    #expect(settings.quotaRefreshInterval == 30)
    settings.quotaRefreshInterval = 60

    #expect(changes == 1)
    #expect(AppSettings(defaults: defaults).quotaRefreshInterval == 60)
  }
}
