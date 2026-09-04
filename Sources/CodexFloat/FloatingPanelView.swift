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

enum LiquidCapsuleMotion {
  struct CubicBezier: Equatable, Sendable {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double
  }

  // Keep the curve monotonic. The previous y overshoot reached a clamped 100%
  // before the animation clock finished, which looked like a dropped tail frame.
  static let expansionDuration: TimeInterval = 0.38
  static let collapseDuration: TimeInterval = 0.30
  static let completionSettleBuffer: TimeInterval = 0.05
  static let expansionCurve = CubicBezier(x1: 0.22, y1: 0.72, x2: 0.24, y2: 1.0)
  static let collapseCurve = CubicBezier(x1: 0.40, y1: 0.0, x2: 0.30, y2: 1.0)

  static func animation(expanding: Bool, reduceMotion: Bool) -> Animation? {
    guard !reduceMotion else { return nil }
    let curve = expanding ? expansionCurve : collapseCurve
    let duration = expanding ? expansionDuration : collapseDuration
    return .timingCurve(curve.x1, curve.y1, curve.x2, curve.y2, duration: duration)
  }
}

enum FloatingPanelLayout {
  // The standard compact row can contain Codex, a three-digit percentage and
  // a localized reset count at the same time. Keep enough room for that worst
  // case so the reset action never touches the rounded clipping boundary.
  static let collapsedWidth: CGFloat = 188
  static let collapsedHeight: CGFloat = 54
  static let collapsedLeadingPadding: CGFloat = 8
  static let collapsedTrailingSafetyInset: CGFloat = 12
  static let collapsedVerticalPadding: CGFloat = 8
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
  static let expandedHeaderSafetyInset: CGFloat = 2
  static let headerGroupSpacing: CGFloat = 6
  static let headerActionSpacing: CGFloat = 4
  static let headerButtonSize: CGFloat = 24
  static let headerProgressSize: CGFloat = 16
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
  static let menuBarLiquidSeedSize = NSSize(width: 74, height: 18)
  static let hoverExpansionDuration = LiquidCapsuleMotion.expansionDuration

  static func shouldRenderExpandedLayer(isCollapsed: Bool, isCollapsing: Bool) -> Bool {
    !isCollapsed || isCollapsing
  }

  static func liquidSurfaceSeedSize(
    canvasSize: NSSize,
    mode: QuotaDisplayMode,
    minimalSize: NSSize = NSSize(width: minimalCollapsedWidth, height: minimalCollapsedHeight)
  ) -> NSSize {
    switch mode {
    case .standard:
      return NSSize(width: collapsedWidth, height: collapsedHeight)
    case .minimal:
      return minimalSize
    case .menuBar:
      return menuBarLiquidSeedSize
    }
  }

  static func liquidCornerRadius(
    progress: CGFloat,
    seedSize: NSSize
  ) -> CGFloat {
    let amount = min(1, max(0, progress))
    // Both end frames use the exact same corner radius. The radius only swells
    // in the middle, which preserves the liquid character without changing
    // shape on the handoff frame.
    let availableBulge = max(0, min(seedSize.width, seedSize.height) / 2 - panelCornerRadius)
    let bulge = min(8, max(4, availableBulge))
    return panelCornerRadius + sin(.pi * amount) * bulge
  }

  static func compactContentProgress(surfaceProgress: CGFloat) -> CGFloat {
    1 - min(1, max(0, surfaceProgress))
  }

  static func expandedContentProgress(surfaceProgress: CGFloat) -> CGFloat {
    min(1, max(0, surfaceProgress))
  }

  static func liquidContentOffset(expandedProgress: CGFloat) -> CGSize {
    let amount = 1 - min(1, max(0, expandedProgress))
    return CGSize(width: -5 * amount, height: -3 * amount)
  }

