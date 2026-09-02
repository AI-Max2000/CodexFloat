import AppKit
import CodexQuotaCore
import SwiftUI
import TiboFeedCore

enum CountdownRefreshPolicy {
  static let detailedWindow: TimeInterval = 10 * 60
  static let detailedInterval: TimeInterval = 1
  static let relaxedInterval: TimeInterval = 60

  static func interval(to resetAt: Date?, now: Date) -> TimeInterval {
    guard let resetAt else { return relaxedInterval }
    let remaining = resetAt.timeIntervalSince(now)
    return remaining > 0 && remaining <= detailedWindow
      ? detailedInterval
      : relaxedInterval
  }
}

enum FloatingPanelLayout {
  static let collapsedWidth: CGFloat = 174
  static let collapsedHeight: CGFloat = 54
  static let minimalCollapsedWidth: CGFloat = 36
  static let minimalCollapsedHeight: CGFloat = 54
  static let minimalCollapsedPadding: CGFloat = 5
  static let minimalContentSize = NSSize(
    width: minimalCollapsedWidth - minimalCollapsedPadding * 2,
    height: minimalCollapsedHeight - minimalCollapsedPadding * 2
  )
  static let expandedPadding: CGFloat = 12
  static let expandedBottomPadding: CGFloat = 8
  static let expandedSectionSpacing: CGFloat = 7
  static let expandedDividerHeight: CGFloat = 1
  static let expandedHeaderHeight: CGFloat = 40
  static let quotaRowHeight: CGFloat = 32
  static let quotaRowSpacing: CGFloat = 6
  static let taskRowSlotHeight: CGFloat = 24
  static let taskHeaderHeight: CGFloat = 14
  static let taskHeaderSpacing: CGFloat = 4
  static let resetProbabilityRowHeight: CGFloat = 28
  static let resetActivityRowHeight: CGFloat = 42
  static let resetRadarRowSpacing: CGFloat = 5
  static let resetRadarIconSize: CGFloat = 10
  static let resetRadarIconFrame: CGFloat = 14
  static let feedbackMinimumHeight: CGFloat = 49
  static let feedbackDefaultHeight: CGFloat = 78
  static let feedbackMaximumHeight: CGFloat = 96
  static let panelCornerRadius: CGFloat = 18
  static let hoverExpansionDuration: TimeInterval = 0.17
  static let expandedContentRevealDuration: TimeInterval = 0.14

  static func shouldRenderExpandedLayer(isCollapsed: Bool, isTransitioning: Bool) -> Bool {
    !isCollapsed && !isTransitioning
  }

  static func compactRevealFraction(expandedProgress: CGFloat) -> CGFloat {
    1 - min(1, max(0, expandedProgress))
  }

  static func interpolatedFrame(from start: NSRect, to end: NSRect, progress: Double) -> NSRect {
    let amount = CGFloat(min(1, max(0, progress)))
    func interpolate(_ startValue: CGFloat, _ endValue: CGFloat) -> CGFloat {
      startValue + (endValue - startValue) * amount
    }
    return NSRect(
      x: interpolate(start.minX, end.minX),
      y: interpolate(start.minY, end.minY),
      width: interpolate(start.width, end.width),
      height: interpolate(start.height, end.height)
    )
  }

  static func draggedFrame(
    from start: NSRect,
    translation: CGSize,
    visibleFrame: NSRect
  ) -> NSRect {
    let proposedX = start.minX + translation.width
    let proposedY = start.minY - translation.height
    let x = min(max(proposedX, visibleFrame.minX), visibleFrame.maxX - start.width)
    let y = min(max(proposedY, visibleFrame.minY), visibleFrame.maxY - start.height)
    return NSRect(x: x, y: y, width: start.width, height: start.height)
  }

  static func quotaListHeight(visibleWindowCount: Int) -> CGFloat {
    let rowCount = max(1, min(visibleWindowCount, 4))
    return CGFloat(rowCount) * quotaRowHeight
      + CGFloat(max(0, rowCount - 1)) * quotaRowSpacing
  }

  static func taskListHeight(configuredCount: Int, loadedCount: Int) -> CGFloat {
    let rowCount = loadedCount == 0 ? 1 : min(max(1, configuredCount), loadedCount, 8)
    return CGFloat(rowCount) * taskRowSlotHeight
  }

