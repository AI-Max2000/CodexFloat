import Combine
import Foundation

enum QuotaDisplayMode: String, CaseIterable, Codable, Identifiable, Sendable {
  case standard
  case minimal
  case menuBar

  var id: String { rawValue }
}

@MainActor
final class AppSettings: ObservableObject {
  private enum Key {
    static let appLanguage = "appLanguage"
    static let notificationsEnabled = "notificationsEnabled"
    static let lowThreshold = "lowThreshold"
    static let criticalThreshold = "criticalThreshold"
    static let quotaRefreshInterval = "quotaRefreshInterval"
    static let notifyResetCredits = "notifyResetCredits"
    static let notifyExpiringCredits = "notifyExpiringCredits"
    static let notifyTibo = "notifyTibo"
    static let notifyFiveHoursBeforeReset = "notifyFiveHoursBeforeReset"
    static let feedEnabled = "feedEnabled"
    static let showResetProbability = "showResetProbability"
    static let quotaDisplayMode = "collapsedDisplayStyle"
    static let hoverExpansionEnabled = "hoverExpansionEnabled"
    static let hoverCollapseDelay = "hoverCollapseDelay"
    static let showPanelOnLaunch = "showPanelOnLaunch"
    static let showOnlyWhenChatGPTIsFrontmost = "showOnlyWhenChatGPTIsFrontmost"
    static let showSupplementaryGPTQuotas = "showSupplementaryGPTQuotas"
    static let shortcutEnabled = "globalHotKeyEnabled"
    static let shortcutConfiguration = "globalHotKeyConfiguration"
    static let showRecentTasks = "showRecentTasks"
    static let recentTaskCount = "recentTaskCount"
    static let notifyTaskCompletion = "notifyTaskCompletion"
  }

  private let defaults: UserDefaults

  @Published var appLanguage: AppLanguage {
    didSet {
      defaults.set(appLanguage.rawValue, forKey: Key.appLanguage)
      onLanguageChange?()
    }
  }