  static func liquidRevealRect(
    in bounds: CGRect,
    progress: CGFloat,
    seedSize: NSSize,
    anchoredToTrailingEdge: Bool,
    anchoredToBottomEdge: Bool = false
  ) -> CGRect {
    let amount = min(1, max(0, progress))
    let seedWidth = min(bounds.width, max(0, seedSize.width))
    let seedHeight = min(bounds.height, max(0, seedSize.height))
    let width = seedWidth + (bounds.width - seedWidth) * amount
    let height = seedHeight + (bounds.height - seedHeight) * amount
    let x = anchoredToTrailingEdge ? bounds.maxX - width : bounds.minX
    let y = anchoredToBottomEdge ? bounds.maxY - height : bounds.minY
    return CGRect(x: x, y: y, width: width, height: height)
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

  static func expandedInnerWidth(canvasWidth: CGFloat) -> CGFloat {
    max(0, canvasWidth - expandedPadding * 2)
  }

  static func headerActionsWidth(showsProgress: Bool) -> CGFloat {
    let buttonWidth = headerButtonSize * 3 + headerActionSpacing * 2
    return showsProgress
      ? buttonWidth + headerActionSpacing + headerProgressSize
      : buttonWidth
  }

  static func headerIdentityWidth(canvasWidth: CGFloat, showsProgress: Bool) -> CGFloat {
    max(
      0,
      expandedInnerWidth(canvasWidth: canvasWidth)
        - expandedHeaderSafetyInset
        - headerGroupSpacing
        - headerActionsWidth(showsProgress: showsProgress)
    )
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
    var sections = [
      expandedHeaderHeight,
      quotaListHeight(
        visibleWindowCount: visibleQuotaWindowCount
      ),
    ]
    if feedbackHeight > 0 {
      sections.insert(max(feedbackMinimumHeight, feedbackHeight), at: 0)
    }
    if showsRecentTasks {
      sections.append(expandedDividerHeight)
      sections.append(
        recentTasksHeight(
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

  private var strings: AppStrings { AppStrings(language: settings.appLanguage) }
  private var isTransitioning: Bool { panelState.isCollapsing || panelState.isExpanding }
  private var isMinimalMode: Bool { settings.quotaDisplayMode == .minimal }
  private var expandedRevealProgress: CGFloat { panelState.revealProgress }
  private var revealDirection: PanelExpansionDirection {
    settings.quotaDisplayMode == .menuBar
      ? PanelExpansionDirection(growsLeft: true) : panelState.expansionDirection
  }
  private var liquidChromeOpacity: Double {
    // The large material surface must not be visible on the compact endpoint.
    // A compact, fixed-size material surface owns that frame so resizing the
    // backing NSWindow cannot alter its blur sample and expose a second handoff.
    Double(expandedContentProgress)
  }
  private var liquidSurfaceProgress: CGFloat {
    settings.quotaDisplayMode == .menuBar
      ? panelState.menuBarPresentationProgress
      : expandedRevealProgress
  }
  private var liquidSeedSize: NSSize {
    FloatingPanelLayout.liquidSurfaceSeedSize(
      canvasSize: panelState.expandedCanvasSize,
      mode: settings.quotaDisplayMode,
      minimalSize: panelState.minimalMeterAppearance.collapsedSize
    )
  }
  private var compactContentProgress: CGFloat {
    FloatingPanelLayout.compactContentProgress(
      surfaceProgress: expandedRevealProgress
    )
  }
  private var expandedContentProgress: CGFloat {
    FloatingPanelLayout.expandedContentProgress(
      surfaceProgress: liquidSurfaceProgress
    )
  }
  private var headerShowsProgress: Bool {
    model.isRefreshingQuota || model.isRefreshingFeed || model.isRefreshingResetForecast
      || model.isRefreshingTasks
  }
  private var visibleQuotaWindowCount: Int {
    quotaDisplay.expanded.count
  }
  private var quotaDisplay: QuotaDisplayPolicy {
    QuotaDisplayPolicy(
      snapshot: model.quota,
      showFiveHour: settings.showFiveHourQuota,
      includingSupplementaryGPT: settings.showSupplementaryGPTQuotas
    )
  }
  private var preferredExpandedHeight: CGFloat {
    FloatingPanelLayout.preferredExpandedHeight(
      visibleQuotaWindowCount: visibleQuotaWindowCount,
      showsRecentTasks: settings.showRecentTasks,
      configuredTaskCount: settings.recentTaskCount,
      loadedTaskCount: model.tasks.count,
      showsFeed: settings.feedEnabled,
      showsResetProbability: settings.showResetProbability,
      feedbackHeight: model.quotaRecovery != nil
        ? (feedbackBannerHeight > 0 ? ceil(feedbackBannerHeight) : 132)
        : FloatingPanelLayout.feedbackBannerHeight(
          isVisible: model.transientFeedback != nil,
          measuredHeight: feedbackBannerHeight
        )
    )
  }

  var body: some View {
    ZStack(alignment: revealDirection.alignment) {
      contentLayers
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: revealDirection.alignment)
    // Keep the final interaction region available while the liquid boundary
    // catches up, so moving from the compact entry into the opening panel does
    // not accidentally reverse the animation.
    .contentShape(Rectangle())
    .onHover(perform: onHoverChanged)
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

  @ViewBuilder private var contentLayers: some View {
    liquidSurface

    compactPresentation
      .mask(alignment: revealDirection.growsUp ? .bottom : .top) {
        Rectangle()
          .scaleEffect(
            x: 1,
            y: compactContentProgress,
            anchor: revealDirection.growsUp ? .bottom : .top
          )
      }
      .allowsHitTesting(panelState.isCollapsed && !isTransitioning)
      .accessibilityHidden(!panelState.isCollapsed)
  }

  private var liquidSurface: some View {
    ZStack(alignment: .topLeading) {
      Rectangle()
        .fill(.ultraThinMaterial)
        .opacity(liquidChromeOpacity)

      if FloatingPanelLayout.shouldRenderExpandedLayer(
        isCollapsed: panelState.isCollapsed,
        isCollapsing: panelState.isCollapsing
      ) {
        expandedLayer
          .offset(
            CGSize(
              width: (revealDirection.growsLeft ? 5 : -5) * (1 - expandedRevealProgress),
              height: (revealDirection.growsUp ? 3 : -3) * (1 - expandedRevealProgress)
            )
          )
          // Cache the stable final-size hierarchy as one compositing surface.
          // Only the cheap mask transforms during the hover animation.
          .compositingGroup()
          .mask(alignment: revealDirection.alignment) {
            Rectangle()
              .scaleEffect(
                x: expandedContentProgress,
                y: expandedContentProgress,
                anchor: revealDirection.unitPoint
              )
          }
      }
    }
    // Apply the liquid boundary once to the material and expanded hierarchy,
    // instead of recalculating the same animated path for each child layer.
    .mask {
      presentationShape.fill(.white)
    }
    .overlay {
      presentationShape
        .strokeBorder(.primary.opacity(0.10), lineWidth: 0.7)
        .opacity(liquidChromeOpacity)
    }
  }

  private var compactPresentation: some View {
    compactLayer
      .background {
        compactSurfaceShape
          .fill(.ultraThinMaterial)
          .opacity(isMinimalMode ? 0 : 1)
      }
      .overlay {
        compactSurfaceShape
          .strokeBorder(.primary.opacity(0.10), lineWidth: 0.7)
          .opacity(isMinimalMode ? 0 : 1)
      }
      .clipShape(compactSurfaceShape)
  }

  private var compactSurfaceShape: RoundedRectangle {
    RoundedRectangle(
      cornerRadius: FloatingPanelLayout.panelCornerRadius,
      style: .continuous
    )
  }

  private var presentationShape: LiquidCapsuleRevealShape {
    LiquidCapsuleRevealShape(
      progress: reduceMotion ? (panelState.isCollapsed ? 0 : 1) : liquidSurfaceProgress,
      seedSize: liquidSeedSize,
      anchoredToTrailingEdge: revealDirection.growsLeft,
      anchoredToBottomEdge: revealDirection.growsUp
    )
  }

  private var expandedLayer: some View {
    ScrollView(panelState.expandedCanvasSize.width < 340 ? [.horizontal, .vertical] : .vertical) {
      expandedContent
        .frame(
          width: FloatingPanelLayout.expandedInnerWidth(
            canvasWidth: max(340, panelState.expandedCanvasSize.width)
          ),
          alignment: .topLeading
        )
        .fixedSize(horizontal: false, vertical: true)
        .padding(
          EdgeInsets(
            top: FloatingPanelLayout.expandedPadding,
            leading: FloatingPanelLayout.expandedPadding,
            bottom: FloatingPanelLayout.expandedBottomPadding,
            trailing: FloatingPanelLayout.expandedPadding
          )
        )
    }
    .scrollBounceBehavior(.basedOnSize)
    // The hierarchy always receives the final inner width. The liquid shape
    // reveals this stable canvas without re-centering individual sections.
    .frame(
      width: panelState.expandedCanvasSize.width,
      height: panelState.expandedCanvasSize.height,
      alignment: .topLeading
    )
  }

  @ViewBuilder private var compactLayer: some View {
    if isMinimalMode {
      minimalCollapsedContent
        .padding(FloatingPanelLayout.minimalCollapsedPadding)
        .frame(
          width: panelState.minimalMeterAppearance.collapsedSize.width,
          height: panelState.minimalMeterAppearance.collapsedSize.height,
          alignment: .center
        )
    } else {
      collapsedContent
        .padding(
          EdgeInsets(
            top: FloatingPanelLayout.collapsedVerticalPadding,
            leading: FloatingPanelLayout.collapsedLeadingPadding,
            bottom: FloatingPanelLayout.collapsedVerticalPadding,
            trailing: FloatingPanelLayout.collapsedTrailingSafetyInset
          )
        )
        .frame(
          width: FloatingPanelLayout.collapsedWidth,
          height: FloatingPanelLayout.collapsedHeight,
          alignment: .topLeading
        )
    }
  }

  private var expandedContent: some View {
    VStack(alignment: .leading, spacing: FloatingPanelLayout.expandedSectionSpacing) {
      if let recovery = model.quotaRecovery {
        QuotaRecoveryView(
          state: recovery, language: settings.appLanguage,
          isRefreshing: model.isRefreshingQuota, action: model.handleQuotaRecovery
        )
        .background {
          GeometryReader { proxy in
            Color.clear.preference(key: FeedbackBannerHeightKey.self, value: proxy.size.height)
          }
        }
      } else if let feedback = model.transientFeedback, !feedback.isExhaustion {
        FeedbackBannerView(
          feedback: feedback, language: settings.appLanguage,
          recoveryAction: model.handleQuotaRecovery
        )
        .transition(.nativeTopReveal)
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
      LiquidCapsuleMotion.animation(
        expanding: model.transientFeedback != nil,
        reduceMotion: reduceMotion
      ),
      value: model.transientFeedback?.id
    )
    .onPreferenceChange(FeedbackBannerHeightKey.self) { height in
      feedbackBannerHeight = ceil(height)
    }
  }

  @ViewBuilder private var collapsedContent: some View {
    if let recovery = model.quotaRecovery {
      CompactQuotaRecoveryView(
        state: recovery, language: settings.appLanguage, action: model.handleQuotaRecovery)
    } else if quotaDisplay.isDual {
      DualCompactQuotaView(
        entries: quotaDisplay.compact,
        planName: model.quota.map(strings.compactPlanName) ?? strings.text(.planUnknown),
        resetCount: model.availableResetCount,
        freshnessColor: freshnessColor,
        lowThreshold: settings.lowThreshold,
        criticalThreshold: settings.criticalThreshold,
        language: settings.appLanguage
      )
    } else {
      HStack(spacing: 7) {
        freshnessDot
        if let entry = quotaDisplay.compact.first, let window = entry.window {
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
              Text("Codex")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: true, vertical: false)
              Text(
                strings.format(.remainingPercentage, QuotaPercentage.text(window.remainingPercent))
              )
              .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
              .fixedSize(horizontal: true, vertical: false)
              if let count = model.availableResetCount, count > 0 {
                Text(strings.format(.resetCountCompact, count))
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.mint)
                  .fixedSize(horizontal: true, vertical: false)
              }
            }
            TimelineView(
              .periodic(
                from: .now,
                by: CountdownRefreshPolicy.interval(to: window.resetsAt, now: Date())
              )
            ) { context in
              Text(
                (entry.kind != .other ? "\(entry.shortLabel(strings)) · " : "")
                  + strings.countdown(to: window.resetsAt, now: context.date)
              )
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: true, vertical: false)
            }
          }
          .layoutPriority(3)
          .fixedSize(horizontal: true, vertical: false)
        } else {
          Text(
            model.quota != nil
              ? strings.text(.quotaWindowNotReturned)
              : (model.quotaError == nil
                ? strings.text(.readingQuota) : strings.text(.quotaUnavailable))
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: true, vertical: false)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var minimalCollapsedContent: some View {
    MinimalQuotaPresentation(
      appearance: panelState.minimalMeterAppearance,
      entries: quotaDisplay.compact,
      lowThreshold: settings.lowThreshold,
      criticalThreshold: settings.criticalThreshold,
      freshness: model.quota?.freshness,
      language: settings.appLanguage,
      recovery: model.quotaRecovery
    )
    // Preserve the exact collapsed layout proposal while the NSPanel grows.
    // Without this fixed canvas, the meter expands to the panel's new size
    // and SwiftUI briefly centers it in the middle of the floating surface.
    .frame(
      width: panelState.minimalMeterAppearance.contentSize.width,
      height: panelState.minimalMeterAppearance.contentSize.height,
      alignment: .center
    )
    .contentShape(Rectangle())
    .onTapGesture {
      if model.quotaRecovery != nil { model.handleQuotaRecovery() }
    }
    .accessibilityAction(named: Text(strings.text(.openCodexUsage))) {
      model.handleQuotaRecovery()
    }
    .help(
      model.quotaRecovery.map { $0.message(strings) + " " + $0.actionTitle(strings) }
        ?? strings.text(.minimalCollapsedHelp)
    )
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
      HStack(spacing: FloatingPanelLayout.headerGroupSpacing) {
        headerIdentity
          .frame(
            width: FloatingPanelLayout.headerIdentityWidth(
              canvasWidth: panelState.expandedCanvasSize.width,
              showsProgress: headerShowsProgress
            ),
            alignment: .leading
          )
          .clipped()
        headerActions
          .fixedSize(horizontal: true, vertical: false)
          .layoutPriority(10)
      }
      .padding(.trailing, FloatingPanelLayout.expandedHeaderSafetyInset)
      .frame(maxWidth: .infinity, alignment: .leading)
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

  private var headerIdentity: some View {
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
      if let quota = model.quota {
        let count = model.availableResetCount ?? 0
        if count > 0 {
          ResetCreditExpiryCarouselView(
            count: count,
            expiresAt: ResetCreditExpiryCarouselPolicy.earliestAvailableExpiry(
              in: quota.resetCredits,
              now: Date()
            ),
            language: settings.appLanguage
          )
        }
      }
      Spacer(minLength: 0)
    }
  }

  private var headerActions: some View {
    HStack(spacing: FloatingPanelLayout.headerActionSpacing) {
      if headerShowsProgress {
        ProgressView()
          .controlSize(.small)
          .scaleEffect(0.65)
          .frame(
            width: FloatingPanelLayout.headerProgressSize,
            height: FloatingPanelLayout.headerButtonSize
          )
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
  }

  private var freshnessDot: some View {
    Circle()
      .fill(freshnessColor)
      .frame(width: 7, height: 7)
      .help(model.quota.map { strings.freshness($0.freshness) } ?? strings.text(.notReadYet))
  }

  @ViewBuilder
  private var quotaList: some View {
    if !quotaDisplay.expanded.isEmpty {
      let entries = quotaDisplay.expanded
      ScrollView(.vertical) {
        LazyVStack(spacing: 6) {
          ForEach(entries) { entry in
            if let window = entry.window {
              quotaRow(window, title: entry.title(strings))
            } else {
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(entry.title(strings)).font(.system(size: 11, weight: .medium))
                  Text(strings.text(.quotaWindowNotReturned))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("--").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
              }
              .frame(height: FloatingPanelLayout.quotaRowHeight)
            }
          }
        }
      }
      .scrollIndicators(.never)
      .frame(height: FloatingPanelLayout.quotaListHeight(visibleWindowCount: entries.count))
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

  private func quotaRow(_ window: RateLimitWindow, title: String) -> some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 11, weight: .medium))
          .lineLimit(1)
        TimelineView(
          .periodic(
            from: .now,
            by: CountdownRefreshPolicy.interval(to: window.resetsAt, now: Date())
          )
        ) { context in
          Text(
            strings.format(
              .resetCountdown,
              strings.countdown(to: window.resetsAt, now: context.date),
              absoluteTime(window.resetsAt)
            )
          )
          .font(.system(size: 10).monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      VStack(alignment: .trailing, spacing: 3) {
        Text(
          strings.format(
            .remainingPercentage,
            QuotaPercentage.text(window.remainingPercent)
          )
        )
        .font(.system(size: 11, weight: .semibold).monospacedDigit())
        QuotaMeterView(
          remainingPercent: window.remainingPercent,
          lowThreshold: settings.lowThreshold,
          criticalThreshold: settings.criticalThreshold,
          width: 74,
          language: settings.appLanguage,
          accessibilityName: title
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
                Text(
                  strings.format(
                    .resetProbability48Hours,
                    Int((probability * 100).rounded())
                  )
                )
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
            Text(strings.activityTimingLine(assessment))
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
        width: FloatingPanelLayout.headerButtonSize,
        height: FloatingPanelLayout.headerButtonSize
      )
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

private struct LiquidCapsuleRevealShape: InsettableShape {
  var progress: CGFloat
  let seedSize: NSSize
  let anchoredToTrailingEdge: Bool
  var anchoredToBottomEdge: Bool = false
  var insetAmount: CGFloat = 0

  nonisolated var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let revealRect = FloatingPanelLayout.liquidRevealRect(
      in: rect,
      progress: progress,
      seedSize: seedSize,
      anchoredToTrailingEdge: anchoredToTrailingEdge,
      anchoredToBottomEdge: anchoredToBottomEdge
    ).insetBy(dx: insetAmount, dy: insetAmount)
    guard revealRect.width > 0, revealRect.height > 0 else { return Path() }
    let requestedRadius = max(
      0,
      FloatingPanelLayout.liquidCornerRadius(
        progress: progress,
        seedSize: seedSize
      ) - insetAmount
    )
    let radius = min(requestedRadius, min(revealRect.width, revealRect.height) / 2)
    return RoundedRectangle(cornerRadius: radius, style: .continuous)
      .path(in: revealRect)
  }

  func inset(by amount: CGFloat) -> LiquidCapsuleRevealShape {
    var copy = self
    copy.insetAmount += amount
    return copy
  }
}

private struct NativeTopRevealModifier: AnimatableModifier {
  var progress: CGFloat

  nonisolated var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    content.mask(alignment: .top) {
      Rectangle()
        .scaleEffect(x: 1, y: min(1, max(0, progress)), anchor: .top)
    }
  }
}

extension AnyTransition {
  fileprivate static var nativeTopReveal: AnyTransition {
    .modifier(
      active: NativeTopRevealModifier(progress: 0),
      identity: NativeTopRevealModifier(progress: 1)
    )
  }
}
