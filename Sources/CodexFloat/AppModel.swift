import ActivityClassifier
import CodexQuotaCore
import Combine
import Foundation
import LocalStore
import Network
import TiboFeedCore
import os

enum ResetForecastRefreshPolicy {
  static let interval: TimeInterval = 5 * 60
}

enum TaskMonitoringRefreshPolicy {
  static let activeInterval: TimeInterval = 2
  static let idleInterval: TimeInterval = 15
  static let activeSummaryInterval: TimeInterval = 10

  static func runtimeInterval(for tasks: [CodexTask]) -> TimeInterval {
    tasks.contains(where: { $0.status == .working }) ? activeInterval : idleInterval
  }
}

@MainActor
final class AppModel: ObservableObject {
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.local.codexfloat",
    category: "model"
  )
  @Published private(set) var quota: QuotaSnapshot?
  @Published private(set) var posts: [FeedPost] = []
  @Published private(set) var assessments: [String: ActivityAssessment] = [:]
  @Published private(set) var quotaError: String?
  @Published private(set) var feedError: String?
  @Published private(set) var feedSourceName: String?
  @Published private(set) var feedFetchedAt: Date?
  @Published private(set) var resetForecast: ResetForecastSnapshot?
  @Published private(set) var resetForecastError: String?
  @Published private(set) var tasks: [CodexTask] = []
  @Published private(set) var taskError: String?
  @Published private(set) var isRefreshingQuota = false
  @Published private(set) var isRefreshingFeed = false
  @Published private(set) var isRefreshingResetForecast = false
  @Published private(set) var isRefreshingTasks = false
  @Published private(set) var networkAvailable = true
  @Published private(set) var transientFeedback: AppFeedback?

  let settings: AppSettings
  private let store: SQLiteStore
  private let quotaClient: CodexAppServerClient
  private let feedMonitor: TiboFeedMonitor
  private let resetForecastSource: any ResetForecastSource
  private let taskRuntimeIndex: CodexTaskRuntimeIndex
  private let notifications: NotificationCoordinator
  private let correlation = ActivityCorrelationEngine()
  private let pathMonitor = NWPathMonitor()
  private let pathQueue = DispatchQueue(label: "com.codexfloat.network")
  private var quotaLoop: Task<Void, Never>?
  private var feedLoop: Task<Void, Never>?
  private var forecastLoop: Task<Void, Never>?
  private var taskLoop: Task<Void, Never>?
  private var feedbackDismissTask: Task<Void, Never>?
  private var hasTaskRuntimeBaseline = false
  private var lastObservedTurnIDs: [String: String] = [:]
  private var quotaRefreshPending = false
  private var hasFeedBaseline = false

  private var strings: AppStrings { AppStrings(language: settings.appLanguage) }

  init(
    store: SQLiteStore,
    quotaClient: CodexAppServerClient = CodexAppServerClient(),
    feedMonitor: TiboFeedMonitor = TiboFeedMonitor(),
    resetForecastSource: any ResetForecastSource = PublicResetForecastSource(),
    taskRuntimeIndex: CodexTaskRuntimeIndex = CodexTaskRuntimeIndex(),
    settings: AppSettings = AppSettings()
  ) {
    self.store = store
    self.quotaClient = quotaClient
    self.feedMonitor = feedMonitor
    self.resetForecastSource = resetForecastSource
    self.taskRuntimeIndex = taskRuntimeIndex
    self.settings = settings
    notifications = NotificationCoordinator(store: store)
  }

  deinit {
    quotaLoop?.cancel()
    feedLoop?.cancel()
    forecastLoop?.cancel()
    taskLoop?.cancel()
    feedbackDismissTask?.cancel()
    pathMonitor.cancel()
  }

  func start() {
    notifications.requestAuthorizationIfNeeded(settings: settings)
    configureNetworkMonitor()
    settings.onNotificationSettingsChange = { [weak self] in
      self?.notificationSettingsDidChange()
    }
    settings.onTaskSettingsChange = { [weak self] in self?.taskSettingsDidChange() }
    settings.onQuotaRefreshSettingsChange = { [weak self] in
      self?.quotaRefreshSettingsDidChange()
    }
    settings.onFeedSettingsChange = { [weak self] in self?.feedSettingsDidChange() }
    Task {
      await loadCache()
      await quotaClient.setRateLimitUpdatedHandler { [weak self] in
        Task { @MainActor in self?.scheduleEventRefresh() }
      }
      await refreshQuota(reason: "启动")
      if settings.feedEnabled { await refreshFeed() }
      if settings.forecastMonitoringNeeded { await refreshResetForecast() }
      if settings.taskMonitoringNeeded { await refreshTasks(reason: "启动") }
      startQuotaLoop()
      startFeedLoop()
      startForecastLoop()
      startTaskLoop()
    }
  }

  func stop() {
    quotaLoop?.cancel()
    feedLoop?.cancel()
    forecastLoop?.cancel()
    taskLoop?.cancel()
    feedbackDismissTask?.cancel()
    pathMonitor.cancel()
    settings.onNotificationSettingsChange = nil
    settings.onTaskSettingsChange = nil
    settings.onQuotaRefreshSettingsChange = nil
    settings.onFeedSettingsChange = nil
    Task { await quotaClient.stop() }
  }

  func refreshAll() {
    Task {
      await refreshQuota(reason: "手动刷新")
      if settings.feedEnabled { await refreshFeed() }
      if settings.forecastMonitoringNeeded { await refreshResetForecast() }
      if settings.taskMonitoringNeeded { await refreshTasks(reason: "手动刷新") }
    }
  }

  func refreshAfterWakeOrShow() {
    Task {
      await refreshQuota(reason: "唤醒或显示")
      if settings.forecastMonitoringNeeded { await refreshResetForecast() }
      if settings.taskMonitoringNeeded { await refreshTasks(reason: "唤醒或显示") }
    }
  }

  func assessment(for post: FeedPost) -> ActivityAssessment? { assessments[post.id] }

  func previewFeedback(_ kind: AppFeedbackKind) {
    let now = Date()
    let remaining = Int(quota?.preferredCodexWindow?.remainingPercent.rounded() ?? 18)
    let refreshAt = quota?.preferredCodexWindow?.resetsAt ?? now.addingTimeInterval(6 * 3_600)
    let feedback: AppFeedback
    switch kind {
    case .tiboReset:
      let expectedAt = now.addingTimeInterval(2 * 3_600)
      feedback = AppFeedback(
        id: "preview-tibo-\(UUID().uuidString)",
        kind: kind,
        payload: .tibo(
          audience: "全部付费用户",
          timing: .future(expectedAt),
          preview: true
        ),
        duration: 20
      )
    case .quotaLow:
      feedback = AppFeedback(
        id: "preview-low-\(UUID().uuidString)",
        kind: kind,
        payload: .quota(
          remaining: min(remaining, Int(settings.lowThreshold.rounded())),
          refreshAt: refreshAt,
          preview: true
        ),
        duration: 20
      )
    case .quotaCritical:
      feedback = AppFeedback(
        id: "preview-critical-\(UUID().uuidString)",
        kind: kind,
        payload: .quota(
          remaining: min(remaining, Int(settings.criticalThreshold.rounded())),
          refreshAt: refreshAt,
          preview: true
        ),
        duration: 20
      )
    }
    present(feedback)
  }

  var resetAnnouncementPosts: [FeedPost] {
    posts.filter { assessments[$0.id]?.type.isResetAnnouncement == true }
  }

  var latestResetAnnouncementPost: FeedPost? {
    resetAnnouncementPosts.first
  }

  func diagnosticsData() async throws -> Data {
    let report = DiagnosticsReport(
      generatedAt: Date(),
      appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "development",
      osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      codexExecutable: redactedPath(CodexExecutableLocator.locate()?.path),
      quotaFreshness: quota?.freshness.rawValue,
      quotaWindowCount: quota?.windows.count ?? 0,
      resetCreditCount: quota?.resetCreditCount,
      lastQuotaSuccess: quota?.observedAt,
      quotaError: sanitized(quotaError),
      feedSource: feedSourceName,
      cachedPostCount: posts.count,
      feedFetchedAt: feedFetchedAt,
      feedError: sanitized(feedError),
      resetForecastUpdatedAt: resetForecast?.sourceUpdatedAt,
      resetForecastConfidence: resetForecast?.confidence.rawValue,
      resetForecastError: sanitized(resetForecastError),
      cachedTaskCount: tasks.count,
      taskError: sanitized(taskError ?? settings.taskMonitoringError),
      databaseBytes: await store.databaseSize()
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(report)
  }

  // Kept separate from start() so cache restoration can be verified without
  // launching the App Server, polling feeds, or requesting notifications.
  func loadCache() async {
    do {
      if let cached = try await store.latestSnapshot() {
        quota = cached.marked(.stale, error: nil)
      }
      posts = try await store.latestPosts()
      assessments = try await store.assessmentsByPostID()
      feedFetchedAt = posts.map(\.fetchedAt).max()
      feedSourceName = posts.first?.source
      hasFeedBaseline = !posts.isEmpty
      resetForecast = try await store.latestResetForecast()
      tasks = try await store.recentTasks(limit: 50)
    } catch {
      quotaError = strings.format(.errorCacheRead, error.localizedDescription)
    }
  }

  private func startQuotaLoop() {
    quotaLoop?.cancel()
    quotaLoop = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        let interval = self.quotaError == nil
          ? self.settings.quotaRefreshInterval
          : min(10, self.settings.quotaRefreshInterval)
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { break }
        await self.refreshQuota(reason: "自动刷新")
      }
    }
  }

  private func startFeedLoop() {
    feedLoop?.cancel()
    feedLoop = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        let interval = await self.feedMonitor.nextPollInterval()
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { break }
        if self.settings.feedEnabled { await self.refreshFeed() }
      }
    }
  }

  private func startForecastLoop() {
    forecastLoop?.cancel()
    forecastLoop = nil
    guard settings.forecastMonitoringNeeded else { return }
    forecastLoop = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(ResetForecastRefreshPolicy.interval))
        guard let self, !Task.isCancelled else { break }
        if self.settings.forecastMonitoringNeeded {
          await self.refreshResetForecast()
        }
      }
    }
  }

  private func startTaskLoop() {
    taskLoop?.cancel()
    taskLoop = nil
    guard settings.taskMonitoringNeeded else { return }
    taskLoop = Task { [weak self] in
      var elapsedSinceSummary: TimeInterval = 0
      while !Task.isCancelled {
        guard let self else { break }
        let wasWorking = self.tasks.contains(where: { $0.status == .working })
        let interval = TaskMonitoringRefreshPolicy.runtimeInterval(for: self.tasks)
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { break }
        if self.settings.taskMonitoringNeeded {
          if wasWorking {
            elapsedSinceSummary += interval
            await self.refreshTaskRuntimeStates()
          } else {
            elapsedSinceSummary = 0
            await self.refreshTasks(reason: "定时更新")
          }
          if elapsedSinceSummary >= TaskMonitoringRefreshPolicy.activeSummaryInterval {
            elapsedSinceSummary = 0
            await self.refreshTasks(reason: "定时更新")
          }
        }
      }
    }
  }

  private func scheduleEventRefresh() {
    guard !quotaRefreshPending else { return }
    quotaRefreshPending = true
    Task {
      try? await Task.sleep(for: .milliseconds(600))
      quotaRefreshPending = false
      await refreshQuota(reason: "额度变化事件")
    }
  }

  private func refreshQuota(reason: String) async {
    guard !isRefreshingQuota else { return }
    isRefreshingQuota = true
    defer { isRefreshingQuota = false }
    let previous = quota
    do {
      let snapshot = try await quotaClient.readSnapshot()
      quota = snapshot
      quotaError = nil
      logger.info("Quota refresh succeeded: \(reason, privacy: .public)")
      try await store.save(snapshot: snapshot)
      notifications.evaluateQuota(previous: previous, current: snapshot, settings: settings)
      if let feedback = AppFeedbackPlanner.quotaFeedback(
        previous: previous,
        current: snapshot,
        lowThreshold: settings.lowThreshold,
        criticalThreshold: settings.criticalThreshold,
        strings: strings
      ) {
        present(feedback)
      }

      if !posts.isEmpty {
        let values = posts.compactMap { assessments[$0.id] }
        let correlated = correlation.correlate(
          posts: posts, assessments: values, previous: previous, current: snapshot)
        assessments = Dictionary(uniqueKeysWithValues: correlated.map { ($0.postID, $0) })
        try await store.save(posts: posts, assessments: correlated)
      }
    } catch {
      let message = "\(localizedReason(reason))：\(error.localizedDescription)"
      quotaError = message
      let safeMessage = sanitized(message) ?? "未知错误"
      logger.error("Quota refresh failed: \(safeMessage, privacy: .public)")
      if let quota {
        self.quota = quota.marked(networkAvailable ? .stale : .offline, error: message)
      }
    }
  }

  private func refreshFeed() async {
    guard !isRefreshingFeed else { return }
    isRefreshingFeed = true
    defer { isRefreshingFeed = false }
    let priorIDs = Set(posts.map(\.id))
    do {
      let result = try await feedMonitor.refresh()
      var merged = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
      for post in result.posts { merged[post.id] = post }
      posts = Array(merged.values)
        .sorted { ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast) }
        .prefix(100).map { $0 }

      var classified = Dictionary(uniqueKeysWithValues: result.assessments.map { ($0.postID, $0) })
      for post in posts where classified[post.id] == nil {
        classified[post.id] = assessments[post.id]
      }
      var values = posts.compactMap { classified[$0.id] }
      if let quota {
        values = correlation.correlate(
          posts: posts, assessments: values, previous: nil, current: quota)
      }
      assessments = Dictionary(uniqueKeysWithValues: values.map { ($0.postID, $0) })
      feedSourceName = result.sourceName
      feedFetchedAt = result.fetchedAt
      feedError = nil
      try await store.save(posts: posts, assessments: values)
      if hasFeedBaseline {
        notifications.evaluateNewPosts(
          posts: posts, assessments: values, previousPostIDs: priorIDs, settings: settings)
        if settings.notifyTibo,
          let feedback = AppFeedbackPlanner.tiboFeedback(
            posts: posts,
            assessments: values,
            previousPostIDs: priorIDs,
            now: result.fetchedAt,
            strings: strings
          )
        {
          present(feedback)
        }
      }
      hasFeedBaseline = true
    } catch {
      feedError = strings.format(.errorSourceUnavailable, error.localizedDescription)
    }
  }

  private func refreshResetForecast() async {
    guard !isRefreshingResetForecast else { return }
    isRefreshingResetForecast = true
    defer { isRefreshingResetForecast = false }
    do {
      let snapshot = try await resetForecastSource.fetch()
      resetForecast = snapshot
      resetForecastError = nil
      try await store.save(resetForecast: snapshot)
    } catch {
      resetForecastError = strings.format(.errorForecastUnavailable, error.localizedDescription)
    }
  }

  private func refreshTasks(reason: String) async {
    guard !isRefreshingTasks else { return }
    isRefreshingTasks = true
    defer { isRefreshingTasks = false }
    do {
      let previous = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
      let requestedLimit = max(settings.recentTaskCount, 8)
      let fetched = try await quotaClient.readRecentTasks(limit: requestedLimit)
      do {
        let states = try await taskRuntimeIndex.latestStates(for: fetched.map(\.id))
        tasks = applyingRuntimeStates(states, to: fetched, previous: previous)
        settings.setTaskMonitoringError(nil)
      } catch {
        tasks = fetched.map { task in
          guard let previousTask = previous[task.id] else { return task }
          return task.withStatus(previousTask.status)
        }
        settings.setTaskMonitoringError(error.localizedDescription)
      }
      taskError = nil
      try await store.save(tasks: tasks)
      hasTaskRuntimeBaseline = true
    } catch {
      taskError = "\(localizedReason(reason))：\(error.localizedDescription)"
    }
  }

  private func refreshTaskRuntimeStates() async {
    guard !tasks.isEmpty else { return }
    do {
      let previous = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
      let states = try await taskRuntimeIndex.latestStates(for: tasks.map(\.id))
      let updated = applyingRuntimeStates(states, to: tasks, previous: previous)
      if updated != tasks {
        tasks = updated
        try? await store.save(tasks: tasks)
      }
      settings.setTaskMonitoringError(nil)
      hasTaskRuntimeBaseline = true
    } catch {
      settings.setTaskMonitoringError(error.localizedDescription)
    }
  }

  private func applyingRuntimeStates(
    _ states: [String: CodexTaskRuntimeState],
    to candidates: [CodexTask],
    previous: [String: CodexTask]
  ) -> [CodexTask] {
    candidates.map { task in
      guard let state = states[task.id] else { return task }
      let status = state.taskStatus()
      let updated = task.withStatus(status)
      let priorTurnID = lastObservedTurnIDs[task.id]
      let completedObservedWorkingTurn =
        previous[task.id]?.status == .working && status == .idle
      let completedBetweenPolls = priorTurnID != nil && priorTurnID != state.turnID
      if hasTaskRuntimeBaseline,
        state.status == .completed,
        completedObservedWorkingTurn || completedBetweenPolls
      {
        notifications.notifyTaskCompleted(
          task: updated,
          turnID: state.turnID,
          settings: settings
        )
      }
      lastObservedTurnIDs[task.id] = state.turnID
      return updated
    }
  }

  private func taskSettingsDidChange() {
    notifications.requestAuthorizationIfNeeded(settings: settings)
    startTaskLoop()
    Task {
      if settings.taskMonitoringNeeded { await refreshTasks(reason: "设置变更") }
    }
  }

  private func notificationSettingsDidChange() {
    notifications.synchronizeScheduledReminders(current: quota, settings: settings)
  }

  private func quotaRefreshSettingsDidChange() {
    startQuotaLoop()
    Task { await refreshQuota(reason: "设置变更") }
  }

  private func feedSettingsDidChange() {
    startForecastLoop()
    Task {
      if settings.feedEnabled { await refreshFeed() }
      if settings.forecastMonitoringNeeded { await refreshResetForecast() }
    }
  }

  private func present(_ feedback: AppFeedback) {
    feedbackDismissTask?.cancel()
    transientFeedback = feedback
    feedbackDismissTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(feedback.duration))
      guard let self, !Task.isCancelled, self.transientFeedback?.id == feedback.id else { return }
      self.transientFeedback = nil
    }
  }

  private func configureNetworkMonitor() {
    pathMonitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor in
        guard let self else { return }
        let wasAvailable = self.networkAvailable
        self.networkAvailable = path.status == .satisfied
        if !wasAvailable, self.networkAvailable {
          await self.refreshQuota(reason: "网络恢复")
          if self.settings.feedEnabled { await self.refreshFeed() }
          if self.settings.forecastMonitoringNeeded { await self.refreshResetForecast() }
          if self.settings.taskMonitoringNeeded { await self.refreshTasks(reason: "网络恢复") }
        }
      }
    }
    pathMonitor.start(queue: pathQueue)
  }

  private func redactedPath(_ path: String?) -> String? {
    guard let path else { return nil }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.replacingOccurrences(of: home, with: "~")
  }

  private func sanitized(_ message: String?) -> String? {
    redactedPath(message)?.prefix(500).description
  }

  private func localizedReason(_ reason: String) -> String {
    switch (settings.appLanguage, reason) {
    case (.simplifiedChinese, _): return reason
    case (.traditionalChinese, "启动"): return "啟動"
    case (.traditionalChinese, "手动刷新"): return "手動更新"
    case (.traditionalChinese, "唤醒或显示"): return "喚醒或顯示"
    case (.traditionalChinese, "定时校准"): return "定時校準"
    case (.traditionalChinese, "自动刷新"): return "自動更新"
    case (.traditionalChinese, "定时更新"): return "定時更新"
    case (.traditionalChinese, "额度变化事件"): return "額度變化事件"
    case (.traditionalChinese, "设置变更"): return "設定變更"
    case (.traditionalChinese, "网络恢复"): return "網路恢復"
    case (.english, "启动"): return "Startup"
    case (.english, "手动刷新"): return "Manual refresh"
    case (.english, "唤醒或显示"): return "Wake or show"
    case (.english, "定时校准"): return "Scheduled calibration"
    case (.english, "自动刷新"): return "Automatic refresh"
    case (.english, "定时更新"): return "Scheduled update"
    case (.english, "额度变化事件"): return "Quota update event"
    case (.english, "设置变更"): return "Settings change"
    case (.english, "网络恢复"): return "Network restored"
    default: return reason
    }
  }
}

private struct DiagnosticsReport: Codable {
  let generatedAt: Date
  let appVersion: String
  let osVersion: String
  let codexExecutable: String?
  let quotaFreshness: String?
  let quotaWindowCount: Int
  let resetCreditCount: Int?
  let lastQuotaSuccess: Date?
  let quotaError: String?
  let feedSource: String?
  let cachedPostCount: Int
  let feedFetchedAt: Date?
  let feedError: String?
  let resetForecastUpdatedAt: Date?
  let resetForecastConfidence: String?
  let resetForecastError: String?
  let cachedTaskCount: Int
  let taskError: String?
  let databaseBytes: Int64
}