  @Published var notificationsEnabled: Bool {
    didSet {
      defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled)
      onNotificationSettingsChange?()
    }
  }
  @Published var lowThreshold: Double {
    didSet { defaults.set(lowThreshold, forKey: Key.lowThreshold) }
  }
  @Published var criticalThreshold: Double {
    didSet { defaults.set(criticalThreshold, forKey: Key.criticalThreshold) }
  }
  @Published var quotaRefreshInterval: Double {
    didSet {
      let allowed = [15.0, 30.0, 60.0, 300.0]
      let normalized = allowed.min(by: { abs($0 - quotaRefreshInterval) < abs($1 - quotaRefreshInterval) })
        ?? 30
      if normalized != quotaRefreshInterval {
        quotaRefreshInterval = normalized
        return
      }
      defaults.set(quotaRefreshInterval, forKey: Key.quotaRefreshInterval)
      onQuotaRefreshSettingsChange?()
    }
  }
  @Published var notifyResetCredits: Bool {
    didSet { defaults.set(notifyResetCredits, forKey: Key.notifyResetCredits) }
  }
  @Published var notifyExpiringCredits: Bool {
    didSet { defaults.set(notifyExpiringCredits, forKey: Key.notifyExpiringCredits) }
  }
  @Published var notifyTibo: Bool { didSet { defaults.set(notifyTibo, forKey: Key.notifyTibo) } }
  @Published var notifyFiveHoursBeforeReset: Bool {
    didSet {
      defaults.set(notifyFiveHoursBeforeReset, forKey: Key.notifyFiveHoursBeforeReset)
      onNotificationSettingsChange?()
    }
  }
  @Published var feedEnabled: Bool {
    didSet {
      defaults.set(feedEnabled, forKey: Key.feedEnabled)
      onFeedSettingsChange?()
    }
  }
  @Published var showResetProbability: Bool {
    didSet {
      defaults.set(showResetProbability, forKey: Key.showResetProbability)
      onFeedSettingsChange?()
    }
  }
  @Published var quotaDisplayMode: QuotaDisplayMode {
    didSet {
      defaults.set(quotaDisplayMode.rawValue, forKey: Key.quotaDisplayMode)
      if quotaDisplayMode == .minimal, !hoverExpansionEnabled {
        hoverExpansionEnabled = true
      }
      onDisplayModeChange?()
    }
  }
  @Published var hoverExpansionEnabled: Bool {
    didSet { defaults.set(hoverExpansionEnabled, forKey: Key.hoverExpansionEnabled) }
  }
  @Published var hoverCollapseDelay: Double {
    didSet { defaults.set(hoverCollapseDelay, forKey: Key.hoverCollapseDelay) }
  }
  @Published var showPanelOnLaunch: Bool {
    didSet { defaults.set(showPanelOnLaunch, forKey: Key.showPanelOnLaunch) }
  }
  @Published var showOnlyWhenChatGPTIsFrontmost: Bool {
    didSet {
      defaults.set(
        showOnlyWhenChatGPTIsFrontmost,
        forKey: Key.showOnlyWhenChatGPTIsFrontmost
      )
      onForegroundVisibilityChange?()
    }
  }
  @Published var showSupplementaryGPTQuotas: Bool {
    didSet { defaults.set(showSupplementaryGPTQuotas, forKey: Key.showSupplementaryGPTQuotas) }
  }
  @Published var globalHotKeyEnabled: Bool {
    didSet {
      defaults.set(globalHotKeyEnabled, forKey: Key.shortcutEnabled)
      onGlobalHotKeyChange?()
    }
  }
  @Published var globalHotKeyConfiguration: HotKeyConfiguration {
    didSet {
      if let data = try? JSONEncoder().encode(globalHotKeyConfiguration) {
        defaults.set(data, forKey: Key.shortcutConfiguration)
      }
      onGlobalHotKeyChange?()
    }
  }
  @Published private(set) var globalHotKeyRegistrationError: String?
  @Published var showRecentTasks: Bool {
    didSet {
      defaults.set(showRecentTasks, forKey: Key.showRecentTasks)
      onTaskSettingsChange?()
    }
  }
  @Published var recentTaskCount: Int {
    didSet {
      let clamped = min(8, max(1, recentTaskCount))
      if clamped != recentTaskCount {
        recentTaskCount = clamped
        return
      }
      defaults.set(recentTaskCount, forKey: Key.recentTaskCount)
      onTaskSettingsChange?()
    }
  }
  @Published var notifyTaskCompletion: Bool {
    didSet {
      defaults.set(notifyTaskCompletion, forKey: Key.notifyTaskCompletion)
      onTaskSettingsChange?()
    }
  }
  @Published private(set) var taskMonitoringError: String?

  var onGlobalHotKeyChange: (() -> Void)?
  var onLanguageChange: (() -> Void)?
  var onDisplayModeChange: (() -> Void)?
  var onForegroundVisibilityChange: (() -> Void)?
  var onNotificationSettingsChange: (() -> Void)?
  var onTaskSettingsChange: (() -> Void)?
  var onQuotaRefreshSettingsChange: (() -> Void)?
  var onFeedSettingsChange: (() -> Void)?

  var taskMonitoringNeeded: Bool { showRecentTasks || notifyTaskCompletion }
  var forecastMonitoringNeeded: Bool { feedEnabled && showResetProbability }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: [
      Key.appLanguage: AppLanguage.simplifiedChinese.rawValue,
      Key.notificationsEnabled: true,
      Key.lowThreshold: 20.0,
      Key.criticalThreshold: 5.0,
      Key.quotaRefreshInterval: 30.0,
      Key.notifyResetCredits: true,
      Key.notifyExpiringCredits: true,
      Key.notifyTibo: true,
      Key.notifyFiveHoursBeforeReset: true,
      Key.feedEnabled: true,
      Key.showResetProbability: true,
      Key.quotaDisplayMode: QuotaDisplayMode.standard.rawValue,
      Key.hoverExpansionEnabled: true,
      Key.hoverCollapseDelay: 0.6,
      Key.showPanelOnLaunch: true,
      Key.showOnlyWhenChatGPTIsFrontmost: true,
      Key.showSupplementaryGPTQuotas: false,
      Key.shortcutEnabled: true,
      Key.showRecentTasks: true,
      Key.recentTaskCount: 3,
      Key.notifyTaskCompletion: true,
    ])
    appLanguage = AppLanguage(rawValue: defaults.string(forKey: Key.appLanguage) ?? "")
      ?? .simplifiedChinese
    notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
    lowThreshold = defaults.double(forKey: Key.lowThreshold)
    criticalThreshold = defaults.double(forKey: Key.criticalThreshold)
    let storedRefreshInterval = defaults.double(forKey: Key.quotaRefreshInterval)
    quotaRefreshInterval = [15.0, 30.0, 60.0, 300.0].min(by: {
      abs($0 - storedRefreshInterval) < abs($1 - storedRefreshInterval)
    }) ?? 30
    notifyResetCredits = defaults.bool(forKey: Key.notifyResetCredits)
    notifyExpiringCredits = defaults.bool(forKey: Key.notifyExpiringCredits)
    notifyTibo = defaults.bool(forKey: Key.notifyTibo)
    notifyFiveHoursBeforeReset = defaults.bool(forKey: Key.notifyFiveHoursBeforeReset)
    feedEnabled = defaults.bool(forKey: Key.feedEnabled)
    showResetProbability = defaults.bool(forKey: Key.showResetProbability)
    quotaDisplayMode =
      QuotaDisplayMode(rawValue: defaults.string(forKey: Key.quotaDisplayMode) ?? "")
      ?? .standard
    hoverExpansionEnabled = defaults.bool(forKey: Key.hoverExpansionEnabled)
    hoverCollapseDelay = defaults.double(forKey: Key.hoverCollapseDelay)
    showPanelOnLaunch = defaults.bool(forKey: Key.showPanelOnLaunch)
    showOnlyWhenChatGPTIsFrontmost = defaults.bool(
      forKey: Key.showOnlyWhenChatGPTIsFrontmost
    )
    showSupplementaryGPTQuotas = defaults.bool(forKey: Key.showSupplementaryGPTQuotas)
    globalHotKeyEnabled = defaults.bool(forKey: Key.shortcutEnabled)
    showRecentTasks = defaults.bool(forKey: Key.showRecentTasks)
    recentTaskCount = min(8, max(1, defaults.integer(forKey: Key.recentTaskCount)))
    notifyTaskCompletion = defaults.bool(forKey: Key.notifyTaskCompletion)
    if let data = defaults.data(forKey: Key.shortcutConfiguration),
      let saved = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data), saved.isValid
    {
      globalHotKeyConfiguration = saved
    } else {
      globalHotKeyConfiguration = .default
    }
    globalHotKeyRegistrationError = nil
    taskMonitoringError = nil
    if quotaDisplayMode == .minimal, !hoverExpansionEnabled {
      hoverExpansionEnabled = true
    }
  }

  func setGlobalHotKeyRegistrationError(_ message: String?) {
    globalHotKeyRegistrationError = message
  }

  func setTaskMonitoringError(_ message: String?) {
    taskMonitoringError = message
  }
}
