import Foundation

public enum DataFreshness: String, Codable, Sendable {
  case fresh
  case stale
  case offline

  public var label: String {
    switch self {
    case .fresh: "新鲜"
    case .stale: "陈旧"
    case .offline: "离线"
    }
  }
}

public enum CodexProTier: String, Codable, Equatable, Sendable {
  case fiveX
  case twentyX
}

public struct RateLimitWindow: Codable, Identifiable, Equatable, Sendable {
  public let id: String
  public let limitID: String
  public let limitName: String?
  public let windowName: String
  public let usedPercent: Double
  public let windowDurationMinutes: Int?
  public let resetsAt: Date?
  public let reachedType: String?

  public init(
    id: String,
    limitID: String,
    limitName: String?,
    windowName: String,
    usedPercent: Double,
    windowDurationMinutes: Int?,
    resetsAt: Date?,
    reachedType: String?
  ) {
    self.id = id
    self.limitID = limitID
    self.limitName = limitName
    self.windowName = windowName
    self.usedPercent = min(100, max(0, usedPercent))
    self.windowDurationMinutes = windowDurationMinutes
    self.resetsAt = resetsAt
    self.reachedType = reachedType
  }

  public var remainingPercent: Double { max(0, 100 - usedPercent) }

  public var displayName: String {
    if let limitName, !limitName.isEmpty { return "\(limitName) · \(windowName)" }
    return "\(limitID) · \(windowName)"
  }

  public var isSupplementaryGPTQuota: Bool {
    let normalizedID = limitID.lowercased()
    let normalizedName = limitName?.lowercased() ?? ""
    return normalizedID == "base_model_inference"
      || normalizedID == "codex_bengalfox"
      || normalizedID.hasPrefix("gpt")
      || normalizedName.contains("gpt-reserve")
      || normalizedName.hasPrefix("gpt-")
  }
}

public struct ResetCredit: Codable, Identifiable, Equatable, Sendable {
  public let id: String
  public let resetType: String?
  public let status: String?
  public let grantedAt: Date?
  public let expiresAt: Date?
  public let title: String?
  public let detail: String?

  public init(
    id: String,
    resetType: String?,
    status: String?,
    grantedAt: Date?,
    expiresAt: Date?,
    title: String?,
    detail: String?
  ) {
    self.id = id
    self.resetType = resetType
    self.status = status
    self.grantedAt = grantedAt
    self.expiresAt = expiresAt
    self.title = title
    self.detail = detail
  }
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
  public let planType: String?
  public let windows: [RateLimitWindow]
  public let resetCreditCount: Int?
  public let resetCredits: [ResetCredit]
  public let creditBalance: Double?
  public let hasCredits: Bool?
  public let spendControlReached: Bool?
  public let observedAt: Date
  public let freshness: DataFreshness
  public let lastError: String?

  public init(
    planType: String?,
    windows: [RateLimitWindow],
    resetCreditCount: Int?,
    resetCredits: [ResetCredit],
    creditBalance: Double?,
    hasCredits: Bool?,
    spendControlReached: Bool?,
    observedAt: Date,
    freshness: DataFreshness = .fresh,
    lastError: String? = nil
  ) {
    self.planType = planType
    self.windows = windows
    self.resetCreditCount = resetCreditCount
    self.resetCredits = resetCredits
    self.creditBalance = creditBalance
    self.hasCredits = hasCredits
    self.spendControlReached = spendControlReached
    self.observedAt = observedAt
    self.freshness = freshness
    self.lastError = lastError
  }

  public func marked(_ freshness: DataFreshness, error: String?) -> QuotaSnapshot {
    QuotaSnapshot(
      planType: planType,
      windows: windows,
      resetCreditCount: resetCreditCount,
      resetCredits: resetCredits,
      creditBalance: creditBalance,
      hasCredits: hasCredits,
      spendControlReached: spendControlReached,
      observedAt: observedAt,
      freshness: freshness,
      lastError: error
    )
  }

