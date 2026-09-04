import CodexQuotaCore
import Foundation

public struct RuleBasedActivityClassifier: Sendable {
  public init() {}

  public func classify(_ post: FeedPost) -> ActivityAssessment {
    let text = post.text
    let lower = text.lowercased()
    let relativeTiming = relativeTiming(in: lower, postedAt: post.postedAt)
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
      && (relativeTiming != nil
        || containsAny(
          lower,
          [
            "tomorrow", "later today", "during the day", "will reset", "will credit",
            "will arrive", "will land", "landing", "planning", "plan to", "soon", "coming",
          ]))
    let universalAudience = containsAny(
      lower, ["all users", "all paid", "every user", "everyone", "all codex", "every codex"])
    let banked =
      mentionsReset
      && containsAny(
        lower,
        [
          "banked", "bank reset", "reset credit", "credit every", "credited every",
          "use it later", "use later", "manually use",
        ])
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
        ? "Tibo 宣布将发放需要用户自行使用的手动重置卡，是否到账以本机账号变化为准。"
        : "Tibo 宣布已发放需要用户自行使用的手动重置卡，是否到账以本机账号变化为准。"
      action = true
      verification = .unverified
    } else if conditional {
      type = .conditionalReset
      confidence = 0.86
      summary = "这是一项需要满足条件的 Reset 奖励；请先核对原帖条件，不代表当前账号可直接重置。"
      action = true
      verification = .unverified
    } else if mentionsReset && universalAudience {
      type = .globalReset
      confidence = futureLanguage ? 0.92 : 0.96
      summary =
        futureLanguage
        ? "Tibo 宣布将由官方直接统一重置额度；这不是需要手动使用的重置卡。"
        : "Tibo 宣布已由官方直接统一重置额度；本机账号是否变化仍需单独验证。"
      action = false
      verification = futureLanguage ? .announced : .unverified
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

    let timing = timingAssessment(
      for: type,
      lower: lower,
      postedAt: post.postedAt,
      relativeTiming: relativeTiming,
      completedReset: completedReset,
      futureLanguage: futureLanguage
    )
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
    postedAt: Date?,
    relativeTiming: RelativeTiming?,
    completedReset: Bool,
    futureLanguage: Bool
  ) -> (date: Date?, note: String) {
    if let relativeTiming {
      let action: String
      switch type {
      case .bankedReset, .conditionalReset:
        action = "发放手动重置卡"
      case .globalReset:
        action = "由官方自动重置"
      default:
        action = "生效"
      }
      return (
        relativeTiming.date,
        "原帖称将在\(relativeTiming.description)\(action)，时间以原帖发布时间为基准推算"
      )
    }

    switch type {
    case .globalReset:
      if futureLanguage {
        if lower.contains("tomorrow") { return (nil, "预计明天由官方自动重置，具体时间待确认") }
        if lower.contains("during the day") || lower.contains("later today") {
          return (nil, "预计原帖当天由官方自动重置，具体时间待确认")
        }
        return (nil, "官方自动重置时间尚未明确")
      }
      if completedReset {
        return (postedAt, "原帖称发布时已经由官方自动重置，仍以账号额度变化为准")
      }
      return (nil, "没有可确认的官方自动重置时间")
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
      if containsAny(
        lower,
        [
          "have credited", "we've credited", "has been credited", "now available", "has arrived",
          "have arrived", "has landed",
        ])
      {
        return (postedAt, "原帖称发布时已经发放手动重置卡，仍以账号到账为准")
      }
      return (nil, "手动重置卡的发放时间待确认")
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

  private struct RelativeTiming {
    let date: Date
    let description: String
  }

  /// Extracts a duration stated by the author and anchors it to the original post time.
  /// Fetch time is deliberately never used: a delayed scrape must not move the promised event.
  private func relativeTiming(in lower: String, postedAt: Date?) -> RelativeTiming? {
    guard let postedAt else { return nil }
    let englishNumber =
      #"(?:an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|[0-9]+(?:\.[0-9]+)?)"#
    let englishUnit = #"(?:minutes?|mins?|m|hours?|hrs?|h|days?|d)"#
    let englishPatterns = [
      #"(?:in|within)\s+(?:(?:about|around|approximately|roughly|nearly|up to|~)\s*)?("#
        + englishNumber + #")\s*("# + englishUnit + #")\b"#,
      #"("# + englishNumber + #")\s*("# + englishUnit + #")\s*(?:from now|later)\b"#,
    ]
    for pattern in englishPatterns {
      if let captures = firstRelevantTimingCaptures(pattern, in: lower), captures.count >= 3,
        let amount = number(captures[1]), let seconds = seconds(for: captures[2]), amount > 0
      {
        return RelativeTiming(
          date: postedAt.addingTimeInterval(amount * seconds),
          description: relativeDescription(amount: amount, unitSeconds: seconds, in: lower)
        )
      }
    }

    let chinesePattern =
      #"(?:约|約|大约|大約|大概|预计|預計)?\s*([0-9]+(?:\.[0-9]+)?)\s*(分钟|分鐘|小时|小時|天)\s*(?:之)?(?:内|內|后|後)"#
    if let captures = firstRelevantTimingCaptures(chinesePattern, in: lower), captures.count >= 3,
      let amount = Double(captures[1]), let seconds = seconds(for: captures[2]), amount > 0
    {
      return RelativeTiming(
        date: postedAt.addingTimeInterval(amount * seconds),
        description: relativeDescription(amount: amount, unitSeconds: seconds, in: lower)
      )
    }
    return nil
  }

  private func firstRelevantTimingCaptures(_ pattern: String, in text: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return nil
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let source = text as NSString
    for match in regex.matches(in: text, range: range) {
      let contextStart = max(0, match.range.location - 48)
      let contextEnd = min(source.length, NSMaxRange(match.range) + 16)
      let context = source.substring(
        with: NSRange(location: contextStart, length: contextEnd - contextStart))
      if containsAny(
        context,
        [
          "expire", "expiry", "valid for", "use within", "must use", "use it within",
          "到期", "过期", "過期", "有效期", "内使用", "內使用",
        ])
      {
        continue
      }
      return (0..<match.numberOfRanges).map { index in
        guard let range = Range(match.range(at: index), in: text) else { return "" }
        return String(text[range])
      }
    }
    return nil
  }

  private func number(_ value: String) -> Double? {
    if let value = Double(value) { return value }
    return [
      "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
      "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
      "twelve": 12,
    ][value]
  }

  private func seconds(for unit: String) -> TimeInterval? {
    if unit == "m" || unit.contains("minute") || unit.hasPrefix("min") || unit.contains("分钟")
      || unit.contains("分鐘")
    {
      return 60
    }
    if unit == "h" || unit.contains("hour") || unit.hasPrefix("hr") || unit.contains("小时")
      || unit.contains("小時")
    {
      return 3_600
    }
    if unit == "d" || unit.contains("day") || unit == "天" { return 86_400 }
    return nil
  }

  private func relativeDescription(amount: Double, unitSeconds: TimeInterval, in text: String) -> String {
    let value = amount.rounded() == amount ? String(Int(amount)) : String(amount)
    let unit = unitSeconds == 60 ? "分钟" : (unitSeconds == 3_600 ? "小时" : "天")
    let approximate = containsAny(
      text, ["about", "around", "approximately", "roughly", "~", "约", "約", "大概"])
    let within = containsAny(text, ["within", "内", "內"])
    return "\(approximate ? "约" : "")\(value)\(unit)\(within ? "内" : "后")"
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
