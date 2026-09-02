import SwiftUI

enum SettingsLayout {
  static let width: CGFloat = 540
  static let height: CGFloat = 620
}

struct SettingsView: View {
  @ObservedObject var settings: AppSettings
  let onPreviewFeedback: (AppFeedbackKind) -> Void
  let onExportDiagnostics: () -> Void

  private var strings: AppStrings { AppStrings(language: settings.appLanguage) }

  var body: some View {
    Form {
      Section(strings.text(.language)) {
        Picker(strings.text(.language), selection: $settings.appLanguage) {
          ForEach(AppLanguage.allCases) { language in
            Text(language.nativeDisplayName).tag(language)
          }
        }
        .pickerStyle(.segmented)
        Text(strings.text(.languageDescription))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section(strings.text(.windowSection)) {
        HStack {
          Text(strings.text(.displayMode))
          Spacer()
          DisplayModeSelector(
            selection: $settings.quotaDisplayMode,
            strings: strings
          )
          .frame(width: 356)
        }
        Toggle(strings.text(.hoverExpand), isOn: $settings.hoverExpansionEnabled)
          .disabled(settings.quotaDisplayMode != .standard)
        HStack {
          Text(strings.text(.collapseAfterMouseLeaves))
          Spacer()
          Picker("", selection: $settings.hoverCollapseDelay) {
            Text(strings.text(.immediately)).tag(0.15)
            Text(durationLabel(0.6)).tag(0.6)
            Text(durationLabel(1.0)).tag(1.0)
            Text(durationLabel(2.0)).tag(2.0)
          }
          .labelsHidden()
          .frame(width: 120)
        }
        .disabled(!settings.hoverExpansionEnabled || settings.quotaDisplayMode == .menuBar)
        Toggle(strings.text(.showOnLaunch), isOn: $settings.showPanelOnLaunch)
        Toggle(
          strings.text(.frontmostOnly),
          isOn: $settings.showOnlyWhenChatGPTIsFrontmost
        )
        .disabled(settings.quotaDisplayMode == .menuBar)
        if settings.quotaDisplayMode == .standard {
          Text(
            settings.hoverExpansionEnabled
              ? strings.text(.hoverEnabledHelp) : strings.text(.hoverDisabledHelp)
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        } else if settings.quotaDisplayMode == .minimal {
          Text(strings.text(.minimalCollapsedHelp))
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if settings.quotaDisplayMode == .menuBar {
          Text(strings.text(.menuBarDisplayHelp))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(settings.quotaDisplayMode == .menuBar
          ? strings.text(.menuBarAlwaysVisibleHelp)
          : (settings.showOnlyWhenChatGPTIsFrontmost
            ? strings.text(.frontmostEnabledHelp) : strings.text(.frontmostDisabledHelp)))
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section(strings.text(.shortcutSection)) {
        Toggle(strings.text(.shortcutEnable), isOn: $settings.globalHotKeyEnabled)
        HStack {
          Text(strings.text(.shortcut))
          Spacer()
          HotKeyRecorderView(
            configuration: $settings.globalHotKeyConfiguration,
            language: settings.appLanguage
          )
          .frame(width: 150, height: 28)
          .disabled(!settings.globalHotKeyEnabled)
          Button(strings.text(.restoreDefault)) {
            settings.globalHotKeyConfiguration = .default
          }
          .disabled(
            !settings.globalHotKeyEnabled
              || settings.globalHotKeyConfiguration == HotKeyConfiguration.default)
        }
        if let error = settings.globalHotKeyRegistrationError {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
        }
        Text(strings.text(.shortcutHelp))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section(strings.text(.taskSection)) {
        Toggle(strings.text(.showRecentTasks), isOn: $settings.showRecentTasks)
        Stepper(value: $settings.recentTaskCount, in: 1...8) {
          HStack {
            Text(strings.text(.taskCount))
            Spacer()
            Text(strings.format(.taskCountValue, settings.recentTaskCount))
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
        }
        .disabled(!settings.showRecentTasks)
        Toggle(strings.text(.taskCompletionNotification), isOn: $settings.notifyTaskCompletion)
          .disabled(!settings.notificationsEnabled)
        if let error = settings.taskMonitoringError {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
        }
        Text(strings.text(.taskHelp))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section(strings.text(.notificationsSection)) {
        Toggle(strings.text(.enableNotifications), isOn: $settings.notificationsEnabled)
        thresholdRow(
          title: strings.text(.lowQuotaAlert), value: $settings.lowThreshold, range: 10...50)
        thresholdRow(
          title: strings.text(.criticalQuotaAlert), value: $settings.criticalThreshold,
          range: 1...15)
        Toggle(strings.text(.newResetCreditAlert), isOn: $settings.notifyResetCredits)
        Toggle(strings.text(.expiringResetCreditAlert), isOn: $settings.notifyExpiringCredits)
        Toggle(strings.text(.tiboResetAlert), isOn: $settings.notifyTibo)
        Toggle(strings.text(.fiveHourAlert), isOn: $settings.notifyFiveHoursBeforeReset)
        HStack(spacing: 8) {
          Text(strings.text(.previewFeedback))
          Spacer()
          Button(strings.text(.previewTibo)) { onPreviewFeedback(.tiboReset) }
          Button(strings.text(.previewLow)) { onPreviewFeedback(.quotaLow) }
          Button(strings.text(.previewCritical)) { onPreviewFeedback(.quotaCritical) }
        }
        Text(strings.text(.previewFeedbackHelp))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section(strings.text(.quotaDisplaySection)) {
        HStack {
          Text(strings.text(.autoRefreshInterval))
          Spacer()
          Picker("", selection: $settings.quotaRefreshInterval) {
            Text(strings.text(.refreshEvery15Seconds)).tag(15.0)
            Text(strings.text(.refreshEvery30Seconds)).tag(30.0)
            Text(strings.text(.refreshEveryMinute)).tag(60.0)
            Text(strings.text(.refreshEveryFiveMinutes)).tag(300.0)
          }
          .labelsHidden()
          .frame(width: 150)
        }
        Text(strings.text(.autoRefreshHelp))
          .font(.caption)
          .foregroundStyle(.secondary)
        Toggle(
          strings.text(.showSupplementaryQuotas),
          isOn: $settings.showSupplementaryGPTQuotas
        )
        Text(strings.text(.supplementaryQuotaHelp))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section(strings.text(.tiboSection)) {
        Toggle(strings.text(.tiboPolling), isOn: $settings.feedEnabled)
        Toggle(
          strings.text(.resetProbabilityToggle),
          isOn: $settings.showResetProbability
        )
        .disabled(!settings.feedEnabled)
        Text(strings.text(.tiboHelp))
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(strings.text(.resetProbabilityHelp))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section(strings.text(.privacySection)) {
        Text(strings.text(.privacyHelp))
          .font(.caption)
          .foregroundStyle(.secondary)
        Button(strings.text(.exportDiagnostics), action: onExportDiagnostics)
      }
    }
    .formStyle(.grouped)
    .padding(8)
    .frame(width: SettingsLayout.width, height: SettingsLayout.height)
    .environment(\.locale, settings.appLanguage.locale)
  }

  private func thresholdRow(title: String, value: Binding<Double>, range: ClosedRange<Double>)
    -> some View
  {
    HStack {
      Text(title)
      Slider(value: value, in: range, step: 1)
      Text("\(Int(value.wrappedValue))%")
        .monospacedDigit()
        .frame(width: 38, alignment: .trailing)
    }
  }

  private func durationLabel(_ seconds: Double) -> String {
    let value = seconds == floor(seconds) ? String(Int(seconds)) : String(format: "%.1f", seconds)
    switch settings.appLanguage {
    case .simplifiedChinese: return "\(value) 秒"
    case .traditionalChinese: return "\(value) 秒"
    case .english: return "\(value) sec"
    }
  }
}

private struct DisplayModeSelector: View {
  @Binding var selection: QuotaDisplayMode
  let strings: AppStrings

  var body: some View {
    HStack(spacing: 2) {
      option(.standard, title: strings.text(.standardDisplayMode))
      option(.minimal, title: strings.text(.minimalDisplayMode))
      option(.menuBar, title: strings.text(.menuBarDisplayMode))
    }
    .padding(3)
    .background {
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.55))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }

  private func option(_ mode: QuotaDisplayMode, title: String) -> some View {
    let isSelected = selection == mode
    return Button {
      selection = mode
    } label: {
      HStack(spacing: 6) {
        DisplayModeGlyph(mode: mode, isSelected: isSelected)
          .frame(width: 28, height: 20)
        Text(title)
          .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
          .lineLimit(1)
          .minimumScaleFactor(0.82)
      }
      .foregroundStyle(isSelected ? Color.primary : Color.secondary)
      .frame(maxWidth: .infinity, minHeight: 30)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background {
      if isSelected {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor))
          .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
      }
    }
    .accessibilityLabel(title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private struct DisplayModeGlyph: View {
  let mode: QuotaDisplayMode
  let isSelected: Bool

  private var accent: Color {
    isSelected ? Color.accentColor : Color.secondary.opacity(0.75)
  }

  var body: some View {
    switch mode {
    case .standard:
      ZStack {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(Color.primary.opacity(isSelected ? 0.06 : 0.035))
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .stroke(Color.primary.opacity(isSelected ? 0.32 : 0.18), lineWidth: 1)
        HStack(spacing: 3) {
          Circle()
            .fill(accent)
            .frame(width: 4, height: 4)
          VStack(alignment: .leading, spacing: 3) {
            Capsule().fill(Color.primary.opacity(0.72)).frame(width: 13, height: 2.5)
            Capsule().fill(accent).frame(width: 10, height: 2.5)
          }
        }
      }

    case .minimal:
      ZStack {
        Capsule()
          .fill(Color.primary.opacity(0.12))
          .frame(width: 6, height: 20)
        VStack(spacing: 0) {
          Spacer(minLength: 0)
          Capsule()
            .fill(accent)
            .frame(width: 6, height: 14)
        }
        .frame(width: 6, height: 20)
      }

    case .menuBar:
      ZStack {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(Color.primary.opacity(isSelected ? 0.06 : 0.035))
        VStack(spacing: 0) {
          HStack(spacing: 2) {
            Spacer(minLength: 0)
            Circle()
              .fill(accent)
              .frame(width: 3, height: 3)
            Capsule()
              .fill(Color.primary.opacity(0.68))
              .frame(width: 6, height: 2.5)
          }
          .padding(.horizontal, 3.5)
          .frame(height: 6)
          .background(Color.primary.opacity(0.13))
          Spacer(minLength: 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .stroke(Color.primary.opacity(isSelected ? 0.32 : 0.18), lineWidth: 1)
      }
      .frame(width: 26, height: 16)
    }
  }
}
