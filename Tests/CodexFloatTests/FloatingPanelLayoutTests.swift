import AppKit
import Foundation
import LocalStore
import Testing

@testable import CodexFloat

// AppKit panel transitions share the main run loop. Serial execution keeps the
// liquid reveal and its completion tasks deterministic in window-level tests.
@Suite("Floating panel adaptive layout", .serialized)
struct FloatingPanelLayoutTests {
  @Test func countdownUsesLowPowerUpdatesUntilTheFinalTenMinutes() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    #expect(CountdownRefreshPolicy.interval(to: nil, now: now) == 60)
    #expect(CountdownRefreshPolicy.interval(to: now.addingTimeInterval(3_600), now: now) == 60)
    #expect(CountdownRefreshPolicy.interval(to: now.addingTimeInterval(601), now: now) == 60)
    #expect(CountdownRefreshPolicy.interval(to: now.addingTimeInterval(600), now: now) == 1)
    #expect(CountdownRefreshPolicy.interval(to: now.addingTimeInterval(30), now: now) == 1)
    #expect(CountdownRefreshPolicy.interval(to: now.addingTimeInterval(-1), now: now) == 60)
  }

  @Test func collapsedBarStaysCompact() {
    #expect(FloatingPanelLayout.collapsedWidth <= 180)
    #expect(FloatingPanelLayout.collapsedHeight <= 56)
    #expect(FloatingPanelLayout.minimalCollapsedWidth == 36)
    #expect(FloatingPanelLayout.minimalCollapsedHeight == 54)
    #expect(FloatingPanelLayout.minimalCollapsedPadding == 5)
    #expect(FloatingPanelLayout.minimalContentSize == NSSize(width: 26, height: 44))
    #expect(FloatingPanelLayout.minimalCollapsedWidth < FloatingPanelLayout.collapsedWidth / 4)
  }

  @Test func minimalMeterKeepsItsCollapsedCanvasDuringExpansion() {
    let collapsedCanvas = NSRect(
      x: FloatingPanelLayout.minimalCollapsedPadding,
      y: FloatingPanelLayout.minimalCollapsedPadding,
      width: FloatingPanelLayout.minimalContentSize.width,
      height: FloatingPanelLayout.minimalContentSize.height
    )
    let expandedPanel = NSSize(width: 420, height: 310)

    #expect(collapsedCanvas.minX == 5)
    #expect(collapsedCanvas.minY == 5)
    #expect(collapsedCanvas.width == 26)
    #expect(collapsedCanvas.height == 44)
    #expect(collapsedCanvas.maxX < expandedPanel.width)
    #expect(collapsedCanvas.maxY < expandedPanel.height)
  }

  @Test func expandedLayerStaysMountedForTheNativeRevealAndCollapse() {
    #expect(
      FloatingPanelLayout.shouldRenderExpandedLayer(
        isCollapsed: false,
        isCollapsing: false
      )
    )
    #expect(
      !FloatingPanelLayout.shouldRenderExpandedLayer(
        isCollapsed: true,
        isCollapsing: false
      )
    )
    #expect(
      FloatingPanelLayout.shouldRenderExpandedLayer(
        isCollapsed: true,
        isCollapsing: true
      )
    )
  }

  @Test func liquidCapsuleUsesOneConcurrentDampedMotion() {
    #expect(FloatingPanelLayout.hoverExpansionDuration == 0.38)
    #expect(LiquidCapsuleMotion.expansionDuration == 0.38)
    #expect(LiquidCapsuleMotion.collapseDuration == 0.30)
    #expect(LiquidCapsuleMotion.completionSettleBuffer == 0.05)
    #expect(
      LiquidCapsuleMotion.expansionCurve
        == LiquidCapsuleMotion.CubicBezier(x1: 0.22, y1: 0.72, x2: 0.24, y2: 1))
    #expect(
      LiquidCapsuleMotion.collapseCurve
        == LiquidCapsuleMotion.CubicBezier(x1: 0.40, y1: 0, x2: 0.30, y2: 1))
  }

  @Test func liquidCapsuleMorphsRadiusAndKeepsItsChosenCornerFixed() {
    let standardSeed = FloatingPanelLayout.liquidSurfaceSeedSize(
      canvasSize: NSSize(width: 340, height: 260),
      mode: .standard
    )
    #expect(standardSeed == NSSize(width: 174, height: 54))
    let minimalSeed = FloatingPanelLayout.liquidSurfaceSeedSize(
      canvasSize: NSSize(width: 340, height: 260),
      mode: .minimal
    )
    #expect(minimalSeed == NSSize(width: 36, height: 54))
    #expect(
      FloatingPanelLayout.liquidCornerRadius(progress: 0, seedSize: standardSeed) == 18)
    #expect(
      FloatingPanelLayout.liquidCornerRadius(progress: 1, seedSize: standardSeed) == 18)
    #expect(
      FloatingPanelLayout.liquidCornerRadius(progress: 0.5, seedSize: standardSeed) > 18)

    let bounds = CGRect(x: 10, y: 20, width: 340, height: 260)
    let standardStart = FloatingPanelLayout.liquidRevealRect(
      in: bounds,
      progress: 0,
      seedSize: standardSeed,
      anchoredToTrailingEdge: false
    )
    let standardEnd = FloatingPanelLayout.liquidRevealRect(
      in: bounds,
      progress: 1,
      seedSize: standardSeed,
      anchoredToTrailingEdge: false
    )
    let minimalStart = FloatingPanelLayout.liquidRevealRect(
      in: bounds,
      progress: 0,
      seedSize: minimalSeed,
      anchoredToTrailingEdge: false
    )
    #expect(standardStart == CGRect(origin: bounds.origin, size: standardSeed))
    #expect(minimalStart == CGRect(origin: bounds.origin, size: minimalSeed))
    #expect(standardEnd == bounds)

    let leading = FloatingPanelLayout.liquidRevealRect(
      in: bounds,
      progress: 0.5,
      seedSize: standardSeed,
      anchoredToTrailingEdge: false
    )
    let trailing = FloatingPanelLayout.liquidRevealRect(
      in: bounds,
      progress: 0.5,
      seedSize: standardSeed,
      anchoredToTrailingEdge: true
    )
    #expect(leading.minX == bounds.minX)
    #expect(trailing.maxX == bounds.maxX)
    #expect(leading.width == trailing.width)
    #expect(leading.height == trailing.height)
  }

  @Test func compactAndExpandedContentShareOneExactMotionClock() {
    for progress in stride(from: CGFloat(0), through: 1, by: 0.05) {
      let compact = FloatingPanelLayout.compactContentProgress(
        surfaceProgress: progress
      )
      let expanded = FloatingPanelLayout.expandedContentProgress(
        surfaceProgress: progress
      )
      #expect(abs(compact + expanded - 1) < 0.0001)
    }
    #expect(FloatingPanelLayout.compactContentProgress(surfaceProgress: 0) == 1)
    #expect(FloatingPanelLayout.expandedContentProgress(surfaceProgress: 0) == 0)
    #expect(FloatingPanelLayout.compactContentProgress(surfaceProgress: 1) == 0)
    #expect(FloatingPanelLayout.expandedContentProgress(surfaceProgress: 1) == 1)
  }

  @Test func liquidCapsuleKeepsCompactContentStationaryWhileRollingItAway() {
    #expect(
      FloatingPanelLayout.liquidContentOffset(expandedProgress: 0)
        == CGSize(width: -5, height: -3))
    #expect(
      FloatingPanelLayout.liquidContentOffset(expandedProgress: 1) == .zero)
  }

  @Test func quotaHeightTracksVisibleRowsAndCapsAtFour() {
    #expect(FloatingPanelLayout.expandedInnerWidth(canvasWidth: 340) == 316)
    #expect(FloatingPanelLayout.expandedInnerWidth(canvasWidth: 520) == 496)
    #expect(FloatingPanelLayout.quotaListHeight(visibleWindowCount: 1) == 32)
    #expect(FloatingPanelLayout.quotaListHeight(visibleWindowCount: 2) == 70)
    #expect(FloatingPanelLayout.quotaListHeight(visibleWindowCount: 8) == 146)
  }

  @Test func headerActionsAlwaysStayInsideTheExpandedSafeArea() {
    #expect(FloatingPanelLayout.headerActionsWidth(showsProgress: false) == 80)
    #expect(FloatingPanelLayout.headerActionsWidth(showsProgress: true) == 100)
    #expect(
      FloatingPanelLayout.headerIdentityWidth(canvasWidth: 340, showsProgress: false) == 228
    )
    #expect(
      FloatingPanelLayout.headerIdentityWidth(canvasWidth: 340, showsProgress: true) == 208
    )
    for showsProgress in [false, true] {
      let occupiedWidth =
        FloatingPanelLayout.headerIdentityWidth(
          canvasWidth: 340,
          showsProgress: showsProgress
        )
        + FloatingPanelLayout.headerGroupSpacing
        + FloatingPanelLayout.headerActionsWidth(showsProgress: showsProgress)
        + FloatingPanelLayout.expandedHeaderSafetyInset
      #expect(occupiedWidth == FloatingPanelLayout.expandedInnerWidth(canvasWidth: 340))
    }
  }

  @Test func taskHeightUsesLoadedRowsInsteadOfConfiguredEmptySlots() {
    #expect(FloatingPanelLayout.taskListHeight(configuredCount: 3, loadedCount: 0) == 24)
    #expect(FloatingPanelLayout.taskListHeight(configuredCount: 3, loadedCount: 1) == 24)
    #expect(FloatingPanelLayout.taskListHeight(configuredCount: 6, loadedCount: 6) == 144)
    #expect(FloatingPanelLayout.taskListHeight(configuredCount: 8, loadedCount: 8) == 192)
    #expect(FloatingPanelLayout.recentTasksHeight(configuredCount: 3, loadedCount: 3) == 90)
  }

  @Test func resetRadarHeightTracksTheVisibleRows() {
    #expect(FloatingPanelLayout.resetRadarHeight(showsProbability: false) == 42)
    #expect(FloatingPanelLayout.resetRadarHeight(showsProbability: true) == 75)
    #expect(FloatingPanelLayout.resetRadarIconSize == 10)
    #expect(FloatingPanelLayout.resetRadarIconFrame == 14)
  }

  @Test func feedbackHeightStartsAtContentSizeAndRejectsRunawayMeasurements() {
    #expect(
      FloatingPanelLayout.feedbackBannerHeight(isVisible: false, measuredHeight: 800) == 0
    )
    #expect(
      FloatingPanelLayout.feedbackBannerHeight(isVisible: true, measuredHeight: 0) == 78
    )
    #expect(
      FloatingPanelLayout.feedbackBannerHeight(isVisible: true, measuredHeight: 82.2) == 83
    )
    #expect(
      FloatingPanelLayout.feedbackBannerHeight(isVisible: true, measuredHeight: 747) == 96
    )
  }

  @Test func expandedHeightIsDerivedFromVisibleContentInsteadOfTheOldWindowFrame() {
    let fullHeight = FloatingPanelLayout.preferredExpandedHeight(
      visibleQuotaWindowCount: 1,
      showsRecentTasks: true,
      configuredTaskCount: 3,
      loadedTaskCount: 3,
      showsFeed: true,
      showsResetProbability: true,
      feedbackHeight: 0
    )
    let withoutTasks = FloatingPanelLayout.preferredExpandedHeight(
      visibleQuotaWindowCount: 1,
      showsRecentTasks: false,
      configuredTaskCount: 3,
      loadedTaskCount: 3,
      showsFeed: true,
      showsResetProbability: true,
      feedbackHeight: 0
    )
    let withoutRadar = FloatingPanelLayout.preferredExpandedHeight(
      visibleQuotaWindowCount: 1,
      showsRecentTasks: true,
      configuredTaskCount: 3,
      loadedTaskCount: 3,
      showsFeed: false,
      showsResetProbability: false,
      feedbackHeight: 0
    )

    #expect(FloatingPanelLayout.expandedPadding == 12)
    #expect(FloatingPanelLayout.expandedBottomPadding == 8)
    #expect(fullHeight == 294)
    #expect(withoutTasks < fullHeight)
    #expect(withoutRadar < fullHeight)
  }

  @Test @MainActor func feedbackBannerDoesNotExpandThePanelIntoEmptySpace() async throws {
    let suiteName = "FloatingPanelFeedbackHeightTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let databaseURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("CodexFloatFeedbackHeight-\(UUID().uuidString).sqlite")
    defer {
      for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(
          at: URL(fileURLWithPath: databaseURL.path + suffix)
        )
      }
    }

    let settings = AppSettings(defaults: defaults)
    settings.quotaDisplayMode = .standard
    settings.hoverExpansionEnabled = true
    let model = AppModel(
      store: try SQLiteStore(databaseURL: databaseURL),
      settings: settings
    )
    let controller = FloatingPanelController(
      model: model,
      placement: PanelPlacementStore(defaults: defaults),
      panelStateDefaults: defaults
    )
    #expect(FloatingPanelLayout.panelCornerRadius == 18)
    #expect(!controller.panel.isOpaque)
    #expect(controller.panel.backgroundColor == .clear)
    #expect(!controller.panel.hasShadow)
    #expect(controller.panel.contentView?.layer?.masksToBounds == true)
    #expect(controller.panel.contentView?.layer?.cornerRadius == 18)
    #expect(controller.panel.contentView?.layerContentsRedrawPolicy == .duringViewResize)
    #expect(controller.panel.contentView?.superview?.layer?.masksToBounds == true)
    #expect(controller.panel.contentView?.superview?.layer?.cornerRadius == 18)
    controller.panel.orderFrontRegardless()
    defer { controller.panel.orderOut(nil) }

    model.previewFeedback(.tiboReset)
    try await Task.sleep(for: .milliseconds(300))

    #expect((controller.panel.contentView?.fittingSize.height ?? 0) < 400)
    #expect(controller.panel.frame.height >= 250)
    #expect(controller.panel.frame.height < 400)
  }

  @Test @MainActor func firstHoverUsesOneStableFinalCanvasForTheLiquidReveal() async throws {
    let suiteName = "FloatingPanelFirstHoverTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let databaseURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("CodexFloatFirstHover-\(UUID().uuidString).sqlite")
    defer {
      for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(
          at: URL(fileURLWithPath: databaseURL.path + suffix)
        )
      }
    }

    let settings = AppSettings(defaults: defaults)
    settings.quotaDisplayMode = .standard
    settings.hoverExpansionEnabled = true
    let model = AppModel(
      store: try SQLiteStore(databaseURL: databaseURL),
      settings: settings
    )
    let controller = FloatingPanelController(
      model: model,
      placement: PanelPlacementStore(defaults: defaults),
      panelStateDefaults: defaults,
      reduceMotionProvider: { false }
    )
    controller.panel.orderFrontRegardless()
    defer { controller.panel.orderOut(nil) }

    // Give the collapsed SwiftUI root one run-loop turn to report the adaptive
    // height before hover expansion begins.
    try await Task.sleep(for: .milliseconds(120))
    let expectedHeight = FloatingPanelLayout.preferredExpandedHeight(
      visibleQuotaWindowCount: 0,
      showsRecentTasks: settings.showRecentTasks,
      configuredTaskCount: settings.recentTaskCount,
      loadedTaskCount: 0,
      showsFeed: settings.feedEnabled,
      showsResetProbability: settings.showResetProbability,
      feedbackHeight: 0
    )

    controller.setCollapsed(false, animated: true)
    var sampledHeights = [controller.panel.frame.height]
    var sampledWidths = [controller.panel.frame.width]
    for _ in 0..<30 {
      try await Task.sleep(for: .milliseconds(10))
      sampledHeights.append(controller.panel.frame.height)
      sampledWidths.append(controller.panel.frame.width)
    }

    #expect(abs(controller.panel.frame.height - expectedHeight) < 1)
    #expect(sampledHeights.allSatisfy { abs($0 - expectedHeight) < 1 })
    #expect(sampledWidths.allSatisfy { abs($0 - 340) < 1 })
  }

  @Test func menuBarDetailsAnchorBelowTheQuotaItem() {
    let anchor = NSRect(x: 500, y: 898, width: 134, height: 24)
    let visible = NSRect(x: 0, y: 87, width: 1_440, height: 811)
    let frame = FloatingPanelLayout.menuBarExpandedFrame(
      anchorFrame: anchor,
      panelSize: NSSize(width: 340, height: 280),
      visibleFrame: visible
    )

    #expect(frame.maxY == anchor.minY)
    #expect(frame.maxX == anchor.maxX)
    #expect(visible.contains(frame))
  }

  @Test @MainActor func menuBarRevealCanReverseBeforeItsCollapseFinishes() async throws {
    let suiteName = "MenuBarNativeRevealTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let databaseURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("CodexFloatMenuBarReveal-\(UUID().uuidString).sqlite")
    defer {
      for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(
          at: URL(fileURLWithPath: databaseURL.path + suffix)
        )
      }
    }

    let settings = AppSettings(defaults: defaults)
    settings.quotaDisplayMode = .menuBar
    let model = AppModel(
      store: try SQLiteStore(databaseURL: databaseURL),
      settings: settings
    )
    let controller = FloatingPanelController(
      model: model,
      placement: PanelPlacementStore(defaults: defaults),
      panelStateDefaults: defaults,
      reduceMotionProvider: { false }
    )

    controller.show(expanded: true)
    #expect(controller.panel.isVisible)
    controller.hide()
    #expect(controller.panel.isVisible)

    try await Task.sleep(for: .milliseconds(60))
    controller.show(expanded: true)
    try await Task.sleep(for: .milliseconds(180))
    #expect(controller.panel.isVisible)

    controller.hide()
    let hideClock = ContinuousClock()
    let hideStartedAt = hideClock.now
    while controller.panel.isVisible,
      hideStartedAt.duration(to: hideClock.now) < .seconds(1)
    {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!controller.panel.isVisible)
  }

  @Test func hoverExpansionKeepsTheTopLeftCornerFixedAndGrowsRightAndDown() {
    let visible = NSRect(x: 0, y: 87, width: 1_440, height: 811)
    let collapsed = NSRect(x: 420, y: 820, width: 174, height: 54)
    let expanded = FloatingPanelLayout.anchoredResizeFrame(
      currentFrame: collapsed,
      targetSize: NSSize(width: 340, height: 280),
      visibleFrame: visible
    )
    #expect(expanded.minX == collapsed.minX)
    #expect(expanded.maxY == collapsed.maxY)
    #expect(expanded.maxX > collapsed.maxX)
    #expect(expanded.minY < collapsed.minY)

    let collapsedNearRightEdge = NSRect(x: 1_246, y: 820, width: 174, height: 54)
    let expandedNearRightEdge = FloatingPanelLayout.anchoredResizeFrame(
      currentFrame: collapsedNearRightEdge,
      targetSize: NSSize(width: 340, height: 280),
      visibleFrame: visible
    )
    #expect(visible.contains(expandedNearRightEdge))
    #expect(expandedNearRightEdge.maxY == collapsedNearRightEdge.maxY)
  }

  @Test func standardCollapsedBarReservesRoomForAnAlignedExpandedPanel() {
    let visible = NSRect(x: 0, y: 87, width: 1_440, height: 811)
    let collapsedNearRightAndBottom = NSRect(
      x: 1_250,
      y: 95,
      width: FloatingPanelLayout.collapsedWidth,
      height: FloatingPanelLayout.collapsedHeight
    )
    let expandedSize = NSSize(width: 340, height: 291)
    let anchored = FloatingPanelLayout.standardCollapsedAnchorFrame(
      currentFrame: collapsedNearRightAndBottom,
      expandedSize: expandedSize,
      visibleFrame: visible
    )
    let expanded = FloatingPanelLayout.anchoredResizeFrame(
      currentFrame: anchored,
      targetSize: expandedSize,
      visibleFrame: visible
    )

    #expect(anchored.minX == visible.maxX - expandedSize.width)
    #expect(anchored.maxY == visible.minY + expandedSize.height)
    #expect(expanded.minX == anchored.minX)
    #expect(expanded.maxY == anchored.maxY)
    #expect(visible.contains(expanded))
  }

  @Test func collapseCanReturnToTheExactPreHoverRestingFrame() {
    let visible = NSRect(x: 0, y: 87, width: 1_440, height: 811)
    let resting = NSRect(
      x: 420,
      y: 820,
      width: FloatingPanelLayout.minimalCollapsedWidth,
      height: FloatingPanelLayout.minimalCollapsedHeight
    )
    let expanded = FloatingPanelLayout.anchoredResizeFrame(
      currentFrame: resting,
      targetSize: NSSize(width: 340, height: 280),
      visibleFrame: visible
    )
    let returned = FloatingPanelLayout.anchoredResizeFrame(
      currentFrame: resting,
      targetSize: resting.size,
      visibleFrame: visible
    )

    #expect(expanded != resting)
    #expect(returned == resting)
  }

  @Test func minimalDragTracksThePointerOneToOneAndStopsAtScreenEdges() {
    let visible = NSRect(x: 0, y: 87, width: 1_440, height: 811)
    let start = NSRect(x: 420, y: 700, width: 24, height: 54)
    let moved = FloatingPanelLayout.draggedFrame(
      from: start,
      translation: CGSize(width: 80, height: 35),
      visibleFrame: visible
    )
    #expect(moved.minX == start.minX + 80)
    #expect(moved.minY == start.minY - 35)

    let clamped = FloatingPanelLayout.draggedFrame(
      from: start,
      translation: CGSize(width: 2_000, height: 2_000),
      visibleFrame: visible
    )
    #expect(clamped.maxX == visible.maxX)
    #expect(clamped.minY == visible.minY)
  }

  @Test func rememberedPlacementKeepsTheTopLeftFixedAcrossPresentationSizes() {
    let visible = NSRect(x: 0, y: 87, width: 1_440, height: 811)
    let original = NSRect(x: 328, y: 692, width: 24, height: 54)
    let record = PanelPlacementGeometry.record(
      for: original,
      expandedWidth: 382,
      visibleFrame: visible
    )
    let restored = PanelPlacementGeometry.restoredFrame(
      from: record,
      panelHeight: 304,
      minimumWidth: 340,
      maximumWidth: 520,
      visibleFrame: visible
    )

    #expect(abs(restored.minX - original.minX) < 0.5)
    #expect(abs(restored.maxY - original.maxY) < 0.5)
    #expect(restored.width == 382)
    #expect(restored.height == 304)
  }

  @Test func firstPlacementUsesCodexLabelThenFallsBackToWindowTopLeft() {
    let visible = NSRect(x: 0, y: 87, width: 1_440, height: 811)
    let codexWindow = NSRect(x: 90, y: 120, width: 1_080, height: 720)
    let codexLabel = NSRect(x: 132, y: 782, width: 58, height: 24)
    let panelSize = NSSize(width: 340, height: 260)

    let besideLabel = PanelPlacementGeometry.initialFrame(
      panelSize: panelSize,
      visibleFrame: visible,
      codexWindowFrame: codexWindow,
      codexLabelFrame: codexLabel
    )
    #expect(besideLabel.minX == codexLabel.maxX + 10)
    #expect(besideLabel.maxY == codexLabel.maxY)

    let collapsedSidebarFallback = PanelPlacementGeometry.initialFrame(
      panelSize: panelSize,
      visibleFrame: visible,
      codexWindowFrame: codexWindow,
      codexLabelFrame: nil
    )
    #expect(collapsedSidebarFallback.minX == codexWindow.minX + 12)
    #expect(collapsedSidebarFallback.maxY == codexWindow.maxY - 38)
  }

  @Test @MainActor func standardAndMinimalModesRememberIndependentPositions() throws {
    let suiteName = "PanelPlacementModeTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let visible = try #require(NSScreen.main?.visibleFrame)
    let standardFrame = NSRect(
      x: visible.minX + 120,
      y: visible.maxY - 290,
      width: 340,
      height: 260
    )
    let minimalFrame = NSRect(
      x: visible.minX + 530,
      y: visible.maxY - 74,
      width: 24,
      height: 54
    )
    let store = PanelPlacementStore(defaults: defaults)
    store.saveUserPlacement(frame: standardFrame, mode: .standard, expandedWidth: 360)
    store.saveUserPlacement(frame: minimalFrame, mode: .minimal, expandedWidth: 410)

    let standardWindow = NSWindow(
      contentRect: .zero,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    let minimalWindow = NSWindow(
      contentRect: .zero,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    let fallback = NSRect(
      x: visible.minX + 12,
      y: visible.maxY - 272,
      width: 340,
      height: 260
    )
    #expect(
      store.restore(
        panel: standardWindow,
        mode: .standard,
        defaultSize: NSSize(width: 340, height: 260),
        minimumWidth: 340,
        maximumWidth: 520,
        initialFrame: fallback
      ))
    #expect(
      store.restore(
        panel: minimalWindow,
        mode: .minimal,
        defaultSize: NSSize(width: 340, height: 260),
        minimumWidth: 340,
        maximumWidth: 520,
        initialFrame: fallback
      ))

    #expect(abs(standardWindow.frame.minX - standardFrame.minX) < 0.5)
    #expect(abs(standardWindow.frame.maxY - standardFrame.maxY) < 0.5)
    #expect(standardWindow.frame.width == 360)
    #expect(abs(minimalWindow.frame.minX - minimalFrame.minX) < 0.5)
    #expect(abs(minimalWindow.frame.maxY - minimalFrame.maxY) < 0.5)
    #expect(minimalWindow.frame.width == 410)
  }

  @Test @MainActor func firstUseDoesNotCreateRememberedUserPlacement() throws {
    let suiteName = "PanelPlacementFirstUseTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let visible = try #require(NSScreen.main?.visibleFrame)
    let initial = NSRect(
      x: visible.minX + 12,
      y: visible.maxY - 272,
      width: 340,
      height: 260
    )
    let window = NSWindow(
      contentRect: .zero,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    let restored = PanelPlacementStore(defaults: defaults).restore(
      panel: window,
      mode: .standard,
      defaultSize: initial.size,
      minimumWidth: 340,
      maximumWidth: 520,
      initialFrame: initial
    )

    #expect(!restored)
    #expect(window.frame == initial)
  }

  @Test @MainActor func switchingDisplayModesRestoresEachModesTopLeftAnchor() async throws {
    let suiteName = "PanelPlacementSwitchTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let databaseURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("CodexFloatPanelSwitch-\(UUID().uuidString).sqlite")
    defer {
      for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(
          at: URL(fileURLWithPath: databaseURL.path + suffix)
        )
      }
    }
    let visible = try #require(NSScreen.main?.visibleFrame)
    let standardAnchor = NSRect(
      x: visible.minX + 180,
      y: visible.maxY - 314,
      width: 340,
      height: 280
    )
    let minimalAnchor = NSRect(
      x: visible.minX + 620,
      y: visible.maxY - 84,
      width: 24,
      height: 54
    )
    let placement = PanelPlacementStore(defaults: defaults)
    placement.saveUserPlacement(
      frame: standardAnchor,
      mode: .standard,
      expandedWidth: 340
    )
    placement.saveUserPlacement(
      frame: minimalAnchor,
      mode: .minimal,
      expandedWidth: 380
    )
    let settings = AppSettings(defaults: defaults)
    settings.quotaDisplayMode = .standard
    settings.hoverExpansionEnabled = true
    let model = AppModel(
      store: try SQLiteStore(databaseURL: databaseURL),
      settings: settings
    )
    let controller = FloatingPanelController(
      model: model,
      placement: placement,
      panelStateDefaults: defaults
    )

    #expect(abs(controller.panel.frame.minX - standardAnchor.minX) < 0.5)
    #expect(abs(controller.panel.frame.maxY - standardAnchor.maxY) < 0.5)

    settings.quotaDisplayMode = .minimal
    try await Task.sleep(for: .milliseconds(80))
    #expect(abs(controller.panel.frame.minX - minimalAnchor.minX) < 0.5)
    #expect(abs(controller.panel.frame.maxY - minimalAnchor.maxY) < 0.5)

    settings.quotaDisplayMode = .standard
    try await Task.sleep(for: .milliseconds(80))
    #expect(abs(controller.panel.frame.minX - standardAnchor.minX) < 0.5)
    #expect(abs(controller.panel.frame.maxY - standardAnchor.maxY) < 0.5)
  }

  @Test @MainActor func menuBarQuotaIndicatorFitsNativeStatusItem() {
    let indicator = MenuBarQuotaIndicator.image(
      remainingPercent: 62,
      countdown: "5天",
      lowThreshold: 20,
      criticalThreshold: 5
    )

    #expect(indicator.size == MenuBarQuotaIndicator.Layout.imageSize)
    #expect(MenuBarQuotaIndicator.Layout.imageSize == NSSize(width: 26, height: 18))
    #expect(MenuBarQuotaIndicator.Layout.statusItemLength == 30)
    let parts = MenuBarQuotaIndicator.percentageParts(remainingPercent: 79)
    let visualGap =
      parts.digitsGlyphFrame.minX
      - MenuBarQuotaIndicator.Layout.trackFrame.maxX
    #expect(visualGap >= 2.5)
    #expect(visualGap <= 4.5)
    #expect(
      MenuBarQuotaIndicator.Layout.imageSize.width
        >= MenuBarQuotaIndicator.Layout.valueFrame.maxX)
    #expect(
      MenuBarQuotaIndicator.Layout.imageSize.height
        >= MenuBarQuotaIndicator.Layout.valueFrame.maxY)
  }

  @Test @MainActor func menuBarQuotaIndicatorResolvesBothSystemAppearances() throws {
    let light = try #require(NSAppearance(named: .aqua))
    let dark = try #require(NSAppearance(named: .darkAqua))

    func luminance(of color: NSColor, appearance: NSAppearance) -> CGFloat {
      var result: CGFloat = 0
      appearance.performAsCurrentDrawingAppearance {
        guard let resolved = color.usingColorSpace(.sRGB) else { return }
        result = 0.2126 * resolved.redComponent
          + 0.7152 * resolved.greenComponent
          + 0.0722 * resolved.blueComponent
      }
      return result
    }

    #expect(MenuBarQuotaIndicator.AppearanceMode.resolve(light) == .light)
    #expect(MenuBarQuotaIndicator.AppearanceMode.resolve(dark) == .dark)
    #expect(
      MenuBarQuotaIndicator.AppearanceMode.light.hoverBackgroundAlpha
        < MenuBarQuotaIndicator.AppearanceMode.dark.hoverBackgroundAlpha
    )

    let semanticParts = MenuBarQuotaIndicator.percentageParts(remainingPercent: 62)
    let semanticTextColor = try #require(
      semanticParts.digits.attribute(.foregroundColor, at: 0, effectiveRange: nil)
        as? NSColor
    )
    #expect(luminance(of: semanticTextColor, appearance: light) < 0.35)
    #expect(luminance(of: semanticTextColor, appearance: dark) > 0.65)

    let lightImage = MenuBarQuotaIndicator.image(
      remainingPercent: 62,
      countdown: "5天",
      lowThreshold: 20,
      criticalThreshold: 5,
      appearance: light,
      isHighlighted: true
    )
    let darkImage = MenuBarQuotaIndicator.image(
      remainingPercent: 62,
      countdown: "5天",
      lowThreshold: 20,
      criticalThreshold: 5,
      appearance: dark,
      isHighlighted: true
    )
    #expect(lightImage.tiffRepresentation != nil)
    #expect(darkImage.tiffRepresentation != nil)
  }

  @Test @MainActor func menuBarQuotaKeepsDigitsCenteredAndAddsASmallerPercentSymbol() throws {
    let parts = MenuBarQuotaIndicator.percentageParts(remainingPercent: 79)
    let symbol = try #require(parts.symbol)
    let symbolFrame = try #require(parts.symbolFrame)
    let digitFont = try #require(
      parts.digits.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    )
    let percentFont = try #require(
      symbol.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    )

    #expect(parts.digits.string == "79")
    #expect(symbol.string == "%")
    #expect(percentFont.pointSize < digitFont.pointSize)
    #expect(
      MenuBarQuotaIndicator.Layout.valueFrame.midX
        == MenuBarQuotaIndicator.Layout.countdownFrame.midX)
    #expect(symbolFrame.minX - parts.digitsGlyphFrame.maxX >= 0.5)
    #expect(symbolFrame.minX < MenuBarQuotaIndicator.Layout.imageSize.width)
    #expect(symbolFrame.maxX <= MenuBarQuotaIndicator.Layout.imageSize.width)
    #expect(symbolFrame.maxY <= MenuBarQuotaIndicator.Layout.imageSize.height)
  }

  @Test @MainActor func threeDigitMenuBarPercentageStillFits() throws {
    let parts = MenuBarQuotaIndicator.percentageParts(remainingPercent: 100)
    let symbolFrame = try #require(parts.symbolFrame)

    #expect(parts.digits.string == "100")
    #expect(parts.symbol?.string == "%")
    #expect(parts.digits.size().width <= MenuBarQuotaIndicator.Layout.valueFrame.width)
    #expect(symbolFrame.minX - parts.digitsGlyphFrame.maxX >= 0.5)
    #expect(symbolFrame.maxX <= MenuBarQuotaIndicator.Layout.imageSize.width)
  }

  @Test func statusItemIsExclusiveToMenuBarDisplayMode() {
    #expect(!MenuBarStatusItemVisibility.shouldShow(for: .standard))
    #expect(!MenuBarStatusItemVisibility.shouldShow(for: .minimal))
    #expect(MenuBarStatusItemVisibility.shouldShow(for: .menuBar))
  }

  @Test func menuBarStatusItemStartsInsideTheVisibleSystemStatusArea() throws {
    let suiteName = "MenuBarStatusItemPlacementTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)

    MenuBarStatusItemPlacement.prepareVisiblePosition(
      defaults: defaults,
      screenFrame: screenFrame
    )
    #expect(
      defaults.integer(forKey: MenuBarStatusItemPlacement.preferredPositionKey) == 1090)

    defaults.set(1180, forKey: MenuBarStatusItemPlacement.preferredPositionKey)
    MenuBarStatusItemPlacement.rememberCurrentPosition(defaults: defaults)
    defaults.removeObject(forKey: MenuBarStatusItemPlacement.preferredPositionKey)
    MenuBarStatusItemPlacement.prepareVisiblePosition(
      defaults: defaults,
      screenFrame: screenFrame
    )
    #expect(defaults.integer(forKey: MenuBarStatusItemPlacement.preferredPositionKey) == 1180)
  }

  @Test @MainActor func movingExpandedPanelUpdatesTheSharedAnchorBeforeSmoothCollapse() async throws
  {
    let suiteName = "FloatingPanelMotionTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let databaseURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("CodexFloatPanelMotion-\(UUID().uuidString).sqlite")
    defer {
      for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(
          at: URL(fileURLWithPath: databaseURL.path + suffix)
        )
      }
    }

    let settings = AppSettings(defaults: defaults)
    settings.quotaDisplayMode = .minimal
    settings.hoverExpansionEnabled = true
    let model = AppModel(
      store: try SQLiteStore(databaseURL: databaseURL),
      settings: settings
    )
    let controller = FloatingPanelController(
      model: model,
      placement: PanelPlacementStore(defaults: defaults),
      panelStateDefaults: defaults,
      reduceMotionProvider: { false }
    )
    let visibleFrame = try #require(NSScreen.main?.visibleFrame)
    let restingFrame = NSRect(
      x: visibleFrame.minX + 180,
      y: visibleFrame.maxY - 180,
      width: FloatingPanelLayout.minimalCollapsedWidth,
      height: FloatingPanelLayout.minimalCollapsedHeight
    )
    controller.panel.setFrame(restingFrame, display: true)
    controller.windowDidMove(Notification(name: NSWindow.didMoveNotification))
    controller.panel.orderFrontRegardless()
    defer { controller.panel.orderOut(nil) }
    #expect(!controller.panel.isMovableByWindowBackground)

    controller.handleHover(true)
    let initialExpansionClock = ContinuousClock()
    let initialExpansionStart = initialExpansionClock.now
    var initialExpansionFrames = [controller.panel.frame]
    while controller.isSurfaceTransitionInFlight,
      initialExpansionStart.duration(to: initialExpansionClock.now) < .seconds(1)
    {
      try await Task.sleep(for: .milliseconds(8))
      initialExpansionFrames.append(controller.panel.frame)
    }
    #expect(controller.panel.frame.width >= 340)
    let initialDistinctWidths = Set(initialExpansionFrames.map { Int($0.width.rounded()) })
    #expect(initialDistinctWidths == Set([340]))
    #expect(initialExpansionFrames.allSatisfy { abs($0.minX - restingFrame.minX) < 1.0 })
    #expect(initialExpansionFrames.allSatisfy { abs($0.maxY - restingFrame.maxY) < 1.0 })
    #expect(
      zip(initialExpansionFrames, initialExpansionFrames.dropFirst()).allSatisfy {
        previous, next in next.width + 0.5 >= previous.width
      })
    controller.setCollapsed(true, animated: false)
    controller.panel.setFrame(restingFrame, display: true, animate: false)
    controller.windowDidMove(Notification(name: NSWindow.didMoveNotification))

    let dragTranslation = CGSize(width: 72, height: 28)
    let draggedRestingFrame = FloatingPanelLayout.draggedFrame(
      from: restingFrame,
      translation: dragTranslation,
      visibleFrame: visibleFrame
    )
    controller.handleMinimalDrag(translation: dragTranslation, ended: false)
    #expect(controller.panel.frame == draggedRestingFrame)
    controller.handleMinimalDrag(translation: dragTranslation, ended: true)
    #expect(controller.panel.frame == draggedRestingFrame)

    // Reversing direction mid-flight keeps the final-size window stable. Only
    // the liquid clipping boundary reverses, so content never receives a new width.
    controller.setCollapsed(false, animated: true)
    try await Task.sleep(for: .milliseconds(90))
    let interruptedExpansionFrame = controller.panel.frame
    let canObserveMidFlightReversal =
      controller.isSurfaceTransitionInFlight
      && interruptedExpansionFrame.width > draggedRestingFrame.width
      && interruptedExpansionFrame.width < 340
    if canObserveMidFlightReversal {
      controller.setCollapsed(true, animated: true)
      let reversalClock = ContinuousClock()
      let reversalStart = reversalClock.now
      var reversalFrames = [controller.panel.frame]
      while controller.isSurfaceTransitionInFlight,
        reversalStart.duration(to: reversalClock.now) < .seconds(1)
      {
        try await Task.sleep(for: .milliseconds(8))
        reversalFrames.append(controller.panel.frame)
      }
      #expect(abs(controller.panel.frame.width - draggedRestingFrame.width) < 0.5)
      #expect(reversalFrames.allSatisfy { abs($0.minX - draggedRestingFrame.minX) < 1.0 })
      #expect(reversalFrames.allSatisfy { abs($0.maxY - draggedRestingFrame.maxY) < 1.0 })
      #expect(
        zip(reversalFrames, reversalFrames.dropFirst()).allSatisfy { previous, next in
          next.width <= previous.width + 0.5
        })
    } else {
      #expect(abs(interruptedExpansionFrame.width - 340) < 0.5)
      #expect(abs(interruptedExpansionFrame.minX - draggedRestingFrame.minX) < 1.0)
      #expect(abs(interruptedExpansionFrame.maxY - draggedRestingFrame.maxY) < 1.0)
      controller.setCollapsed(true, animated: false)
      #expect(abs(controller.panel.frame.width - draggedRestingFrame.width) < 0.5)
    }

    controller.setCollapsed(false, animated: true)
    let expansionClock = ContinuousClock()
    let expansionStart = expansionClock.now
    while controller.isSurfaceTransitionInFlight,
      expansionStart.duration(to: expansionClock.now) < .seconds(1)
    {
      try await Task.sleep(for: .milliseconds(8))
    }
    let expandedFrame = controller.panel.frame
    #expect(controller.panel.isMovableByWindowBackground)
    #expect(abs(expandedFrame.minX - draggedRestingFrame.minX) < 0.5)
    #expect(abs(expandedFrame.maxY - draggedRestingFrame.maxY) < 0.5)

    let movedExpandedFrame = expandedFrame.offsetBy(dx: 64, dy: -36)
    controller.panel.setFrame(movedExpandedFrame, display: true, animate: false)
    controller.windowDidMove(Notification(name: NSWindow.didMoveNotification))
    let expectedRestingFrame = FloatingPanelLayout.anchoredResizeFrame(
      currentFrame: movedExpandedFrame,
      targetSize: draggedRestingFrame.size,
      visibleFrame: visibleFrame
    )

    controller.setCollapsed(true, animated: true)
    let clock = ContinuousClock()
    let startedAt = clock.now
    var samples = [controller.panel.frame]
    while controller.isCollapseAnimationInFlight,
      startedAt.duration(to: clock.now) < .seconds(1)
    {
      try await Task.sleep(for: .milliseconds(8))
      samples.append(controller.panel.frame)
    }

    let finalFrame = controller.panel.frame
    let elapsed = startedAt.duration(to: clock.now)
    #expect(!controller.isCollapseAnimationInFlight)
    #expect(!controller.panel.isMovableByWindowBackground)
    #expect(elapsed < .milliseconds(600))
    #expect(abs(finalFrame.minX - expectedRestingFrame.minX) < 0.5)
    #expect(abs(finalFrame.minY - expectedRestingFrame.minY) < 0.5)
    #expect(abs(finalFrame.width - expectedRestingFrame.width) < 0.5)
    #expect(abs(finalFrame.height - expectedRestingFrame.height) < 0.5)
    #expect(Set(samples.dropLast().map { Int($0.width.rounded()) }) == Set([340]))
    #expect(samples.allSatisfy { abs($0.minX - expectedRestingFrame.minX) < 1.0 })
    #expect(samples.allSatisfy { abs($0.maxY - expectedRestingFrame.maxY) < 1.0 })
    #expect(
      zip(samples, samples.dropFirst()).allSatisfy { previous, next in
        next.width <= previous.width + 0.5 && next.height <= previous.height + 0.5
      })
  }
}
