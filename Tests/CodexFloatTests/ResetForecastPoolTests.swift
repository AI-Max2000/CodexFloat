import Foundation
import LocalStore
import Testing
@testable import CodexFloat
@testable import TiboFeedCore

private final class ForecastTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value = Date(timeIntervalSince1970: 1_790_000_000)
  func now() -> Date { lock.withLock { value } }
  func advance(_ seconds: TimeInterval) { lock.withLock { value.addTimeInterval(seconds) } }
}

private actor ForecastStub: ResetForecastSource {
  nonisolated let sourceURL: URL
  let clock: ForecastTestClock
  var calls = 0
  var failure: ForecastSourceIssue?
  var probability: Double
  var age: TimeInterval = 0
  var lastReset: Date
  var wrongURL = false
  init(_ name: String, clock: ForecastTestClock, probability: Double) {
    sourceURL = URL(string: "https://\(name).example/")!
    self.clock = clock
    self.probability = probability
    lastReset = clock.now().addingTimeInterval(-86_400)
  }
  func configure(failure: ForecastSourceIssue? = nil, age: TimeInterval = 0,
                 reset: Date? = nil, wrongURL: Bool = false) {
    self.failure = failure
    self.age = age
    if let reset { lastReset = reset }
    self.wrongURL = wrongURL
  }
  func fetch() async throws -> ResetForecastSnapshot {
    calls += 1
    // Yield so simultaneous callers exercise the pool's shared in-flight task.
    await Task.yield()
    switch failure {
    case .network: throw URLError(.notConnectedToInternet)
    case .invalid, .missedReset: throw ResetForecastError.invalidPayload("fixture")
    case .stale: throw ResetForecastError.staleData("fixture")
    case nil: break
    }
    return ResetForecastSnapshot(
      probability24Hours: min(probability, 0.2), probability48Hours: probability,
      confidence: .low, confidenceNote: nil,
      sourceUpdatedAt: clock.now().addingTimeInterval(-age), fetchedAt: clock.now(),
      lastResetAt: lastReset, modelVersion: "fixture", recentMedianDays: nil,
      weightedMeanDays: nil, commonWindowLabel: nil, commonWindowTimeZone: nil,
      latestSignalSummary: nil, latestSignalURL: nil, milestones: [],
      sourceURL: wrongURL ? URL(string: "https://other.example/")! : sourceURL)
  }
}

private struct PoolFixture {
  let clock = ForecastTestClock()
  let primary: ForecastStub
  let secondary: ForecastStub
  let third: ForecastStub
  let pool: ResetForecastPool
  let providers: [ResetForecastProvider]
  init(evidence: Bool = false, mirror: Bool = false) {
    primary = ForecastStub("primary", clock: clock, probability: 0.52)
    secondary = ForecastStub("secondary", clock: clock, probability: 0.35)
    third = ForecastStub("third", clock: clock, probability: 0.28)
    providers = [
      .init(id: "a", name: "Primary", source: primary,
            eventEvidenceGroup: evidence ? "first-ledger" : nil),
      .init(id: "b", name: "Backup", source: secondary,
            eventEvidenceGroup: evidence ? (mirror ? "first-ledger" : "second-ledger") : nil),
      .init(id: "c", name: "Third", source: third)
    ]
    let clock = self.clock
    pool = ResetForecastPool(providers: providers, clock: { clock.now() })
  }
}

@Suite("Multi-source reset forecast")
struct ResetForecastPoolTests {
  @Test func defaultPoolUsesThreeCompatibleSourcesWithoutUnverifiedLedgerVotes() {
    let providers = ResetForecastPool.defaultProviders
    #expect(providers.map(\.id) == ["monitor", "whenreset", "codex-reset"])
    #expect(providers[1].eventEvidenceGroup == nil)
    #expect(ResetForecastPool.pollInterval == ResetForecastRefreshPolicy.interval)
  }

  @Test func emptyPoolIsUnavailableNotZero() async {
    let pool = ResetForecastPool(providers: [])
    await #expect(throws: ResetForecastPoolError.self) { try await pool.fetch() }
    #expect(await pool.cachedForecast() == nil)
    #expect(await pool.report().selection == .unavailable)
  }

