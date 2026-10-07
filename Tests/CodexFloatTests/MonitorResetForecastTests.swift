import Foundation
import LocalStore
import Testing
@testable import TiboFeedCore
@testable import CodexFloat

@Suite("Benchmark-selected reset forecast")
struct MonitorResetForecastTests {
  static let now = ISO8601DateFormatter().date(from: "2026-10-07T10:10:00Z")!

  // Minimal synthetic fixture matching the inspected public SSR contract.
  static func html(p24: String = "30", p48: String = "52", updated: String = "2026-10-07T10:00:57.193Z",
                   state: String = "current") -> String {
    """
    <html><body><time dateTime="2026-10-07T03:35:09.000Z" data-testid="reset-exact-time">last reset</time>
    <p>24 hours</p><div aria-label="Historical probability of another global reset within 24 hours: \(p24)%">
    <span>0%</span><span class="sr-only">Final forecast: \(p24)%</span></div>
    <p>48 hours</p><div aria-label="Historical probability of another global reset within 48 hours: \(p48)%">
    <span>0%</span><span class="sr-only">Final forecast: \(p48)%</span></div>
    <section data-testid="monitor-freshness"><time dateTime="2026-10-07T10:09:59Z">Just now</time></section>
    <script>snapshot:$R[14]={status:"degraded",updatedAt:"\(updated)",forecastStatus:"\(state)",score:30};
    forecast:$R[262]={activeFeatures:$R[263]=[],algorithmVersion:"gpt-5.6-medium-hybrid-v2"};</script>
    </body></html>
    """
  }

  static func snapshot() throws -> ResetForecastSnapshot {
    try MonitorResetForecastSource.parse(htmlData: Data(html().utf8), fetchedAt: now)
  }

  @Test func readsFinalValuesAndSourceTimeNotAnimationOrHeartbeat() throws {
    let result = try Self.snapshot()
    #expect(result.probability24Hours == 0.30)
    #expect(result.availableProbability48Hours(at: Self.now) == 0.52)
    #expect(result.sourceURL == MonitorResetForecastSource.homepageURL)
    #expect(result.sourceUpdatedAt < Self.now.addingTimeInterval(-500))
    #expect(result.lastResetAt == ISO8601DateFormatter().date(from: "2026-10-07T03:35:09Z"))
    #expect(result.modelVersion == "gpt-5.6-medium-hybrid-v2")
    #expect(result.milestones.isEmpty)
    #expect(result.confidence == .low)
  }

  @Test(arguments: [("0", "0"), ("30.5", "52.5"), ("100", "100")])
  func acceptsZeroDecimalsAndUpperBound(values: (String, String)) throws {
    let result = try MonitorResetForecastSource.parse(
      htmlData: Data(Self.html(p24: values.0, p48: values.1).utf8), fetchedAt: Self.now)
    #expect(result.probability48Hours == Double(values.1)! / 100)
  }

  @Test(arguments: [("30", "101"), ("-1", "52"), ("NaN", "52"), ("80", "20"), ("30", "")])
  func rejectsInvalidOrInconsistentProbabilities(values: (String, String)) {
    #expect(throws: ResetForecastError.self) {
      try MonitorResetForecastSource.parse(
        htmlData: Data(Self.html(p24: values.0, p48: values.1).utf8), fetchedAt: Self.now)
    }
  }

  @Test(arguments: ["2026-10-07T03:00:00Z", "2026-10-07T11:00:00Z", "", "not-a-date"])
  func rejectsStaleFutureOrUnknownSourceTime(updated: String) {
    #expect(throws: ResetForecastError.self) {
      try MonitorResetForecastSource.parse(htmlData: Data(Self.html(updated: updated).utf8), fetchedAt: Self.now)
    }
  }

  @Test func rejectsChangedMarkupAndStaleStatusInsteadOfUsingFetchTime() {
    for html in ["<html>48 hours 0%</html>", Self.html(state: "stale"),
      Self.html().replacingOccurrences(of: "snapshot:", with: "unrecognized:")]
    {
      #expect(throws: ResetForecastError.self) {
        try MonitorResetForecastSource.parse(htmlData: Data(html.utf8), fetchedAt: Self.now)
      }
    }
    #expect(throws: ResetForecastError.self) {
      try MonitorResetForecastSource.parse(
        htmlData: Data(repeating: 65, count: MonitorResetForecastSource.maximumResponseBytes + 1), fetchedAt: Self.now)
    }
  }

  @Test func cachedProbabilityExpiresWithoutAnotherSuccessfulFetch() throws {
    let result = try Self.snapshot()
    #expect(result.availableProbability48Hours(at: result.sourceUpdatedAt.addingTimeInterval(21600)) == 0.52)
    #expect(result.availableProbability48Hours(at: result.sourceUpdatedAt.addingTimeInterval(21601)) == nil)
  }

  @Test @MainActor func launchDoesNotReusePreviousProviderOrHideSelectedProviderCache() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SQLiteStore(databaseURL: directory.appendingPathComponent("test.sqlite"))
    let suite = "ForecastCacheTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let old = try PublicResetForecastSource.parse(
      forecastData: Data(#"{"updated_at":"2026-10-07T10:09:59Z","probabilities":{"rounded_48h":28}}"#.utf8),
      timelineData: Data(#"{"milestones":[]}"#.utf8), fetchedAt: Self.now)
    try await store.save(resetForecast: old)
    let model = AppModel(store: store, resetForecastSource: MonitorResetForecastSource(),
                         settings: AppSettings(defaults: defaults))
    await model.loadCache()
    #expect(model.resetForecast == nil)
    let selected = try Self.snapshot()
    try await store.save(resetForecast: selected)
    await model.loadCache()
    #expect(model.resetForecast == selected)
    #expect(try await store.latestResetForecast(sourceURL: old.sourceURL) == old)
    #expect(try await store.latestResetForecast() == old)
  }

  @Test func sourceAndScopeAreLocalizedWithoutMixingOldMilestones() throws {
    let snapshot = try Self.snapshot()
    for language in AppLanguage.allCases {
      let strings = AppStrings(language: language)
      let help = strings.resetForecastHelp(snapshot, now: Self.now)
      #expect(help.contains("codexreset.org"))
      #expect(help.contains("81"))
      #expect(!help.contains(strings.text(.forecastNoMilestone)))
      #expect(strings.resetForecastSummary(snapshot, now: Self.now) == strings.text(.forecastMonitorSummary))
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEX_FLOAT_LIVE_FORECAST_TEST"] == "1"))
  func liveSelectedProviderReturnsFreshForecast() async throws {
    let result = try await MonitorResetForecastSource().fetch()
    #expect(result.sourceURL == MonitorResetForecastSource.homepageURL)
    #expect(result.availableProbability48Hours() != nil)
    print("Selected forecast: \(result.sourceURL.host!) 48h=\(result.probability48Hours!) sourceUpdatedAt=\(result.sourceUpdatedAt)")
  }
}
