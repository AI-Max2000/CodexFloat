import AppKit
import CodexQuotaCore
import Foundation
import LocalStore
import Testing

@testable import CodexFloat

enum RecoveryFixture {
  static let now = Date(timeIntervalSince1970: 2_000_000_000)
  static func window(
    remaining: Double = 0, id: String = "codex:primary", minutes: Int = 10_080,
    resetAt: Date? = now.addingTimeInterval(10_000)
  ) -> RateLimitWindow {
    RateLimitWindow(
      id: id, limitID: id.components(separatedBy: ":")[0], limitName: nil,
      windowName: "主窗口", usedPercent: 100 - remaining, windowDurationMinutes: minutes,
      resetsAt: resetAt, reachedType: nil)
  }
  static func credit(
    id: String = "fixture", status: String? = "available",
    expiresAt: Date? = now.addingTimeInterval(3600)
  ) -> ResetCredit {
    ResetCredit(
      id: id, resetType: "codexRateLimits", status: status, grantedAt: nil,
      expiresAt: expiresAt, title: nil, detail: nil)
  }
  static func snapshot(
    windows: [RateLimitWindow] = [window()], count: Int? = 1,
    credits: [ResetCredit] = [], freshness: DataFreshness = .fresh,
    observedAt: Date = now, spendLimit: Bool? = nil
  ) -> QuotaSnapshot {
    QuotaSnapshot(
      planType: "plus", windows: windows, resetCreditCount: count, resetCredits: credits,
      creditBalance: nil, hasCredits: nil, spendControlReached: spendLimit,
      observedAt: observedAt, freshness: freshness)
  }
}

@Suite("Quota exhaustion and manual reset boundaries")
struct QuotaRecoveryTests {
  let strings = AppStrings(language: .simplifiedChinese)

