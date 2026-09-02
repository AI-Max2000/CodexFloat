import AppKit
import CodexQuotaCore
import Foundation
import Testing

@testable import CodexFloat

enum QuotaDisplayFixture {
  static let now = Date(timeIntervalSince1970: 2_000_000_000)

  static func window(
    id: String = "codex:primary", limitID: String = "codex", minutes: Int? = 300,
    remaining: Double = 72, resetIn: TimeInterval? = 3 * 3_600 + 24 * 60
  ) -> RateLimitWindow {
    RateLimitWindow(
      id: id, limitID: limitID, limitName: nil, windowName: "primary",
      usedPercent: 100 - remaining, windowDurationMinutes: minutes,
      resetsAt: resetIn.map { now.addingTimeInterval($0) }, reachedType: nil
    )
  }

  static var windows: [RateLimitWindow] {
    [
      window(),
      window(
        id: "codex:secondary", minutes: 10_080, remaining: 18,
        resetIn: 4 * 86_400 + 6 * 3_600),
    ]
  }

  static func snapshot(plan: String? = "plus", windows: [RateLimitWindow]? = nil) -> QuotaSnapshot {
    QuotaSnapshot(
      planType: plan, windows: windows ?? Self.windows, resetCreditCount: 1,
      resetCredits: [], creditBalance: nil, hasCredits: nil, spendControlReached: nil,
      observedAt: now
    )
  }
}

@Suite("Capability-based quota display")
struct QuotaDisplayPolicyTests {
  @Test func toggleOffShowsWeeklyAndDoesNotMutateTheSnapshot() {
    let snapshot = QuotaDisplayFixture.snapshot()
    let display = QuotaDisplayPolicy(snapshot: snapshot, showFiveHour: false)
    #expect(!display.isDual)
    #expect(display.compact.map(\.kind) == [.weekly])
    #expect(display.compact.first?.percentage == "18%")
    #expect(display.expanded.map(\.kind) == [.weekly])
    #expect(snapshot.windows.count == 2)
    #expect(snapshot.windows.first?.remainingPercent == 72)
  }