  @Test func cancelledRefreshDoesNotMarkProvidersUnhealthy() async {
    let f = PoolFixture()
    let task = Task { try await f.pool.fetch() }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await f.pool.persistedState().sources.isEmpty)
  }

  @Test func choosesOneProbabilityNotAverageAndPollsAllSources() async throws {
    let f = PoolFixture()
    let result = try await f.pool.fetch()
    #expect(result.probability48Hours == 0.52)
    #expect(result.sourceURL == f.primary.sourceURL)
    #expect(await f.primary.calls == 1)
    #expect(await f.secondary.calls == 1)
    #expect(await f.third.calls == 1)
    #expect(await f.pool.report().selection == .preferred)
  }

  @Test func concurrentManualAndWakeRefreshesRespectMinimumPollingInterval() async throws {
    let f = PoolFixture()
    async let first = f.pool.fetch()
    async let second = f.pool.fetch()
    let values = try await [first, second]
    #expect(values[0] == values[1])
    for _ in 0..<5 { _ = try await f.pool.fetch() }
    f.clock.advance(299)
    _ = try await f.pool.fetch()
    #expect(await f.primary.calls == 1)
    f.clock.advance(1)
    _ = try await f.pool.fetch()
    #expect(await f.primary.calls == 2)
  }

  @Test func unchangedProbabilityWithFreshSourceTimeStaysHealthy() async throws {
    let f = PoolFixture()
    let first = try await f.pool.fetch()
    f.clock.advance(300)
    let second = try await f.pool.fetch()
    #expect(first.probability48Hours == second.probability48Hours)
    #expect(second.sourceUpdatedAt > first.sourceUpdatedAt)
    #expect(await f.pool.report().sources.allSatisfy { $0.status == .healthy })
  }

  @Test func failsOverImmediatelyAndDoesNotFlapBackOnRecovery() async throws {
    let f = PoolFixture()
    _ = try await f.pool.fetch()
    await f.primary.configure(failure: .network)
    f.clock.advance(300)
    let fallback = try await f.pool.fetch()
    #expect(fallback.sourceURL == f.secondary.sourceURL)
    #expect(fallback.probability48Hours == 0.35)
    await f.primary.configure()
    f.clock.advance(300)
    #expect(try await f.pool.fetch().sourceURL == f.secondary.sourceURL)
    #expect(await f.pool.report().selection == .failover)
    #expect(await f.pool.report().sources[0].status == .healthy)
  }

  @Test func repeatedConnectionFailureIsIsolatedAndProbedSlowly() async throws {
    let f = PoolFixture()
    await f.primary.configure(failure: .network)
    for _ in 0..<3 { _ = try await f.pool.fetch(); f.clock.advance(300) }
    #expect(await f.primary.calls == 3)
    #expect(await f.pool.report().sources[0].status == .quarantined)
    _ = try await f.pool.fetch()
    #expect(await f.primary.calls == 3)
    f.clock.advance(1500)
    _ = try await f.pool.fetch()
    #expect(await f.primary.calls == 4)
  }

  @Test(arguments: [ForecastSourceIssue.stale, .invalid])
  func invalidSourcesRequireTwoSpacedRecoveryChecks(issue: ForecastSourceIssue) async throws {
    let f = PoolFixture()
    await f.primary.configure(failure: issue)
    _ = try await f.pool.fetch()
    #expect(await f.pool.report().sources[0].status == .quarantined)
    await f.primary.configure()
    f.clock.advance(1800)
    _ = try await f.pool.fetch()
    #expect(await f.pool.report().sources[0].status == .recovering)
    f.clock.advance(300)
    _ = try await f.pool.fetch()
    #expect(await f.primary.calls == 2)
    f.clock.advance(1500)
    #expect(try await f.pool.fetch().sourceURL == f.secondary.sourceURL)
    #expect(await f.pool.report().sources[0].status == .healthy)
  }

  @Test func failedProbeResetsRecoveryStreak() async throws {
    let f = PoolFixture()
    await f.primary.configure(failure: .invalid)
    _ = try await f.pool.fetch()
    await f.primary.configure()
    f.clock.advance(1800)
    _ = try await f.pool.fetch()
    await f.primary.configure(failure: .network)
    f.clock.advance(1800)
    _ = try await f.pool.fetch()
    #expect(await f.pool.report().sources[0].status == .quarantined)
    await f.primary.configure()
    f.clock.advance(1800)
    _ = try await f.pool.fetch()
    #expect(await f.pool.report().sources[0].status == .recovering)
  }

  @Test(arguments: [21_601.0, -301.0])
  func staleOrFutureSourceTimeIsRejectedEvenWithRecentFetch(age: Double) async throws {
    let f = PoolFixture()
    await f.primary.configure(age: age)
    #expect(try await f.pool.fetch().sourceURL == f.secondary.sourceURL)
    #expect(await f.pool.report().sources[0].status == .quarantined)
  }

  @Test func allOfflineKeepsBoundedCacheAndThenStopsReportingNumber() async throws {
    let f = PoolFixture()
    let first = try await f.pool.fetch()
    for source in [f.primary, f.secondary, f.third] { await source.configure(failure: .network) }
    f.clock.advance(300)
    #expect(try await f.pool.fetch() == first)
    #expect(await f.pool.report().selection == .cached)
    f.clock.advance(21_301)
    await #expect(throws: ResetForecastPoolError.self) { try await f.pool.fetch() }
    #expect(await f.pool.cachedForecast() == nil)
    #expect(await f.pool.report().selection == .unavailable)
  }

  @Test func knownLocalOutageDoesNotQuarantineHealthySourcesOrDelayRecovery() async throws {
    let f = PoolFixture()
    let first = try await f.pool.fetch()
    for _ in 0..<5 {
      f.clock.advance(300)
      #expect(await f.pool.useOfflineCache() == first)
    }
    #expect(await f.primary.calls == 1)
    #expect(await f.pool.report().selection == .cached)
    #expect(await f.pool.persistedState().sources.values.allSatisfy { !$0.quarantined })
    let recovered = try await f.pool.fetch()
    #expect(recovered.fetchedAt == f.clock.now())
    #expect(await f.primary.calls == 2)
    #expect(await f.pool.report().selection == .preferred)
  }

  @Test func invalidResponseRevokesCacheRatherThanMasqueradingAsNetworkFailure() async throws {
    let f = PoolFixture()
    _ = try await f.pool.fetch()
    await f.primary.configure(wrongURL: true)
    await f.secondary.configure(failure: .network)
    await f.third.configure(failure: .network)
    f.clock.advance(300)
    await #expect(throws: ResetForecastPoolError.self) { try await f.pool.fetch() }
    #expect(await f.pool.cachedForecast() == nil)
  }

  @Test func twoIndependentEventBaselinesExcludeProviderMissingReset() async throws {
    let f = PoolFixture(evidence: true)
    await f.primary.configure(reset: f.clock.now().addingTimeInterval(-3600))
    await f.secondary.configure(reset: f.clock.now().addingTimeInterval(-3500))
    _ = try await f.pool.fetch()
    #expect(await f.pool.report().sources[2].issue == .missedReset)
    #expect(await f.pool.report().sources[2].status == .quarantined)
    let baseline = await f.pool.persistedState().corroboratedResetAt
    #expect(baseline == f.clock.now().addingTimeInterval(-3600))
  }

  @Test func loneNewBaselineOrMirrorsCannotEvictOtherSources() async throws {
    for mirror in [false, true] {
      let f = PoolFixture(evidence: true, mirror: mirror)
      await f.primary.configure(reset: f.clock.now().addingTimeInterval(-3600))
      if mirror { await f.secondary.configure(reset: f.clock.now().addingTimeInterval(-3500)) }
      _ = try await f.pool.fetch()
      #expect(await f.pool.report().sources.allSatisfy { $0.status == .healthy })
      #expect(await f.pool.persistedState().corroboratedResetAt == nil)
    }
  }

  @Test func missingEventProbeDeadlineIsNeitherAcceleratedNorPostponedByOtherPolls() async throws {
    let f = PoolFixture(evidence: true)
    await f.primary.configure(reset: f.clock.now().addingTimeInterval(-3600))
    await f.secondary.configure(reset: f.clock.now().addingTimeInterval(-3500))
    _ = try await f.pool.fetch()
    for _ in 0..<5 { f.clock.advance(300); _ = try await f.pool.fetch() }
    #expect(await f.third.calls == 1)
    f.clock.advance(300)
    _ = try await f.pool.fetch()
    #expect(await f.third.calls == 2)
    #expect(await f.pool.report().sources[2].status == .quarantined)
  }

  @Test func savedSelectionAndIsolationSurviveRestartWithoutChangingSourceURL() async throws {
    let f = PoolFixture()
    await f.primary.configure(failure: .stale)
    let selected = try await f.pool.fetch()
    let data = try JSONEncoder().encode(await f.pool.persistedState())
    let restored = ResetForecastPool(providers: f.providers, clock: { f.clock.now() })
    await restored.restore(try JSONDecoder().decode(ResetForecastPoolState.self, from: data))
    #expect(await restored.cachedForecast() == selected)
    #expect(await restored.report().sources[0].status == .quarantined)
    #expect(try await restored.fetch().sourceURL == f.secondary.sourceURL)
    #expect(await f.primary.calls == 1)
  }

  @Test func unknownRemovedProvidersAndMismatchedURLsNeverRestore() async throws {
    let f = PoolFixture()
    _ = try await f.pool.fetch()
    var state = await f.pool.persistedState()
    state.selectedID = "removed"
    let restored = ResetForecastPool(providers: f.providers, clock: { f.clock.now() })
    await restored.restore(state)
    #expect(await restored.cachedForecast() == nil)
    state.selectedID = "b" // Snapshot still belongs to a, not b.
    await restored.restore(state)
    #expect(await restored.cachedForecast() == nil)
    state.schemaVersion = 99
    await restored.restore(state)
    #expect(await restored.persistedState().sources.isEmpty)
  }

  @Test func backwardClockCannotPostponeRefreshIndefinitely() async throws {
    let f = PoolFixture()
    _ = try await f.pool.fetch()
    let saved = await f.pool.persistedState()
    f.clock.advance(-86_400)
    let restored = ResetForecastPool(providers: f.providers, clock: { f.clock.now() })
    await restored.restore(saved)
    #expect(await restored.cachedForecast() == nil)
    for health in await restored.persistedState().sources.values {
      #expect(health.nextAttemptAt == f.clock.now())
    }
  }

  @Test @MainActor func appPersistsPoolAndClearsExpiredValueWithoutTouchingOtherSettings() async throws {
    let f = PoolFixture()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SQLiteStore(databaseURL: directory.appendingPathComponent("pool.sqlite"))
    let suite = "PoolTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(store: store, resetForecastSource: f.pool, settings: AppSettings(defaults: defaults))
    await model.refreshResetForecast()
    #expect(model.resetForecast?.sourceURL == f.primary.sourceURL)
    #expect(try await store.resetForecastPoolState() == f.pool.persistedState())
    let restoredPool = ResetForecastPool(providers: f.providers, clock: { f.clock.now() })
    let restored = AppModel(store: store, resetForecastSource: restoredPool, settings: AppSettings(defaults: defaults))
    await restored.loadCache()
    #expect(restored.resetForecast == model.resetForecast)
    #expect(restored.resetForecastPoolReport?.selection == .cached)
    for source in [f.primary, f.secondary, f.third] { await source.configure(failure: .network) }
    f.clock.advance(21_601)
    await model.refreshResetForecast()
    #expect(model.resetForecast == nil)
    #expect(model.resetForecastError == AppStrings(language: .simplifiedChinese).text(.forecastPoolUnavailable))
    #expect(model.resetForecastPoolReport?.selection == .unavailable)
  }

  @Test func threeLanguagesShowOnlySelectedProbabilityAndNoCheckCountdown() async throws {
    let f = PoolFixture()
    let snapshot = try await f.pool.fetch()
    let report = await f.pool.report()
    for language in AppLanguage.allCases {
      let strings = AppStrings(language: language)
      let summary = strings.resetForecastSummary(snapshot, now: f.clock.now(), pool: report)
      let help = strings.resetForecastPoolHelp(report)
      #expect(summary == strings.text(.forecastPoolSummary))
      #expect(!help.contains("35%") && !help.contains("28%"))
      #expect(!help.contains("即将") && !help.contains("next check"))
      #expect(help.contains(strings.text(.forecastStatusHealthy)))
      #expect(help.contains(strings.text(.forecastPoolPolicy)))
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEX_FLOAT_LIVE_FORECAST_TEST"] == "1"))
  func livePoolVerifiesAllThreeProvidersAndOneSelectedNumber() async throws {
    let pool = ResetForecastPool()
    let snapshot = try await pool.fetch()
    let report = await pool.report()
    #expect(snapshot.availableProbability48Hours() != nil)
    #expect(report.sources.count == 3)
    #expect(report.sources.allSatisfy { $0.status == .healthy })
    print("Live pool: \(snapshot.sourceURL.host!) 48h=\(snapshot.probability48Hours!), health=\(report.sources)")
  }
}

@Suite("WhenReset public API adapter")
struct WhenResetForecastTests {
  static let now = MonitorResetForecastTests.now
  static let fixture = #"{"updated_at":"2026-10-07T10:00:00Z","data_as_of":"2026-10-01T03:00:00Z","product":"codex","target":"global hard reset (banked excluded)","model":"climatology","probabilities":{"raw_24h":0.15,"raw_48h":0.3529},"hours_since_last":6.5,"sample_n":51}"#

  @Test func readsProbabilityAndKeepsLedgerTimeDistinctFromForecastTime() throws {
    let result = try WhenResetForecastSource.parse(data: Data(Self.fixture.utf8), fetchedAt: Self.now)
    #expect(result.probability48Hours == 0.3529)
    #expect(result.sourceURL == WhenResetForecastSource.homepageURL)
    #expect(result.lastResetAt == ISO8601DateFormatter().date(from: "2026-10-07T03:30:00Z"))
    #expect(result.sourceUpdatedAt == ISO8601DateFormatter().date(from: "2026-10-07T10:00:00Z"))
  }

  @Test(arguments: [
    ("global hard reset (banked excluded)", "any reset including banked"),
    ("codex", "claude"), ("0.3529", "1.1"), ("0.3529", "0.01"),
    ("6.5", "-1"), ("\"sample_n\":51", "\"sample_n\":0"),
    ("2026-10-07T10:00:00Z", "2026-10-07T01:00:00Z"),
    ("2026-10-07T10:00:00Z", "2026-10-08T10:00:00Z"),
    ("2026-10-01T03:00:00Z", "2026-10-08T03:00:00Z")
  ])
  func rejectsOtherTargetsInvalidProbabilityAndStaleClock(replacement: (String, String)) {
    let data = Data(Self.fixture.replacingOccurrences(of: replacement.0, with: replacement.1).utf8)
    #expect(throws: ResetForecastError.self) {
      try WhenResetForecastSource.parse(data: data, fetchedAt: Self.now)
    }
  }

  @Test func rejectsOversizedOrChangedSchemaAndPreservesRealZero() throws {
    for data in [Data(), Data("<html>login</html>".utf8), Data(repeating: 65, count: 256_001)] {
      #expect(throws: ResetForecastError.self) { try WhenResetForecastSource.parse(data: data, fetchedAt: Self.now) }
    }
    let zero = Self.fixture.replacingOccurrences(of: "0.15", with: "0").replacingOccurrences(of: "0.3529", with: "0")
    #expect(try WhenResetForecastSource.parse(data: Data(zero.utf8), fetchedAt: Self.now).probability48Hours == 0)
  }
}
