import CodexQuotaCore
import Foundation
import Testing

@testable import CodexFloat

@Suite("Application refresh policies")
struct AppModelRefreshPolicyTests {
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
