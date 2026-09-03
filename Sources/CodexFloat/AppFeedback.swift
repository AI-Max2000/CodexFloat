import CodexQuotaCore
import Foundation

enum AppFeedbackKind: String, Equatable, Sendable {
  case tiboReset
  case quotaLow
  case quotaCritical
}

enum TiboFeedbackTiming: Equatable, Sendable {
  case future(Date)
  case effective(Date)
  case unknown
}

enum AppFeedbackPayload: Equatable, Sendable {
  case recovery(QuotaRecoveryState)
  case quota(remaining: Double, refreshAt: Date?, preview: Bool)
  case tibo(audience: String, timing: TiboFeedbackTiming, preview: Bool)
}

struct LocalizedAppFeedback: Equatable, Sendable {
  let title: String
  let message: String
  let callout: String?
  let compactTitle: String
}

struct AppFeedback: Identifiable, Equatable, Sendable {
  let id: String
  let kind: AppFeedbackKind
  let payload: AppFeedbackPayload
  let duration: TimeInterval

  var isExhaustion: Bool {
    if case .recovery = payload { return true }
    return false
  }

  func localized(using strings: AppStrings) -> LocalizedAppFeedback {
    switch payload {
    case .recovery(let state):
      return LocalizedAppFeedback(
        title: state.title(strings), message: state.message(strings),
        callout: state.actionTitle(strings), compactTitle: state.title(strings))
    case .quota(let remaining, let refreshAt, let preview):
      let titleKey: LocalizedTextKey =
        kind == .quotaCritical ? .feedbackQuotaCriticalTitle : .feedbackQuotaLowTitle
      let calloutKey: LocalizedTextKey =
        kind == .quotaCritical ? .feedbackQuotaCriticalCallout : .feedbackQuotaLowCallout
      let compactKey: LocalizedTextKey =
        kind == .quotaCritical ? .feedbackMenuQuotaCritical : .feedbackMenuQuotaLow
      return LocalizedAppFeedback(
        title: prefixed(strings.text(titleKey), preview: preview, strings: strings),
        message: strings.format(
          .feedbackQuotaMessage,
          QuotaPercentage.text(remaining),
          refreshAt.map { strings.fullDateTime($0) } ?? strings.text(.timeUnknown)
        ),
        callout: strings.text(calloutKey),
        compactTitle: prefixed(
          strings.format(compactKey, QuotaPercentage.text(remaining)),
          preview: preview,
          strings: strings
        )
      )

    case .tibo(let audience, let timing, let preview):
      let localizedAudience = strings.audience(audience)
      let message: String
      let callout: String
      let compactTitle: String
      switch timing {
      case .future(let effectiveAt):
        message = strings.format(
          .feedbackTiboFuture,
          localizedAudience,
          strings.fullDateTime(effectiveAt)
        )
        callout = strings.text(.feedbackTiboCallout)
        compactTitle = strings.format(
          .feedbackMenuTiboFuture,
          strings.shortDateTime(effectiveAt)
        )
      case .effective(let effectiveAt):
        message = strings.format(
          .feedbackTiboEffective,
          localizedAudience,
          strings.fullDateTime(effectiveAt)
        )
        callout = strings.text(.feedbackTiboCallout)
        compactTitle = strings.text(.feedbackMenuTiboEffective)
      case .unknown:
        message = strings.format(.feedbackTiboUnknown, localizedAudience)
        callout = strings.text(.feedbackTiboUnknownCallout)
        compactTitle = strings.text(.feedbackMenuTiboUnknown)
      }
      return LocalizedAppFeedback(
        title: prefixed(
          strings.text(.feedbackTiboTitle),
          preview: preview,
          strings: strings
        ),
        message: message,
        callout: callout,
        compactTitle: prefixed(compactTitle, preview: preview, strings: strings)
      )
    }
  }

  private func prefixed(_ value: String, preview: Bool, strings: AppStrings) -> String {
    preview ? "\(strings.text(.feedbackPreviewPrefix)) · \(value)" : value
  }
}

enum AppFeedbackPlanner {
  static func quotaFeedback(
    previous: QuotaSnapshot?,
    current: QuotaSnapshot,
    lowThreshold: Double,
    criticalThreshold: Double,
    strings: AppStrings
  ) -> AppFeedback? {
    if let recovery = QuotaRecoveryState.evaluate(current, now: current.observedAt),
      recovery.kind == .exhausted
    {
      if let previous,
        !QuotaRecoveryState.eligibleWindows(in: previous, now: current.observedAt).isEmpty
      {
        return nil
      }
      return AppFeedback(
        id: "quota-exhausted-\(Int(current.observedAt.timeIntervalSince1970))",
        kind: .quotaCritical, payload: .recovery(recovery), duration: 12)
    }
    guard current.freshness == .fresh,
      QuotaRecoveryState.evaluate(current, now: current.observedAt) == nil
    else { return nil }
    guard let currentWindow = current.preferredCodexWindow,
      let previousWindow = matchingPreviousWindow(currentWindow, in: previous)
    else { return nil }

    let remaining = currentWindow.remainingPercent
    let resetAnchor = Int(currentWindow.resetsAt?.timeIntervalSince1970 ?? 0)

    if previousWindow.remainingPercent > criticalThreshold,
      currentWindow.remainingPercent <= criticalThreshold
    {
      return AppFeedback(
        id: "quota-critical-\(currentWindow.id)-\(resetAnchor)",
        kind: .quotaCritical,
        payload: .quota(
          remaining: remaining,
          refreshAt: currentWindow.resetsAt,
          preview: false
        ),
        duration: 9
      )
    }

    if previousWindow.remainingPercent > lowThreshold,
      currentWindow.remainingPercent <= lowThreshold
    {
      return AppFeedback(
        id: "quota-low-\(currentWindow.id)-\(resetAnchor)",
        kind: .quotaLow,
        payload: .quota(
          remaining: remaining,
          refreshAt: currentWindow.resetsAt,
          preview: false
        ),
        duration: 7
      )
    }

    return nil
  }

  static func tiboFeedback(
    posts: [FeedPost],
    assessments: [ActivityAssessment],
    previousPostIDs: Set<String>,
    now: Date,
    strings: AppStrings
  ) -> AppFeedback? {
    let postByID = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
    let candidates = assessments.compactMap { assessment -> (FeedPost, ActivityAssessment)? in
      guard !previousPostIDs.contains(assessment.postID),
        assessment.confidence >= 0.85,
        assessment.type.isResetAnnouncement,
        let post = postByID[assessment.postID]
      else { return nil }
      return (post, assessment)
    }
    .sorted {
      ($0.0.postedAt ?? .distantPast) > ($1.0.postedAt ?? .distantPast)
    }

    guard let (post, assessment) = candidates.first else { return nil }

    let timing: TiboFeedbackTiming
    if let effectiveAt = assessment.effectiveAt, effectiveAt > now {
      timing = .future(effectiveAt)
    } else if let effectiveAt = assessment.effectiveAt {
      timing = .effective(effectiveAt)
    } else {
      timing = .unknown
    }

    return AppFeedback(
      id: "tibo-\(post.id)-\(assessment.type.rawValue)",
      kind: .tiboReset,
      payload: .tibo(
        audience: assessment.audience,
        timing: timing,
        preview: false
      ),
      duration: 12
    )
  }

  private static func matchingPreviousWindow(
    _ current: RateLimitWindow,
    in previous: QuotaSnapshot?
  ) -> RateLimitWindow? {
    guard let previous else { return nil }
    return previous.windows.first(where: { $0.id == current.id })
      ?? previous.preferredCodexWindow
  }
}
