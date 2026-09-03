import CodexQuotaCore
import Foundation
import TiboFeedCore

enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
  case simplifiedChinese = "zh-Hans"
  case traditionalChinese = "zh-Hant"
  case english = "en"

  var id: String { rawValue }

  var nativeDisplayName: String {
    switch self {
    case .simplifiedChinese: "简体中文"
    case .traditionalChinese: "繁體中文"
    case .english: "English"
    }
  }

  var locale: Locale { Locale(identifier: rawValue) }
}

enum LocalizedTextKey: String, CaseIterable {
  case quotaExhausted, quotaNeedsVerification, quotaResetPending, quotaSpendBlocked
  case quotaVerifyBeforeReset, quotaResetPendingHelp, quotaSpendBlockedHelp
  case quotaResetAvailable, quotaNoResetAvailable, quotaResetCountUnknown
  case goManualReset, openCodexUsage, manualResetNavigationHelp, manualResetOpenFailed
  case quotaExhaustedAlert, remainingPercentage
  case language, languageDescription, unknown
  case windowSection, displayMode, standardDisplayMode, minimalDisplayMode, menuBarDisplayMode
  case minimalCollapsedHelp, menuBarDisplayHelp, hoverExpand, collapseAfterMouseLeaves, immediately
  case minimalAppearance, minimalStyle, minimalVertical, minimalHorizontal, minimalRing
  case minimalLength, minimalHeight, minimalDiameter, minimalThickness, minimalScale,
    minimalPreview, minimalPoints
  case minimalAppearanceHelp, minimalRingQuotaHelp, minimalLinearQuotaHelp
  case showOnLaunch, frontmostOnly, hoverEnabledHelp, hoverDisabledHelp, menuBarAlwaysVisibleHelp
  case frontmostEnabledHelp, frontmostDisabledHelp
  case followCodexWindow, followCodexWindowHelp
  case shortcutSection, shortcutEnable, shortcut, restoreDefault, shortcutHelp
  case taskSection, showRecentTasks, taskCount, taskCountValue, taskCompletionNotification, taskHelp
  case notificationsSection, enableNotifications, lowQuotaAlert, criticalQuotaAlert
  case newResetCreditAlert, expiringResetCreditAlert, tiboResetAlert, fiveHourAlert
  case quotaDisplaySection, showSupplementaryQuotas, supplementaryQuotaHelp
  case showFiveHourQuota, fiveHourQuotaHelp, fiveHourOnlyHelp, fiveHourQuota, weeklyQuota
  case fiveHourQuotaShort, weeklyQuotaShort, quotaWindowNotReturned, quotaAwaitingRefresh
  case fiveHourQuotaPeriod, weeklyQuotaPeriod
  case autoRefreshInterval, refreshEvery15Seconds, refreshEvery30Seconds
  case refreshEveryMinute, refreshEveryFiveMinutes, autoRefreshHelp
  case tiboSection, tiboPolling, tiboHelp, resetProbabilityToggle, resetProbabilityHelp
  case privacySection, privacyHelp, exportDiagnostics
  case refresh, settings, hide, hideHelp
  case remainingCompact, resetCountCompact, resetCountHeader, resetExpiryCompact
  case readingQuota, quotaUnavailable, quotaRefreshFailed, connectingCodex
  case updatedJustNow, dataOutOfDate, offlineData, notReadYet
  case refreshingPreviousQuota, refreshFailedShowingPrevious, offlineShowingPrevious
  case resetCountdown, remainingQuota, recentTasks, readingTasks, openTask
  case taskIdle, taskWorking, taskError
  case noTiboResetAnnouncement, expectedReset, expectedResetTimeLine
  case effectiveWhenAnnounced, pendingConfirmation
  case resetProbability48Hours, resetProbabilityCalculating, resetProbabilityExpired
  case forecastConfidenceLow, forecastConfidenceMedium, forecastConfidenceHigh
  case forecastConfidenceUnavailable, forecastCadence, forecastLatestMilestone
  case forecastNextMillion, forecastNextMajorMilestone, forecastMillionPromiseActive
  case forecastMillionPromiseEnded, forecastNoMilestone, forecastUpdatedAt
  case forecastDisclaimer
  case globalReset, bankedReset, conditionalReset, limitChange, plannedActivity, incidentOrFix,
    other
  case announced, observed, unverified, expired
  case audienceAllPaid, audiencePlus, audiencePro, audienceBusiness, audienceCodex, audienceUnknown
  case activitySummaryGlobal, activitySummaryBanked, activitySummaryConditional
  case activitySummaryLimit, activitySummaryPlanned, activitySummaryIncident, activitySummaryOther
  case activityHistoryTitle, noResetAnnouncements, unrelatedPostsHidden
  case confidence, audience, actionRequired, noActionOrPending, evidence, viewOriginalPost
  case sourceStatus, timeUnknown, waitingForSource, notUpdated
  case quotaDetailsTitle, dynamicQuotaWindows, windowMinutes, resetsAt
  case extraResetCredits, availableCount, countOnlyNoDetails, resetCreditDefaultTitle
  case status, creditedAt, expiresAt, readOnlyResetHelp, balanceAndLimits, balance
  case spendLimitReached, yes, no, quotaUnavailableTitle, planUnknown, lastSuccessfulUpdate
  case menuRefresh, menuQuotaDetails, menuActivityHistory, menuSettings, menuQuit
  case menuTogglePanel, menuTogglePanelShortcut
  case menuBarQuotaTitle, menuBarQuotaHelp, menuBarQuotaUnavailable
  case startupFailed, globalHotKeyUnavailable
  case notifyQuotaLow, notifyQuotaCritical, notifyResetAddedTitle, notifyResetAddedBody
  case notifyResetExpiryTitle, notifyResetExpiryBody, notifyTiboFiveHourTitle
  case notifyTiboBody, notifyTiboFiveHourBody, notifyTaskCompletedTitle
  case notifyQuotaWithinFiveHours, notifyQuotaInFiveHours, notifyQuotaResetBody
  case timingAlreadyEffective, timingPending
  case feedbackTiboTitle, feedbackTiboFuture, feedbackTiboEffective, feedbackTiboUnknown
  case feedbackTiboCallout, feedbackTiboUnknownCallout
  case feedbackQuotaLowTitle, feedbackQuotaCriticalTitle, feedbackQuotaMessage
  case feedbackQuotaLowCallout, feedbackQuotaCriticalCallout
  case feedbackMenuTiboFuture, feedbackMenuTiboEffective, feedbackMenuTiboUnknown
  case feedbackMenuQuotaLow, feedbackMenuQuotaCritical
  case feedbackPreviewPrefix, previewFeedback, previewTibo, previewLow, previewCritical
  case previewFeedbackHelp
  case pressNewShortcut, shortcutNeedsModifier, shortcutButtonHelp
  case errorSourceUnavailable, errorForecastUnavailable, errorCacheRead
}

struct AppStrings: Sendable {
  let language: AppLanguage

  init(language: AppLanguage) {
    self.language = language
  }

  func text(_ key: LocalizedTextKey) -> String {
    guard let value = Self.table[key] else { return key.rawValue }
    return switch language {
    case .simplifiedChinese: value.hans
    case .traditionalChinese: value.hant
    case .english: value.en
    }
  }

  func format(_ key: LocalizedTextKey, _ arguments: CVarArg...) -> String {
    String(format: text(key), locale: language.locale, arguments: arguments)
  }