  @Test func exhaustedWithCountOnlyIsActionable() throws {
    let state = try #require(
      QuotaRecoveryState.evaluate(RecoveryFixture.snapshot(count: 2), now: RecoveryFixture.now))
    #expect(state.canOpenManualReset)
    #expect(state.resets == .available(2))
    #expect(state.actionTitle(strings) == "去手动重置")
    #expect(state.message(strings).contains("2 次"))
  }

  @Test func hiddenFiveHourExhaustionDoesNotOfferManualReset() {
    let snapshot = RecoveryFixture.snapshot(windows: [
      RecoveryFixture.window(minutes: 300),
      RecoveryFixture.window(remaining: 84, id: "codex:secondary", minutes: 10_080),
    ])
    let display = QuotaDisplayPolicy(snapshot: snapshot, showFiveHour: false)
    #expect(display.compact.first?.percentage == "84%")
    #expect(QuotaRecoveryState.evaluate(snapshot, now: RecoveryFixture.now) == nil)
  }

  @Test func supplementaryExhaustionDoesNotClaimCodexExhaustion() {
    let snapshot = RecoveryFixture.snapshot(windows: [
      RecoveryFixture.window(remaining: 50),
      RecoveryFixture.window(id: "gpt-reserve:primary"),
    ])
    #expect(QuotaRecoveryState.evaluate(snapshot, now: RecoveryFixture.now) == nil)
  }

  @Test func onlyWeeklyExhaustionWithCreditsEnablesRecoveryAcrossSnapshotStates() {
    for minutes in [300, 1_440, 10_080, 43_200] {
      for count in [0, 2] {
        for freshness in [DataFreshness.fresh, .stale, .offline] {
          for spendLimit in [false, true] {
            let snapshot = RecoveryFixture.snapshot(
              windows: [RecoveryFixture.window(minutes: minutes)], count: count,
              freshness: freshness, spendLimit: spendLimit)
            let state = QuotaRecoveryState.evaluate(snapshot, now: RecoveryFixture.now)
            #expect((state != nil) == (minutes == 10_080 && count > 0))
          }
        }
      }
    }
  }

  @Test func fiveHourAndNoResetCasesRetainLegacyCriticalFeedback() throws {
    for (minutes, count) in [(300, 2), (300, 0), (10_080, 0)] {
      let old = RecoveryFixture.window(remaining: 50, minutes: minutes)
      let exhausted = RecoveryFixture.window(minutes: minutes)
      let feedback = try #require(
        AppFeedbackPlanner.quotaFeedback(
          previous: RecoveryFixture.snapshot(windows: [old], count: count),
          current: RecoveryFixture.snapshot(windows: [exhausted], count: count),
          lowThreshold: 20, criticalThreshold: 5, strings: strings))
      #expect(feedback.kind == .quotaCritical)
      #expect(!feedback.isExhaustion)
      let plan = try #require(
        NotificationPlanner.thresholdCrossing(
          old: old, current: exhausted, threshold: 5,
          title: strings.text(.notifyQuotaCritical), strings: strings))
      #expect(!plan.opensUsageSettings)
    }
  }

  @Test func exhaustedFiveHourDoesNotSuppressNewWeeklyRecovery() throws {
    let fiveHour = RecoveryFixture.window(minutes: 300)
    let previous = RecoveryFixture.snapshot(windows: [
      fiveHour, RecoveryFixture.window(remaining: 60, id: "codex:secondary"),
    ])
    let current = RecoveryFixture.snapshot(windows: [
      fiveHour, RecoveryFixture.window(id: "codex:secondary"),
    ])
    let state = try #require(QuotaRecoveryState.evaluate(current, now: RecoveryFixture.now))
    #expect(state.windows.map(\.id) == ["codex:secondary"])
    #expect(state.canOpenManualReset)
    #expect(!state.message(strings).contains("5 小时"))
    #expect(
      AppFeedbackPlanner.quotaFeedback(
        previous: previous, current: current, lowThreshold: 20, criticalThreshold: 5,
        strings: strings)?.isExhaustion == true)
  }

  @Test func invalidRecoveryStatesCannotCreateManualResetNotifications() {
    let states = [
      QuotaRecoveryState(kind: .exhausted, windows: [], resets: .available(1)),
      QuotaRecoveryState(
        kind: .exhausted, windows: [RecoveryFixture.window(minutes: 300)], resets: .available(1)),
      QuotaRecoveryState(
        kind: .exhausted, windows: [RecoveryFixture.window(remaining: 30)], resets: .available(1)),
      QuotaRecoveryState(
        kind: .exhausted, windows: [RecoveryFixture.window()], resets: .unavailable),
      QuotaRecoveryState(kind: .exhausted, windows: [RecoveryFixture.window()], resets: .unknown),
    ]
    for state in states {
      #expect(!state.canOpenManualReset)
      #expect(
        NotificationPlanner.exhausted(state: state, episodeID: "test", strings: strings) == nil)
    }
  }

  @Test func weeklyEpisodeRecoversEvenWhenFiveHourRemainsEmpty() throws {
    var episode = QuotaExhaustionEpisode()
    let fiveHour = RecoveryFixture.window(minutes: 300)
    let exhausted = RecoveryFixture.snapshot(windows: [
      fiveHour, RecoveryFixture.window(id: "codex:secondary"),
    ])
    #expect(
      episode.update(
        snapshot: RecoveryFixture.snapshot(windows: [fiveHour]), now: RecoveryFixture.now) == nil)
    #expect(episode.id == nil)
    let firstID = episode.update(snapshot: exhausted, now: RecoveryFixture.now)
    let first = try #require(firstID)
    #expect(episode.exhaustedWindowIDs == ["codex:secondary"])
    _ = episode.update(
      snapshot: RecoveryFixture.snapshot(windows: [
        fiveHour, RecoveryFixture.window(remaining: 80, id: "codex:secondary"),
      ]), now: RecoveryFixture.now)
    #expect(episode.id == nil)
    let nextID = episode.update(snapshot: exhausted, now: RecoveryFixture.now)
    let next = try #require(nextID)
    #expect(next != first)
  }

  @Test func newlyAvailableResetsStartRecoveryButUnknownCountsDoNotRepeatAlerts() throws {
    var episode = QuotaExhaustionEpisode()
    let available = RecoveryFixture.snapshot(count: 1)
    let empty = RecoveryFixture.snapshot(count: 0)
    let firstID = episode.update(snapshot: available, now: RecoveryFixture.now)
    let first = try #require(firstID)
    #expect(
      episode.update(snapshot: RecoveryFixture.snapshot(count: nil), now: RecoveryFixture.now)
        == nil)
    #expect(episode.id == first)
    #expect(episode.update(snapshot: available, now: RecoveryFixture.now) == first)
    _ = episode.update(snapshot: empty, now: RecoveryFixture.now)
    #expect(episode.id == nil)
    let nextID = episode.update(snapshot: available, now: RecoveryFixture.now)
    let next = try #require(nextID)
    #expect(next != first)
    #expect(
      AppFeedbackPlanner.quotaFeedback(
        previous: empty, current: available, lowThreshold: 20, criticalThreshold: 5,
        strings: strings)?.isExhaustion == true)
  }

  @Test func fractionalRemainderNeverDisplaysZeroOrOffersReset() {
    let window = RecoveryFixture.window(remaining: 0.2)
    #expect(QuotaPercentage.text(window.remainingPercent) == "<1%")
    #expect(QuotaDisplayEntry(kind: .fiveHour, window: window).percentage == "<1%")
    #expect(
      QuotaRecoveryState.evaluate(
        RecoveryFixture.snapshot(windows: [window]), now: RecoveryFixture.now) == nil)
    #expect(QuotaPercentage.text(0) == "0%")
    #expect(QuotaPercentage.text(.nan) == "--")
    let feedback = AppFeedbackPlanner.quotaFeedback(
      previous: RecoveryFixture.snapshot(windows: [RecoveryFixture.window(remaining: 50)]),
      current: RecoveryFixture.snapshot(windows: [window]), lowThreshold: 20,
      criticalThreshold: 5, strings: strings)
    #expect(feedback?.localized(using: strings).message.contains("<1%") == true)
    let notification = NotificationPlanner.thresholdCrossing(
      old: RecoveryFixture.window(remaining: 50), current: window, threshold: 5,
      title: strings.text(.notifyQuotaCritical), strings: strings)
    #expect(notification?.body.contains("<1%") == true)
  }

  @Test func zeroCountOverridesResidualDetailRowsAndKeepsOriginalPresentation() {
    let snapshot = RecoveryFixture.snapshot(count: 0, credits: [RecoveryFixture.credit()])
    #expect(ResetAvailability.resolve(snapshot, now: RecoveryFixture.now) == .unavailable)
    #expect(QuotaRecoveryState.evaluate(snapshot, now: RecoveryFixture.now) == nil)
  }

  @Test func missingCountAndUnknownStatusesAreNotZeroOrSpendable() {
    for status: String? in [nil, "used", "consumed", "expired", "revoked", "new-server-status"] {
      let snapshot = RecoveryFixture.snapshot(
        count: nil, credits: [RecoveryFixture.credit(status: status)])
      #expect(ResetAvailability.resolve(snapshot, now: RecoveryFixture.now) == .unknown)
      #expect(QuotaRecoveryState.evaluate(snapshot, now: RecoveryFixture.now) == nil)
    }
    #expect(
      ResetAvailability.resolve(RecoveryFixture.snapshot(count: nil), now: RecoveryFixture.now)
        == .unknown)
  }

  @Test func explicitAvailableDetailsCanBeUsedWhenCountIsMissing() {
    let credit = RecoveryFixture.credit()
    let snapshot = RecoveryFixture.snapshot(count: nil, credits: [credit, credit])
    #expect(ResetAvailability.resolve(snapshot, now: RecoveryFixture.now) == .available(1))
  }

  @Test func countRemainsAuthoritativeWhenDetailsAreCapped() {
    let snapshot = RecoveryFixture.snapshot(count: 4, credits: [RecoveryFixture.credit()])
    #expect(ResetAvailability.resolve(snapshot, now: RecoveryFixture.now) == .available(4))
  }

  @Test func creditExpiringAfterReadIsRemovedWithoutDoubleSubtractingOldExpiry() {
    let credits = [
      RecoveryFixture.credit(id: "old", expiresAt: RecoveryFixture.now.addingTimeInterval(-1)),
      RecoveryFixture.credit(id: "new", expiresAt: RecoveryFixture.now.addingTimeInterval(10)),
    ]
    let snapshot = RecoveryFixture.snapshot(count: 1, credits: credits)
    #expect(ResetAvailability.resolve(snapshot, now: RecoveryFixture.now) == .available(1))
    #expect(
      ResetAvailability.resolve(snapshot, now: RecoveryFixture.now.addingTimeInterval(10))
        == .unavailable)
    #expect(
      QuotaRecoveryState.evaluate(snapshot, now: RecoveryFixture.now.addingTimeInterval(10)) == nil)
  }

  @Test func staleOfflineAndAgedSnapshotsRequireRefresh() {
    for freshness in [DataFreshness.stale, .offline] {
      let state = QuotaRecoveryState.evaluate(
        RecoveryFixture.snapshot(freshness: freshness), now: RecoveryFixture.now)
      #expect(state?.needsRefresh == true)
      #expect(state?.canOpenManualReset == false)
    }
    let aged = QuotaRecoveryState.evaluate(
      RecoveryFixture.snapshot(), now: RecoveryFixture.now.addingTimeInterval(331))
    #expect(aged?.kind == .needsRefresh)
  }

  @Test func resetAnchorPassingNeedsFreshVerificationNotAnAutomaticReset() {
    let snapshot = RecoveryFixture.snapshot(windows: [
      RecoveryFixture.window(resetAt: RecoveryFixture.now)
    ])
    #expect(QuotaRecoveryState.evaluate(snapshot, now: RecoveryFixture.now)?.kind == .awaitingReset)
    let noAnchor = RecoveryFixture.snapshot(windows: [RecoveryFixture.window(resetAt: nil)])
    #expect(
      QuotaRecoveryState.evaluate(noAnchor, now: RecoveryFixture.now)?.canOpenManualReset == true)
  }

  @Test func spendLimitDoesNotPromiseResetWillUnlockAccount() {
    let state = QuotaRecoveryState.evaluate(
      RecoveryFixture.snapshot(spendLimit: true), now: RecoveryFixture.now)
    #expect(state?.kind == .spendLimit)
    #expect(state?.canOpenManualReset == false)
  }

  @Test func recoveredQuotaRemovesRecoveryUI() {
    #expect(
      QuotaRecoveryState.evaluate(
        RecoveryFixture.snapshot(windows: [RecoveryFixture.window(remaining: 100)], count: 0),
        now: RecoveryFixture.now) == nil)
    #expect(QuotaRecoveryState.evaluate(nil, now: RecoveryFixture.now) == nil)
  }

  @Test func episodeSurvivesRepeatedReadsRelaunchAndChangingAnchors() throws {
    var gate = QuotaExhaustionEpisode()
    let started = gate.update(snapshot: RecoveryFixture.snapshot(), now: RecoveryFixture.now)
    let first = try #require(started)
    #expect(gate.update(snapshot: RecoveryFixture.snapshot(), now: RecoveryFixture.now) == first)
    var relaunched = try JSONDecoder().decode(
      QuotaExhaustionEpisode.self, from: JSONEncoder().encode(gate))
    let shifted = RecoveryFixture.snapshot(windows: [
      RecoveryFixture.window(resetAt: RecoveryFixture.now.addingTimeInterval(20_000))
    ])
    #expect(relaunched.update(snapshot: shifted, now: RecoveryFixture.now) == first)
    #expect(
      relaunched.update(
        snapshot: RecoveryFixture.snapshot(freshness: .offline), now: RecoveryFixture.now) == nil)
    #expect(relaunched.id == first)
    _ = relaunched.update(
      snapshot: RecoveryFixture.snapshot(windows: [RecoveryFixture.window(remaining: 70)]),
      now: RecoveryFixture.now)
    #expect(relaunched.id == nil)
    #expect(
      relaunched.update(snapshot: RecoveryFixture.snapshot(), now: RecoveryFixture.now) != first)
  }

  @Test func exhaustedFeedbackTakesPrecedenceAndDoesNotRepeatForOldZero() throws {
    let exhausted = RecoveryFixture.snapshot()
    let feedback = try #require(
      AppFeedbackPlanner.quotaFeedback(
        previous: RecoveryFixture.snapshot(windows: [RecoveryFixture.window(remaining: 50)]),
        current: exhausted, lowThreshold: 20, criticalThreshold: 5, strings: strings))
    #expect(feedback.isExhaustion)
    #expect(feedback.localized(using: strings).title == "额度已耗尽")
    #expect(
      AppFeedbackPlanner.quotaFeedback(
        previous: exhausted.marked(.stale, error: nil), current: exhausted, lowThreshold: 20,
        criticalThreshold: 5, strings: strings) == nil)
  }

  @Test func notificationIsReadOnlyAndHasActionInAllLanguages() throws {
    let state = try #require(
      QuotaRecoveryState.evaluate(RecoveryFixture.snapshot(), now: RecoveryFixture.now))
    for language in AppLanguage.allCases {
      let strings = AppStrings(language: language)
      let plan = try #require(
        NotificationPlanner.exhausted(state: state, episodeID: "test", strings: strings))
      #expect(plan.opensUsageSettings)
      #expect(plan.key == "quota-exhausted-test")
      #expect(plan.body.contains("Codex"))
      #expect(!plan.title.isEmpty)
    }
  }

  @Test func temporarilyMissingExhaustedWindowDoesNotStartAnotherEpisode() {
    var gate = QuotaExhaustionEpisode()
    let id = gate.update(snapshot: RecoveryFixture.snapshot(), now: RecoveryFixture.now)
    _ = gate.update(
      snapshot: RecoveryFixture.snapshot(windows: [
        RecoveryFixture.window(remaining: 80, id: "codex:secondary", minutes: 10_080)
      ]), now: RecoveryFixture.now)
    #expect(gate.id == id)
    #expect(gate.update(snapshot: RecoveryFixture.snapshot(), now: RecoveryFixture.now) == id)
  }

  @Test func decoderRejectsNonFiniteUsageInsteadOfShowingFakeZero() {
    #expect(throws: QuotaDecodeError.self) {
      try QuotaDecoder.decodeResult([
        "rateLimits": ["limitId": "codex", "primary": ["usedPercent": "NaN"]]
      ])
    }
    #expect(throws: QuotaDecodeError.self) {
      try QuotaDecoder.decodeResult([
        "rateLimits": ["limitId": "codex", "primary": ["usedPercent": "inf"]]
      ])
    }
  }

  @Test @MainActor func navigationOnlyOpensFixedUsageURLAndReportsFailure() {
    var opened: [URL] = []
    let navigator = ManualResetNavigator(openURL: {
      opened.append($0)
      return true
    })
    #expect(navigator.open())
    #expect(opened.map(\.absoluteString) == ["codex://settings/usage"])
    #expect(opened.first?.fragment == nil)
    #expect(!ManualResetNavigator(openURL: { _ in false }).open())
  }

  @Test @MainActor func oldRecoveryActionsDoNotNavigateWithoutEligibleWeeklyQuota() throws {
    let suite = "RecoveryAction.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: directory)
    }
    let store = try SQLiteStore(databaseURL: directory.appendingPathComponent("fixture.sqlite"))
    let settings = AppSettings(defaults: defaults)
    settings.notificationsEnabled = false
    var opened: [URL] = []
    let navigator = ManualResetNavigator(openURL: {
      opened.append($0)
      return true
    })
    for (minutes, remaining, count) in [(300, 0.0, 2), (10_080, 0.0, 0), (10_080, 80.0, 2)] {
      let snapshot = RecoveryFixture.snapshot(
        windows: [RecoveryFixture.window(remaining: remaining, minutes: minutes)],
        count: count, observedAt: Date())
      let model = AppModel(
        store: store, settings: settings, resetNavigator: navigator, initialQuota: snapshot)
      model.handleQuotaRecovery()
    }
    #expect(opened.isEmpty)
  }

  @Test @MainActor func exhaustionSettingDefaultsOnAndPersists() throws {
    let name = "RecoverySettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = AppSettings(defaults: defaults)
    #expect(settings.notifyQuotaExhausted)
    settings.notifyQuotaExhausted = false
    #expect(!AppSettings(defaults: defaults).notifyQuotaExhausted)
  }

  @Test func failedNotificationCanRetryWithoutReleasingOtherKeys() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SQLiteStore(databaseURL: directory.appendingPathComponent("fixture.sqlite"))
    #expect(try await store.claimNotification(key: "exhausted"))
    #expect(try await store.claimNotification(key: "other"))
    #expect(try await !store.claimNotification(key: "exhausted"))
    try await store.releaseNotification(key: "exhausted")
    #expect(try await store.claimNotification(key: "exhausted"))
    #expect(try await !store.claimNotification(key: "other"))
  }
}
