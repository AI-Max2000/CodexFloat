import SwiftUI

struct QuotaRecoveryView: View {
  let state: QuotaRecoveryState
  let language: AppLanguage
  var isRefreshing = false
  let action: () -> Void
  private var strings: AppStrings { AppStrings(language: language) }
  private var accent: Color { state.needsRefresh ? .orange : .red }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .top, spacing: 8) {
        Image(
          systemName: state.needsRefresh
            ? "arrow.clockwise.circle.fill" : "exclamationmark.circle.fill"
        )
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(state.needsRefresh ? Color.orange : Color.red)
        VStack(alignment: .leading, spacing: 3) {
          Text(state.title(strings)).font(.system(size: 12, weight: .bold))
          Text(state.message(strings))
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Button(action: action) {
        HStack(spacing: 5) {
          Text(state.actionTitle(strings)).font(.system(size: 11, weight: .semibold))
          Spacer(minLength: 4)
          Image(systemName: state.needsRefresh ? "arrow.clockwise" : "arrow.up.right")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .foregroundStyle(
          state.canOpenManualReset || state.needsRefresh ? Color.white : Color.primary
        )
        .background(
          state.needsRefresh
            ? Color(red: 0.55, green: 0.29, blue: 0.04)
            : (state.canOpenManualReset
              ? Color(red: 0.72, green: 0.12, blue: 0.17)
              : Color.secondary.opacity(0.12)),
          in: RoundedRectangle(cornerRadius: 7))
      }
      .buttonStyle(.plain)
      .disabled(state.needsRefresh && isRefreshing)
      .help(strings.text(.manualResetNavigationHelp))
      if !state.needsRefresh {
        Text(strings.text(.manualResetNavigationHelp))
          .font(.system(size: 9)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.3), lineWidth: 1))
    .accessibilityElement(children: .contain)
  }
}

struct CompactQuotaRecoveryView: View {
  let state: QuotaRecoveryState
  let language: AppLanguage
  let action: () -> Void
  private var strings: AppStrings { AppStrings(language: language) }

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "exclamationmark.circle.fill")
        .font(.system(size: 14)).foregroundStyle(.red)
      VStack(alignment: .leading, spacing: 3) {
        // Keep the title as window-drag background. Only the explicit action
        // row is a button, so the exhausted capsule can still be repositioned.
        Text(state.kind == .exhausted ? "Codex · 0%" : state.title(strings))
          .font(.system(size: 13, weight: .bold))
        Button(action: action) {
          HStack(spacing: 3) {
            Text(state.actionTitle(strings))
            Image(systemName: state.needsRefresh ? "arrow.clockwise" : "arrow.up.right")
          }
          .font(.system(size: 10, weight: .semibold)).foregroundStyle(.red)
        }
        .buttonStyle(.plain)
      }
      .lineLimit(1).minimumScaleFactor(0.8)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .help(state.message(strings))
    .accessibilityElement(children: .contain)
  }
}
