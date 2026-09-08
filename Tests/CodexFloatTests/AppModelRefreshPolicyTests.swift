import CodexQuotaCore
import Foundation
import Testing
import LocalStore
import ActivityClassifier

@testable import CodexFloat

@Suite("Application refresh policies")
struct AppModelRefreshPolicyTests {
  @Test @MainActor func launchRecoversAndPersistsMissedResetFromCachedSnapshots() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SQLiteStore(databaseURL: directory.appendingPathComponent("state.sqlite"))
    let now = Date()
    for (used, offset, resetOffset) in [(14.0, -30.0, 86400.0), (0.0, 0.0, 172800.0)] {
      try await store.save(snapshot: QuotaSnapshot(
        planType: "pro", windows: [RateLimitWindow(
          id: "codex:primary", limitID: "codex", limitName: nil, windowName: "weekly",
          usedPercent: used, windowDurationMinutes: 10080,
          resetsAt: now.addingTimeInterval(resetOffset), reachedType: nil)],
        resetCreditCount: 3, resetCredits: [], creditBalance: nil, hasCredits: nil,
        spendControlReached: nil, observedAt: now.addingTimeInterval(offset)))
    }
    let post = FeedPost(id: "relaunch", text: "We will do a global reset for all paid subscriptions.",
      postedAt: now.addingTimeInterval(-3600), originalURL: URL(string: "https://x.com/thsottiaux/status/1")!,
      source: "fixture", fetchedAt: now)
    try await store.save(posts: [post], assessments: [RuleBasedActivityClassifier().classify(post)])
    let suite = "ResetRecoveryTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(store: store, settings: AppSettings(defaults: defaults))
    await model.loadCache()
    #expect(model.assessments[post.id]?.verification == .observed)
    #expect(model.assessments[post.id]?.observedAt == now)
    let persisted = try await store.assessmentsByPostID()
    #expect(persisted[post.id]?.verification == .observed)
    #expect(persisted[post.id]?.observedAt == now)
  }

  @Test func taskMonitoringPollsQuicklyOnlyWhileWorkIsActive() {
    let completed = task(status: .idle)
    let failed = task(status: .error)
    let working = task(status: .working)

    #expect(TaskMonitoringRefreshPolicy.runtimeInterval(for: []) == 15)
    #expect(TaskMonitoringRefreshPolicy.runtimeInterval(for: [completed, failed]) == 15)
    #expect(TaskMonitoringRefreshPolicy.runtimeInterval(for: [completed, working]) == 2)
    #expect(TaskMonitoringRefreshPolicy.activeSummaryInterval == 10)
  }

  private func task(status: CodexTaskStatus) -> CodexTask {
    CodexTask(
      id: UUID().uuidString,
      title: "Fixture",
      status: status,
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
      source: "test"
    )
  }
}