  @Test func toggleOnShowsTwoIndependentValuesAndResetAnchors() {
    let display = QuotaDisplayPolicy(snapshot: QuotaDisplayFixture.snapshot(), showFiveHour: true)
    #expect(display.isDual)
    #expect(display.compact.map(\.kind) == [.fiveHour, .weekly])
    #expect(display.compact.map(\.percentage) == ["72%", "18%"])
    #expect(display.compact[0].window?.resetsAt != display.compact[1].window?.resetsAt)
    #expect(display.expanded == display.compact)
    let strings = AppStrings(language: .simplifiedChinese)
    #expect(
      display.compact.map { $0.compactCountdown(strings, now: QuotaDisplayFixture.now) }
        == ["3时24分", "4天6时"])
    #expect(
      QuotaMeterPalette.components(remainingPercent: 72, lowThreshold: 20, criticalThreshold: 5)
        == .init(red: 0.18, green: 0.72, blue: 0.34))
    #expect(
      QuotaMeterPalette.components(remainingPercent: 18, lowThreshold: 20, criticalThreshold: 5)
        == .init(red: 0.98, green: 0.68, blue: 0.08))
  }

  @Test func identifiesDurationsInsteadOfAssumingPrimaryAndSecondary() {
    let windows = [
      QuotaDisplayFixture.window(id: "codex:primary", minutes: 10_080, remaining: 23),
      QuotaDisplayFixture.window(id: "codex:secondary", minutes: 300, remaining: 81),
    ]
    let display = QuotaDisplayPolicy(
      snapshot: QuotaDisplayFixture.snapshot(plan: " PLUS\n", windows: windows), showFiveHour: true
    )
    #expect(display.compact.map(\.percentage) == ["81%", "23%"])
  }

  @Test func actualWindowsEnableTheSettingRegardlessOfPlanName() {
    for plan: String? in [
      "plus", "pro", "prolite", "team", "business", "free", "go", "future", nil,
    ] {
      let snapshot = QuotaDisplayFixture.snapshot(plan: plan)
      let display = QuotaDisplayPolicy(snapshot: snapshot, showFiveHour: true)
      #expect(display.hasFiveHourWindow)
      #expect(!display.isFiveHourAlwaysVisible)
      #expect(display.isDual)
      #expect(display.compact.map(\.kind) == [.fiveHour, .weekly])
      #expect(display.expanded.compactMap(\.window) == snapshot.windows)
      let off = QuotaDisplayPolicy(snapshot: snapshot, showFiveHour: false)
      #expect(off.compact.map(\.kind) == [.weekly])
    }
    #expect(!QuotaDisplayPolicy(snapshot: nil, showFiveHour: true).isDual)
  }

  @Test func planNameCannotInventMissingFiveHourSupport() {
    for plan: String? in ["plus", "free", "pro", nil] {
      let snapshot = QuotaDisplayFixture.snapshot(
        plan: plan, windows: [QuotaDisplayFixture.windows[1]])
      for enabled in [false, true] {
        let display = QuotaDisplayPolicy(snapshot: snapshot, showFiveHour: enabled)
        #expect(!display.hasFiveHourWindow)
        #expect(!display.isDual)
        #expect(display.expanded.map(\.kind) == [.weekly])
        #expect(display.compact.first?.percentage == "18%")
      }
    }
  }

  @Test func missingWindowsStayUnknownAndNeverBorrowSupplementaryQuota() {
    let snapshot = QuotaDisplayFixture.snapshot(windows: [
      QuotaDisplayFixture.window(id: "gpt-spark:primary", limitID: "gpt-spark", remaining: 100)
    ])
    let display = QuotaDisplayPolicy(snapshot: snapshot, showFiveHour: true)
    #expect(display.compact.map(\.percentage) == ["--"])
    #expect(display.expanded.isEmpty)
    #expect(!display.hasFiveHourWindow)
    #expect(display.compact.allSatisfy { $0.window == nil })
    let supplementary = QuotaDisplayPolicy(
      snapshot: snapshot, showFiveHour: true, includingSupplementaryGPT: true)
    #expect(!supplementary.hasFiveHourWindow)
    #expect(!supplementary.isDual)
    #expect(supplementary.expanded.map(\.kind) == [.other])
    #expect(
      QuotaDisplayEntry(kind: .fiveHour, window: nil).help(
        AppStrings(language: .english), now: QuotaDisplayFixture.now)
        == "5-hour quota · Quota not returned yet")
  }

  @Test func oneMissingWindowDoesNotHideTheOther() {
    for window in QuotaDisplayFixture.windows {
      for enabled in [false, true] {
        let display = QuotaDisplayPolicy(
          snapshot: QuotaDisplayFixture.snapshot(windows: [window]), showFiveHour: enabled)
        #expect(!display.isDual)
        #expect(display.compact.count == 1)
        #expect(display.compact.compactMap(\.window) == [window])
        #expect(display.expanded.compactMap(\.window) == [window])
        #expect(display.isFiveHourAlwaysVisible == (window.windowDurationMinutes == 300))
      }
    }
  }

  @Test func unknownFutureDurationsAndIDsRemainVisibleWithoutMislabeling() {
    let unknown = [
      QuotaDisplayFixture.window(id: "codex:future", minutes: nil),
      QuotaDisplayFixture.window(id: "codex:daily", minutes: 1_440),
      QuotaDisplayFixture.window(id: "future:primary", limitID: "future", minutes: 300),
    ]
    let display = QuotaDisplayPolicy(
      snapshot: QuotaDisplayFixture.snapshot(windows: unknown), showFiveHour: true)
    #expect(!display.hasFiveHourWindow)
    #expect(display.compact.map(\.kind) == [.other])
    #expect(display.compact.first?.window == unknown[0])
    #expect(display.expanded.filter { $0.kind == .other }.compactMap(\.window) == unknown)
    #expect(Set(display.expanded.map(\.id)).count == display.expanded.count)
  }

  @Test func supplementaryToggleDoesNotOverrideFiveHourToggle() {
    let windows =
      QuotaDisplayFixture.windows + [
        QuotaDisplayFixture.window(id: "gpt:primary", limitID: "gpt", remaining: 100)
      ]
    let snapshot = QuotaDisplayFixture.snapshot(windows: windows)
    let off = QuotaDisplayPolicy(
      snapshot: snapshot, showFiveHour: false, includingSupplementaryGPT: true)
    #expect(off.expanded.map(\.kind) == [.weekly, .other])
    let on = QuotaDisplayPolicy(
      snapshot: snapshot, showFiveHour: true, includingSupplementaryGPT: true)
    #expect(on.expanded.map(\.kind) == [.fiveHour, .weekly, .other])
  }

  @Test func dueOrUnknownTimeDoesNotInventAResetTime() {
    let strings = AppStrings(language: .simplifiedChinese)
    let unknown = QuotaDisplayEntry(
      kind: .fiveHour, window: QuotaDisplayFixture.window(resetIn: nil))
    let due = QuotaDisplayEntry(kind: .fiveHour, window: QuotaDisplayFixture.window(resetIn: 0))
    #expect(unknown.compactCountdown(strings, now: QuotaDisplayFixture.now) == "--")
    #expect(due.compactCountdown(strings, now: QuotaDisplayFixture.now) == "待更新")
  }

  @Test func staleValuesAreRetainedAndDisplayIDsAreStable() {
    let snapshot = QuotaDisplayFixture.snapshot()
    let fresh = QuotaDisplayPolicy(snapshot: snapshot, showFiveHour: true)
    let stale = QuotaDisplayPolicy(
      snapshot: snapshot.marked(.offline, error: "fixture"), showFiveHour: true)
    #expect(fresh.compact == stale.compact)
    #expect(fresh.expanded.map(\.id) == stale.expanded.map(\.id))
  }

  @Test @MainActor func preferenceDefaultsOffAndPersistsBothDirections() throws {
    let suite = "QuotaDisplayPolicyTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    #expect(!settings.showFiveHourQuota)
    settings.showFiveHourQuota = true
    #expect(AppSettings(defaults: defaults).showFiveHourQuota)
    settings.showFiveHourQuota = false
    #expect(!AppSettings(defaults: defaults).showFiveHourQuota)
  }

  @Test @MainActor func legacyPlusPreferenceMigratesWithoutOverridingANewerChoice() throws {
    for oldValue in [false, true] {
      let suite = "QuotaPreferenceMigration.\(UUID().uuidString)"
      let defaults = try #require(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      defaults.set(oldValue, forKey: "showPlusFiveHourQuota")
      let migrated = AppSettings(defaults: defaults)
      #expect(migrated.showFiveHourQuota == oldValue)
      #expect(defaults.object(forKey: "showFiveHourQuota") as? Bool == oldValue)
      migrated.showFiveHourQuota = !oldValue
      #expect(AppSettings(defaults: defaults).showFiveHourQuota == !oldValue)
    }
  }

  @Test func missingThenRestoredWindowsReapplyThePreferenceWithoutFakeValues() {
    let full = QuotaDisplayFixture.snapshot(plan: "free")
    let onlyFive = QuotaDisplayFixture.snapshot(
      plan: "free", windows: [QuotaDisplayFixture.windows[0]])
    let empty = QuotaDisplayFixture.snapshot(plan: "free", windows: [])
    #expect(
      QuotaDisplayPolicy(snapshot: onlyFive, showFiveHour: false).compact.map(\.kind) == [.fiveHour]
    )
    #expect(
      QuotaDisplayPolicy(snapshot: full, showFiveHour: false).compact.map(\.kind) == [.weekly])
    #expect(QuotaDisplayPolicy(snapshot: full, showFiveHour: true).isDual)
    #expect(QuotaDisplayPolicy(snapshot: empty, showFiveHour: true).expanded.isEmpty)
    #expect(
      QuotaDisplayPolicy(snapshot: empty, showFiveHour: true).compact.first?.percentage == "--")
  }

  @Test @MainActor func explicitlySavedNewPreferenceWinsOverTheLegacyValue() throws {
    let suite = "QuotaPreferencePrecedence.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "showPlusFiveHourQuota")
    defaults.set(false, forKey: "showFiveHourQuota")
    #expect(!AppSettings(defaults: defaults).showFiveHourQuota)
    #expect(!AppSettings(defaults: defaults).showFiveHourQuota)
  }

  @Test func extraWindowsWithTheSameDurationAreNotSilentlyDropped() {
    let extra = QuotaDisplayFixture.window(id: "codex:future", minutes: 300)
    let display = QuotaDisplayPolicy(
      snapshot: QuotaDisplayFixture.snapshot(windows: QuotaDisplayFixture.windows + [extra]),
      showFiveHour: true)
    #expect(display.expanded.count == 3)
    #expect(display.expanded.last?.window == extra)
    #expect(display.expanded.last?.kind == .other)
  }

  @Test @MainActor func nativeMenuBarReadingsFitWithoutOverlapInAllLanguages() throws {
    let first = MenuBarDualQuotaIndicator.cellFrame(at: 0)
    let second = MenuBarDualQuotaIndicator.cellFrame(at: 1)
    #expect(first.maxX < second.minX)
    #expect(second.maxX == MenuBarDualQuotaIndicator.imageSize.width)
    for language in AppLanguage.allCases {
      let strings = AppStrings(language: language)
      for remaining in [0.0, 5, 20, 99, 100] {
        let entries = [
          QuotaDisplayEntry(
            kind: .fiveHour,
            window: QuotaDisplayFixture.window(remaining: remaining)),
          QuotaDisplayEntry(
            kind: .weekly,
            window: QuotaDisplayFixture.window(
              minutes: 10_080, remaining: remaining,
              resetIn: 6 * 86_400 + 23 * 3_600)),
        ]
        for entry in entries {
          let width = ("\(entry.shortLabel(strings)) \(entry.percentage)" as NSString).size(
            withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .semibold)])
            .width
          #expect(
            width <= MenuBarDualQuotaIndicator.textWidth,
            "\(language) \(entry.percentage) width \(width)")
          let countdownWidth =
            (entry.compactCountdown(strings, now: QuotaDisplayFixture.now) as NSString).size(
              withAttributes: [.font: NSFont.systemFont(ofSize: 6.3, weight: .medium)]).width
          #expect(countdownWidth <= MenuBarDualQuotaIndicator.textWidth)
        }
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
          let image = MenuBarDualQuotaIndicator.image(
            entries: entries, strings: strings, now: QuotaDisplayFixture.now,
            lowThreshold: 20, criticalThreshold: 5,
            appearance: try #require(NSAppearance(named: appearanceName)))
          #expect(image.size == NSSize(width: 100, height: 18))
          #expect(image.tiffRepresentation != nil)
        }
      }
    }
  }
}