  static func recentTasksHeight(configuredCount: Int, loadedCount: Int) -> CGFloat {
    taskHeaderHeight + taskHeaderSpacing
      + taskListHeight(configuredCount: configuredCount, loadedCount: loadedCount)
  }

  static func resetRadarHeight(showsProbability: Bool) -> CGFloat {
    showsProbability
      ? resetProbabilityRowHeight + resetRadarRowSpacing + resetActivityRowHeight
      : resetActivityRowHeight
  }

  static func feedbackBannerHeight(isVisible: Bool, measuredHeight: CGFloat) -> CGFloat {
    guard isVisible else { return 0 }
    guard measuredHeight > 0 else { return feedbackDefaultHeight }
    return min(
      feedbackMaximumHeight,
      max(feedbackMinimumHeight, ceil(measuredHeight))
    )
  }

  static func preferredExpandedHeight(
    visibleQuotaWindowCount: Int,
    showsRecentTasks: Bool,
    configuredTaskCount: Int,
    loadedTaskCount: Int,
    showsFeed: Bool,
    showsResetProbability: Bool,
    feedbackHeight: CGFloat
  ) -> CGFloat {
    var sections = [expandedHeaderHeight, quotaListHeight(
      visibleWindowCount: visibleQuotaWindowCount
    )]
    if feedbackHeight > 0 {
      sections.insert(max(feedbackMinimumHeight, feedbackHeight), at: 0)
    }
    if showsRecentTasks {
      sections.append(expandedDividerHeight)
      sections.append(recentTasksHeight(
        configuredCount: configuredTaskCount,
        loadedCount: loadedTaskCount
      ))
    }
    if showsFeed {
      sections.append(expandedDividerHeight)
      sections.append(resetRadarHeight(showsProbability: showsResetProbability))
    }
    return ceil(
      sections.reduce(0, +)
        + CGFloat(max(0, sections.count - 1)) * expandedSectionSpacing
        + expandedPadding
        + expandedBottomPadding
    )
  }

  static func menuBarExpandedFrame(
    anchorFrame: NSRect,
    panelSize: NSSize,
    visibleFrame: NSRect,
    gap: CGFloat = 0
  ) -> NSRect {
    let x = min(
      max(anchorFrame.maxX - panelSize.width, visibleFrame.minX + 8),
      visibleFrame.maxX - panelSize.width - 8
    )
    let preferredY = anchorFrame.minY - gap - panelSize.height
    let y = max(visibleFrame.minY + 8, preferredY)
    return NSRect(origin: NSPoint(x: x, y: y), size: panelSize)
  }

  static func anchoredResizeFrame(
    currentFrame: NSRect,
    targetSize: NSSize,
    visibleFrame: NSRect
  ) -> NSRect {
    // Keep the visual origin stable: hover expansion grows right and down from the top-left.
    let proposedX = currentFrame.minX
    let x = min(
      max(proposedX, visibleFrame.minX),
      visibleFrame.maxX - targetSize.width
    )
    let y = min(
      max(currentFrame.maxY - targetSize.height, visibleFrame.minY),
      visibleFrame.maxY - targetSize.height
    )
    return NSRect(origin: NSPoint(x: x, y: y), size: targetSize)
  }

  static func standardCollapsedAnchorFrame(
    currentFrame: NSRect,
    expandedSize: NSSize,
    visibleFrame: NSRect
  ) -> NSRect {
    // A collapsed standard bar must leave enough room to grow right and down.
    // Clamping the compact anchor now prevents the expanded panel from moving
    // its top-left corner later.
    let maximumX = max(visibleFrame.minX, visibleFrame.maxX - expandedSize.width)
    let x = min(max(currentFrame.minX, visibleFrame.minX), maximumX)
    let minimumTop = min(visibleFrame.maxY, visibleFrame.minY + expandedSize.height)
    let top = min(max(currentFrame.maxY, minimumTop), visibleFrame.maxY)
    return NSRect(
      x: x,
      y: top - currentFrame.height,
      width: currentFrame.width,
      height: currentFrame.height
    )
  }
}

private struct FeedbackBannerHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