  public var proTier: CodexProTier? {
    switch planType?.lowercased() {
    case "prolite": .fiveX
    case "pro": .twentyX
    default: nil
    }
  }

  public var preferredCodexWindow: RateLimitWindow? {
    let exactCodex = windows.filter { $0.limitID.lowercased() == "codex" }
    if let primary = exactCodex.first(where: { $0.id.hasSuffix(":primary") }) {
      return primary
    }
    if let first = exactCodex.first { return first }

    let codexNamed = windows.filter {
      $0.limitID.localizedCaseInsensitiveContains("codex")
        || ($0.limitName?.localizedCaseInsensitiveContains("codex") ?? false)
    }
    if let primary = codexNamed.first(where: { $0.id.hasSuffix(":primary") }) {
      return primary
    }
    return codexNamed.first ?? windows.first
  }

  public func visibleWindows(includingSupplementaryGPT: Bool) -> [RateLimitWindow] {
    includingSupplementaryGPT ? windows : windows.filter { !$0.isSupplementaryGPTQuota }
  }
}

public struct FeedPost: Codable, Identifiable, Equatable, Sendable {
  public let id: String
  public let text: String
  public let postedAt: Date?
  public let originalURL: URL
  public let source: String
  public let fetchedAt: Date

  public init(
    id: String, text: String, postedAt: Date?, originalURL: URL, source: String, fetchedAt: Date
  ) {
    self.id = id
    self.text = text
    self.postedAt = postedAt
    self.originalURL = originalURL
    self.source = source
    self.fetchedAt = fetchedAt
  }
}

public enum ActivityType: String, Codable, CaseIterable, Sendable {
  case globalReset
  case bankedReset
  case conditionalReset
  case limitChange
  case plannedActivity
  case incidentOrFix
  case other

  public var label: String {
    switch self {
    case .globalReset: "即时重置"
    case .bankedReset: "额外 Reset"
    case .conditionalReset: "条件奖励"
    case .limitChange: "额度变化"
    case .plannedActivity: "活动预告"
    case .incidentOrFix: "异常与修复"
    case .other: "其他"
    }
  }

  public var isResetAnnouncement: Bool {
    switch self {
    case .globalReset, .bankedReset, .conditionalReset, .plannedActivity: true
    case .limitChange, .incidentOrFix, .other: false
    }
  }
}

public enum VerificationState: String, Codable, Sendable {
  case announced
  case observed
  case unverified
  case expired

  public var label: String {
    switch self {
    case .announced: "已宣布"
    case .observed: "账号已观察到变化"
    case .unverified: "已宣布，尚未在本机验证"
    case .expired: "已过期"
    }
  }
}

public struct ActivityAssessment: Codable, Identifiable, Equatable, Sendable {
  public var id: String { postID }
  public let postID: String
  public let type: ActivityType
  public let chineseSummary: String
  public let audience: String
  public let effectiveAt: Date?
  public let timingNote: String?
  public let requiresAction: Bool
  public let evidence: [String]
  public let confidence: Double
  public var verification: VerificationState

  public init(
    postID: String,
    type: ActivityType,
    chineseSummary: String,
    audience: String,
    effectiveAt: Date?,
    timingNote: String? = nil,
    requiresAction: Bool,
    evidence: [String],
    confidence: Double,
    verification: VerificationState
  ) {
    self.postID = postID
    self.type = type
    self.chineseSummary = chineseSummary
    self.audience = audience
    self.effectiveAt = effectiveAt
    self.timingNote = timingNote
    self.requiresAction = requiresAction
    self.evidence = evidence
    self.confidence = min(1, max(0, confidence))
    self.verification = verification
  }
}

public protocol QuotaSource: Sendable {
  func readSnapshot() async throws -> QuotaSnapshot
}

public protocol FeedSource: Sendable {
  var name: String { get }
  func fetch() async throws -> [FeedPost]
}