  func freshness(_ freshness: DataFreshness) -> String {
    switch freshness {
    case .fresh: text(.updatedJustNow)
    case .stale: text(.dataOutOfDate)
    case .offline: text(.offlineData)
    }
  }

  func taskStatus(_ status: CodexTaskStatus) -> String {
    switch status {
    case .idle: text(.taskIdle)
    case .working: text(.taskWorking)
    case .error: text(.taskError)
    }
  }

  func compactPlanName(_ quota: QuotaSnapshot) -> String {
    switch quota.proTier {
    case .fiveX: "PRO 5X"
    case .twentyX: "PRO 20X"
    case nil: quota.planType?.uppercased() ?? text(.planUnknown)
    }
  }

  func planDisplayName(_ quota: QuotaSnapshot) -> String {
    switch (quota.proTier, language) {
    case (.fiveX, .simplifiedChinese): "Pro 5 倍额度"
    case (.fiveX, .traditionalChinese): "Pro 5 倍額度"
    case (.fiveX, .english): "Pro 5x quota"
    case (.twentyX, .simplifiedChinese): "Pro 20 倍额度"
    case (.twentyX, .traditionalChinese): "Pro 20 倍額度"
    case (.twentyX, .english): "Pro 20x quota"
    case (nil, _): quota.planType?.uppercased() ?? text(.planUnknown)
    }
  }

  func activityType(_ type: ActivityType) -> String {
    switch type {
    case .globalReset: text(.globalReset)
    case .bankedReset: text(.bankedReset)
    case .conditionalReset: text(.conditionalReset)
    case .limitChange: text(.limitChange)
    case .plannedActivity: text(.plannedActivity)
    case .incidentOrFix: text(.incidentOrFix)
    case .other: text(.other)
    }
  }

  func verification(_ state: VerificationState) -> String {
    switch state {
    case .announced: text(.announced)
    case .observed: text(.observed)
    case .unverified: text(.unverified)
    case .expired: text(.expired)
    }
  }

  func activitySummary(_ assessment: ActivityAssessment) -> String {
    switch assessment.type {
    case .globalReset: text(.activitySummaryGlobal)
    case .bankedReset: text(.activitySummaryBanked)
    case .conditionalReset: text(.activitySummaryConditional)
    case .limitChange: text(.activitySummaryLimit)
    case .plannedActivity: text(.activitySummaryPlanned)
    case .incidentOrFix: text(.activitySummaryIncident)
    case .other: text(.activitySummaryOther)
    }
  }

  func audience(_ rawValue: String) -> String {
    switch rawValue {
    case "全部付费用户": text(.audienceAllPaid)
    case "Plus 用户": text(.audiencePlus)
    case "Pro 用户": text(.audiencePro)
    case "Business 用户": text(.audienceBusiness)
    case "Codex 用户": text(.audienceCodex)
    default: text(.audienceUnknown)
    }
  }

  func resetCreditTitle(_ rawValue: String?) -> String {
    guard let rawValue, !rawValue.isEmpty else { return text(.resetCreditDefaultTitle) }
    let normalized = rawValue.lowercased()
    if normalized == "reset" || normalized.contains("rate-limit reset") {
      return text(.resetCreditDefaultTitle)
    }
    return rawValue
  }

  func resetCreditStatus(_ rawValue: String?) -> String {
    guard let rawValue else { return text(.unknown) }
    switch rawValue.lowercased() {
    case "available", "active", "unused":
      return switch language {
      case .simplifiedChinese: "可用"
      case .traditionalChinese: "可用"
      case .english: "Available"
      }
    case "used", "consumed":
      return switch language {
      case .simplifiedChinese: "已使用"
      case .traditionalChinese: "已使用"
      case .english: "Used"
      }
    case "expired": return text(.expired)
    default: return rawValue
    }
  }

  func evidence(_ values: [String]) -> String {
    let mapped = values.map { value in
      if value == "未发现明确触发短语" {
        return switch language {
        case .simplifiedChinese: "未发现明确关键词"
        case .traditionalChinese: "未發現明確關鍵詞"
        case .english: "No clear trigger phrase found"
        }
      }
      return value
    }
    return mapped.joined(separator: ", ")
  }

  func windowDisplayName(_ window: RateLimitWindow) -> String {
    let name = window.limitName?.isEmpty == false ? window.limitName! : window.limitID
    let windowName: String
    switch (window.windowName, language) {
    case ("主窗口", .traditionalChinese): windowName = "主視窗"
    case ("次窗口", .traditionalChinese): windowName = "次視窗"
    case ("主窗口", .english): windowName = "Primary window"
    case ("次窗口", .english): windowName = "Secondary window"
    default: windowName = window.windowName
    }
    return "\(name) · \(windowName)"
  }

  func shortTime(_ date: Date) -> String {
    formatted(date, style: .dateTime.hour().minute())
  }

  func timeWithSeconds(_ date: Date) -> String {
    formatted(date, style: .dateTime.hour().minute().second())
  }

  func shortDateTime(_ date: Date) -> String {
    formatted(date, style: .dateTime.month().day().hour().minute())
  }

  func zonedShortDateTime(_ date: Date) -> String {
    "\(shortDateTime(date)) \(displayTimeZoneLabel)"
  }

  func fullDateTime(_ date: Date, seconds: Bool = false) -> String {
    let value: String
    if seconds {
      value = formatted(date, style: .dateTime.year().month().day().hour().minute().second())
    } else {
      value = formatted(date, style: .dateTime.year().month().day().hour().minute())
    }
    return "\(value) \(displayTimeZoneLabel)"
  }

  func countdown(to date: Date?, now: Date) -> String {
    guard let date else { return text(.timeUnknown) }
    let seconds = max(0, Int(date.timeIntervalSince(now)))
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    let remainder = seconds % 60
    if days > 0 {
      switch language {
      case .simplifiedChinese: return "\(days)天 \(hours)时"
      case .traditionalChinese: return "\(days)天 \(hours)時"
      case .english: return "\(days)d \(hours)h"
      }
    }
    if hours > 0 { return String(format: "%02d:%02d:%02d", hours, minutes, remainder) }
    return String(format: "%02d:%02d", minutes, remainder)
  }

  func menuBarCountdown(to date: Date?, now: Date) -> String {
    guard let date else { return text(.timeUnknown) }
    let seconds = max(0, Int(date.timeIntervalSince(now)))
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    if days > 0 {
      return switch language {
      case .simplifiedChinese: "\(days)天\(hours)时"
      case .traditionalChinese: "\(days)天\(hours)時"
      case .english: "\(days)d \(hours)h"
      }
    }
    if hours > 0 {
      return switch language {
      case .simplifiedChinese: "\(hours)时\(minutes)分"
      case .traditionalChinese: "\(hours)時\(minutes)分"
      case .english: "\(hours)h \(minutes)m"
      }
    }
    return switch language {
    case .simplifiedChinese: "\(minutes)分"
    case .traditionalChinese: "\(minutes)分"
    case .english: "\(minutes)m"
    }
  }

  func menuBarBadgeCountdown(to date: Date?, now: Date) -> String {
    guard let date else { return "--" }
    let seconds = max(0, Int(date.timeIntervalSince(now)))
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    if days > 0 {
      return switch language {
      case .simplifiedChinese, .traditionalChinese: "\(days)天"
      case .english: "\(days)d"
      }
    }
    if hours > 0 {
      return switch language {
      case .simplifiedChinese: "\(hours)时"
      case .traditionalChinese: "\(hours)時"
      case .english: "\(hours)h"
      }
    }
    return switch language {
    case .simplifiedChinese, .traditionalChinese: "\(minutes)分"
    case .english: "\(minutes)m"
    }
  }

