import CodexQuotaCore
import SwiftUI

struct QuotaDetailsView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var settings: AppSettings

  private var strings: AppStrings { AppStrings(language: settings.appLanguage) }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(strings.text(.quotaDetailsTitle)).font(.title2.weight(.semibold))
          Text(statusLine)
            .font(.caption)
            .foregroundStyle(statusColor)
        }
        Spacer()
        Button {
          model.refreshAll()
        } label: {
          Label(strings.text(.refresh), systemImage: "arrow.clockwise")
        }
        .disabled(model.isRefreshingQuota)
      }
      .padding(16)

      Divider()

      if let quota = model.quota {
        List {
          Section(strings.text(.dynamicQuotaWindows)) {
            ForEach(
              quota.visibleWindows(includingSupplementaryGPT: settings.showSupplementaryGPTQuotas)
            ) { window in
              VStack(alignment: .leading, spacing: 5) {
                HStack {
                  Text(strings.windowDisplayName(window)).font(.body.weight(.semibold))
                  Spacer()
                  if let reached = window.reachedType {
                    Text(reached).font(.caption).foregroundStyle(.red)
                  }
                }
                QuotaMeterView(
                  remainingPercent: window.remainingPercent,
                  lowThreshold: settings.lowThreshold,
                  criticalThreshold: settings.criticalThreshold,
                  width: 320,
                  language: settings.appLanguage,
                  accessibilityName: strings.windowDisplayName(window)
                )
                HStack {
                  Text(
                    strings.format(
                      .remainingPercentage,
                      QuotaPercentage.text(window.remainingPercent)
                    ))
                  if let duration = window.windowDurationMinutes {
                    Text(strings.format(.windowMinutes, duration))
                  }
                  Spacer()
                  Text(
                    strings.format(
                      .resetsAt,
                      window.resetsAt.map { strings.fullDateTime($0, seconds: true) }
                        ?? strings.text(.timeUnknown)
                    ))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
              }
              .padding(.vertical, 4)
            }
          }

          Section(strings.text(.extraResetCredits)) {
            HStack {
              Text(strings.text(.availableCount))
              Spacer()
              Text("\(quota.resetCreditCount ?? quota.resetCredits.count)").monospacedDigit()
            }
            if quota.resetCredits.isEmpty, (quota.resetCreditCount ?? 0) > 0 {
              Text(strings.text(.countOnlyNoDetails))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            ForEach(quota.resetCredits) { credit in
              VStack(alignment: .leading, spacing: 4) {
                Text(strings.resetCreditTitle(credit.title))
                  .font(.body.weight(.medium))
                if let detail = credit.detail {
                  Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                  Text(strings.format(.status, strings.resetCreditStatus(credit.status)))
                  if let granted = credit.grantedAt {
                    Text(strings.format(.creditedAt, strings.shortDateTime(granted)))
                  }
                  Spacer()
                  Text(
                    strings.format(
                      .expiresAt,
                      credit.expiresAt.map { strings.fullDateTime($0) }
                        ?? strings.text(.timeUnknown)
                    ))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
              }
              .padding(.vertical, 3)
            }
            Text(strings.text(.readOnlyResetHelp))
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if quota.creditBalance != nil || quota.spendControlReached != nil {
            Section(strings.text(.balanceAndLimits)) {
              if let balance = quota.creditBalance {
                LabeledContent(strings.text(.balance), value: balance.formatted())
              }
              if let reached = quota.spendControlReached {
                LabeledContent(
                  strings.text(.spendLimitReached),
                  value: reached ? strings.text(.yes) : strings.text(.no)
                )
              }
            }
          }
        }
        .listStyle(.inset)
      } else {
        ContentUnavailableView(
          strings.text(.quotaUnavailableTitle),
          systemImage: "gauge.with.dots.needle.33percent",
          description: Text(model.quotaError ?? strings.text(.connectingCodex))
        )
      }
    }
    .frame(minWidth: 660, minHeight: 500)
    .environment(\.locale, settings.appLanguage.locale)
  }

  private var statusLine: String {
    guard let quota = model.quota else { return model.quotaError ?? strings.text(.notReadYet) }
    let plan = strings.planDisplayName(quota)
    let status = strings.format(
      .lastSuccessfulUpdate,
      plan,
      strings.freshness(quota.freshness),
      strings.fullDateTime(quota.observedAt, seconds: true)
    )
    if let quotaError = model.quotaError { return "\(status) · \(quotaError)" }
    return status
  }

  private var statusColor: Color {
    switch model.quota?.freshness {
    case .fresh: .secondary
    case .stale: .orange
    case .offline: .red
    case nil: .secondary
    }
  }

}
