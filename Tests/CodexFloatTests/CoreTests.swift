import Foundation
import SQLite3
import Testing

@testable import ActivityClassifier
@testable import CodexQuotaCore
@testable import LocalStore
@testable import TiboFeedCore

@Suite("Quota decoding")
struct QuotaDecoderTests {
  @Test func decodesDynamicBucketsAndHashesOpaqueResetID() throws {
    let json = #"""
      {"id":2,"result":{
        "rateLimitsByLimitId":{
          "codex":{"limitId":"codex","planType":"plus","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000000000}},
          "mystery_model":{"limitId":"mystery_model","limitName":"New Model","secondary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":2000600000}}
        },
        "rateLimitResetCredits":{"availableCount":1,"credits":[{"id":"secret-opaque-id","status":"available","title":"Reset","description":"One reset","grantedAt":1900000000,"expiresAt":2000000000}]}
      }}
      """#.data(using: .utf8)!

    let snapshot = try QuotaDecoder.decodeResponse(
      json, observedAt: Date(timeIntervalSince1970: 100))
    #expect(snapshot.planType == "plus")
    #expect(snapshot.windows.count == 2)
    #expect(snapshot.windows.map(\.limitID) == ["codex", "mystery_model"])
    #expect(snapshot.windows[0].remainingPercent == 75)
    #expect(snapshot.resetCreditCount == 1)
    #expect(snapshot.resetCredits[0].id != "secret-opaque-id")
    #expect(snapshot.resetCredits[0].id.count == 24)
  }

  @Test func missingWindowsFailsInsteadOfRenderingZero() {
    let json = #"{"id":2,"result":{"rateLimitsByLimitId":{}}}"#.data(using: .utf8)!
    var didThrow = false
    do { _ = try QuotaDecoder.decodeResponse(json) } catch { didThrow = true }
    #expect(didThrow)
  }

  @Test func collapsedWindowPrefersCodexPrimaryOverReserve() {
    let reserve = RateLimitWindow(
      id: "gpt-reserve:primary",
      limitID: "gpt-reserve",
      limitName: nil,
      windowName: "主窗口",
      usedPercent: 0,
      windowDurationMinutes: 10_080,
      resetsAt: nil,
      reachedType: nil
    )
    let codexSecondary = RateLimitWindow(
      id: "codex:secondary",
      limitID: "codex",
      limitName: nil,
      windowName: "次窗口",
      usedPercent: 30,
      windowDurationMinutes: 10_080,
      resetsAt: nil,
      reachedType: nil
    )
    let codexPrimary = RateLimitWindow(
      id: "codex:primary",
      limitID: "codex",
      limitName: nil,
      windowName: "主窗口",
      usedPercent: 10,
      windowDurationMinutes: 300,
      resetsAt: nil,
      reachedType: nil
    )
    let snapshot = QuotaSnapshot(
      planType: "pro",
      windows: [reserve, codexSecondary, codexPrimary],
      resetCreditCount: 0,
      resetCredits: [],
      creditBalance: nil,
      hasCredits: nil,
      spendControlReached: nil,
      observedAt: Date()
    )

    #expect(snapshot.preferredCodexWindow?.id == "codex:primary")
    #expect(snapshot.preferredCodexWindow?.remainingPercent == 90)
  }

  @Test func supplementaryGPTWindowsAreFilteredByDisplayPreference() {
    let windows = [
      RateLimitWindow(
        id: "base_model_inference:primary", limitID: "base_model_inference",
        limitName: "gpt-reserve", windowName: "主窗口", usedPercent: 0,
        windowDurationMinutes: 10_080, resetsAt: nil, reachedType: nil),
      RateLimitWindow(
        id: "codex:primary", limitID: "codex", limitName: nil, windowName: "主窗口",
        usedPercent: 10, windowDurationMinutes: 300, resetsAt: nil, reachedType: nil),
      RateLimitWindow(
        id: "codex_bengalfox:primary", limitID: "codex_bengalfox",
        limitName: "GPT-5.3-Codex-Spark", windowName: "主窗口", usedPercent: 0,
        windowDurationMinutes: 300, resetsAt: nil, reachedType: nil),
      RateLimitWindow(
        id: "codex_bengalfox:secondary", limitID: "codex_bengalfox",
        limitName: "GPT-5.3-Codex-Spark", windowName: "次窗口", usedPercent: 0,
        windowDurationMinutes: 10_080, resetsAt: nil, reachedType: nil),
    ]
    let snapshot = QuotaSnapshot(
      planType: "pro", windows: windows, resetCreditCount: 0, resetCredits: [],
      creditBalance: nil, hasCredits: nil, spendControlReached: nil, observedAt: Date())

    #expect(
      snapshot.visibleWindows(includingSupplementaryGPT: false).map(\.id) == ["codex:primary"])
    #expect(snapshot.visibleWindows(includingSupplementaryGPT: true).count == 4)
  }

  @Test func proPlanTypesMapToOfficialFiveAndTwentyTimesTiers() {
    let common: (String) -> QuotaSnapshot = { planType in
      QuotaSnapshot(
        planType: planType, windows: [], resetCreditCount: 0, resetCredits: [],
        creditBalance: nil, hasCredits: nil, spendControlReached: nil, observedAt: Date())
    }

    #expect(common("prolite").proTier == .fiveX)
    #expect(common("pro").proTier == .twentyX)
    #expect(common("plus").proTier == nil)
    #expect(common("unknown").proTier == nil)
  }
}

@Suite("Feed parsing")
struct FeedParserTests {
  @Test func twiscanParserRestoresOriginalXURL() throws {
    let html = #"""
      <a href="https://twiscan.com/en/x/thsottiaux/2094252447271366730">2026.08.31 09:30</a>
      <div class="text-sm" id="clamp-2094252447271366730-0">
        We have now reset usage for all paid subscriptions &amp; Codex.
      </div>
      """#
    let posts = try TwiscanFeedSource.parse(html: html, now: Date())
    #expect(posts.count == 1)
    #expect(posts[0].id == "2094252447271366730")
    #expect(posts[0].text == "We have now reset usage for all paid subscriptions & Codex.")
    #expect(posts[0].postedAt == Date(timeIntervalSince1970: 1_788_143_667.415))
    #expect(
      posts[0].originalURL.absoluteString == "https://x.com/thsottiaux/status/2094252447271366730")
  }

  @Test func realBankedResetUsesSnowflakePublicationTimeAndPostRelativePromise() throws {
    let now = Date(timeIntervalSince1970: 1_788_490_800)  // 2026-09-04 11:00 Beijing
    let html = #"""
      <a href="https://twiscan.com/en/x/thsottiaux/2095651088502591861">3 hours ago</a>
      <div id="clamp-2095651088502591861-0">
        We will give one banked reset for every day you don't have access to Astra on your paid ChatGPT plan, starting today. First one will land in ~ 3 hours.
      </div>
      """#

    let post = try #require(TwiscanFeedSource.parse(html: html, now: now).first)
    let exactPostTime = Date(timeIntervalSince1970: 1_788_477_129.470)
    let assessment = RuleBasedActivityClassifier().classify(post)

    #expect(post.postedAt == exactPostTime)
    #expect(assessment.type == .bankedReset)
    #expect(assessment.effectiveAt == exactPostTime.addingTimeInterval(3 * 3_600))
  }

  @Test func twiteeAstroPayloadParser() throws {
    let html = #"""
      &quot;id&quot;:[0,&quot;2090766694897619318&quot;],&quot;handle&quot;:[0,&quot;thsottiaux&quot;],&quot;displayName&quot;:[0,&quot;Tibo&quot;],&quot;text&quot;:[0,&quot;We will credit every Codex user with a BANKED reset.\nUse it later.&quot;],&quot;postedAt&quot;:[0,&quot;2026-08-21T11:43:19+00:00&quot;]
      """#
    let posts = try TwiteeFeedSource.parse(html: html, now: Date())
    #expect(posts.count == 1)
    #expect(posts[0].text.contains("BANKED reset"))
    #expect(posts[0].postedAt != nil)
  }
}

@Suite("Codex task decoding")
struct CodexTaskDecoderTests {
  @Test func decodesRuntimeStatesWithoutUsingChatPreviewAsTitle() throws {
    let data = #"""
      {"id":2,"result":{"data":[
        {"id":"thread-active","name":"Build task monitor","preview":"private prompt","updatedAt":100,"recencyAt":110,"source":"vscode","status":{"type":"active","activeFlags":[]}},
        {"id":"thread-error","name":"Fix build","updatedAt":90,"source":"cli","status":{"type":"systemError"}},
        {"id":"thread-idle","name":null,"preview":"must not become a title","updatedAt":80,"source":"vscode","status":{"type":"notLoaded"}}
      ],"nextCursor":null}}
      """#.data(using: .utf8)!

    let tasks = try CodexTaskDecoder.decodeListResponse(data)

    #expect(tasks.map(\.status) == [.working, .error, .idle])
    #expect(tasks[0].title == "Build task monitor")
    #expect(tasks[0].updatedAt == Date(timeIntervalSince1970: 110))
    #expect(tasks[0].deepLink?.absoluteString == "codex://threads/thread-active")
    #expect(tasks[2].title == "未命名任务")
  }
}

@Suite("Reset forecast")
struct ResetForecastTests {
  @Test func parsesProbabilityAndProjectsMillionUserGrowthWithoutExtendingExpiredPromise() throws {
    let forecast = #"""
      {
        "updated_at":"2026-08-31T16:34:31.630Z",
        "last_reset_at":"2026-08-31T02:34:27.000Z",
        "confidence":"low",
        "confidence_note":"experimental",
        "probabilities":{"raw_24h":0.275,"raw_48h":0.474,"rounded_24h":25,"rounded_48h":45},
        "model":{"version":"rate-v3"},
        "cadence":{"recent_median_days":2.1,"weighted_mean_days":5.1},
        "time_window":{"label":"11 PM - 2 AM","timezone":"UTC"},
        "latest_alert":{"summary":"25M active users reset","url":"https://x.com/thsottiaux/status/25"}
      }
      """#.data(using: .utf8)!
    let timeline = #"""
      {"milestones":[
        {"users_m":20,"announced_at":"2026-08-21T02:34:27Z","group":"credits","url":"https://x.com/thsottiaux/status/20"},
        {"users_m":25,"announced_at":"2026-08-31T02:34:27Z","group":"reset","url":"https://x.com/thsottiaux/status/25"}
      ]}
      """#.data(using: .utf8)!
    let fetchedAt = try #require(ISO8601DateFormatter().date(from: "2026-08-31T16:35:00Z"))
    let snapshot = try PublicResetForecastSource.parse(
      forecastData: forecast, timelineData: timeline, fetchedAt: fetchedAt)

    #expect(snapshot.probability24Hours == 0.25)
    #expect(snapshot.probability48Hours == 0.45)
    #expect(snapshot.availableProbability48Hours(at: fetchedAt) == 0.45)
    #expect(snapshot.modelVersion == "rate-v3")
    let projection = try #require(snapshot.milestoneProjection)
    #expect(projection.latestUsersMillion == 25)
    #expect(abs((projection.growthMillionPerDay ?? 0) - 0.5) < 0.001)
    #expect(projection.nextMillionUsers == 26)
    #expect(projection.nextMajorMilestoneUsers == 30)
    #expect(!projection.oneMillionResetPromiseStillApplies)
    #expect(projection.nextMillionEstimatedAt == projection.latestObservedAt.addingTimeInterval(2 * 86_400))
    #expect(snapshot.availableProbability48Hours(at: snapshot.sourceUpdatedAt.addingTimeInterval(7 * 3_600)) == nil)
  }

  @Test func invalidProbabilityFailsClosedInsteadOfClamping() throws {
    let forecast = #"""
      {"updated_at":"2026-08-31T16:34:31Z","confidence":"low",
       "probabilities":{"raw_24h":-0.2,"raw_48h":1.2},"model":{},"cadence":{},"time_window":{}}
      """#.data(using: .utf8)!
    let timeline = #"{"milestones":[]}"#.data(using: .utf8)!
    let snapshot = try PublicResetForecastSource.parse(
      forecastData: forecast, timelineData: timeline, fetchedAt: Date())

    #expect(snapshot.probability24Hours == nil)
    #expect(snapshot.probability48Hours == nil)
  }
}

@Suite("Rule classifier")
struct ActivityClassifierTests {
  private let classifier = RuleBasedActivityClassifier()

  @Test func labeledHistoricalCasesHaveNoCanResetFalsePositive() {
    let cases: [(String, ActivityType)] = [
      ("We are reseting usage for all paid users of Codex and ChatGPT Work.", .globalReset),
      (
        "During the day we will credit every Codex user with a BANKED reset that you can use later.",
        .bankedReset
      ),
      ("Tomorrow we will reset usage for all Plus users.", .plannedActivity),
      ("Tomorrow we will bring back the 5h limit for Plus accounts across Codex.", .limitChange),
      ("We fixed an issue that showed incorrect limits for some accounts.", .incidentOrFix),
      ("Gimme, gimme, gimme Codex after midnight. Ship it by morning.", .other),
    ]

    for (index, item) in cases.enumerated() {
      let assessment = classifier.classify(post(id: "\(index)", text: item.0))
      #expect(assessment.type == item.1, Comment(rawValue: item.0))
      if item.1 != .globalReset && item.1 != .bankedReset {
        #expect(!assessment.chineseSummary.contains("可以重置"))
      }
    }
  }

  @Test func ambiguousFutureResetIsNotObserved() {
    let assessment = classifier.classify(
      post(id: "planned", text: "Soon we plan to reset everyone for a celebration."))
    #expect(assessment.type == .globalReset)
    #expect(assessment.verification == .announced)
    #expect(assessment.effectiveAt == nil)
    #expect(assessment.timingNote == "官方自动重置时间尚未明确")
  }

  @Test func tomorrowMessageKeepsTimeUnverified() {
    let assessment = classifier.classify(
      post(id: "tomorrow", text: "Tomorrow we will reset usage for every Codex user."))
    #expect(assessment.type == .globalReset)
    #expect(assessment.effectiveAt == nil)
    #expect(assessment.timingNote?.contains("明天") == true)
    #expect(assessment.requiresAction == false)
  }

  @Test func bankedResetRelativeTimeUsesPostTimeNotFetchTime() throws {
    let postedAt = Date(timeIntervalSince1970: 1_788_477_120)  // 2026-09-04 07:12 Beijing
    let fetchedAt = postedAt.addingTimeInterval(31 * 60)
    let assessment = classifier.classify(
      post(
        id: "astra-banked",
        text: "We will credit each affected paid ChatGPT plan with a BANKED reset. The first one will arrive in about 3 hours.",
        postedAt: postedAt,
        fetchedAt: fetchedAt
      ))

    #expect(assessment.type == .bankedReset)
    #expect(assessment.requiresAction)
    #expect(assessment.effectiveAt == postedAt.addingTimeInterval(3 * 3_600))
    #expect(assessment.effectiveAt != fetchedAt.addingTimeInterval(3 * 3_600))
    #expect(assessment.timingNote?.contains("发放手动重置卡") == true)
  }

  @Test func relativeDurationIsReadFromEachPostInsteadOfHardCoded() {
    let postedAt = Date(timeIntervalSince1970: 1_788_478_320)
    let twoHours = classifier.classify(
      post(
        id: "two-hours",
        text: "We will credit every Codex user with a banked reset within 2 hours.",
        postedAt: postedAt
      ))
    let ninetyMinutes = classifier.classify(
      post(
        id: "ninety-minutes",
        text: "We will credit every Codex user with a banked reset in 90 minutes.",
        postedAt: postedAt
      ))
    let shorthand = classifier.classify(
      post(
        id: "shorthand",
        text: "The first BANKED reset will be landing in ~3h. Use it later.",
        postedAt: postedAt
      ))

    #expect(twoHours.effectiveAt == postedAt.addingTimeInterval(2 * 3_600))
    #expect(ninetyMinutes.effectiveAt == postedAt.addingTimeInterval(90 * 60))
    #expect(shorthand.effectiveAt == postedAt.addingTimeInterval(3 * 3_600))
  }

  @Test func futureAutomaticResetIsDifferentFromManualResetCredit() {
    let postedAt = Date(timeIntervalSince1970: 1_788_478_320)
    let automatic = classifier.classify(
      post(
        id: "automatic",
        text: "We will reset usage for every Codex user in four hours.",
        postedAt: postedAt
      ))
    let manual = classifier.classify(
      post(
        id: "manual",
        text: "We will credit every Codex user with a BANKED reset in four hours. Use it later.",
        postedAt: postedAt
      ))

    #expect(automatic.type == .globalReset)
    #expect(!automatic.requiresAction)
    #expect(automatic.verification == .announced)
    #expect(automatic.effectiveAt == postedAt.addingTimeInterval(4 * 3_600))
    #expect(manual.type == .bankedReset)
    #expect(manual.requiresAction)
    #expect(manual.effectiveAt == postedAt.addingTimeInterval(4 * 3_600))
  }

  @Test func bankedResetWithoutTimingDoesNotUsePublicationTimeAsFallback() {
    let postedAt = Date(timeIntervalSince1970: 1_788_478_320)
    let assessment = classifier.classify(
      post(
        id: "no-timing",
        text: "A BANKED reset is coming soon and can be used later.",
        postedAt: postedAt
      ))

    #expect(assessment.type == .bankedReset)
    #expect(assessment.effectiveAt == nil)
    #expect(assessment.timingNote?.contains("待确认") == true)
  }

  @Test func expiryDurationIsNotMistakenForGrantTime() {
    let postedAt = Date(timeIntervalSince1970: 1_788_477_120)
    let assessment = classifier.classify(
      post(
        id: "expiry",
        text: "We have credited every Codex user with a BANKED reset. It expires in 48 hours.",
        postedAt: postedAt
      ))

    #expect(assessment.type == .bankedReset)
    #expect(assessment.effectiveAt == postedAt)
    #expect(assessment.timingNote?.contains("已经发放手动重置卡") == true)
  }

  @Test func completedResetIsNotMadeFutureByUnrelatedSoonLanguage() throws {
    let latest = post(
      id: "latest",
      text:
        "We hit 25M active users and to celebrate we have now reset usage for all paid subscriptions for ChatGPT Work and Codex. See you soon for more news."
    )
    let assessment = classifier.classify(latest)

    #expect(assessment.type == .globalReset)
    #expect(assessment.type.isResetAnnouncement)
    #expect(assessment.effectiveAt == latest.postedAt)
    #expect(!ActivityType.limitChange.isResetAnnouncement)
    #expect(!ActivityType.incidentOrFix.isResetAnnouncement)
    #expect(!ActivityType.other.isResetAnnouncement)
  }

  private func post(
    id: String,
    text: String,
    postedAt: Date = Date(),
    fetchedAt: Date = Date()
  ) -> FeedPost {
    FeedPost(
      id: id, text: text, postedAt: postedAt,
      originalURL: URL(string: "https://x.com/thsottiaux/status/\(id)")!, source: "fixture",
      fetchedAt: fetchedAt)
  }
}

@Suite("Five-hour reminder planning")
struct ResetReminderPlannerTests {
  @Test func schedulesExactlyFiveHoursBeforeFutureReset() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let resetsAt = now.addingTimeInterval(10 * 3_600)
    let plan = try #require(ResetReminderPlanner.plan(resetsAt: resetsAt, now: now))
    #expect(plan.fireAt == now.addingTimeInterval(5 * 3_600))
    #expect(!plan.shouldDeliverImmediately)
  }

  @Test func deliversImmediatelyWhenAlreadyInsideFiveHourWindow() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let resetsAt = now.addingTimeInterval(3 * 3_600)
    let plan = try #require(ResetReminderPlanner.plan(resetsAt: resetsAt, now: now))
    #expect(plan.fireAt == now)
    #expect(plan.shouldDeliverImmediately)
  }

  @Test func ignoresExpiredResetAnchor() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(ResetReminderPlanner.plan(resetsAt: now.addingTimeInterval(-1), now: now) == nil)
  }

  @Test func rollingWindowDoesNotProduceAFixedReminder() {
    let observedAt = Date(timeIntervalSince1970: 2_000_000)
    let previousObservedAt = observedAt.addingTimeInterval(-30)
    let previous = reminderWindow(resetsAt: previousObservedAt.addingTimeInterval(5 * 3_600))
    let current = reminderWindow(resetsAt: observedAt.addingTimeInterval(5 * 3_600))

    let plan = ResetReminderPlanner.stablePlan(
      window: current,
      previousWindow: previous,
      observedAt: observedAt,
      previousObservedAt: previousObservedAt
    )

    #expect(plan == nil)
  }

  @Test func fixedAnchorProducesOneStableCycleKeyDespiteSmallJitter() throws {
    let observedAt = Date(timeIntervalSince1970: 2_000_000)
    let previousObservedAt = observedAt.addingTimeInterval(-30)
    let anchor = observedAt.addingTimeInterval(10 * 3_600)
    let previous = reminderWindow(resetsAt: anchor)
    let first = try #require(ResetReminderPlanner.stablePlan(
      window: reminderWindow(resetsAt: anchor.addingTimeInterval(2)),
      previousWindow: previous,
      observedAt: observedAt,
      previousObservedAt: previousObservedAt
    ))
    let second = try #require(ResetReminderPlanner.stablePlan(
      window: reminderWindow(resetsAt: anchor.addingTimeInterval(8)),
      previousWindow: previous,
      observedAt: observedAt.addingTimeInterval(30),
      previousObservedAt: observedAt
    ))

    #expect(first.cycleKey == second.cycleKey)
    #expect(!first.shouldDeliverImmediately)
  }

  @Test func firstObservationWaitsForAComparisonInsteadOfScheduling() {
    let observedAt = Date(timeIntervalSince1970: 2_000_000)
    let plan = ResetReminderPlanner.stablePlan(
      window: reminderWindow(resetsAt: observedAt.addingTimeInterval(10 * 3_600)),
      previousWindow: nil,
      observedAt: observedAt,
      previousObservedAt: nil
    )
    #expect(plan == nil)
  }

  private func reminderWindow(resetsAt: Date) -> RateLimitWindow {
    RateLimitWindow(
      id: "codex:primary",
      limitID: "codex",
      limitName: "Codex",
      windowName: "主窗口",
      usedPercent: 20,
      windowDurationMinutes: 300,
      resetsAt: resetsAt,
      reachedType: nil
    )
  }
}

@Suite("Account correlation")
struct CorrelationTests {
  @Test func unexpectedUsageDropVerifiesGlobalReset() {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let previous = snapshot(
      used: 85, observed: now.addingTimeInterval(-600), resetsAt: now.addingTimeInterval(10_000))
    let current = snapshot(used: 10, observed: now, resetsAt: now.addingTimeInterval(20_000))
    let post = FeedPost(
      id: "1", text: "reset", postedAt: now.addingTimeInterval(-300),
      originalURL: URL(string: "https://x.com/thsottiaux/status/1")!, source: "fixture",
      fetchedAt: now)
    let assessment = ActivityAssessment(
      postID: "1", type: .globalReset, chineseSummary: "", audience: "", effectiveAt: now,
      requiresAction: false, evidence: [], confidence: 1, verification: .unverified)
    let result = ActivityCorrelationEngine().correlate(
      posts: [post], assessments: [assessment], previous: previous, current: current, now: now)
    #expect(result[0].verification == .observed)
  }

  @Test func naturalScheduledResetIsNotAttributedToPost() {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let previous = snapshot(
      used: 85, observed: now.addingTimeInterval(-600), resetsAt: now.addingTimeInterval(-10))
    let current = snapshot(used: 0, observed: now, resetsAt: now.addingTimeInterval(18_000))
    let post = FeedPost(
      id: "1", text: "reset", postedAt: now.addingTimeInterval(-300),
      originalURL: URL(string: "https://x.com/thsottiaux/status/1")!, source: "fixture",
      fetchedAt: now)
    let assessment = ActivityAssessment(
      postID: "1", type: .globalReset, chineseSummary: "", audience: "", effectiveAt: now,
      requiresAction: false, evidence: [], confidence: 1, verification: .unverified)
    let result = ActivityCorrelationEngine().correlate(
      posts: [post], assessments: [assessment], previous: previous, current: current, now: now)
    #expect(result[0].verification == .unverified)
  }

  private func snapshot(used: Double, observed: Date, resetsAt: Date) -> QuotaSnapshot {
    QuotaSnapshot(
      planType: "plus",
      windows: [
        RateLimitWindow(
          id: "codex:primary", limitID: "codex", limitName: nil, windowName: "主窗口",
          usedPercent: used, windowDurationMinutes: 300, resetsAt: resetsAt, reachedType: nil)
      ],
      resetCreditCount: 0,
      resetCredits: [],
      creditBalance: nil,
      hasCredits: nil,
      spendControlReached: nil,
      observedAt: observed
    )
  }
}

@Suite("SQLite cache")
struct SQLiteStoreTests {
  @Test func roundTripAndNotificationDeduplication() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "CodexFloatTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SQLiteStore(databaseURL: directory.appendingPathComponent("state.sqlite"))
    let snapshot = QuotaSnapshot(
      planType: "plus", windows: [], resetCreditCount: 2, resetCredits: [], creditBalance: nil,
      hasCredits: nil, spendControlReached: nil, observedAt: Date(timeIntervalSince1970: 123))
    try await store.save(snapshot: snapshot)
    let loaded = try await store.latestSnapshot()
    #expect(loaded == snapshot)
    let first = try await store.claimNotification(key: "once")
    let second = try await store.claimNotification(key: "once")
    #expect(first)
    #expect(!second)

    let retentionNow = Date(timeIntervalSince1970: 10_000_000)
    _ = try await store.claimNotification(
      key: "expired",
      now: retentionNow.addingTimeInterval(-SQLiteStore.notificationRetention - 1)
    )
    _ = try await store.claimNotification(key: "retention-trigger", now: retentionNow)
    #expect(try await store.claimNotification(key: "expired", now: retentionNow))

    for index in 0..<(SQLiteStore.maximumNotificationKeyCount + 5) {
      _ = try await store.claimNotification(
        key: "bounded-\(index)",
        now: retentionNow.addingTimeInterval(Double(index + 1))
      )
    }
    #expect(try await store.notificationKeyCount() == SQLiteStore.maximumNotificationKeyCount)

    let tasks = [
      CodexTask(
        id: "thread-1", title: "First", status: .working,
        updatedAt: Date(timeIntervalSince1970: 200), source: "vscode"),
      CodexTask(
        id: "thread-2", title: "Second", status: .idle,
        updatedAt: Date(timeIntervalSince1970: 100), source: "cli"),
    ]
    try await store.save(tasks: tasks)
    #expect(try await store.recentTasks(limit: 1) == [tasks[0]])

    let forecast = ResetForecastSnapshot(
      probability24Hours: 0.25,
      probability48Hours: 0.45,
      confidence: .low,
      confidenceNote: "experimental",
      sourceUpdatedAt: Date(timeIntervalSince1970: 300),
      fetchedAt: Date(timeIntervalSince1970: 301),
      lastResetAt: Date(timeIntervalSince1970: 200),
      modelVersion: "test",
      recentMedianDays: 2.1,
      weightedMeanDays: 5.1,
      commonWindowLabel: "11 PM - 2 AM",
      commonWindowTimeZone: "UTC",
      latestSignalSummary: nil,
      latestSignalURL: nil,
      milestones: []
    )
    try await store.save(resetForecast: forecast)
    #expect(try await store.latestResetForecast() == forecast)
  }
}

@Suite("Codex task runtime index")
struct CodexTaskRuntimeIndexTests {
  @Test func readsOnlyLatestTurnStateAndMapsVisibleStatuses() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "CodexFloatRuntimeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("thread_history_1.sqlite")

    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    let schema = """
      CREATE TABLE thread_turns (
          thread_id TEXT NOT NULL,
          turn_id TEXT NOT NULL,
          rollout_ordinal INTEGER NOT NULL,
          status TEXT NOT NULL,
          started_at INTEGER,
          completed_at INTEGER,
          PRIMARY KEY (thread_id, turn_id)
      );
      CREATE TABLE thread_items (
          thread_id TEXT NOT NULL,
          item_json TEXT NOT NULL
      );
      INSERT INTO thread_items VALUES ('working', 'private chat content');
      INSERT INTO thread_turns VALUES ('working', 'turn-old', 1, 'completed', 50, 60);
      INSERT INTO thread_turns VALUES ('working', 'turn-new', 2, 'inProgress', 990, NULL);
      INSERT INTO thread_turns VALUES ('failed', 'turn-failed', 1, 'failed', 900, 910);
      INSERT INTO thread_turns VALUES ('done', 'turn-done', 1, 'completed', 800, 820);
      INSERT INTO thread_turns VALUES ('stale', 'turn-stale', 1, 'inProgress', 1, NULL);
      """
    #expect(sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK)

    let index = CodexTaskRuntimeIndex(databaseURL: databaseURL)
    let states = try await index.latestStates(for: ["working", "failed", "done", "stale"])
    let now = Date(timeIntervalSince1970: 1_000)

    #expect(states.count == 4)
    #expect(states["working"]?.turnID == "turn-new")
    #expect(states["working"]?.taskStatus(now: now) == .working)
    #expect(states["failed"]?.taskStatus(now: now) == .error)
    #expect(states["done"]?.taskStatus(now: now) == .idle)
    #expect(states["stale"]?.taskStatus(now: now, staleInProgressAfter: 100) == .idle)

    #expect(
      sqlite3_exec(
        database,
        "UPDATE thread_turns SET status = 'completed', completed_at = 1010 WHERE turn_id = 'turn-new';",
        nil,
        nil,
        nil
      ) == SQLITE_OK
    )
    let transitioned = try await index.latestStates(for: ["working"])
    #expect(transitioned["working"]?.status == .completed)
    #expect(transitioned["working"]?.taskStatus(now: now) == .idle)
  }
}

@Suite("Live integration")
struct LiveIntegrationTests {
  @Test func currentCodexAppServerAndFeed() async throws {
    guard ProcessInfo.processInfo.environment["CODEX_FLOAT_LIVE_TEST"] == "1" else { return }
    let client = CodexAppServerClient()
    let snapshot = try await client.readSnapshot()
    #expect(!snapshot.windows.isEmpty)
    let tasks = try await client.readRecentTasks(limit: 3)
    #expect(!tasks.isEmpty)
    #expect(tasks.allSatisfy { !$0.title.isEmpty })
    let refreshedSnapshot = try await client.readSnapshot()
    #expect(!refreshedSnapshot.windows.isEmpty)
    let runtimeStates = try await CodexTaskRuntimeIndex().latestStates(for: tasks.map(\.id))
    #expect(!runtimeStates.isEmpty)
    await client.stop()
    let result = try await TiboFeedMonitor().refresh()
    #expect(!result.posts.isEmpty)
    #expect(result.posts.count == result.assessments.count)
    let forecast = try await PublicResetForecastSource().fetch()
    #expect(forecast.probability48Hours != nil)
    #expect(!forecast.milestones.isEmpty)
  }
}
