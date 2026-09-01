import CodexQuotaCore
import Foundation
import LocalStore
@preconcurrency import UserNotifications

private final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }
}

@MainActor
final class NotificationCoordinator {
  private let store: SQLiteStore
  private let presentationDelegate = ForegroundNotificationDelegate()
  private var reminderPreviousSnapshot: QuotaSnapshot?
  private var reminderCurrentSnapshot: QuotaSnapshot?
  private var removedLegacyPendingReminders = false

  init(store: SQLiteStore) {
    self.store = store
  }

  func requestAuthorizationIfNeeded(settings: AppSettings) {
    guard settings.notificationsEnabled, notificationsAvailable else { return }
    Task {
      let center = UNUserNotificationCenter.current()
      center.delegate = presentationDelegate
      await removeLegacyPendingRemindersIfNeeded(from: center)
      try? await store.pruneNotificationKeys()
      _ = try? await center.requestAuthorization(options: [
        .alert, .sound,
      ])
    }
  }

  func evaluateQuota(previous: QuotaSnapshot?, current: QuotaSnapshot, settings: AppSettings) {
    let strings = AppStrings(language: settings.appLanguage)
    let reminderPrevious = previous ?? reminderCurrentSnapshot
    reminderPreviousSnapshot = reminderPrevious
    reminderCurrentSnapshot = current
    guard settings.notificationsEnabled else {
      cancelScheduledFiveHourReminders()
      return
    }

    if settings.notifyFiveHoursBeforeReset {
      for window in current.windows {
        scheduleFiveHourQuotaReminder(
          for: window,
          current: current,
          previous: reminderPrevious,
          strings: strings
        )
      }
    } else {
      cancelScheduledFiveHourReminders()
    }

    if let previous {
      let oldByID = Dictionary(uniqueKeysWithValues: previous.windows.map { ($0.id, $0) })
      for window in current.windows {
        guard let old = oldByID[window.id] else { continue }
        if let critical = NotificationPlanner.thresholdCrossing(
          old: old,
          current: window,
          threshold: settings.criticalThreshold,
          title: strings.text(.notifyQuotaCritical),
          strings: strings
        ) {
          dispatch(critical)
        } else if let low = NotificationPlanner.thresholdCrossing(
          old: old,
          current: window,
          threshold: settings.lowThreshold,
          title: strings.text(.notifyQuotaLow),
          strings: strings
        ) {
          dispatch(low)
        }
      }

      let oldCount = previous.resetCreditCount ?? previous.resetCredits.count
      let newCount = current.resetCreditCount ?? current.resetCredits.count
      if settings.notifyResetCredits,
        let plan = NotificationPlanner.resetCreditIncrease(
          oldCount: oldCount,
          newCount: newCount,
          observedAt: current.observedAt,
          strings: strings
        )
      {
        dispatch(plan)
      }
    }

    if settings.notifyExpiringCredits {
      for credit in current.resetCredits {
        if let plan = NotificationPlanner.expiringResetCredit(
          credit,
          observedAt: current.observedAt,
          strings: strings
        ) {
          dispatch(plan)
        }
      }
    }
  }

  func evaluateNewPosts(
    posts: [FeedPost],
    assessments: [ActivityAssessment],
    previousPostIDs: Set<String>,
    settings: AppSettings
  ) {
    guard settings.notificationsEnabled, settings.notifyTibo else { return }
    let strings = AppStrings(language: settings.appLanguage)
    let postByID = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
    for assessment in assessments where !previousPostIDs.contains(assessment.postID) {
      guard let post = postByID[assessment.postID] else { continue }
      NotificationPlanner.tiboReset(
        post: post,
        assessment: assessment,
        includeFiveHourReminder: settings.notifyFiveHoursBeforeReset,
        now: Date(),
        strings: strings
      ).forEach(dispatch)
    }
  }