  func expectedResetTime(_ assessment: ActivityAssessment) -> String {
    if let effectiveAt = assessment.effectiveAt {
      let value = zonedShortDateTime(effectiveAt)
      if assessment.type == .globalReset { return format(.effectiveWhenAnnounced, value) }
      return value
    }
    return text(.pendingConfirmation)
  }

  func forecastConfidence(_ confidence: ResetForecastConfidence) -> String {
    switch confidence {
    case .low: text(.forecastConfidenceLow)
    case .medium: text(.forecastConfidenceMedium)
    case .high: text(.forecastConfidenceHigh)
    case .unavailable: text(.forecastConfidenceUnavailable)
    }
  }

  func resetForecastSummary(_ forecast: ResetForecastSnapshot, now: Date) -> String {
    guard forecast.availableProbability48Hours(at: now) != nil else {
      return text(.resetProbabilityExpired)
    }
    var parts = [forecastConfidence(forecast.confidence)]
    if let recent = forecast.recentMedianDays {
      parts.append(format(.forecastCadence, decimal(recent)))
    }
    if let milestone = forecast.milestoneProjection {
      parts.append(format(.forecastLatestMilestone, decimal(milestone.latestUsersMillion)))
    }
    return parts.joined(separator: " · ")
  }

  func resetForecastHelp(_ forecast: ResetForecastSnapshot, now: Date) -> String {
    var lines: [String] = []
    if let probability = forecast.availableProbability48Hours(at: now) {
      lines.append(format(.resetProbability48Hours, Int((probability * 100).rounded())))
    } else {
      lines.append(text(.resetProbabilityExpired))
    }
    if let recent = forecast.recentMedianDays {
      lines.append(format(.forecastCadence, decimal(recent)))
    }
    if let milestone = forecast.milestoneProjection {
      lines.append(format(.forecastLatestMilestone, decimal(milestone.latestUsersMillion)))
      if let estimated = milestone.nextMillionEstimatedAt {
        lines.append(
          format(
            .forecastNextMillion,
            decimal(milestone.nextMillionUsers),
            zonedShortDateTime(estimated)
          ))
      }
      if milestone.nextMajorMilestoneUsers != milestone.nextMillionUsers,
        let estimated = milestone.nextMajorMilestoneEstimatedAt
      {
        lines.append(
          format(
            .forecastNextMajorMilestone,
            decimal(milestone.nextMajorMilestoneUsers),
            zonedShortDateTime(estimated)
          ))
      }
      lines.append(
        text(
          milestone.oneMillionResetPromiseStillApplies
            ? .forecastMillionPromiseActive : .forecastMillionPromiseEnded
        ))
    } else {
      lines.append(text(.forecastNoMilestone))
    }
    lines.append(format(.forecastUpdatedAt, zonedShortDateTime(forecast.sourceUpdatedAt)))
    lines.append(text(.forecastDisclaimer))
    return lines.joined(separator: "\n")
  }

  private func decimal(_ value: Double) -> String {
    let rounded = value.rounded()
    if abs(rounded - value) < 0.05 { return String(Int(rounded)) }
    return String(format: "%.1f", locale: language.locale, value)
  }

