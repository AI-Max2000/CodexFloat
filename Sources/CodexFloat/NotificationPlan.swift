import ActivityClassifier
import CodexQuotaCore
import Foundation
import TiboFeedCore

enum NotificationDelivery: Equatable, Sendable {
  case immediate
  case scheduled(at: Date, replacingPrefix: String)
}

struct NotificationPlan: Equatable, Sendable {
  let key: String
  let title: String
  let body: String
  let delivery: NotificationDelivery
  var opensUsageSettings = false
}

enum NotificationPlanner {
  static func exhausted(
    state: QuotaRecoveryState, episodeID: String, strings: AppStrings
  ) -> NotificationPlan? {
    guard state.canOpenManualReset else { return nil }
    return NotificationPlan(
      key: "quota-exhausted-\(episodeID)", title: "Codex · \(state.title(strings))",
      body: state.message(strings) + " " + strings.text(.manualResetNavigationHelp),
      delivery: .immediate, opensUsageSettings: true)
  }

  static func fiveHourQuota(
    window: RateLimitWindow,
    previousWindow: RateLimitWindow?,
    observedAt: Date,
    previousObservedAt: Date?,
    strings: AppStrings
  ) -> NotificationPlan? {
    guard
      let reminder = ResetReminderPlanner.stablePlan(
        window: window,
        previousWindow: previousWindow,
        observedAt: observedAt,
        previousObservedAt: previousObservedAt
      )
    else { return nil }

    let prefix = "quota-five-hour-v2-\(window.id)-"
    let body = strings.format(
      .notifyQuotaResetBody,
      strings.windowDisplayName(window),
      strings.fullDateTime(reminder.resetsAt),
      QuotaPercentage.text(window.remainingPercent)
    )
    return NotificationPlan(
      key: "\(prefix)\(reminder.cycleKey)",
      title: strings.text(
        reminder.shouldDeliverImmediately ? .notifyQuotaWithinFiveHours : .notifyQuotaInFiveHours
      ),
      body: body,
      delivery: reminder.shouldDeliverImmediately
        ? .immediate
        : .scheduled(at: reminder.fireAt, replacingPrefix: prefix)
    )
  }

  static func thresholdCrossing(
    old: RateLimitWindow,
    current: RateLimitWindow,
    threshold: Double,
    title: String,
    strings: AppStrings
  ) -> NotificationPlan? {
    guard old.remainingPercent > threshold, current.remainingPercent <= threshold else {
      return nil
    }
    return NotificationPlan(
      key:
        "threshold-\(current.id)-\(Int(threshold))-\(Int(current.resetsAt?.timeIntervalSince1970 ?? 0))",
      title: "Codex · \(title)",
      body: strings.format(
        .notifyQuotaResetBody,
        strings.windowDisplayName(current),
        current.resetsAt.map { strings.fullDateTime($0) } ?? strings.text(.timeUnknown),
        QuotaPercentage.text(current.remainingPercent)
      ),
      delivery: .immediate
    )
  }

  static func resetCreditIncrease(
    oldCount: Int,
    newCount: Int,
    observedAt: Date,
    strings: AppStrings
  ) -> NotificationPlan? {
    guard newCount > oldCount else { return nil }
    return NotificationPlan(
      key: "reset-credit-count-\(newCount)-\(Int(observedAt.timeIntervalSince1970 / 3_600))",
      title: strings.text(.notifyResetAddedTitle),
      body: strings.format(.notifyResetAddedBody, oldCount, newCount),
      delivery: .immediate
    )
  }

  static func expiringResetCredit(
    _ credit: ResetCredit,
    observedAt: Date,
    strings: AppStrings
  ) -> NotificationPlan? {
    guard credit.status == "available", let expiry = credit.expiresAt else { return nil }
    let remaining = expiry.timeIntervalSince(observedAt)
    guard remaining > 0, remaining <= 48 * 3_600 else { return nil }
    return NotificationPlan(
      key: "reset-expiry-\(credit.id)",
      title: strings.text(.notifyResetExpiryTitle),
      body: strings.format(
        .notifyResetExpiryBody,
        strings.resetCreditTitle(credit.title)
      ),
      delivery: .immediate
    )
  }

  static func tiboReset(
    post: FeedPost,
    assessment: ActivityAssessment,
    includeFiveHourReminder: Bool,
    now: Date,
    strings: AppStrings
  ) -> [NotificationPlan] {
    guard assessment.confidence >= 0.85, assessment.type.isResetAnnouncement else { return [] }

    let timing: String
    if assessment.type == .globalReset, let effectiveAt = assessment.effectiveAt,
      effectiveAt <= now
    {
      timing = strings.format(.timingAlreadyEffective, strings.fullDateTime(effectiveAt))
    } else if let effectiveAt = assessment.effectiveAt {
      timing = strings.fullDateTime(effectiveAt)
    } else {
      timing = strings.text(.timingPending)
    }
    var plans = [
      NotificationPlan(
        key: "tibo-\(post.id)-\(assessment.type.rawValue)",
        title: "Tibo · \(strings.activityType(assessment.type))",
        body: strings.format(
          .notifyTiboBody,
          strings.audience(assessment.audience),
          timing,
          strings.activitySummary(assessment)
        ) + " "
          + strings.text(
            assessment.effectiveAt == nil ? .feedbackTiboUnknownCallout : .feedbackTiboCallout
          ),
        delivery: .immediate
      )
    ]
    if includeFiveHourReminder,
      let effectiveAt = assessment.effectiveAt,
      effectiveAt.timeIntervalSince(now) > 5 * 3_600
    {
      let prefix = "tibo-five-hour-\(post.id)"
      plans.append(
        NotificationPlan(
          key: prefix,
          title: strings.text(.notifyTiboFiveHourTitle),
          body: strings.format(
            .notifyTiboFiveHourBody,
            strings.audience(assessment.audience),
            strings.activityType(assessment.type),
            strings.fullDateTime(effectiveAt)
          ),
          delivery: .scheduled(
            at: effectiveAt.addingTimeInterval(-5 * 3_600),
            replacingPrefix: prefix
          )
        )
      )
    }
    return plans
  }

  static func taskCompleted(
    task: CodexTask,
    turnID: String?,
    strings: AppStrings
  ) -> NotificationPlan {
    let notificationID = turnID ?? "\(Int(task.updatedAt.timeIntervalSince1970))"
    return NotificationPlan(
      key: "task-completed-\(task.id)-\(notificationID)",
      title: strings.text(.notifyTaskCompletedTitle),
      body: task.title,
      delivery: .immediate
    )
  }
}
