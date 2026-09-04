import Foundation
import Testing

@testable import CodexFloat
@testable import CodexQuotaCore

@Suite("Transient feedback planning")
struct AppFeedbackTests {
  private let strings = AppStrings(language: .simplifiedChinese)

  @Test func directDropToCriticalDoesNotAlsoProduceLowFeedback() {
    let reset = Date(timeIntervalSince1970: 2_000_000_000)
    let previous = snapshot(remaining: 55, resetsAt: reset)
    let current = snapshot(remaining: 4, resetsAt: reset)

    let feedback = AppFeedbackPlanner.quotaFeedback(
      previous: previous,
      current: current,
      lowThreshold: 20,
      criticalThreshold: 5,
      strings: strings
    )

    let content = feedback?.localized(using: strings)
    #expect(feedback?.kind == .quotaCritical)
    #expect(content?.message.contains("4%") == true)
    #expect(content?.compactTitle.contains("即将用尽") == true)
  }

  @Test func crossingLowThresholdProducesOrangeFeedback() {
    let reset = Date(timeIntervalSince1970: 2_000_000_000)
    let feedback = AppFeedbackPlanner.quotaFeedback(
      previous: snapshot(remaining: 21, resetsAt: reset),
      current: snapshot(remaining: 19, resetsAt: reset),
      lowThreshold: 20,
      criticalThreshold: 5,
      strings: strings
    )

    #expect(feedback?.kind == .quotaLow)
    #expect(feedback?.localized(using: strings).message.contains("19%") == true)
  }

  @Test func newTiboResetIncludesAudienceAndExplicitExpectedTime() {
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let effectiveAt = now.addingTimeInterval(7_200)
    let post = FeedPost(
      id: "new-reset",
      text: "Reset for all paid users at 8pm",
      postedAt: now,
      originalURL: URL(string: "https://x.com/thsottiaux/status/new-reset")!,
      source: "fixture",
      fetchedAt: now
    )
    let assessment = ActivityAssessment(
      postID: post.id,
      type: .plannedActivity,
      chineseSummary: "",
      audience: "全部付费用户",
      effectiveAt: effectiveAt,
      requiresAction: false,
      evidence: ["reset"],
      confidence: 0.91,
      verification: .unverified
    )

    let feedback = AppFeedbackPlanner.tiboFeedback(
      posts: [post],
      assessments: [assessment],
      previousPostIDs: [],
      now: now,
      strings: strings
    )

    let content = feedback?.localized(using: strings)
    #expect(feedback?.kind == .tiboReset)
    #expect(content?.message.contains("全部付费用户") == true)
    #expect(content?.message.contains(strings.fullDateTime(effectiveAt)) == true)
    #expect(content?.callout == "请尽情吩咐 Codex 吧～")
  }

  @Test func tiboResetWithoutTimeSaysPendingInsteadOfInventingATime() {
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let post = FeedPost(
      id: "pending-reset",
      text: "A reset is coming soon",
      postedAt: now,
      originalURL: URL(string: "https://x.com/thsottiaux/status/pending-reset")!,
      source: "fixture",
      fetchedAt: now
    )
    let assessment = ActivityAssessment(
      postID: post.id,
      type: .plannedActivity,
      chineseSummary: "",
      audience: "Codex 用户",
      effectiveAt: nil,
      requiresAction: false,
      evidence: ["coming soon"],
      confidence: 0.88,
      verification: .unverified
    )

    let feedback = AppFeedbackPlanner.tiboFeedback(
      posts: [post], assessments: [assessment], previousPostIDs: [], now: now, strings: strings)

    let content = feedback?.localized(using: strings)
    #expect(content?.message.contains("未给出明确时间") == true)
    #expect(content?.callout == "时间确认后会再次提醒你。")
  }

  @Test func bankedResetFeedbackSaysManualCreditInsteadOfAutomaticReset() {
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let effectiveAt = now.addingTimeInterval(3 * 3_600)
    let post = FeedPost(
      id: "manual-credit", text: "A banked reset will arrive in 3 hours", postedAt: now,
      originalURL: URL(string: "https://x.com/thsottiaux/status/manual-credit")!,
      source: "fixture", fetchedAt: now)
    let assessment = ActivityAssessment(
      postID: post.id, type: .bankedReset, chineseSummary: "", audience: "Codex 用户",
      effectiveAt: effectiveAt, requiresAction: true, evidence: ["banked reset"],
      confidence: 0.92, verification: .announced)

    let feedback = AppFeedbackPlanner.tiboFeedback(
      posts: [post], assessments: [assessment], previousPostIDs: [], now: now, strings: strings)
    let content = feedback?.localized(using: strings)

    #expect(content?.title.contains("手动重置卡") == true)
    #expect(content?.message.contains("需要你自行使用") == true)
    #expect(content?.message.contains("不会自动重置额度") == true)
    #expect(content?.compactTitle.contains("手动重置卡") == true)
  }

  @Test func activeFeedbackRelocalizesWithoutBeingRecreated() {
    let reset = Date(timeIntervalSince1970: 2_000_000_000)
    let feedback = AppFeedbackPlanner.quotaFeedback(
      previous: snapshot(remaining: 21, resetsAt: reset),
      current: snapshot(remaining: 19, resetsAt: reset),
      lowThreshold: 20,
      criticalThreshold: 5,
      strings: strings
    )

    #expect(feedback?.localized(using: strings).title == "Codex 额度偏低")
    #expect(
      feedback?.localized(using: AppStrings(language: .english)).title
        == "Codex quota is low"
    )
  }

  private func snapshot(remaining: Double, resetsAt: Date) -> QuotaSnapshot {
    QuotaSnapshot(
      planType: "pro",
      windows: [
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
      ],
      resetCreditCount: 0,
      resetCredits: [],
      creditBalance: nil,
      hasCredits: nil,
      spendControlReached: nil,
      observedAt: Date(timeIntervalSince1970: 1_900_000_000)
    )
  }
}
