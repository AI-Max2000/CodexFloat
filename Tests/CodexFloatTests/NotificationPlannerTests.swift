import Foundation
import Testing

@testable import CodexFloat
@testable import CodexQuotaCore

@Suite("Notification planning")
struct NotificationPlannerTests {
  private let strings = AppStrings(language: .simplifiedChinese)
  private let now = Date(timeIntervalSince1970: 2_000_000_000)

  @Test func criticalThresholdCrossingCreatesOneStableImmediatePlan() throws {
    let resetAt = now.addingTimeInterval(8 * 3_600)
    let plan = try #require(
      NotificationPlanner.thresholdCrossing(
        old: window(remaining: 16, resetsAt: resetAt),
        current: window(remaining: 15, resetsAt: resetAt),
        threshold: 15,
        title: strings.text(.notifyQuotaCritical),
        strings: strings
      ))

    #expect(plan.delivery == .immediate)
    #expect(plan.key == "threshold-codex:primary-15-\(Int(resetAt.timeIntervalSince1970))")
    #expect(plan.title.contains("即将用尽"))
    #expect(plan.body.contains("15%"))
    #expect(
      NotificationPlanner.thresholdCrossing(
        old: window(remaining: 15, resetsAt: resetAt),
        current: window(remaining: 14, resetsAt: resetAt),
        threshold: 15,
        title: strings.text(.notifyQuotaCritical),
        strings: strings
      ) == nil)
  }

  @Test func resetCreditAndExpiryPlansFailClosedOutsideTheirWindows() throws {
    let increase = try #require(
      NotificationPlanner.resetCreditIncrease(
        oldCount: 0,
        newCount: 1,
        observedAt: now,
        strings: strings
      ))
    #expect(increase.key.hasPrefix("reset-credit-count-1-"))
    #expect(increase.body.contains("0") && increase.body.contains("1"))
    #expect(
      NotificationPlanner.resetCreditIncrease(
        oldCount: 1,
        newCount: 1,
        observedAt: now,
        strings: strings
      ) == nil)

    let expiring = credit(expiresAt: now.addingTimeInterval(47 * 3_600))
    #expect(
      NotificationPlanner.expiringResetCredit(
        expiring,
        observedAt: now,
        strings: strings
      )?.key == "reset-expiry-credit-1")
    #expect(
      NotificationPlanner.expiringResetCredit(
        credit(expiresAt: now.addingTimeInterval(49 * 3_600)),
        observedAt: now,
        strings: strings
      ) == nil)
  }

  @Test func futureTiboResetCreatesImmediateAndFiveHourPlans() throws {
    let effectiveAt = now.addingTimeInterval(7 * 3_600)
    let post = FeedPost(
      id: "post-1",
      text: "reset at 8pm",
      postedAt: now,
      originalURL: URL(string: "https://x.com/thsottiaux/status/post-1")!,
      source: "fixture",
      fetchedAt: now
    )
    let assessment = ActivityAssessment(
      postID: post.id,
      type: .plannedActivity,
      chineseSummary: "计划重置",
      audience: "全部付费用户",
      effectiveAt: effectiveAt,
      requiresAction: false,
      evidence: ["at 8pm"],
      confidence: 0.92,
      verification: .unverified
    )

    let plans = NotificationPlanner.tiboReset(
      post: post,
      assessment: assessment,
      includeFiveHourReminder: true,
      now: now,
      strings: strings
    )
    #expect(plans.count == 2)
    #expect(plans[0].delivery == .immediate)
    #expect(plans[0].body.contains("全部付费用户"))
    #expect(
      plans[1].delivery
        == .scheduled(
          at: effectiveAt.addingTimeInterval(-5 * 3_600),
          replacingPrefix: "tibo-five-hour-post-1"
        )
    )
  }

  @Test func uncertainOrLowConfidenceTiboPostsNeverPromiseAReset() {
    let post = FeedPost(
      id: "post-2",
      text: "maybe",
      postedAt: now,
      originalURL: URL(string: "https://x.com/thsottiaux/status/post-2")!,
      source: "fixture",
      fetchedAt: now
    )
    let lowConfidence = ActivityAssessment(
      postID: post.id,
      type: .plannedActivity,
      chineseSummary: "待确认",
      audience: "Codex 用户",
      effectiveAt: nil,
      requiresAction: false,
      evidence: ["maybe"],
      confidence: 0.4,
      verification: .unverified
    )

    #expect(
      NotificationPlanner.tiboReset(
        post: post,
        assessment: lowConfidence,
        includeFiveHourReminder: true,
        now: now,
        strings: strings
      ).isEmpty)
  }

  @Test func taskCompletionPlanUsesTurnIDForDeduplication() {
    let task = CodexTask(
      id: "thread-1",
      title: "发布前回归",
      status: .idle,
      updatedAt: now,
      source: "codex"
    )
    let plan = NotificationPlanner.taskCompleted(task: task, turnID: "turn-7", strings: strings)

    #expect(plan.key == "task-completed-thread-1-turn-7")
    #expect(plan.title == strings.text(.notifyTaskCompletedTitle))
    #expect(plan.body == "发布前回归")
    #expect(plan.delivery == .immediate)
  }

  @Test func quotaReminderPlanPreservesStableCycleAndFireTime() throws {
    let previousObservedAt = now.addingTimeInterval(-30)
    let resetAt = now.addingTimeInterval(8 * 3_600)
    let plan = try #require(
      NotificationPlanner.fiveHourQuota(
        window: window(remaining: 75, resetsAt: resetAt.addingTimeInterval(3)),
        previousWindow: window(remaining: 76, resetsAt: resetAt),
        observedAt: now,
        previousObservedAt: previousObservedAt,
        strings: strings
      ))

    guard case .scheduled(let fireAt, let prefix) = plan.delivery else {
      Issue.record("Expected a scheduled five-hour reminder")
      return
    }
    let observedResetAt = resetAt.addingTimeInterval(3)
    let normalizedAnchor = Date(
      timeIntervalSince1970: (observedResetAt.timeIntervalSince1970 / 300).rounded() * 300
    )
    #expect(fireAt == normalizedAnchor.addingTimeInterval(-5 * 3_600))
    #expect(prefix == "quota-five-hour-v2-codex:primary-")
    #expect(plan.key.hasPrefix(prefix))
  }

  private func window(remaining: Double, resetsAt: Date) -> RateLimitWindow {
    RateLimitWindow(
      id: "codex:primary",
      limitID: "codex",
      limitName: "Codex",
      windowName: "主窗口",
      usedPercent: 100 - remaining,
      windowDurationMinutes: 300,
      resetsAt: resetsAt,
      reachedType: nil
    )
  }

  private func credit(expiresAt: Date) -> ResetCredit {
    ResetCredit(
      id: "credit-1",
      resetType: "banked",
      status: "available",
      grantedAt: now,
      expiresAt: expiresAt,
      title: "额外重置",
      detail: nil
    )
  }
}