  func notifyTaskCompleted(task: CodexTask, turnID: String?, settings: AppSettings) {
    guard settings.notificationsEnabled, settings.notifyTaskCompletion else { return }
    dispatch(
      NotificationPlanner.taskCompleted(
        task: task,
        turnID: turnID,
        strings: AppStrings(language: settings.appLanguage)
      ))
  }

  func synchronizeScheduledReminders(current: QuotaSnapshot?, settings: AppSettings) {
    guard settings.notificationsEnabled, settings.notifyFiveHoursBeforeReset else {
      cancelScheduledFiveHourReminders()
      return
    }
    requestAuthorizationIfNeeded(settings: settings)
    guard let current else { return }
    let strings = AppStrings(language: settings.appLanguage)
    for window in current.windows {
      scheduleFiveHourQuotaReminder(
        for: window,
        current: current,
        previous: reminderPreviousSnapshot,
        strings: strings
      )
    }
  }

  private func scheduleFiveHourQuotaReminder(
    for window: RateLimitWindow,
    current: QuotaSnapshot,
    previous: QuotaSnapshot?,
    strings: AppStrings
  ) {
    let previousWindow = previous?.windows.first(where: { $0.id == window.id })
    guard
      let plan = NotificationPlanner.fiveHourQuota(
        window: window,
        previousWindow: previousWindow,
        observedAt: current.observedAt,
        previousObservedAt: previous?.observedAt,
        strings: strings
      )
    else { return }
    dispatch(plan)
  }

  private func dispatch(_ plan: NotificationPlan) {
    switch plan.delivery {
    case .immediate:
      deliver(key: plan.key, title: plan.title, body: plan.body)
    case .scheduled(let date, let prefix):
      schedule(
        key: plan.key,
        prefix: prefix,
        title: plan.title,
        body: plan.body,
        at: date
      )
    }
  }

  private func deliver(key: String, title: String, body: String) {
    guard notificationsAvailable else { return }
    Task {
      guard (try? await store.claimNotification(key: key)) == true else { return }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      let request = UNNotificationRequest(identifier: key, content: content, trigger: nil)
      try? await UNUserNotificationCenter.current().add(request)
    }
  }

  private func schedule(
    key: String,
    prefix: String,
    title: String,
    body: String,
    at date: Date
  ) {
    guard notificationsAvailable, date > Date() else { return }
    Task {
      let center = UNUserNotificationCenter.current()
      center.delegate = presentationDelegate
      let pending = await center.pendingNotificationRequests()
      let obsolete = pending.map(\.identifier).filter { $0.hasPrefix(prefix) && $0 != key }
      if !obsolete.isEmpty { center.removePendingNotificationRequests(withIdentifiers: obsolete) }
      guard (try? await store.claimNotification(key: key)) == true else { return }

      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      let trigger = UNTimeIntervalNotificationTrigger(
        timeInterval: max(1, date.timeIntervalSinceNow),
        repeats: false
      )
      let request = UNNotificationRequest(identifier: key, content: content, trigger: trigger)
      try? await center.add(request)
    }
  }

  private func cancelScheduledFiveHourReminders() {
    guard notificationsAvailable else { return }
    Task {
      let center = UNUserNotificationCenter.current()
      let identifiers = await center.pendingNotificationRequests().map(\.identifier).filter {
        $0.hasPrefix("quota-five-hour-") || $0.hasPrefix("tibo-five-hour-")
      }
      if !identifiers.isEmpty {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
      }
    }
  }

  private func removeLegacyPendingRemindersIfNeeded(from center: UNUserNotificationCenter) async {
    guard !removedLegacyPendingReminders else { return }
    removedLegacyPendingReminders = true
    let identifiers = await center.pendingNotificationRequests().map(\.identifier).filter {
      $0.hasPrefix("quota-five-hour-") && !$0.hasPrefix("quota-five-hour-v2-")
    }
    if !identifiers.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
  }

  private var notificationsAvailable: Bool {
    Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
  }
}
