import SwiftUI

struct MinimalAppearanceSettingsView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var settings: AppSettings
  private var strings: AppStrings { AppStrings(language: settings.appLanguage) }
  private var appearance: MinimalMeterAppearance { settings.minimalMeterAppearance.normalized }
  private var dimensions: MinimalMeterDimensions { appearance.dimensions }

  var body: some View {
    Picker(strings.text(.minimalStyle), selection: $settings.minimalMeterAppearance.style) {
      ForEach(MinimalMeterStyle.allCases) { style in
        Label(strings.text(style.titleKey), systemImage: symbol(for: style)).tag(style)
      }
    }
    .pickerStyle(.segmented)

    HStack {
      Text(strings.text(.minimalPreview)).font(.caption).foregroundStyle(.secondary)
      Spacer()
      let size = appearance.collapsedSize
      Text("\(Int(size.width)) × \(Int(size.height)) \(strings.text(.minimalPoints))")
        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
    }
    preview

    dimensionRow(
      title: strings.text(
        appearance.style == .ring
          ? .minimalDiameter : (appearance.style == .vertical ? .minimalHeight : .minimalLength)),
      keyPath: \.length, range: appearance.style == .ring ? 20...80 : 20...160)
    dimensionRow(
      title: strings.text(.minimalThickness), keyPath: \.thickness,
      range: 2...(appearance.style == .ring ? min(10, floor(dimensions.length / 6)) : 12))
    dimensionRow(
      title: strings.text(.minimalScale), keyPath: \.scale, range: 50...200, multiplier: 100)

    HStack {
      Text(strings.text(.minimalAppearanceHelp))
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 12)
      Button(strings.text(.restoreDefault)) {
        settings.minimalMeterAppearance.dimensions = .defaults(for: appearance.style)
      }
      .disabled(dimensions == MinimalMeterDimensions.defaults(for: appearance.style))
    }
    if QuotaDisplayPolicy(snapshot: model.quota, showFiveHour: settings.showFiveHourQuota).isDual {
      Text(
        strings.text(appearance.style == .ring ? .minimalRingQuotaHelp : .minimalLinearQuotaHelp)
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }

  private var preview: some View {
    let size = appearance.contentSize
    let scale = min(1, 150 / size.height, 440 / size.width)
    return MinimalQuotaPresentation(
      appearance: appearance,
      entries: QuotaDisplayPolicy(snapshot: model.quota, showFiveHour: settings.showFiveHourQuota)
        .compact,
      lowThreshold: settings.lowThreshold, criticalThreshold: settings.criticalThreshold,
      freshness: model.quota?.freshness, language: settings.appLanguage
    )
    .scaleEffect(scale)
    .frame(maxWidth: .infinity)
    .frame(height: max(54, size.height * scale + 16))
    .background(
      Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8)
    )
    .clipped()
    .animation(nil, value: appearance)
  }

  private func dimensionRow(
    title: String, keyPath: WritableKeyPath<MinimalMeterDimensions, Double>,
    range: ClosedRange<Double>, multiplier: Double = 1
  ) -> some View {
    let binding = Binding<Double>(
      get: { dimensions[keyPath: keyPath] * multiplier },
      set: { value in
        guard value.isFinite else { return }
        var updated = appearance
        updated.dimensions[keyPath: keyPath] =
          min(range.upperBound, max(range.lowerBound, value.rounded())) / multiplier
        settings.minimalMeterAppearance = updated.normalized
      })
    return HStack(spacing: 10) {
      Text(title).frame(width: 72, alignment: .leading)
      Slider(value: binding, in: range).accessibilityLabel(title)
      TextField(title, value: binding, format: .number.precision(.fractionLength(0)))
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing).frame(width: 52)
      Text(multiplier == 100 ? "%" : strings.text(.minimalPoints))
        .foregroundStyle(.secondary).frame(width: 22, alignment: .leading)
    }
  }

  private func symbol(for style: MinimalMeterStyle) -> String {
    switch style {
    case .vertical: "rectangle.portrait.fill"
    case .horizontal: "rectangle.fill"
    case .ring: "circle.lefthalf.filled"
    }
  }
}
