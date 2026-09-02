import CodexQuotaCore
import SwiftUI

struct QuotaMeterView: View {
  let remainingPercent: Double
  let lowThreshold: Double
  let criticalThreshold: Double
  var width: CGFloat
  var language: AppLanguage = .simplifiedChinese
  var accessibilityName: String?

  private var clampedRemaining: Double { min(100, max(0, remainingPercent)) }

  var body: some View {
    ZStack(alignment: .leading) {
      Capsule()
        .fill(Color(nsColor: .tertiaryLabelColor).opacity(0.24))
      Capsule()
        .fill(fillColor)
        .frame(width: width * clampedRemaining / 100)
    }
    .overlay {
      Capsule()
        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
    }
    .frame(width: width, height: 7)
    .animation(.easeInOut(duration: 0.55), value: clampedRemaining)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityTitle)
    .accessibilityValue(accessibilityValue)
    .help(helpText)
  }

  private var fillColor: Color {
    QuotaMeterPalette.fillColor(
      remainingPercent: clampedRemaining,
      lowThreshold: lowThreshold,
      criticalThreshold: criticalThreshold
    )
  }

  private var accessibilityTitle: String {
    QuotaMeterAccessibility.title(name: accessibilityName, language: language)
  }

  private var accessibilityValue: String {
    let value = Int(clampedRemaining.rounded())
    return switch language {
    case .simplifiedChinese: "剩余 \(value)%，总量 100%"
    case .traditionalChinese: "剩餘 \(value)%，總量 100%"
    case .english: "\(value)% remaining out of 100%"
    }
  }

  private var helpText: String {
    switch language {
    case .simplifiedChinese: "彩色表示剩余额度，灰色表示已用额度"
    case .traditionalChinese: "彩色表示剩餘額度，灰色表示已用額度"
    case .english: "Color shows remaining quota; gray shows used quota"
    }
  }
}

enum QuotaMeterAccessibility {
  static func title(name: String?, language: AppLanguage) -> String {
    let resolvedName = name ?? "Codex"
    return switch language {
    case .simplifiedChinese: "\(resolvedName) 剩余额度"
    case .traditionalChinese: "\(resolvedName) 剩餘額度"
    case .english: "\(resolvedName) quota remaining"
    }
  }
}

struct MinimalQuotaMeterView: View {
  let remainingPercent: Double?
  let lowThreshold: Double
  let criticalThreshold: Double
  let freshness: DataFreshness?
  let language: AppLanguage

  var meterHeight: CGFloat = 38
  var accessibilityName: String?
  private var clampedRemaining: Double? {
    remainingPercent.map { min(100, max(0, $0)) }
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      Capsule()
        .fill(Color(nsColor: .tertiaryLabelColor).opacity(0.26))
      if let clampedRemaining, clampedRemaining > 0 {
        Capsule()
          .fill(fillColor)
          .frame(height: max(2, meterHeight * clampedRemaining / 100))
      }
    }
    .overlay {
      Capsule()
        .strokeBorder(borderColor, lineWidth: 0.7)
    }
    .frame(width: 6, height: meterHeight)
    .animation(.easeInOut(duration: 0.55), value: clampedRemaining)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityTitle)
    .accessibilityValue(accessibilityValue)
    .help(helpText)
  }

  private var fillColor: Color {
    guard let clampedRemaining else { return .gray }
    return QuotaMeterPalette.fillColor(
      remainingPercent: clampedRemaining,
      lowThreshold: lowThreshold,
      criticalThreshold: criticalThreshold
    )
  }

  private var borderColor: Color {
    switch freshness {
    case .stale: .orange.opacity(0.65)
    case .offline: .red.opacity(0.70)
    case .fresh, nil: .primary.opacity(0.18)
    }
  }

  private var accessibilityTitle: String {
    if let accessibilityName {
      return QuotaMeterAccessibility.title(name: accessibilityName, language: language)
    }
    return switch language {
    case .simplifiedChinese: "Codex 极简额度"
    case .traditionalChinese: "Codex 極簡額度"
    case .english: "Codex minimal quota meter"
    }
  }

  private var accessibilityValue: String {
    guard let clampedRemaining else {
      return switch language {
      case .simplifiedChinese: "额度暂不可用"
      case .traditionalChinese: "額度暫時無法使用"
      case .english: "Quota unavailable"
      }
    }
    let value = Int(clampedRemaining.rounded())
    return switch language {
    case .simplifiedChinese: "剩余 \(value)%"
    case .traditionalChinese: "剩餘 \(value)%"
    case .english: "\(value)% remaining"
    }
  }

  private var helpText: String {
    switch language {
    case .simplifiedChinese: "彩色高度表示剩余额度，悬停查看详情"
    case .traditionalChinese: "彩色高度表示剩餘額度，懸停查看詳情"
    case .english: "Colored height shows remaining quota; hover for details"
    }
  }
}

enum QuotaMeterPalette {
  struct Components: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
      Color(red: red, green: green, blue: blue)
    }

    static func mixed(from: Components, to: Components, progress: Double) -> Components {
      let amount = min(1, max(0, progress))
      return Components(
        red: from.red + (to.red - from.red) * amount,
        green: from.green + (to.green - from.green) * amount,
        blue: from.blue + (to.blue - from.blue) * amount
      )
    }
  }

  static let normal = Components(red: 0.18, green: 0.72, blue: 0.34)
  static let low = Components(red: 0.98, green: 0.68, blue: 0.08)
  static let critical = Components(red: 0.94, green: 0.22, blue: 0.19)

  static func fillColor(
    remainingPercent: Double,
    lowThreshold: Double,
    criticalThreshold: Double
  ) -> Color {
    components(
      remainingPercent: remainingPercent,
      lowThreshold: lowThreshold,
      criticalThreshold: criticalThreshold
    ).color
  }

  static func components(
    remainingPercent: Double,
    lowThreshold: Double,
    criticalThreshold: Double
  ) -> Components {
    let remaining = min(100, max(0, remainingPercent))
    let criticalPoint = min(100, max(0, criticalThreshold))
    let lowPoint = min(100, max(criticalPoint, lowThreshold))
    let thresholdGap = max(1, lowPoint - criticalPoint)
    let transitionWidth = min(8, max(3, thresholdGap * 0.30))

    if remaining <= criticalPoint { return critical }

    let criticalTransitionEnd = min(lowPoint, criticalPoint + transitionWidth)
    if remaining < criticalTransitionEnd {
      let progress =
        (remaining - criticalPoint)
        / max(0.001, criticalTransitionEnd - criticalPoint)
      return .mixed(from: critical, to: low, progress: progress)
    }

    if remaining <= lowPoint { return low }

    let lowTransitionEnd = min(100, lowPoint + transitionWidth)
    if remaining < lowTransitionEnd {
      let progress = (remaining - lowPoint) / max(0.001, lowTransitionEnd - lowPoint)
      return .mixed(from: low, to: normal, progress: progress)
    }

    return normal
  }
}
