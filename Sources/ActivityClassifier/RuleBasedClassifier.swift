import CodexQuotaCore
import Foundation

public struct RuleBasedActivityClassifier: Sendable {
  public init() {}

  public func classify(_ post: FeedPost) -> ActivityAssessment {
    let text = post.text
    let lower = text.lowercased()
    let mentionsReset = containsAny(lower, ["reset", "resetting", "reseting"])
    let completedReset =
      mentionsReset
      && containsAny(
        lower,
        [
          "have now reset", "has now reset", "we have reset", "we've reset", "we reset usage",
          "are resetting usage", "are reseting usage",
        ])
    let futureLanguage =
      !completedReset
      && containsAny(
        lower,
        [
          "tomorrow", "later today", "during the day", "will reset", "will credit", "planning",
          "plan to", "soon", "coming",
        ])
    let universalAudience = containsAny(
      lower, ["all users", "all paid", "every user", "everyone", "all codex", "every codex"])
    let banked =
      mentionsReset
      && containsAny(lower, ["banked", "reset credit", "credit every", "credited every"])
    let conditional =
      mentionsReset
      && containsAny(
        lower,
        ["if you", "when you", "invite", "eligible", "winner", "milestone", "complete", "unlock"])
    let incident = containsAny(
      lower,
      [
        "incident", "outage", "issue", "bug", "incorrect limit", "wrong limit", "fixed", "fixing",
        "degraded",
      ])
    let limitChange = containsAny(
      lower,
      [
        "usage limit", "usage limits", "5h limit", "weekly limit", "rate limit", "consumption",
        "pricing", "subscription", "plan limits",
      ])

    let type: ActivityType
    let confidence: Double
    let summary: String
    let action: Bool
    let verification: VerificationState

    if banked {
      type = .bankedReset
      confidence = futureLanguage ? 0.91 : 0.97
      summary =
        futureLanguage
        ? "Tibo 宣布将发放可自行使用的额外 Reset，是否到账以本机账号变化为准。"
        : "Tibo 宣布已发放可自行使用的额外 Reset，是否到账以本机账号变化为准。"
      action = true
      verification = .unverified
    } else if conditional {
      type = .conditionalReset
      confidence = 0.86
      summary = "这是一项需要满足条件的 Reset 奖励；请先核对原帖条件，不代表当前账号可直接重置。"
      action = true
      verification = .unverified
    } else if mentionsReset && universalAudience && !futureLanguage {
      type = .globalReset
      confidence = 0.96
      summary = "Tibo 宣布面向相关用户的额度已统一重置；本机账号是否变化仍需单独验证。"
      action = false
      verification = .unverified
    } else if mentionsReset && futureLanguage {
      type = .plannedActivity
      confidence = 0.88
      summary = "Tibo 预告了 Reset 或庆祝活动，目前尚未确认在你的账号生效。"
      action = false
      verification = .announced
    } else if incident {
      type = .incidentOrFix
      confidence = 0.84
      summary = "Tibo 提到了额度异常、修复或服务状态；这不是可用 Reset 的确认。"
      action = false
      verification = .announced
    } else if limitChange {
      type = .limitChange
      confidence = 0.83
      summary = "Tibo 提到了额度窗口、套餐或消耗规则变化；请以账号实际额度为准。"
      action = false
      verification = .announced
    } else {
      type = .other
      confidence = 0.72
      summary = "这条帖子没有明确、可操作的额度重置信息。"
      action = false
      verification = .announced
    }

    let timing = timingAssessment(for: type, lower: lower, postedAt: post.postedAt)
    return ActivityAssessment(
      postID: post.id,
      type: type,
      chineseSummary: summary,
      audience: audience(in: lower),
      effectiveAt: timing.date,
      timingNote: timing.note,
      requiresAction: action,
      evidence: evidence(in: text, for: type),
      confidence: confidence,
      verification: verification
    )
  }

  private func containsAny(_ text: String, _ terms: [String]) -> Bool {
    terms.contains(where: text.contains)
  }

  private func audience(in lower: String) -> String {
    if lower.contains("all paid") { return "全部付费用户" }
    if lower.contains("plus") { return "Plus 用户" }
    if lower.contains("pro") { return "Pro 用户" }
    if lower.contains("business") { return "Business 用户" }
    if lower.contains("every codex") || lower.contains("all codex") { return "Codex 用户" }
    return "受众待确认"
  }

