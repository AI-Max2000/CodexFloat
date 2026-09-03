import SwiftUI

struct FeedbackBannerView: View {
  let feedback: AppFeedback
  let language: AppLanguage
  var isPopover = false
  var recoveryAction: () -> Void = {}

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isPulsing = false
  private var content: LocalizedAppFeedback {
    feedback.localized(using: AppStrings(language: language))
  }

  var body: some View {
    if case .recovery(let state) = feedback.payload {
      QuotaRecoveryView(state: state, language: language, action: recoveryAction)
    } else {
      standardBanner
    }
  }

  private var standardBanner: some View {
    HStack(alignment: .top, spacing: 10) {
      ZStack {
        Circle()
          .fill(accent.opacity(isPulsing ? 0.22 : 0.10))
          .frame(width: 31, height: 31)
          .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.08 : 0.94))
        Image(systemName: symbol)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(accent)
      }

      VStack(alignment: .leading, spacing: 3) {
        Text(content.title)
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(1)
        Text(content.message)
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if let callout = content.callout {
          Text(callout)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(accent)
            .padding(.top, 1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(isPopover ? 12 : 9)
    .background {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(accent.opacity(isPopover ? 0.10 : 0.075))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(accent.opacity(isPulsing ? 0.62 : 0.28), lineWidth: 1)
    }
    .animation(animation, value: isPulsing)
    .onAppear { beginAnimation() }
    .onChange(of: feedback.id) { _, _ in beginAnimation() }
    .accessibilityElement(children: .combine)
  }

  private var accent: Color {
    switch feedback.kind {
    case .tiboReset: .mint
    case .quotaLow: .orange
    case .quotaCritical: .red
    }
  }

  private var symbol: String {
    switch feedback.kind {
    case .tiboReset: "arrow.counterclockwise.circle.fill"
    case .quotaLow: "gauge.with.dots.needle.67percent"
    case .quotaCritical: "exclamationmark.triangle.fill"
    }
  }

  private var animation: Animation? {
    guard !reduceMotion else { return nil }
    let duration: Double
    switch feedback.kind {
    case .tiboReset: duration = 0.9
    case .quotaLow: duration = 1.25
    case .quotaCritical: duration = 0.55
    }
    return .easeInOut(duration: duration).repeatForever(autoreverses: true)
  }

  private func beginAnimation() {
    isPulsing = false
    guard !reduceMotion else { return }
    DispatchQueue.main.async { isPulsing = true }
  }
}
