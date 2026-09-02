import CodexQuotaCore
import SwiftUI

/// Fits inside the existing 174 × 54 capsule; enabling dual quotas must not
/// change the resting window frame or its liquid-reveal seed geometry.
struct DualCompactQuotaView: View {
  let entries: [QuotaDisplayEntry]
  let planName: String
  let resetCount: Int?
  let freshnessColor: Color
  let lowThreshold: Double
  let criticalThreshold: Double
  let language: AppLanguage

  private var strings: AppStrings { AppStrings(language: language) }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      HStack(spacing: 6) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 3) {
            Circle().fill(freshnessColor).frame(width: 5, height: 5)
            Text("Codex").font(.system(size: 13, weight: .semibold, design: .rounded))
          }
          if let resetCount, resetCount > 0 {
            Text(strings.format(.resetCountCompact, resetCount))
              .foregroundStyle(.mint)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          } else {
            Text(planName).foregroundStyle(.secondary)
              .lineLimit(1).minimumScaleFactor(0.8)
          }
        }
        .font(.system(size: 8.5, weight: .semibold))
        .frame(width: 53, alignment: .leading)

        ForEach(entries) { entry in
          VStack(spacing: 1) {
            Text(entry.periodLabel(strings))
              .font(.system(size: 8.5, weight: .medium))
              .foregroundStyle(.secondary)
            Text(entry.percentage)
              .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
              .foregroundStyle(
                entry.window.map {
                  QuotaMeterPalette.fillColor(
                    remainingPercent: $0.remainingPercent,
                    lowThreshold: lowThreshold,
                    criticalThreshold: criticalThreshold
                  )
                } ?? Color.secondary)
            Text(entry.compactCountdown(strings, now: context.date))
              .font(.system(size: 8.5).monospacedDigit())
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
          .frame(width: 45)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(entry.help(strings, now: context.date))
          .help(entry.help(strings, now: context.date))
        }
      }
      .frame(height: 38)
    }
  }
}

struct DualMinimalQuotaView: View {
  let entries: [QuotaDisplayEntry]
  let lowThreshold: Double
  let criticalThreshold: Double
  let freshness: DataFreshness?
  let language: AppLanguage

  var body: some View {
    HStack(spacing: 2) {
      ForEach(entries) { entry in
        VStack(spacing: 2) {
          MinimalQuotaMeterView(
            remainingPercent: entry.window?.remainingPercent,
            lowThreshold: lowThreshold,
            criticalThreshold: criticalThreshold,
            freshness: freshness,
            language: language,
            meterHeight: 28,
            accessibilityName: entry.title(AppStrings(language: language))
          )
          Text(entry.shortLabel(AppStrings(language: language)))
            .font(.system(size: 7, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(width: 12)
      }
    }
  }
}