  private func evidence(in text: String, for type: ActivityType) -> [String] {
    let lower = text.lowercased()
    let terms: [String]
    switch type {
    case .globalReset:
      terms = ["reset usage", "resetting usage", "reseting usage", "all paid", "every user"]
    case .bankedReset: terms = ["banked reset", "reset credit", "credit every"]
    case .conditionalReset: terms = ["if you", "when you", "invite", "eligible", "milestone"]
    case .limitChange: terms = ["usage limits", "usage limit", "5h limit", "weekly", "pricing"]
    case .plannedActivity:
      terms = ["tomorrow", "during the day", "will reset", "will credit", "soon"]
    case .incidentOrFix: terms = ["incident", "outage", "issue", "bug", "fixed"]
    case .other: terms = []
    }
    let matches = terms.filter(lower.contains)
    return matches.isEmpty ? ["未发现明确触发短语"] : Array(matches.prefix(4))
  }

  private func timingAssessment(
    for type: ActivityType,
    lower: String,
    postedAt: Date?
  ) -> (date: Date?, note: String) {
    switch type {
    case .globalReset:
      return (postedAt, "原帖称已经生效，仍以账号额度变化为准")
    case .bankedReset:
      if lower.contains("tomorrow") {
        return (nil, "预计明天发放，具体时间待确认")
      }
      if lower.contains("during the day") || lower.contains("later today") {
        return (nil, "预计原帖当天陆续发放，具体时间待确认")
      }
      if lower.contains("will credit") {
        return (nil, "已宣布即将发放，具体时间待确认")
      }
      return (postedAt, "原帖称已经发放，仍以账号到账为准")
    case .conditionalReset:
      return (nil, "满足原帖条件后生效，具体时间取决于完成条件的时间")
    case .plannedActivity:
      if lower.contains("tomorrow") {
        return (nil, "预计明天，具体时间待确认")
      }
      if lower.contains("during the day") || lower.contains("later today") {
        return (nil, "预计原帖当天，具体时间待确认")
      }
      return (nil, "尚未公布具体时间")
    case .limitChange:
      return (nil, "规则生效时间以原帖和账号实际变化为准")
    case .incidentOrFix:
      return (nil, "修复时间以服务状态和账号实际恢复为准")
    case .other:
      return (nil, "没有可确认的刷新时间")
    }
  }
}

public struct ActivityCorrelationEngine: Sendable {
  public init() {}

  public func correlate(
    posts: [FeedPost],
    assessments: [ActivityAssessment],
    previous: QuotaSnapshot?,
    current: QuotaSnapshot,
    now: Date = Date()
  ) -> [ActivityAssessment] {
    guard let previous else { return assessments }
    var result = assessments
    let postByID = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })

    let previousCredits = previous.resetCreditCount ?? previous.resetCredits.count
    let currentCredits = current.resetCreditCount ?? current.resetCredits.count
    if currentCredits > previousCredits,
      let index = newestCandidateIndex(
        types: [.bankedReset, .conditionalReset], in: result, posts: postByID,
        before: current.observedAt, maxAge: 7 * 86_400)
    {
      result[index].verification = .observed
    }

    if hasUnexpectedQuotaReset(previous: previous, current: current),
      let index = newestCandidateIndex(
        types: [.globalReset], in: result, posts: postByID, before: current.observedAt,
        maxAge: 36 * 3_600)
    {
      result[index].verification = .observed
    }

    for index in result.indices {
      if let postDate = postByID[result[index].postID]?.postedAt,
        now.timeIntervalSince(postDate) > 14 * 86_400,
        result[index].verification != .observed
      {
        result[index].verification = .expired
      }
    }
    return result
  }

  private func newestCandidateIndex(
    types: Set<ActivityType>,
    in assessments: [ActivityAssessment],
    posts: [String: FeedPost],
    before: Date,
    maxAge: TimeInterval
  ) -> Int? {
    assessments.indices
      .filter { types.contains(assessments[$0].type) }
      .filter {
        guard let date = posts[assessments[$0].postID]?.postedAt else { return false }
        return date <= before && before.timeIntervalSince(date) <= maxAge
      }
      .max { lhs, rhs in
        (posts[assessments[lhs].postID]?.postedAt ?? .distantPast)
          < (posts[assessments[rhs].postID]?.postedAt ?? .distantPast)
      }
  }

  private func hasUnexpectedQuotaReset(previous: QuotaSnapshot, current: QuotaSnapshot) -> Bool {
    let previousByID = Dictionary(uniqueKeysWithValues: previous.windows.map { ($0.id, $0) })
    for window in current.windows {
      guard let old = previousByID[window.id] else { continue }
      let naturalReset =
        old.resetsAt.map { current.observedAt >= $0.addingTimeInterval(-120) } ?? false
      if !naturalReset && old.usedPercent - window.usedPercent >= 30 { return true }
    }
    return false
  }
}
