import CodexQuotaCore
import SwiftUI

/// A fixed layout proposal is shared by the resting entry and both motion
/// endpoints. Quota updates change the fill, never the size of this canvas.
struct MinimalQuotaPresentation: View {
  let appearance: MinimalMeterAppearance
  let entries: [QuotaDisplayEntry]
  let lowThreshold: Double
  let criticalThreshold: Double
  let freshness: DataFreshness?
  let language: AppLanguage
  var recovery: QuotaRecoveryState?

  private var dimensions: MinimalMeterDimensions {
    appearance.dimensions.normalized(for: appearance.style)
  }
  private var strings: AppStrings { AppStrings(language: language) }
  private var isDual: Bool { entries.count > 1 }
  private var visibleEntries: [QuotaDisplayEntry] { Array(entries.prefix(2)) }

  var body: some View {
    Group {
      switch appearance.style {
      case .vertical:
        HStack(spacing: 2) {
          if isDual {
            ForEach(visibleEntries) { entry in
              VStack(spacing: 2) {
                linearMeter(entry, length: dimensions.length - 10)
                periodLabel(entry)
              }
              .frame(width: max(12, dimensions.thickness))
            }
          } else {
            linearMeter(visibleEntries.first, length: dimensions.length)
          }
        }
      case .horizontal:
        VStack(spacing: 4) {
          if isDual {
            ForEach(visibleEntries) { entry in
              HStack(spacing: 4) {
                periodLabel(entry).frame(width: 14)
                horizontalMeter(entry)
              }
            }
          } else {
            horizontalMeter(visibleEntries.first)
          }
        }
      case .ring:
        ZStack {
          ringMeter(visibleEntries.first, diameter: dimensions.length)
          if isDual {
            ringMeter(visibleEntries.last, diameter: dimensions.length - 3 * dimensions.thickness)
          }
        }
        .accessibilityElement(children: .contain)
        .help(isDual ? strings.text(.minimalRingQuotaHelp) : strings.text(.minimalCollapsedHelp))
      }
    }
    .scaleEffect(dimensions.scale)
    .frame(width: appearance.contentSize.width, height: appearance.contentSize.height)
  }

  private func periodLabel(_ entry: QuotaDisplayEntry) -> some View {
    Text(entry.shortLabel(strings))
      .font(.system(size: 7, weight: .medium))
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
  }

  private func linearMeter(_ entry: QuotaDisplayEntry?, length: Double) -> some View {
    MinimalQuotaMeterView(
      remainingPercent: entry?.window?.remainingPercent,
      lowThreshold: lowThreshold, criticalThreshold: criticalThreshold,
      freshness: freshness, language: language,
      meterHeight: length, meterWidth: dimensions.thickness,
      accessibilityName: entry?.title(strings),
      recoveryEmphasis: MinimalRecoveryEmphasis.resolve(entry: entry, recovery: recovery))
  }

  private func horizontalMeter(_ entry: QuotaDisplayEntry?) -> some View {
    linearMeter(entry, length: dimensions.length)
      .rotationEffect(.degrees(90))
      .frame(width: dimensions.length, height: dimensions.thickness)
  }

  private func ringMeter(_ entry: QuotaDisplayEntry?, diameter: Double) -> some View {
    MinimalRingQuotaView(
      remainingPercent: entry?.window?.remainingPercent,
      diameter: diameter, thickness: dimensions.thickness,
      lowThreshold: lowThreshold, criticalThreshold: criticalThreshold,
      freshness: freshness, language: language, accessibilityName: entry?.title(strings),
      recoveryEmphasis: MinimalRecoveryEmphasis.resolve(entry: entry, recovery: recovery))
  }
}

struct MinimalRingQuotaView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let remainingPercent: Double?
  let diameter: Double
  let thickness: Double
  let lowThreshold: Double
  let criticalThreshold: Double
  let freshness: DataFreshness?
  let language: AppLanguage
  let accessibilityName: String?
  var recoveryEmphasis: MinimalRecoveryEmphasis?

  nonisolated static func fraction(_ remaining: Double?) -> Double? {
    guard let remaining, remaining.isFinite else { return nil }
    return min(1, max(0, remaining / 100))
  }

  private var fraction: Double? { Self.fraction(remainingPercent) }
  private var accessibilityValue: String {
    guard let fraction else { return AppStrings(language: language).text(.quotaUnavailable) }
    let percent = QuotaPercentage.text(fraction * 100)
    return switch language {
    case .simplifiedChinese: "剩余 \(percent)"
    case .traditionalChinese: "剩餘 \(percent)"
    case .english: "\(percent) remaining"
    }
  }

  var body: some View {
    ZStack {
      Circle().inset(by: thickness / 2)
        .stroke(Color(nsColor: .tertiaryLabelColor).opacity(0.26), lineWidth: thickness)
      if let fraction, fraction > 0 {
        Circle().inset(by: thickness / 2)
          .trim(from: 0, to: fraction)
          .stroke(
            QuotaMeterPalette.fillColor(
              remainingPercent: fraction * 100, lowThreshold: lowThreshold,
              criticalThreshold: criticalThreshold),
            style: StrokeStyle(lineWidth: thickness, lineCap: .round)
          )
          .rotationEffect(.degrees(-90))
      }
    }
    .frame(width: diameter, height: diameter)
    .overlay {
      if let recoveryEmphasis {
        // Two inset circles trace the empty track's real edges. No generic
        // rounded rectangle, out-of-bounds stroke, or icon over the meter.
        ZStack {
          Circle().strokeBorder(recoveryEmphasis.color.opacity(0.85), lineWidth: 0.9)
          Circle().inset(by: thickness)
            .strokeBorder(recoveryEmphasis.color.opacity(0.5), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
      } else if freshness == .stale || freshness == .offline {
        Circle().strokeBorder(
          freshness == .offline ? Color.red.opacity(0.7) : Color.orange.opacity(0.65),
          lineWidth: 0.7)
      }
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: fraction)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: recoveryEmphasis)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(QuotaMeterAccessibility.title(name: accessibilityName, language: language))
    .accessibilityValue(accessibilityValue)
    .help(
      "\(QuotaMeterAccessibility.title(name: accessibilityName, language: language)) · \(accessibilityValue)"
    )
  }
}