struct FloatingPanelView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var settings: AppSettings
  @ObservedObject var panelState: PanelUIState
  let onHoverChanged: (Bool) -> Void
  let onMinimalDragChanged: (CGSize, Bool) -> Void
  let onRefresh: () -> Void
  let onOpenSettings: () -> Void
  let onHide: () -> Void
  let onPreferredExpandedHeightChanged: (CGFloat) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var feedbackBannerHeight: CGFloat = 0
  @State private var expandedRevealProgress: CGFloat = 0

  private var strings: AppStrings { AppStrings(language: settings.appLanguage) }
  private var isTransitioning: Bool { panelState.isCollapsing || panelState.isExpanding }
  private var isMinimalMode: Bool { settings.quotaDisplayMode == .minimal }
  private var panelChromeOpacity: Double {
    isMinimalMode && panelState.isCollapsed && !isTransitioning ? 0 : 1
  }
  private var visibleQuotaWindowCount: Int {
    guard let quota = model.quota else { return 0 }
    return quota.visibleWindows(
      includingSupplementaryGPT: settings.showSupplementaryGPTQuotas
    ).count
  }
  private var preferredExpandedHeight: CGFloat {
    FloatingPanelLayout.preferredExpandedHeight(
      visibleQuotaWindowCount: visibleQuotaWindowCount,
      showsRecentTasks: settings.showRecentTasks,
      configuredTaskCount: settings.recentTaskCount,
      loadedTaskCount: model.tasks.count,
      showsFeed: settings.feedEnabled,
      showsResetProbability: settings.showResetProbability,
      feedbackHeight: FloatingPanelLayout.feedbackBannerHeight(
        isVisible: model.transientFeedback != nil,
        measuredHeight: feedbackBannerHeight
      )
    )
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      // Keep this inexpensive layer alive as the stationary transition surface.
      // The expanded hierarchy contains lists, materials, and TimelineViews;
      // laying it out on every frame resize makes the window miss vsync.
      // Keep the compact presentation mounted for the full handoff. Its mask
      // retracts from the bottom while expanded content reveals left-to-right,
      // so it never jumps, recenters, or disappears in a single frame.
      compactLayer
        .mask(alignment: .top) {
          Rectangle()
            .scaleEffect(
              x: 1,
              y: FloatingPanelLayout.compactRevealFraction(
                expandedProgress: expandedRevealProgress
              ),
              anchor: .top
            )
        }
        .allowsHitTesting(panelState.isCollapsed && !isTransitioning)
        .accessibilityHidden(!panelState.isCollapsed)

      if FloatingPanelLayout.shouldRenderExpandedLayer(
        isCollapsed: panelState.isCollapsed,
        isTransitioning: isTransitioning
      ) {
        expandedLayer
          .mask(alignment: .leading) {
            Rectangle()
              .scaleEffect(
                x: reduceMotion ? 1 : expandedRevealProgress,
                y: 1,
                anchor: .leading
              )
          }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background {
      panelShape
        .fill(.ultraThinMaterial)
        .opacity(panelChromeOpacity)
    }
    .overlay {
      panelShape
        .strokeBorder(.primary.opacity(0.10), lineWidth: 0.7)
        .opacity(panelChromeOpacity)
    }
    // Clip every content layer with the exact same continuous curve as the
    // material and border. This prevents partially laid-out rows from painting
    // into the transparent corners while the NSPanel changes size.
    .clipShape(panelShape)
    .contentShape(panelShape)
    .onHover(perform: onHoverChanged)
    .onAppear {
      synchronizeContentLayers(isCollapsed: panelState.isCollapsed)
    }
    .onChange(of: panelState.isCollapsed) { _, isCollapsed in
      animateContentLayers(isCollapsed: isCollapsed)
    }
    .onChange(of: isTransitioning) { _, transitioning in
      animateContentAfterFrameTransition(isTransitioning: transitioning)
    }
    // Keep the controller's target height current even while only the collapsed
    // presentation is visible. Otherwise the first hover starts toward the old
    // height and is corrected without animation after expandedContent appears.
    .onAppear {
      onPreferredExpandedHeightChanged(preferredExpandedHeight)
    }
    .onChange(of: preferredExpandedHeight) { _, height in
      onPreferredExpandedHeightChanged(height)
    }
  }

  private var panelShape: RoundedRectangle {
    RoundedRectangle(
      cornerRadius: FloatingPanelLayout.panelCornerRadius,
      style: .continuous
    )
  }

  private var expandedLayer: some View {
    expandedContent
      .padding(
        EdgeInsets(
          top: FloatingPanelLayout.expandedPadding,
          leading: FloatingPanelLayout.expandedPadding,
          bottom: FloatingPanelLayout.expandedBottomPadding,
          trailing: FloatingPanelLayout.expandedPadding
        )
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder private var compactLayer: some View {
    if isMinimalMode {
      minimalCollapsedContent
        .padding(FloatingPanelLayout.minimalCollapsedPadding)
        .frame(
          width: FloatingPanelLayout.minimalCollapsedWidth,
          height: FloatingPanelLayout.minimalCollapsedHeight,
          alignment: .topLeading
        )
    } else {
      collapsedContent
        .padding(8)
        .frame(
          width: FloatingPanelLayout.collapsedWidth,
          height: FloatingPanelLayout.collapsedHeight,
          alignment: .topLeading
        )
    }
  }

  private func synchronizeContentLayers(isCollapsed: Bool) {
    expandedRevealProgress = isCollapsed ? 0 : 1
  }

  private func animateContentLayers(isCollapsed: Bool) {
    guard !reduceMotion else {
      synchronizeContentLayers(isCollapsed: isCollapsed)
      return
    }

    if isCollapsed {
      // Remove wide rows in the same update that starts the collapse. Keeping
      // them mounted after the window narrows would recreate the cropped edge.
      var transaction = Transaction(animation: nil)
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        expandedRevealProgress = 0
      }
    } else if !isTransitioning {
      revealExpandedContent()
    }
  }

  private func animateContentAfterFrameTransition(isTransitioning: Bool) {
    guard !reduceMotion else {
      synchronizeContentLayers(isCollapsed: panelState.isCollapsed)
      return
    }

    if isTransitioning {
      var transaction = Transaction(animation: nil)
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        expandedRevealProgress = 0
      }
    } else if !panelState.isCollapsed {
      revealExpandedContent()
    }
  }

  private func revealExpandedContent() {
    withAnimation(
      .timingCurve(
        0.37,
        0.0,
        0.63,
        1.0,
        duration: FloatingPanelLayout.expandedContentRevealDuration
      )
    ) {
      expandedRevealProgress = 1
    }
  }

  private var expandedContent: some View {
    VStack(spacing: FloatingPanelLayout.expandedSectionSpacing) {
      if let feedback = model.transientFeedback {
        FeedbackBannerView(feedback: feedback, language: settings.appLanguage)
          .transition(.move(edge: .top).combined(with: .opacity))
          .background {
            GeometryReader { proxy in
              Color.clear.preference(
                key: FeedbackBannerHeightKey.self,
                value: proxy.size.height
              )
            }
          }
      }
      header
      quotaList
      if settings.showRecentTasks {
        Divider()
          .frame(height: FloatingPanelLayout.expandedDividerHeight)
          .opacity(0.45)
        recentTasks
      }
      if settings.feedEnabled {
        Divider()
          .frame(height: FloatingPanelLayout.expandedDividerHeight)
          .opacity(0.45)
        resetRadarSection
      }
    }
    .animation(
      reduceMotion ? nil : .snappy(duration: 0.24),
      value: model.transientFeedback?.id
    )
    .onPreferenceChange(FeedbackBannerHeightKey.self) { height in
      feedbackBannerHeight = ceil(height)
    }
  }

  private var collapsedContent: some View {
    HStack(spacing: 7) {
      freshnessDot
      if let window = model.quota?.preferredCodexWindow {
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 4) {
            Text("Codex")
              .font(.system(size: 18, weight: .semibold, design: .rounded))
              .fixedSize(horizontal: true, vertical: false)
            Text(strings.format(.remainingCompact, Int(window.remainingPercent.rounded())))
              .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
              .fixedSize(horizontal: true, vertical: false)
            if let count = model.quota?.resetCreditCount, count > 0 {
              Text(strings.format(.resetCountCompact, count))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.mint)
                .fixedSize(horizontal: true, vertical: false)
            }
          }
          TimelineView(.periodic(
            from: .now,
            by: CountdownRefreshPolicy.interval(to: window.resetsAt, now: Date())
          )) { context in
            Text(strings.countdown(to: window.resetsAt, now: context.date))
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: true, vertical: false)
          }
        }
        .layoutPriority(3)
        .fixedSize(horizontal: true, vertical: false)
      } else {
        Text(
          model.quotaError == nil ? strings.text(.readingQuota) : strings.text(.quotaUnavailable)
        )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: true, vertical: false)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var minimalCollapsedContent: some View {
    MinimalQuotaMeterView(
      remainingPercent: model.quota?.preferredCodexWindow?.remainingPercent,
      lowThreshold: settings.lowThreshold,
      criticalThreshold: settings.criticalThreshold,
      freshness: model.quota?.freshness,
      language: settings.appLanguage
    )
    // Preserve the exact collapsed layout proposal while the NSPanel grows.
    // Without this fixed canvas, the meter expands to the panel's new size
    // and SwiftUI briefly centers it in the middle of the floating surface.
    .frame(
      width: FloatingPanelLayout.minimalContentSize.width,
      height: FloatingPanelLayout.minimalContentSize.height,
      alignment: .center
    )
    .contentShape(Rectangle())
    .highPriorityGesture(
      DragGesture(minimumDistance: 1, coordinateSpace: .global)
        .onChanged { value in
          onMinimalDragChanged(value.translation, false)
        }
        .onEnded { value in
          onMinimalDragChanged(value.translation, true)
        }
    )
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 6) {
        freshnessDot
        Text("Codex")
          .font(.system(size: 14, weight: .semibold))
          .fixedSize(horizontal: true, vertical: false)
        if let quota = model.quota, quota.planType != nil {
          Text(strings.compactPlanName(quota))
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
        }
        if let count = model.quota?.resetCreditCount, count > 0 {
          Text(strings.format(.resetCountHeader, count))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.mint)
            .fixedSize(horizontal: true, vertical: false)
        }
        Spacer(minLength: 3)
        if model.isRefreshingQuota || model.isRefreshingFeed || model.isRefreshingResetForecast
          || model.isRefreshingTasks
        {
          ProgressView().controlSize(.small).scaleEffect(0.65)
        }
        iconButton("arrow.clockwise", action: onRefresh, disabled: model.isRefreshingQuota)
          .accessibilityLabel(strings.text(.refresh))
          .help(strings.text(.menuRefresh))
        iconButton("gearshape", action: onOpenSettings)
          .accessibilityLabel(strings.text(.settings))
          .help(strings.text(.settings))
        iconButton("eye.slash", action: onHide)
          .accessibilityLabel(strings.text(.hide))
          .help(strings.text(.hideHelp))
      }
      .frame(height: 28)

      HStack(spacing: 4) {
        if let quota = model.quota {
          Text(quotaUpdateStatus(quota))
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .layoutPriority(1)
        }
        if let quotaError = model.quotaError {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 9))
            .foregroundStyle(.orange)
            .accessibilityLabel(strings.format(.quotaRefreshFailed, quotaError))
            .help(quotaError)
        }
        Spacer(minLength: 0)
      }
      .frame(height: 11)
    }
    .frame(height: FloatingPanelLayout.expandedHeaderHeight, alignment: .top)
  }

  private var freshnessDot: some View {
    Circle()
      .fill(freshnessColor)
      .frame(width: 7, height: 7)
      .help(model.quota.map { strings.freshness($0.freshness) } ?? strings.text(.notReadYet))
  }

  @ViewBuilder
  private var quotaList: some View {
    if let quota = model.quota, !quota.windows.isEmpty {
      let windows = quota.visibleWindows(
        includingSupplementaryGPT: settings.showSupplementaryGPTQuotas)
      ScrollView(.vertical) {
        LazyVStack(spacing: 6) {
          ForEach(windows) { window in
            quotaRow(window)
          }
        }
      }
      .scrollIndicators(.never)
      .frame(height: FloatingPanelLayout.quotaListHeight(visibleWindowCount: windows.count))
    } else {
      HStack {
        Text(model.quotaError ?? strings.text(.connectingCodex))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        Spacer()
      }
      .frame(height: FloatingPanelLayout.quotaListHeight(visibleWindowCount: 0))
    }
  }

  private func quotaRow(_ window: RateLimitWindow) -> some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(strings.windowDisplayName(window))
          .font(.system(size: 11, weight: .medium))
          .lineLimit(1)
        TimelineView(.periodic(
          from: .now,
          by: CountdownRefreshPolicy.interval(to: window.resetsAt, now: Date())
        )) { context in
          Text(strings.format(
            .resetCountdown,
            strings.countdown(to: window.resetsAt, now: context.date),
            absoluteTime(window.resetsAt)
          ))
          .font(.system(size: 10).monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      VStack(alignment: .trailing, spacing: 3) {
        Text(strings.format(
          .remainingQuota,
          Int(window.remainingPercent.rounded())
        ))
        .font(.system(size: 11, weight: .semibold).monospacedDigit())
        QuotaMeterView(
          remainingPercent: window.remainingPercent,
          lowThreshold: settings.lowThreshold,
          criticalThreshold: settings.criticalThreshold,
          width: 74,
          language: settings.appLanguage,
          accessibilityName: strings.windowDisplayName(window)
        )
      }
    }
  }

  private var recentTasks: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 5) {
        Text(strings.text(.recentTasks))
          .font(.system(size: 10, weight: .semibold))
        if let taskError = model.taskError, model.tasks.isEmpty {
          Text(taskError)
            .font(.system(size: 9))
            .foregroundStyle(.red)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        Text("\(min(settings.recentTaskCount, model.tasks.count))/\(settings.recentTaskCount)")
          .font(.system(size: 9).monospacedDigit())
          .foregroundStyle(.tertiary)
      }
      .frame(height: FloatingPanelLayout.taskHeaderHeight)

      if model.tasks.isEmpty {
        HStack(spacing: 5) {
          ProgressView().controlSize(.mini)
          Text(model.taskError ?? strings.text(.readingTasks))
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
          Spacer(minLength: 0)
        }
        .frame(height: 24)
      } else {
        ScrollView(.vertical) {
          LazyVStack(spacing: 2) {
            ForEach(Array(model.tasks.prefix(settings.recentTaskCount))) { task in
              taskRow(task)
            }
          }
        }
        .scrollIndicators(.never)
        .frame(
          height: FloatingPanelLayout.taskListHeight(
            configuredCount: settings.recentTaskCount,
            loadedCount: model.tasks.count
          )
        )
      }
    }
    .frame(
      height: FloatingPanelLayout.recentTasksHeight(
        configuredCount: settings.recentTaskCount,
        loadedCount: model.tasks.count
      ),
      alignment: .top
    )
    .fixedSize(horizontal: false, vertical: true)
  }

  private func taskRow(_ task: CodexTask) -> some View {
    Button {
      guard let url = task.deepLink else { return }
      NSWorkspace.shared.open(url)
    } label: {
      HStack(spacing: 6) {
        Circle()
          .fill(taskColor(task.status))
          .frame(width: 7, height: 7)
        Text(task.title)
          .font(.system(size: 11, weight: .medium))
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(strings.taskStatus(task.status))
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(taskColor(task.status))
          .fixedSize(horizontal: true, vertical: false)
        Image(systemName: "arrow.up.right")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.tertiary)
      }
      .frame(height: 22)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(strings.format(.openTask, task.title))
  }

  @ViewBuilder
  private var resetRadarSection: some View {
    VStack(spacing: FloatingPanelLayout.resetRadarRowSpacing) {
      if settings.showResetProbability {
        resetProbabilityLine
      }
      activityLine
    }
    .frame(
      height: FloatingPanelLayout.resetRadarHeight(
        showsProbability: settings.showResetProbability
      ),
      alignment: .top
    )
    .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private var resetProbabilityLine: some View {
    if let forecast = model.resetForecast {
      TimelineView(.periodic(from: .now, by: 60)) { context in
        Button {
          NSWorkspace.shared.open(forecast.sourceURL)
        } label: {
          HStack(spacing: 6) {
            resetRadarIcon(
              "gauge.with.dots.needle.50percent",
              color: resetProbabilityColor(forecast, now: context.date)
            )
            VStack(alignment: .leading, spacing: 1) {
              if let probability = forecast.availableProbability48Hours(at: context.date) {
                Text(strings.format(
                  .resetProbability48Hours,
                  Int((probability * 100).rounded())
                ))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(resetProbabilityColor(forecast, now: context.date))
                .lineLimit(1)
              } else {
                Text(strings.text(.resetProbabilityExpired))
                  .font(.system(size: 10, weight: .semibold))
                  .foregroundStyle(.orange)
              }
              Text(strings.resetForecastSummary(forecast, now: context.date))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "info.circle")
              .font(.system(size: 9))
              .foregroundStyle(.tertiary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(resetForecastHelp(forecast, now: context.date))
      }
    } else {
      HStack(spacing: 6) {
        resetRadarIcon("gauge.with.dots.needle.50percent", color: .secondary)
        Text(
          model.isRefreshingResetForecast
            ? strings.text(.resetProbabilityCalculating)
            : (model.resetForecastError ?? strings.text(.resetProbabilityCalculating))
        )
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        Spacer(minLength: 0)
      }
    }
  }

  @ViewBuilder
  private var activityLine: some View {
    if let post = model.latestResetAnnouncementPost, let assessment = model.assessment(for: post) {
      Button {
        NSWorkspace.shared.open(post.originalURL)
      } label: {
        HStack(spacing: 6) {
          resetRadarIcon(
            activityIcon(assessment.type),
            color: activityColor(assessment)
          )
          VStack(alignment: .leading, spacing: 1) {
            Text(
              "Tibo · \(strings.activityType(assessment.type)) · \(strings.verification(assessment.verification))"
            )
              .font(.system(size: 10, weight: .semibold))
              .lineLimit(1)
            Text(strings.format(
              .expectedResetTimeLine,
              strings.expectedResetTime(assessment)
            ))
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .fixedSize(horizontal: false, vertical: true)
            Text(strings.format(.audience, strings.audience(assessment.audience)))
              .font(.system(size: 9))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Spacer(minLength: 0)
          Image(systemName: "arrow.up.right").font(.system(size: 9))
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    } else {
      HStack(spacing: 6) {
        resetRadarIcon(
          model.feedError == nil
            ? "dot.radiowaves.left.and.right" : "wifi.exclamationmark",
          color: .secondary
        )
        Text(model.feedError ?? strings.text(.noTiboResetAnnouncement))
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer()
      }
    }
  }

  private var freshnessColor: Color {
    switch model.quota?.freshness {
    case .fresh: .green
    case .stale: .orange
    case .offline: .red
    case nil: .secondary
    }
  }

  private func activityColor(_ assessment: ActivityAssessment) -> Color {
    switch assessment.verification {
    case .observed: .green
    case .unverified: .orange
    case .announced: .secondary
    case .expired: .gray
    }
  }

  private func resetProbabilityColor(_ forecast: ResetForecastSnapshot, now: Date) -> Color {
    guard let probability = forecast.availableProbability48Hours(at: now) else { return .orange }
    switch probability {
    case 0.75...: return .pink
    case 0.50...: return .orange
    default: return .blue
    }
  }

  private func resetForecastHelp(_ forecast: ResetForecastSnapshot, now: Date) -> String {
    let base = strings.resetForecastHelp(forecast, now: now)
    guard let error = model.resetForecastError else { return base }
    return "\(base)\n\(error)"
  }

  private func taskColor(_ status: CodexTaskStatus) -> Color {
    switch status {
    case .idle: .green
    case .working: .yellow
    case .error: .red
    }
  }

  private func activityIcon(_ type: ActivityType) -> String {
    switch type {
    case .globalReset: "arrow.counterclockwise.circle"
    case .bankedReset: "banknote"
    case .conditionalReset: "checklist"
    case .limitChange: "slider.horizontal.3"
    case .plannedActivity: "calendar.badge.clock"
    case .incidentOrFix: "wrench.and.screwdriver"
    case .other: "text.bubble"
    }
  }

  private func resetRadarIcon(_ symbol: String, color: Color) -> some View {
    Image(systemName: symbol)
      .font(.system(size: FloatingPanelLayout.resetRadarIconSize, weight: .semibold))
      .foregroundStyle(color)
      .frame(
        width: FloatingPanelLayout.resetRadarIconFrame,
        height: FloatingPanelLayout.resetRadarIconFrame,
        alignment: .center
      )
  }

  private func iconButton(_ symbol: String, action: @escaping () -> Void, disabled: Bool = false)
    -> some View
  {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(
        width: 28, height: 28)
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .opacity(disabled ? 0.45 : 0.8)
  }

  private func absoluteTime(_ date: Date?) -> String {
    guard let date else { return strings.text(.timeUnknown) }
    return strings.shortDateTime(date)
  }

  private func quotaUpdateStatus(_ quota: QuotaSnapshot) -> String {
    if model.isRefreshingQuota, quota.freshness != .fresh {
      return strings.text(.refreshingPreviousQuota)
    }
    if quota.freshness == .offline {
      return strings.format(.offlineShowingPrevious, strings.shortTime(quota.observedAt))
    }
    if quota.freshness == .stale, model.quotaError != nil {
      return strings.format(
        .refreshFailedShowingPrevious,
        strings.shortTime(quota.observedAt)
      )
    }
    return "\(strings.freshness(quota.freshness)) \(strings.shortTime(quota.observedAt))"
  }
}
