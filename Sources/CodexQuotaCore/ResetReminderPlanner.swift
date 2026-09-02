import Foundation

public struct ResetReminderPlan: Equatable, Sendable {
  public let fireAt: Date
  public let resetsAt: Date
  public let notificationAnchor: Date
  public let shouldDeliverImmediately: Bool

  public init(
    fireAt: Date,
    resetsAt: Date,
    notificationAnchor: Date? = nil,
    shouldDeliverImmediately: Bool
  ) {
    self.fireAt = fireAt
    self.resetsAt = resetsAt
    self.notificationAnchor = notificationAnchor ?? resetsAt
    self.shouldDeliverImmediately = shouldDeliverImmediately
  }

  public var cycleKey: Int { Int(notificationAnchor.timeIntervalSince1970) }
}

public enum ResetReminderPlanner {
  public static func plan(
    resetsAt: Date?,
    now: Date,
    leadTime: TimeInterval = 5 * 3_600
  ) -> ResetReminderPlan? {
    guard let resetsAt, resetsAt > now else { return nil }
    let fireAt = resetsAt.addingTimeInterval(-leadTime)
    return ResetReminderPlan(
      fireAt: max(fireAt, now),
      resetsAt: resetsAt,
      shouldDeliverImmediately: fireAt <= now
    )
  }

  /// Produces a stable reminder only after two observations prove that the reset anchor is fixed.
  /// Rolling windows commonly return `resetsAt = observedAt + duration`; scheduling against that
  /// value would create a new notification on every refresh, so those windows intentionally return
  /// no fixed-time reminder.
  public static func stablePlan(
    window: RateLimitWindow,
    previousWindow: RateLimitWindow?,
    observedAt: Date,
    previousObservedAt: Date?,
    leadTime: TimeInterval = 5 * 3_600,
    anchorGranularity: TimeInterval = 5 * 60
  ) -> ResetReminderPlan? {
    guard let resetsAt = window.resetsAt,
      let previousResetsAt = previousWindow?.resetsAt,
      let previousObservedAt,
      observedAt > previousObservedAt,
      resetsAt > observedAt
    else { return nil }

    let elapsed = observedAt.timeIntervalSince(previousObservedAt)
    let anchorDrift = resetsAt.timeIntervalSince(previousResetsAt)
    let previousRemaining = previousResetsAt.timeIntervalSince(previousObservedAt)
    let currentRemaining = resetsAt.timeIntervalSince(observedAt)
    let tolerance = max(5, min(90, elapsed * 0.25))
    let followsObservationClock = abs(anchorDrift - elapsed) <= tolerance
    let durationStayedConstant = abs(currentRemaining - previousRemaining) <= tolerance
    if followsObservationClock, durationStayedConstant { return nil }

    let granularity = max(60, anchorGranularity)
    let normalizedTimestamp =
      (resetsAt.timeIntervalSince1970 / granularity).rounded() * granularity
    let notificationAnchor = Date(timeIntervalSince1970: normalizedTimestamp)
    let fireAt = notificationAnchor.addingTimeInterval(-leadTime)
    return ResetReminderPlan(
      fireAt: max(fireAt, observedAt),
      resetsAt: resetsAt,
      notificationAnchor: notificationAnchor,
      shouldDeliverImmediately: fireAt <= observedAt
    )
  }
}
