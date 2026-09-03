import CodexQuotaCore
import Foundation

struct QuotaDisplayEntry: Identifiable, Equatable {
  enum Kind: Equatable { case fiveHour, weekly, other }

  let kind: Kind
  let window: RateLimitWindow?

  var id: String {
    switch kind {
    case .fiveHour: "quota:five-hour"
    case .weekly: "quota:weekly"
    case .other: window?.id ?? "unavailable"
    }
  }

  var percentage: String {
    window.map { QuotaPercentage.text($0.remainingPercent) } ?? "--"
  }

  func title(_ strings: AppStrings) -> String {
    switch kind {
    case .fiveHour: strings.text(.fiveHourQuota)
    case .weekly: strings.text(.weeklyQuota)
    case .other: window.map(strings.windowDisplayName) ?? "Codex"
    }
  }

  func shortLabel(_ strings: AppStrings) -> String {
    switch kind {
    case .fiveHour: strings.text(.fiveHourQuotaShort)
    case .weekly: strings.text(.weeklyQuotaShort)
    case .other: "Codex"
    }
  }

  func compactCountdown(_ strings: AppStrings, now: Date) -> String {
    guard let date = window?.resetsAt else { return "--" }
    guard date > now else { return strings.text(.quotaAwaitingRefresh) }
    return strings.menuBarCountdown(to: date, now: now).replacingOccurrences(of: " ", with: "")
  }

  func periodLabel(_ strings: AppStrings) -> String {
    switch kind {
    case .fiveHour: strings.text(.fiveHourQuotaPeriod)
    case .weekly: strings.text(.weeklyQuotaPeriod)
    case .other: "Codex"
    }
  }

  func help(_ strings: AppStrings, now: Date) -> String {
    guard let window else { return "\(title(strings)) · \(strings.text(.quotaWindowNotReturned))" }
    return
      "\(title(strings)) · \(strings.format(.remainingPercentage, QuotaPercentage.text(window.remainingPercent))) · \(strings.countdown(to: window.resetsAt, now: now))"
  }
}

/// A display preference only: raw snapshots, quota notifications and detailed
/// diagnostics keep all server windows. Never infer a period from primary/secondary.
struct QuotaDisplayPolicy {
  let isDual: Bool
  let hasFiveHourWindow: Bool
  let isFiveHourAlwaysVisible: Bool
  let compact: [QuotaDisplayEntry]
  let expanded: [QuotaDisplayEntry]

  init(snapshot: QuotaSnapshot?, showFiveHour: Bool, includingSupplementaryGPT: Bool = false) {
    guard let snapshot else {
      isDual = false
      hasFiveHourWindow = false
      isFiveHourAlwaysVisible = false
      compact = [QuotaDisplayEntry(kind: .other, window: nil)]
      expanded = []
      return
    }
    let visible = snapshot.visibleWindows(includingSupplementaryGPT: includingSupplementaryGPT)
    // Capability comes from returned standard Codex windows, not the plan name
    // or a supplementary model bucket with a coincidentally matching duration.
    let codex = visible.filter { $0.limitID.lowercased() == "codex" }
    let fiveHour = codex.first { $0.windowDurationMinutes == 300 }
    let weekly = codex.first { $0.windowDurationMinutes == 10_080 }
    hasFiveHourWindow = fiveHour != nil
    isFiveHourAlwaysVisible = fiveHour != nil && weekly == nil
    var periods: [QuotaDisplayEntry] = []
    if let fiveHour, showFiveHour || isFiveHourAlwaysVisible {
      periods.append(QuotaDisplayEntry(kind: .fiveHour, window: fiveHour))
    }
    if let weekly { periods.append(QuotaDisplayEntry(kind: .weekly, window: weekly)) }
    isDual = periods.count == 2

    let preferred = visible.first { $0.id == snapshot.preferredCodexWindow?.id } ?? visible.first
    compact = periods.isEmpty ? [QuotaDisplayEntry(kind: .other, window: preferred)] : periods
    let handledIDs = Set([fiveHour?.id, weekly?.id].compactMap { $0 })
    // Never manufacture a weekly/5-hour row. Unknown future windows stay intact,
    // and a missing weekly window cannot make the only 5-hour reading disappear.
    expanded =
      periods
      + visible.filter { !handledIDs.contains($0.id) }.map {
        QuotaDisplayEntry(kind: .other, window: $0)
      }
  }
}