  private var displayTimeZone: TimeZone {
    switch language {
    case .simplifiedChinese, .traditionalChinese:
      TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3_600)!
    case .english:
      TimeZone(identifier: "America/Los_Angeles") ?? TimeZone(secondsFromGMT: -8 * 3_600)!
    }
  }

  private var displayTimeZoneLabel: String {
    switch language {
    case .simplifiedChinese: "北京时间"
    case .traditionalChinese: "北京時間"
    case .english: "PT"
    }
  }

  private func formatted(_ date: Date, style: Date.FormatStyle) -> String {
    var configured = style.locale(language.locale)
    configured.timeZone = displayTimeZone
    return date.formatted(configured)
  }

  private static let table: [LocalizedTextKey: (hans: String, hant: String, en: String)] = [
    .quotaExhausted: ("额度已耗尽", "額度已耗盡", "Quota exhausted"),
    .quotaNeedsVerification: ("额度需要重新确认", "額度需要重新確認", "Quota needs checking"),
    .quotaResetPending: ("已到刷新时间，等待确认", "已到刷新時間，等待確認", "Reset due · awaiting update"),
    .quotaSpendBlocked: ("已达到支出上限", "已達到支出上限", "Spending limit reached"),
    .quotaVerifyBeforeReset: (
      "当前是旧数据，先刷新，避免误用重置次数。", "目前是舊資料，請先重新整理，避免誤用重置次數。",
      "This is older data. Refresh before deciding to use a reset."
    ),
    .quotaResetPendingHelp: (
      "刷新时间已到，但尚未收到恢复后的额度。请先重新检查。", "刷新時間已到，但尚未收到恢復後的額度。請先重新檢查。",
      "The reset time has passed, but restored quota is not confirmed. Check again first."
    ),
    .quotaSpendBlockedHelp: (
      "额外重置不一定解除支出限制，请到 Codex 用量设置确认。", "額外重置不一定解除支出限制，請到 Codex 用量設定確認。",
      "A reset may not remove a spending limit. Check Codex usage settings."
    ),
    .quotaResetAvailable: (
      "还有 %d 次额外重置，可到设置手动使用。", "還有 %d 次額外重置，可到設定手動使用。",
      "%d extra resets available. Use one manually in settings."
    ),
    .quotaNoResetAvailable: (
      "暂无可用额外重置，请等待额度刷新。", "暫無可用額外重置，請等待額度刷新。",
      "No extra resets available. Wait for quota to refresh."
    ),
    .quotaResetCountUnknown: (
      "重置次数尚未确认，可到 Codex 用量设置查看。", "重置次數尚未確認，可到 Codex 用量設定查看。",
      "Reset availability is unknown. Check Codex usage settings."
    ),
    .goManualReset: ("去手动重置", "前往手動重置", "Go to manual reset"),
    .openCodexUsage: ("查看用量设置", "查看用量設定", "Open usage settings"),
    .manualResetNavigationHelp: (
      "仅打开 Codex「设置 → 用量」，请在使用量上限重置区域确认；不会自动消耗次数。", "僅開啟 Codex「設定 → 用量」，請在使用量上限重置區域確認；不會自動消耗次數。",
      "Opens Codex Settings → Usage. Find Usage limit resets and confirm there. No reset is used automatically."
    ),
    .manualResetOpenFailed: (
      "未能打开 Codex 用量设置。请先安装或启动 Codex，再进入「设置 → 用量 → 使用量上限重置」。",
      "未能開啟 Codex 用量設定。請先安裝或啟動 Codex，再進入「設定 → 用量 → 使用量上限重置」。",
      "Could not open Codex usage settings. Install or start Codex, then go to Settings → Usage → Usage limit resets."
    ),
    .quotaExhaustedAlert: (
      "周额度耗尽且有重置次数时提醒", "週額度耗盡且有重置次數時提醒",
      "Notify when weekly quota runs out and resets are available"
    ),
    .remainingPercentage: ("剩余 %@", "剩餘 %@", "%@ remaining"),
    .language: ("语言", "語言", "Language"),
    .languageDescription: (
      "切换后立即生效，包括浮窗、菜单、设置和之后的通知；中文时间使用北京时间，英文时间使用美国太平洋时间。",
      "切換後立即生效，包括懸浮視窗、選單、設定和之後的通知；中文時間使用北京時間，英文時間使用美國太平洋時間。",
      "Changes apply immediately to the floating window, menus, settings, and future notifications. Chinese uses Beijing Time; English uses U.S. Pacific Time."
    ),
    .unknown: ("未知", "未知", "Unknown"),
    .windowSection: ("浮窗", "懸浮視窗", "Floating window"),
    .displayMode: ("显示形态", "顯示形態", "Display mode"),
    .standardDisplayMode: ("完整额度", "完整額度", "Full quota"),
    .minimalDisplayMode: ("极简进度条", "極簡進度條", "Minimal meter"),
    .menuBarDisplayMode: ("菜单栏额度", "選單列額度", "Menu bar quota"),
    .minimalCollapsedHelp: (
      "极简模式可选择竖条、横条或圆环；彩色部分表示剩余额度，悬停查看详情。", "極簡模式可選擇直條、橫條或圓環；彩色部分表示剩餘額度，懸停查看詳情。",
      "Choose a vertical bar, horizontal bar, or ring. Color shows remaining quota; hover for details."
    ),
    .minimalAppearance: ("极简外观", "極簡外觀", "Minimal appearance"),
    .minimalStyle: ("样式", "樣式", "Style"),
    .minimalVertical: ("竖条", "直條", "Vertical"),
    .minimalHorizontal: ("横条", "橫條", "Horizontal"),
    .minimalRing: ("圆环", "圓環", "Ring"),
    .minimalLength: ("长度", "長度", "Length"),
    .minimalHeight: ("高度", "高度", "Height"),
    .minimalDiameter: ("直径", "直徑", "Diameter"),
    .minimalThickness: ("粗细", "粗細", "Thickness"),
    .minimalScale: ("整体大小", "整體大小", "Scale"),
    .minimalPreview: ("实时预览", "即時預覽", "Live preview"),
    .minimalPoints: ("点", "點", "pt"),
    .minimalAppearanceHelp: (
      "拖动滑块或输入数值，立即生效；各样式分别记忆尺寸。预览过大时会等比缩小，悬浮组件按设置尺寸显示。",
      "拖曳滑桿或輸入數值，立即生效；各樣式分別記住尺寸。預覽過大時會等比縮小，懸浮元件依設定尺寸顯示。",
      "Drag a slider or enter a value. Each style remembers its dimensions. Large previews are scaled to fit; the floating entry uses your chosen size."
    ),
    .minimalRingQuotaHelp: (
      "双额度时：外环为 5 小时，内环为每周；悬停查看各自数值。", "雙額度時：外環為 5 小時，內環為每週；懸停查看各自數值。",
      "With two quotas: outer ring = 5-hour, inner ring = weekly. Hover for each reading."
    ),
    .minimalLinearQuotaHelp: (
      "双额度分别标注周期；颜色和长度各自表示剩余额度。", "雙額度分別標示週期；顏色和長度各自表示剩餘額度。",
      "Paired bars are labeled by period; each color and length represents its own remaining quota."
    ),
    .menuBarDisplayHelp: (
      "显示在 macOS 右侧系统状态栏，由系统自动避开应用菜单；悬停自动展开完整浮窗，移开后收起，右键打开功能菜单。",
      "顯示在 macOS 右側系統狀態列，由系統自動避開應用程式選單；懸停自動展開完整懸浮視窗，移開後收起，右鍵開啟功能選單。",
      "Shown as a native item on the right side of the macOS menu bar, where the system keeps it clear of app menus. Hover to reveal the full window; it closes after you move away. Right-click for the action menu."
    ),
    .hoverExpand: ("鼠标移入时自动展开", "滑鼠移入時自動展開", "Expand when pointer hovers"),
    .collapseAfterMouseLeaves: ("鼠标移出后收起", "滑鼠移出後收起", "Collapse after pointer leaves"),
    .immediately: ("立即", "立即", "Immediately"),
    .showOnLaunch: ("启动时显示浮窗", "啟動時顯示懸浮視窗", "Show floating window at launch"),
    .frontmostOnly: (
      "仅在 ChatGPT 或 Codex 位于前台时显示", "僅在 ChatGPT 或 Codex 位於前景時顯示",
      "Show only while ChatGPT or Codex is in front"
    ),
    .followCodexWindow: ("跟随 Codex 窗口移动", "跟隨 Codex 視窗移動", "Move with the Codex window"),
    .followCodexWindowHelp: (
      "移动 Codex 窗口时暂时隐藏工具，松手并停稳后在固定位置恢复。未手动摆放时跟随 Codex 标题；拖动后改为记忆窗口内的位置，完整额度和极简进度条使用同一锚点。关闭后可独立摆放。",
      "移動 Codex 視窗時暫時隱藏工具，放開滑鼠並停穩後在固定位置恢復。未手動擺放時跟隨 Codex 標題；拖曳後改為記憶視窗內的位置，完整額度和極簡進度條使用同一錨點。關閉後可獨立擺放。",
      "Temporarily hide the tool while Codex moves and restore it after the window settles. Before manual placement it follows the Codex label; after dragging it remembers one window-relative anchor shared by full and minimal modes. Turn this off to position it independently."
    ),
    .hoverEnabledHelp: (
      "平时只显示紧凑额度条；鼠标移入后展开，移出后自动收起。", "平時只顯示精簡額度列；滑鼠移入後展開，移出後自動收起。",
      "Normally shows a compact quota bar. Hover to expand; move away to collapse."
    ),
    .hoverDisabledHelp: (
      "关闭后浮窗保持展开。隐藏后可用全局快捷键或重新打开应用恢复。", "關閉後懸浮視窗會保持展開。隱藏後可用全域快捷鍵或重新開啟應用程式恢復。",
      "When disabled, the window stays expanded. After hiding it, use the global shortcut or reopen the app to restore it."
    ),
    .frontmostEnabledHelp: (
      "切到其他应用时自动隐藏，返回 ChatGPT 或 Codex 时自动恢复。手动隐藏后不会自动恢复。",
      "切到其他應用程式時自動隱藏，返回 ChatGPT 或 Codex 時自動恢復。手動隱藏後不會自動恢復。",
      "Automatically hides in other apps and returns with ChatGPT or Codex. A manual hide remains hidden."
    ),
    .frontmostDisabledHelp: (
      "浮窗会继续显示在其他应用上方。", "懸浮視窗會繼續顯示在其他應用程式上方。", "The floating window stays above other apps."
    ),
    .menuBarAlwaysVisibleHelp: (
      "菜单栏额度始终显示，不受前台应用限制；这个开关只作用于完整额度和极简进度条。", "選單列額度會持續顯示，不受前景應用程式限制；此開關只套用於完整額度和極簡進度列。",
      "Menu bar quota always stays visible, regardless of the frontmost app. This setting only affects Full quota and Minimal meter modes."
    ),
    .shortcutSection: ("全局快捷键", "全域快捷鍵", "Global shortcut"),
    .shortcutEnable: ("启用快速显示与隐藏", "啟用快速顯示與隱藏", "Enable quick show and hide"),
    .shortcut: ("快捷键", "快捷鍵", "Shortcut"),
    .restoreDefault: ("恢复默认", "恢復預設", "Restore default"),
    .shortcutHelp: (
      "点击快捷键框后直接按新组合。至少包含 Control、Option 或 Command；按 Esc 取消。",
      "點擊快捷鍵框後直接按新組合。至少包含 Control、Option 或 Command；按 Esc 取消。",
      "Click the shortcut field and press a new combination. Include Control, Option, or Command; press Esc to cancel."
    ),
    .taskSection: ("Codex 任务", "Codex 任務", "Codex tasks"),
    .showRecentTasks: ("展开时显示最近任务", "展開時顯示最近任務", "Show recent tasks when expanded"),
    .taskCount: ("任务数量", "任務數量", "Number of tasks"),
    .taskCountValue: ("%d 个", "%d 個", "%d"),
    .taskCompletionNotification: ("任务完成时通知", "任務完成時通知", "Notify when a task completes"),
    .taskHelp: (
      "每 2 秒只读检查任务状态：绿色为完成或空闲，黄色为进行中，红色为失败。不读取聊天正文。",
      "每 2 秒以唯讀方式檢查任務狀態：綠色為完成或閒置，黃色為進行中，紅色為失敗。不讀取對話內容。",
      "Checks task state read-only every 2 seconds: green means complete or idle, yellow means working, and red means failed. Chat content is never read."
    ),
    .notificationsSection: ("通知", "通知", "Notifications"),
    .enableNotifications: ("启用系统通知", "啟用系統通知", "Enable system notifications"),
    .lowQuotaAlert: ("额度偏低提醒", "額度偏低提醒", "Low quota alert"),
    .criticalQuotaAlert: ("额度即将用尽提醒", "額度即將用盡提醒", "Critical quota alert"),
    .newResetCreditAlert: ("新增额外重置次数", "新增額外重置次數", "New extra reset"),
    .expiringResetCreditAlert: (
      "额外重置次数将在 48 小时内过期", "額外重置次數將在 48 小時內過期", "Extra reset expires within 48 hours"
    ),
    .tiboResetAlert: ("Tibo 发布新的重置消息", "Tibo 發布新的重置消息", "New reset announcement from Tibo"),
    .fiveHourAlert: ("额度刷新前 5 小时提醒", "額度更新前 5 小時提醒", "Alert 5 hours before quota refresh"),
    .quotaDisplaySection: ("额度显示", "額度顯示", "Quota display"),
    .showFiveHourQuota: (
      "显示 5 小时额度", "顯示 5 小時額度", "Show 5-hour quota"
    ),
    .fiveHourQuotaHelp: (
      "已检测到 5 小时和每周额度。默认只显示每周；开启后，完整额度与菜单栏并列显示双读数，极简形态显示双细条。按账号实际返回的窗口识别，不限制套餐，也不改变通知规则。",
      "已偵測到 5 小時與每週額度。預設只顯示每週；開啟後，完整額度與選單列並排顯示雙讀數，極簡形態顯示雙細條。依帳號實際回傳的視窗識別，不限方案，也不改變通知規則。",
      "5-hour and weekly quotas detected. Weekly is shown by default. Enable paired readings in Full quota and the menu bar, and twin meters in Minimal mode. Availability follows returned windows, not your plan. Notification rules are unchanged."
    ),
    .fiveHourOnlyHelp: (
      "当前账号未返回每周额度，5 小时额度会作为主额度始终显示。不会生成不存在的每周额度；之前的开关选择仍会保留。",
      "目前帳號未回傳每週額度，5 小時額度會作為主要額度持續顯示。不會產生不存在的每週額度；先前的開關選擇仍會保留。",
      "No weekly window was returned, so the 5-hour quota stays visible as the main reading. No weekly quota is invented. Your saved preference is retained."
    ),
    .fiveHourQuota: ("5 小时额度", "5 小時額度", "5-hour quota"),
    .weeklyQuota: ("每周额度", "每週額度", "Weekly quota"),
    .fiveHourQuotaShort: ("5时", "5時", "5h"),
    .fiveHourQuotaPeriod: ("5 小时", "5 小時", "5-hour"),
    .weeklyQuotaPeriod: ("每周", "每週", "Weekly"),
    .weeklyQuotaShort: ("周", "週", "Wk"),
    .quotaWindowNotReturned: ("暂未返回此额度", "暫未回傳此額度", "Quota not returned yet"),
    .quotaAwaitingRefresh: ("待更新", "待更新", "Due"),
    .autoRefreshInterval: ("额度自动刷新", "額度自動更新", "Automatic quota refresh"),
    .refreshEvery15Seconds: ("每 15 秒", "每 15 秒", "Every 15 seconds"),
    .refreshEvery30Seconds: ("每 30 秒", "每 30 秒", "Every 30 seconds"),
    .refreshEveryMinute: ("每 1 分钟", "每 1 分鐘", "Every minute"),
    .refreshEveryFiveMinutes: ("每 5 分钟", "每 5 分鐘", "Every 5 minutes"),
    .autoRefreshHelp: (
      "Codex 额度变化时立即刷新；没有事件时按所选间隔校准。失败后每 10 秒自动重试。", "Codex 額度變化時立即更新；沒有事件時按所選間隔校準。失敗後每 10 秒自動重試。",
      "Refreshes immediately when Codex reports a quota change and checks at the selected interval otherwise. Retries every 10 seconds after a failure."
    ),
    .showSupplementaryQuotas: (
      "显示 GPT-5.3 和 GPT 备用额度", "顯示 GPT-5.3 和 GPT 備用額度", "Show GPT-5.3 and GPT reserve quotas"
    ),
    .supplementaryQuotaHelp: (
      "默认只显示标准 Codex 额度。开启后额外显示 GPT-5.3-Codex-Spark 的主、次窗口以及 GPT 备用额度。",
      "預設只顯示標準 Codex 額度。開啟後另外顯示 GPT-5.3-Codex-Spark 的主、次視窗與 GPT 備用額度。",
      "By default, only standard Codex quotas are shown. Enable this to also show GPT-5.3-Codex-Spark primary and secondary windows and GPT reserve quota."
    ),
    .tiboSection: ("Tibo 重置消息", "Tibo 重置消息", "Tibo reset updates"),
    .tiboPolling: (
      "每 5 分钟检查，失败后自动降低频率", "每 5 分鐘檢查，失敗後自動降低頻率",
      "Check every 5 minutes and back off after failures"
    ),
    .tiboHelp: (
      "只显示与额度重置直接相关的公告和预计时间。", "只顯示與額度重置直接相關的公告與預計時間。",
      "Shows only announcements directly related to quota resets and their expected time."
    ),
    .resetProbabilityToggle: ("显示未来 48 小时重置概率", "顯示未來 48 小時重置機率", "Show 48-hour reset probability"),
    .resetProbabilityHelp: (
      "每 5 分钟自动获取最新预测，并结合近期重置节奏、Tibo 明确信号、数据新鲜度和用户里程碑。用户增长只作证据：“每增加 100 万就重置”的公开承诺已在 1000 万时结束。",
      "每 5 分鐘自動取得最新預測，並結合近期重置節奏、Tibo 明確訊號、資料新鮮度與用戶里程碑。用戶成長只作證據：「每增加 100 萬就重置」的公開承諾已在 1000 萬時結束。",
      "Fetches the latest forecast every 5 minutes and combines recent reset cadence, explicit Tibo signals, source freshness, and user milestones. Growth is evidence only: the public every-1M promise ended at 10M users."
    ),
    .privacySection: ("隐私与诊断", "隱私與診斷", "Privacy and diagnostics"),
    .privacyHelp: (
      "只读取本机 Codex 的额度和任务状态；不读取登录凭据、聊天正文、浏览器登录信息或 Codex 运行记录。",
      "只讀取本機 Codex 的額度和任務狀態；不讀取登入憑證、對話內容、瀏覽器登入資訊或 Codex 執行記錄。",
      "Reads only local Codex quota and task status. It never reads credentials, chat content, browser sessions, or Codex rollout logs."
    ),
    .exportDiagnostics: ("导出脱敏诊断…", "匯出去識別化診斷…", "Export redacted diagnostics…"),
    .refresh: ("刷新", "更新", "Refresh"),
    .settings: ("设置", "設定", "Settings"),
    .hide: ("隐藏", "隱藏", "Hide"),
    .hideHelp: (
      "隐藏浮窗；可用全局快捷键或重新打开应用恢复", "隱藏懸浮視窗；可用全域快捷鍵或重新開啟應用程式恢復",
      "Hide the window; use the global shortcut or reopen the app to restore it"
    ),
    .remainingCompact: ("余%d%%", "餘%d%%", "%d%% left"),
    .resetCountCompact: ("%d次重置", "%d次重置", "%d reset"),
    .resetCountHeader: ("%d 次额外重置", "%d 次額外重置", "%d extra reset"),
    .resetExpiryCompact: ("最早到期：%@", "最早到期：%@", "Expires in %@"),
    .readingQuota: ("正在读取额度…", "正在讀取額度…", "Reading quota…"),
    .quotaUnavailable: ("额度暂不可用", "額度暫時無法使用", "Quota unavailable"),
    .quotaRefreshFailed: ("额度刷新失败：%@", "額度更新失敗：%@", "Quota refresh failed: %@"),
    .connectingCodex: ("正在连接本机 Codex…", "正在連線本機 Codex…", "Connecting to local Codex…"),
    .updatedJustNow: ("刚刚更新", "剛剛更新", "Updated just now"),
    .dataOutOfDate: ("上次数据", "上次資料", "Previous data"),
    .offlineData: ("离线数据", "離線資料", "Offline data"),
    .notReadYet: ("尚未读取", "尚未讀取", "Not read yet"),
    .refreshingPreviousQuota: ("正在刷新上次数据…", "正在更新上次資料…", "Refreshing previous data…"),
    .refreshFailedShowingPrevious: (
      "刷新失败 · 显示 %@ 数据", "更新失敗 · 顯示 %@ 資料", "Refresh failed · showing %@ data"
    ),
    .offlineShowingPrevious: ("离线 · 显示 %@ 数据", "離線 · 顯示 %@ 資料", "Offline · showing %@ data"),
    .resetCountdown: ("距离刷新 %@ · %@", "距離更新 %@ · %@", "Refresh in %@ · %@"),
    .remainingQuota: ("剩余 %d%%", "剩餘 %d%%", "%d%% left"),
    .recentTasks: ("最近任务", "最近任務", "Recent tasks"),
    .readingTasks: ("正在读取 Codex 任务…", "正在讀取 Codex 任務…", "Reading Codex tasks…"),
    .openTask: ("在 Codex 中打开“%@”", "在 Codex 中開啟「%@」", "Open \"%@\" in Codex"),
    .taskIdle: ("已完成", "已完成", "Complete"),
    .taskWorking: ("进行中", "進行中", "Working"),
    .taskError: ("失败", "失敗", "Failed"),
    .noTiboResetAnnouncement: (
      "暂无新的 Tibo 重置公告", "暫無新的 Tibo 重置公告", "No new reset announcement from Tibo"
    ),
    .expectedReset: ("预计重置：%@ · %@", "預計重置：%@ · %@", "Expected reset: %@ · %@"),
    .expectedResetTimeLine: ("预计重置：%@", "預計重置：%@", "Expected reset: %@"),
    .effectiveWhenAnnounced: (
      "公告时已生效（约 %@）", "公告時已生效（約 %@）", "Effective when announced (about %@)"
    ),
    .pendingConfirmation: ("待确认", "待確認", "To be confirmed"),
    .resetProbability48Hours: (
      "未来 48 小时重置概率 %d%%", "未來 48 小時重置機率 %d%%", "%d%% reset probability in the next 48 hours"
    ),
    .resetProbabilityCalculating: ("正在计算重置概率…", "正在計算重置機率…", "Calculating reset probability…"),
    .resetProbabilityExpired: (
      "预测数据已过期，等待刷新", "預測資料已過期，等待更新", "Forecast expired; waiting for refresh"
    ),
    .forecastConfidenceLow: ("低置信度", "低信心", "Low confidence"),
    .forecastConfidenceMedium: ("中等置信度", "中等信心", "Medium confidence"),
    .forecastConfidenceHigh: ("高置信度", "高信心", "High confidence"),
    .forecastConfidenceUnavailable: ("置信度不可用", "信心不可用", "Confidence unavailable"),
    .forecastCadence: ("近期约 %@ 天一次", "近期約 %@ 天一次", "About every %@ days recently"),
    .forecastLatestMilestone: ("最近 %@M 用户里程碑", "最近 %@M 用戶里程碑", "Latest %@M-user milestone"),
    .forecastNextMillion: (
      "按近期增长速度，%@M 约在 %@（仅作增长参考）", "按近期成長速度，%@M 約在 %@（僅作成長參考）",
      "At recent growth speed, %@M is estimated around %@ (growth context only)"
    ),
    .forecastNextMajorMilestone: (
      "下一个重要里程碑 %@M 约在 %@", "下一個重要里程碑 %@M 約在 %@", "Next major %@M milestone is estimated around %@"
    ),
    .forecastMillionPromiseActive: (
      "历史“每增加 100 万重置”承诺仍在 1000 万范围内。", "歷史「每增加 100 萬重置」承諾仍在 1000 萬範圍內。",
      "The historical every-1M reset promise is still within its up-to-10M scope."
    ),
    .forecastMillionPromiseEnded: (
      "每增加 100 万就重置的承诺已在 1000 万结束；之后的增长只作参考，不单独加概率。",
      "每增加 100 萬就重置的承諾已在 1000 萬結束；之後的成長只作參考，不單獨增加機率。",
      "The every-1M promise ended at 10M; later growth is context and does not add probability by itself."
    ),
    .forecastNoMilestone: (
      "暂无可验证的用户里程碑数据。", "暫無可驗證的用戶里程碑資料。", "No verifiable user-milestone data is available."
    ),
    .forecastUpdatedAt: ("预测数据更新于 %@", "預測資料更新於 %@", "Forecast data updated %@"),
    .forecastDisclaimer: (
      "这是非官方实验性预测，不是 OpenAI 承诺；工作计划仍应以当前可用额度为准。", "這是非官方實驗性預測，不是 OpenAI 承諾；工作計畫仍應以目前可用額度為準。",
      "This is an unofficial experimental forecast, not an OpenAI promise. Plan work around the quota currently available."
    ),
    .globalReset: ("统一重置", "統一重置", "Global reset"),
    .bankedReset: ("额外重置次数", "額外重置次數", "Extra reset"),
    .conditionalReset: ("条件奖励", "條件獎勵", "Conditional reward"),
    .limitChange: ("额度变化", "額度變化", "Limit change"),
    .plannedActivity: ("活动预告", "活動預告", "Planned activity"),
    .incidentOrFix: ("异常或修复", "異常或修復", "Incident or fix"),
    .other: ("其他", "其他", "Other"),
    .announced: ("已公告", "已公告", "Announced"),
    .observed: ("账号已观察到变化", "帳號已觀察到變化", "Observed on your account"),
    .unverified: ("已公告，本机尚未验证", "已公告，本機尚未驗證", "Announced, not yet verified locally"),
    .expired: ("已过期", "已過期", "Expired"),
    .audienceAllPaid: ("全部付费用户", "全部付費用戶", "All paid users"),
    .audiencePlus: ("Plus 用户", "Plus 用戶", "Plus users"),
    .audiencePro: ("Pro 用户", "Pro 用戶", "Pro users"),
    .audienceBusiness: ("Business 用户", "Business 用戶", "Business users"),
    .audienceCodex: ("Codex 用户", "Codex 用戶", "Codex users"),
    .audienceUnknown: ("受众待确认", "對象待確認", "Audience to be confirmed"),
    .activitySummaryGlobal: (
      "Tibo 宣布相关用户的额度已统一重置，仍需核对本机账号变化。", "Tibo 宣布相關用戶的額度已統一重置，仍需核對本機帳號變化。",
      "Tibo announced a global quota reset for the relevant users; local account changes still need verification."
    ),
    .activitySummaryBanked: (
      "Tibo 宣布发放可自行使用的额外重置次数，是否到账以本机账号变化为准。", "Tibo 宣布發放可自行使用的額外重置次數，是否到帳以本機帳號變化為準。",
      "Tibo announced an extra reset you can use manually; local account changes determine whether it arrived."
    ),
    .activitySummaryConditional: (
      "这是需要满足条件的重置奖励，不代表当前账号可直接重置。", "這是需要滿足條件的重置獎勵，不代表目前帳號可直接重置。",
      "This reset reward requires conditions and does not mean your account can reset immediately."
    ),
    .activitySummaryLimit: (
      "Tibo 提到了额度窗口、套餐或消耗规则变化，以账号实际额度为准。", "Tibo 提到了額度視窗、方案或用量規則變化，以帳號實際額度為準。",
      "Tibo mentioned changes to quota windows, plans, or usage rules; your account quota is the source of truth."
    ),
    .activitySummaryPlanned: (
      "Tibo 预告了重置或活动，目前尚未确认在你的账号生效。", "Tibo 預告了重置或活動，目前尚未確認在你的帳號生效。",
      "Tibo previewed a reset or event that has not yet been confirmed on your account."
    ),
    .activitySummaryIncident: (
      "Tibo 提到额度异常、修复或服务状态；这不是可用重置次数的确认。", "Tibo 提到額度異常、修復或服務狀態；這不是可用重置次數的確認。",
      "Tibo mentioned a quota issue, fix, or service status; this is not confirmation of an available reset."
    ),
    .activitySummaryOther: (
      "这条帖子没有明确、可操作的额度重置信息。", "這則貼文沒有明確、可操作的額度重置資訊。",
      "This post has no clear, actionable quota reset information."
    ),
    .activityHistoryTitle: ("Tibo 重置记录", "Tibo 重置記錄", "Tibo reset history"),
    .noResetAnnouncements: ("暂无重置公告", "暫無重置公告", "No reset announcements"),
    .unrelatedPostsHidden: (
      "与额度重置无关的 Tibo 帖子不会显示在这里", "與額度重置無關的 Tibo 貼文不會顯示在這裡",
      "Tibo posts unrelated to quota resets are hidden here"
    ),
    .confidence: ("可信度 %d%%", "可信度 %d%%", "Confidence %d%%"),
    .audience: ("对象：%@", "對象：%@", "Audience: %@"),
    .actionRequired: ("需要操作", "需要操作", "Action required"),
    .noActionOrPending: ("无需操作或待确认", "無需操作或待確認", "No action or pending confirmation"),
    .evidence: ("判断依据：%@", "判斷依據：%@", "Evidence: %@"),
    .viewOriginalPost: ("查看原帖", "查看原文", "View original post"),
    .sourceStatus: (
      "来源：%@ · 更新：%@ · 只显示重置公告", "來源：%@ · 更新：%@ · 只顯示重置公告",
      "Source: %@ · Updated: %@ · Reset announcements only"
    ),
    .timeUnknown: ("时间未知", "時間未知", "Time unknown"),
    .waitingForSource: ("等待数据来源", "等待資料來源", "Waiting for source"),
    .notUpdated: ("尚未更新", "尚未更新", "Not updated"),
    .quotaDetailsTitle: ("Codex 额度详情", "Codex 額度詳情", "Codex quota details"),
    .dynamicQuotaWindows: ("额度窗口", "額度視窗", "Quota windows"),
    .windowMinutes: ("窗口 %d 分钟", "視窗 %d 分鐘", "%d-minute window"),
    .resetsAt: ("刷新：%@", "更新：%@", "Refreshes: %@"),
    .extraResetCredits: ("额外重置次数", "額外重置次數", "Extra resets"),
    .availableCount: ("可用数量", "可用數量", "Available"),
    .countOnlyNoDetails: (
      "服务只返回了数量，没有可展示的详情。", "服務只回傳了數量，沒有可顯示的詳情。",
      "The service returned a count but no displayable details."
    ),
    .resetCreditDefaultTitle: ("额外重置次数", "額外重置次數", "Extra reset"),
    .status: ("状态：%@", "狀態：%@", "Status: %@"),
    .creditedAt: ("到账：%@", "到帳：%@", "Credited: %@"),
    .expiresAt: ("过期：%@", "過期：%@", "Expires: %@"),
    .readOnlyResetHelp: (
      "只读模式：Codex Float 不会自动使用额外重置次数。", "唯讀模式：Codex Float 不會自動使用額外重置次數。",
      "Read-only mode: Codex Float never uses an extra reset automatically."
    ),
    .balanceAndLimits: ("余额与限制", "餘額與限制", "Balance and limits"),
    .balance: ("余额", "餘額", "Balance"),
    .spendLimitReached: ("已触发消费限制", "已觸發消費限制", "Spend limit reached"),
    .yes: ("是", "是", "Yes"),
    .no: ("否", "否", "No"),
    .quotaUnavailableTitle: ("额度暂不可用", "額度暫時無法使用", "Quota unavailable"),
    .planUnknown: ("套餐未知", "方案未知", "Plan unknown"),
    .lastSuccessfulUpdate: (
      "%@ · %@ · 最后成功更新 %@", "%@ · %@ · 最後成功更新 %@", "%@ · %@ · Last successful update %@"
    ),
    .menuRefresh: ("立即刷新", "立即更新", "Refresh now"),
    .menuQuotaDetails: ("额度详情…", "額度詳情…", "Quota details…"),
    .menuActivityHistory: ("Tibo 重置记录…", "Tibo 重置記錄…", "Tibo reset history…"),
    .menuSettings: ("设置…", "設定…", "Settings…"),
    .menuQuit: ("退出 Codex Float", "結束 Codex Float", "Quit Codex Float"),
    .menuTogglePanel: ("显示或隐藏浮窗", "顯示或隱藏懸浮視窗", "Show or hide floating window"),
    .menuTogglePanelShortcut: ("显示或隐藏浮窗（%@）", "顯示或隱藏懸浮視窗（%@）", "Show or hide floating window (%@)"),
    .menuBarQuotaTitle: ("%d%%·%@", "%d%%·%@", "%d%%·%@"),
    .menuBarQuotaHelp: (
      "Codex 剩余 %d%%，%@ 刷新。悬停查看完整内容。", "Codex 剩餘 %d%%，%@ 更新。懸停查看完整內容。",
      "Codex has %d%% remaining and refreshes %@. Hover for full details."
    ),
    .menuBarQuotaUnavailable: ("--·暂不可用", "--·暫時無法使用", "--·Unavailable"),
    .startupFailed: ("Codex Float 无法启动", "Codex Float 無法啟動", "Codex Float could not start"),
    .globalHotKeyUnavailable: ("无法使用该快捷键：%@", "無法使用該快捷鍵：%@", "Could not use this shortcut: %@"),
    .notifyQuotaLow: ("额度偏低", "額度偏低", "Quota is low"),
    .notifyQuotaCritical: ("额度即将用尽", "額度將要用盡", "Quota is almost used up"),
    .notifyResetAddedTitle: ("Codex 新增额外重置次数", "Codex 新增額外重置次數", "New Codex extra reset"),
    .notifyResetAddedBody: (
      "已在你的账号观察到额外重置次数从 %d 增加到 %d。", "已在你的帳號觀察到額外重置次數從 %d 增加到 %d。",
      "Extra resets on your account increased from %d to %d."
    ),
    .notifyResetExpiryTitle: ("额外重置次数即将过期", "額外重置次數即將過期", "Extra reset expires soon"),
    .notifyResetExpiryBody: (
      "%@ 将在 48 小时内过期。助手不会自动使用它。", "%@ 將在 48 小時內過期。助手不會自動使用它。",
      "%@ expires within 48 hours. The assistant will not use it automatically."
    ),
    .notifyTiboFiveHourTitle: (
      "Tibo 活动将在 5 小时后生效", "Tibo 活動將在 5 小時後生效", "Tibo event starts in 5 hours"
    ),
    .notifyTiboBody: ("对象：%@ · 时间：%@。%@", "對象：%@ · 時間：%@。%@", "Audience: %@ · Time: %@. %@"),
    .notifyTiboFiveHourBody: (
      "对象：%@ · %@ · 预计 %@", "對象：%@ · %@ · 預計 %@", "Audience: %@ · %@ · Expected %@"
    ),
    .notifyTaskCompletedTitle: ("Codex 任务已完成", "Codex 任務已完成", "Codex task completed"),
    .notifyQuotaWithinFiveHours: (
      "Codex 额度将在 5 小时内刷新", "Codex 額度將在 5 小時內更新", "Codex quota refreshes within 5 hours"
    ),
    .notifyQuotaInFiveHours: (
      "Codex 额度将在 5 小时后刷新", "Codex 額度將在 5 小時後更新", "Codex quota refreshes in 5 hours"
    ),
    .notifyQuotaResetBody: (
      "%@ 将在 %@ 刷新，当前剩余 %@。", "%@ 將在 %@ 更新，目前剩餘 %@。",
      "%@ refreshes at %@ and currently has %@ remaining."
    ),
    .timingAlreadyEffective: (
      "原帖称已经生效，公告时间为 %@", "原文表示已經生效，公告時間為 %@",
      "The original post says it was already effective; announced at %@"
    ),
    .timingPending: ("具体时间待确认", "具體時間待確認", "Exact time to be confirmed"),
    .feedbackTiboTitle: ("Tibo 发布了重置消息", "Tibo 發布了重置消息", "Tibo announced a quota reset"),
    .feedbackTiboFuture: (
      "适用对象：%@。预计 %@ 可以重置额度。", "適用對象：%@。預計 %@ 可以重置額度。", "For %@. Quota is expected to reset at %@."
    ),
    .feedbackTiboEffective: (
      "适用对象：%@。Tibo 称重置已于 %@ 生效，正在等待本机额度验证。", "適用對象：%@。Tibo 表示重置已於 %@ 生效，正在等待本機額度驗證。",
      "For %@. Tibo says the reset took effect at %@; waiting for local quota verification."
    ),
    .feedbackTiboUnknown: (
      "适用对象：%@。Tibo 已预告重置，但暂未给出明确时间。", "適用對象：%@。Tibo 已預告重置，但暫未提供明確時間。",
      "For %@. Tibo previewed a reset but has not provided an exact time."
    ),
    .feedbackTiboCallout: ("请尽情吩咐 Codex 吧～", "請盡情吩咐 Codex 吧～", "Feel free to put Codex to work!"),
    .feedbackTiboUnknownCallout: (
      "时间确认后会再次提醒你。", "時間確認後會再次提醒你。", "You will be alerted again when the time is confirmed."
    ),
    .feedbackQuotaLowTitle: ("Codex 额度偏低", "Codex 額度偏低", "Codex quota is low"),
    .feedbackQuotaCriticalTitle: ("Codex 额度即将用尽", "Codex 額度即將用盡", "Codex quota is almost used up"),
    .feedbackQuotaMessage: (
      "当前剩余 %@，预计 %@ 刷新。", "目前剩餘 %@，預計 %@ 更新。", "%@ remains and is expected to refresh at %@."
    ),
    .feedbackQuotaLowCallout: (
      "建议先安排重要任务。", "建議先安排重要任務。", "Consider prioritizing important tasks."
    ),
    .feedbackQuotaCriticalCallout: (
      "请优先完成正在进行的任务。", "請優先完成正在進行的任務。", "Prioritize tasks already in progress."
    ),
    .feedbackMenuTiboFuture: ("预计重置 · %@", "預計重置 · %@", "Reset expected · %@"),
    .feedbackMenuTiboEffective: ("Tibo 已发布重置", "Tibo 已發布重置", "Tibo reset announced"),
    .feedbackMenuTiboUnknown: ("重置时间待确认", "重置時間待確認", "Reset time pending"),
    .feedbackMenuQuotaLow: ("Codex 偏低 · %@", "Codex 偏低 · %@", "Codex low · %@"),
    .feedbackMenuQuotaCritical: ("Codex 即将用尽 · %@", "Codex 即將用盡 · %@", "Codex critical · %@"),
    .feedbackPreviewPrefix: ("预览", "預覽", "Preview"),
    .previewFeedback: ("预览反馈动效", "預覽回饋動效", "Preview feedback"),
    .previewTibo: ("重置消息", "重置消息", "Reset"),
    .previewLow: ("额度偏低", "額度偏低", "Low"),
    .previewCritical: ("即将用尽", "即將用盡", "Critical"),
    .previewFeedbackHelp: (
      "切换显示形态后，可在这里直接检查对应的颜色、动效和提示文案。", "切換顯示形態後，可在這裡直接檢查對應的顏色、動效與提示文字。",
      "Switch display modes, then use these buttons to check each color, animation, and message."
    ),
    .pressNewShortcut: ("请按新快捷键…", "請按新快捷鍵…", "Press a new shortcut…"),
    .shortcutNeedsModifier: ("需要包含 ⌃、⌥ 或 ⌘", "需要包含 ⌃、⌥ 或 ⌘", "Include ⌃, ⌥, or ⌘"),
    .shortcutButtonHelp: ("点击后按新的全局快捷键", "點擊後按新的全域快捷鍵", "Click and press a new global shortcut"),
    .errorSourceUnavailable: ("数据来源暂不可用：%@", "資料來源暫時無法使用：%@", "Feed source unavailable: %@"),
    .errorForecastUnavailable: (
      "重置概率来源暂不可用：%@", "重置機率來源暫時無法使用：%@", "Reset forecast source unavailable: %@"
    ),
    .errorCacheRead: ("缓存读取失败：%@", "快取讀取失敗：%@", "Could not read cache: %@"),
  ]
}
