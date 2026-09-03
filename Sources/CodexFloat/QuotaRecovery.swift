import CodexQuotaCore
import Foundation

enum ResetAvailability: Equatable, Sendable {
  case available(Int)
  case unavailable
  case unknown

  var count: Int? {
    switch self {
    case .available(let count): count
    case .unavailable: 0
    case .unknown: nil
    }
  }

  static func resolve(_ snapshot: QuotaSnapshot, now: Date) -> Self {
    // The API count is authoritative; the detail list may be truncated or null.
    if let count = snapshot.resetCreditCount {
      guard count >= 0 else { return .unknown }
      guard count > 0 else { return .unavailable }
      // Only subtract credits that expired AFTER this snapshot. Do not subtract
      // already-expired rows from a server count which has already excluded them.
      let expiredSinceRead = Set(
        snapshot.resetCredits.filter {
          $0.status == "available"
            && $0.expiresAt.map {
              $0 > snapshot.observedAt && $0 <= now
            } == true
        }.map(\.id)
      ).count
      let remaining = max(0, count - expiredSinceRead)
      return remaining > 0 ? .available(remaining) : .unavailable
    }
    let available = Set(
      snapshot.resetCredits.filter {
        $0.status == "available"
          && ($0.resetType == nil || $0.resetType == "codexRateLimits")
          && ($0.expiresAt == nil || $0.expiresAt! > now)
      }.map(\.id)
    ).count
    // Missing count + missing/unknown details is NOT evidence of zero credits.
    return available > 0 ? .available(available) : .unknown
  }
}

struct QuotaRecoveryState: Equatable, Sendable {
  enum Kind: Equatable, Sendable { case exhausted, needsRefresh, awaitingReset, spendLimit }
  let kind: Kind
  let windows: [RateLimitWindow]
  let resets: ResetAvailability

  var canOpenManualReset: Bool {
    kind == .exhausted && (resets.count ?? 0) > 0 && !windows.isEmpty
      && windows.allSatisfy { Self.isWeeklyCodexWindow($0) && $0.remainingPercent <= 0 }
  }
  var needsRefresh: Bool { kind == .needsRefresh || kind == .awaitingReset }

  static func isWeeklyCodexWindow(_ window: RateLimitWindow) -> Bool {
    window.limitID.lowercased() == "codex" && window.windowDurationMinutes == 10_080
  }

  static func eligibleWindows(in snapshot: QuotaSnapshot, now: Date) -> [RateLimitWindow] {
    guard (ResetAvailability.resolve(snapshot, now: now).count ?? 0) > 0 else { return [] }
    return snapshot.windows.filter { isWeeklyCodexWindow($0) && $0.remainingPercent <= 0 }
  }

  static func evaluate(_ snapshot: QuotaSnapshot?, now: Date = Date()) -> Self? {
    guard let snapshot else { return nil }
    // Recovery UX is exclusively for exhausted weekly quota with usable resets.
    // Five-hour limits and accounts without resets retain the original UI.
    // Use the actual duration, not primary/secondary labels or display settings.
    let exhausted = eligibleWindows(in: snapshot, now: now)
    guard !exhausted.isEmpty else { return nil }
    let resets = ResetAvailability.resolve(snapshot, now: now)
    if snapshot.freshness != .fresh || now.timeIntervalSince(snapshot.observedAt) > 330
      || snapshot.observedAt.timeIntervalSince(now) > 60
    {
      return Self(kind: .needsRefresh, windows: exhausted, resets: .unknown)
    }
    if snapshot.spendControlReached == true {
      return Self(kind: .spendLimit, windows: exhausted, resets: resets)
    }
    if !exhausted.isEmpty, exhausted.allSatisfy({ $0.resetsAt.map { $0 <= now } == true }) {
      return Self(kind: .awaitingReset, windows: exhausted, resets: resets)
    }
    return Self(kind: .exhausted, windows: exhausted, resets: resets)
  }

  func title(_ strings: AppStrings) -> String {
    let key: LocalizedTextKey =
      switch kind {
      case .exhausted: .quotaExhausted
      case .needsRefresh: .quotaNeedsVerification
      case .awaitingReset: .quotaResetPending
      case .spendLimit: .quotaSpendBlocked
      }
    return strings.text(key)
  }

  func message(_ strings: AppStrings) -> String {
    switch kind {
    case .needsRefresh: return strings.text(.quotaVerifyBeforeReset)
    case .awaitingReset: return strings.text(.quotaResetPendingHelp)
    case .spendLimit: return strings.text(.quotaSpendBlockedHelp)
    case .exhausted:
      let resetMessage: String =
        switch resets {
        case .available(let count): strings.format(.quotaResetAvailable, count)
        case .unavailable: strings.text(.quotaNoResetAvailable)
        case .unknown: strings.text(.quotaResetCountUnknown)
        }
      let names = windows.map { window in
        switch window.windowDurationMinutes {
        case 300: strings.text(.fiveHourQuota)
        case 10_080: strings.text(.weeklyQuota)
        default: strings.windowDisplayName(window)
        }
      }.joined(separator: " / ")
      return names.isEmpty ? resetMessage : "\(names) · \(resetMessage)"
    }
  }

  func actionTitle(_ strings: AppStrings) -> String {
    strings.text(needsRefresh ? .refresh : (canOpenManualReset ? .goManualReset : .openCodexUsage))
  }
}

/// Persists an episode, not a threshold or rounded percentage. Repeated polling,
/// app relaunch, or a changing reset anchor cannot repeatedly alert at zero.
struct QuotaExhaustionEpisode: Codable, Equatable {
  private(set) var id: String?
  private(set) var exhaustedWindowIDs: Set<String> = []

  mutating func update(snapshot: QuotaSnapshot, now: Date) -> String? {
    guard snapshot.freshness == .fresh,
      abs(now.timeIntervalSince(snapshot.observedAt)) <= 330
    else { return nil }
    let weekly = snapshot.windows.filter(QuotaRecoveryState.isWeeklyCodexWindow)
    guard !weekly.isEmpty else { return nil }
    if ResetAvailability.resolve(snapshot, now: now) == .unavailable {
      // Newly granted resets can make an exhausted week actionable again.
      id = nil
      exhaustedWindowIDs = []
      return nil
    }
    if weekly.allSatisfy({ $0.remainingPercent > 0 }) {
      // A missing weekly bucket is not proof it recovered. Wait until all
      // previously exhausted windows are explicitly returned with quota again.
      let recovered = Set(weekly.filter { $0.remainingPercent > 0 }.map(\.id))
      if exhaustedWindowIDs.isSubset(of: recovered) {
        id = nil
        exhaustedWindowIDs = []
      }
      return nil
    }
    guard QuotaRecoveryState.evaluate(snapshot, now: now)?.kind == .exhausted else { return nil }
    if id == nil { id = UUID().uuidString }
    exhaustedWindowIDs.formUnion(weekly.filter { $0.remainingPercent <= 0 }.map(\.id))
    return id
  }
}

enum QuotaPercentage {
  static func text(_ remaining: Double) -> String {
    guard remaining.isFinite else { return "--" }
    if remaining > 0 && remaining < 1 { return "<1%" }
    return "\(Int(min(100, max(0, remaining)).rounded()))%"
  }
}
