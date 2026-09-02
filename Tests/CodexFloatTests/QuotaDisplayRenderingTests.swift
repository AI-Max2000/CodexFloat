import AppKit
import CodexQuotaCore
import Foundation
import LocalStore
import SwiftUI
import Testing

@testable import CodexFloat

// Part of the serialized AppKit suite: opening panels concurrently would make
// hover and layout assertions depend on the other test's pointer tracking.
extension FloatingPanelLayoutTests {
  @Test @MainActor func fiveHourToggleKeepsRestingAnchorsAndAdaptsExpandedHeight() async throws {
    let suite = "QuotaDisplayRendering.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: directory)
    }
    let store = try SQLiteStore(databaseURL: directory.appendingPathComponent("fixture.sqlite"))
    let previewNow = Date()
    let previewWindows = QuotaDisplayFixture.windows.map { window in
      RateLimitWindow(
        id: window.id, limitID: window.limitID, limitName: nil, windowName: window.windowName,
        usedPercent: window.usedPercent, windowDurationMinutes: window.windowDurationMinutes,
        resetsAt: window.resetsAt.map {
          previewNow.addingTimeInterval($0.timeIntervalSince(QuotaDisplayFixture.now))
        },
        reachedType: nil)
    }
    try await store.save(
      snapshot: QuotaSnapshot(
        planType: "free", windows: previewWindows, resetCreditCount: 0, resetCredits: [],
        creditBalance: nil, hasCredits: nil, spendControlReached: nil, observedAt: previewNow))
    let settings = AppSettings(defaults: defaults)
    settings.showRecentTasks = false
    settings.feedEnabled = false
    settings.showResetProbability = false
    settings.hoverCollapseDelay = 2
    let model = AppModel(store: store, settings: settings)
    // This does not start live polling, notifications or a Codex process.
    await model.loadCache()
    #expect(QuotaDisplayPolicy(snapshot: model.quota, showFiveHour: false).hasFiveHourWindow)

    for mode in [QuotaDisplayMode.standard, .minimal] {
      settings.quotaDisplayMode = mode
      settings.showFiveHourQuota = false
      let controller = FloatingPanelController(
        model: model, placement: PanelPlacementStore(defaults: defaults),
        panelStateDefaults: defaults, reduceMotionProvider: { false })
      let visible = try #require(NSScreen.main?.visibleFrame)
      controller.panel.setFrameOrigin(NSPoint(x: visible.minX + 120, y: visible.maxY - 300))
      controller.windowDidMove(Notification(name: NSWindow.didMoveNotification))
      controller.panel.orderFrontRegardless()
      defer { controller.panel.orderOut(nil) }
      try await Task.sleep(for: .milliseconds(80))
      let restingFrame = controller.panel.frame
      settings.showFiveHourQuota = true
      try await Task.sleep(for: .milliseconds(80))
      #expect(controller.panel.frame == restingFrame)
      controller.setCollapsed(false, animated: true)
      let clock = ContinuousClock()
      let start = clock.now
      while controller.isSurfaceTransitionInFlight, start.duration(to: clock.now) < .seconds(2) {
        #expect(abs(controller.panel.frame.minX - restingFrame.minX) < 1)
        #expect(abs(controller.panel.frame.maxY - restingFrame.maxY) < 1)
        try await Task.sleep(for: .milliseconds(16))
      }
      #expect(!controller.isSurfaceTransitionInFlight)
      let doubleHeight = controller.panel.frame.height
      settings.showFiveHourQuota = false
      try await Task.sleep(for: .milliseconds(120))
      // One row is 99 pt of content, clamped to the existing 104 pt panel minimum.
      #expect(doubleHeight == 137)
      #expect(controller.panel.frame.height == 104)
      settings.showFiveHourQuota = true
      try await Task.sleep(for: .milliseconds(120))
      #expect(abs(controller.panel.frame.height - doubleHeight) < 1)
      controller.setCollapsed(true, animated: true)
      let collapseStart = clock.now
      while controller.isSurfaceTransitionInFlight,
        collapseStart.duration(to: clock.now) < .seconds(2)
      {
        try await Task.sleep(for: .milliseconds(16))
      }
      #expect(controller.panel.frame == restingFrame)
    }

    // Optional native-view evidence, generated only when explicitly requested.
    // All values above and in these images are fixtures, never account data.
    if let outputPath = ProcessInfo.processInfo.environment["CODEX_FLOAT_QUOTA_PREVIEW_DIR"] {
      let output = URL(fileURLWithPath: outputPath, isDirectory: true)
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      settings.showFiveHourQuota = true
      for language in AppLanguage.allCases {
        settings.appLanguage = language
        for dark in [false, true] {
          let panelState = PanelUIState(defaults: defaults, initiallyCollapsed: false)
          panelState.expandedCanvasSize = NSSize(width: 340, height: 137)
          settings.quotaDisplayMode = .standard
          let content = QuotaDisplayPreview(model: model, state: panelState, dark: dark)
          let hosting = NSHostingView(rootView: content)
          let frame = NSRect(x: 0, y: 0, width: 396, height: 344)
          let window = NSWindow(
            contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
          window.isReleasedWhenClosed = false
          window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
          window.contentView = hosting
          window.setFrame(frame, display: true)
          window.orderFrontRegardless()
          defer { window.orderOut(nil) }
          try await Task.sleep(for: .milliseconds(120))
          hosting.layoutSubtreeIfNeeded()
          let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
          hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
          let data = try #require(bitmap.representation(using: .png, properties: [:]))
          let name = "quota-display-\(language.rawValue)-\(dark ? "dark" : "light").png"
          try data.write(to: output.appendingPathComponent(name))
        }
      }
    }
  }
}

@MainActor private struct QuotaDisplayPreview: View {
  let model: AppModel
  let state: PanelUIState
  let dark: Bool
  private var entries: [QuotaDisplayEntry] {
    QuotaDisplayPolicy(snapshot: model.quota, showFiveHour: true).compact
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("按实际窗口展示 · Free 示例数据")
        .font(.system(size: 13, weight: .semibold))
      HStack(alignment: .center, spacing: 16) {
        DualCompactQuotaView(
          entries: entries,
          planName: model.quota.map(
            AppStrings(language: model.settings.appLanguage).compactPlanName) ?? "",
          resetCount: model.quota?.resetCreditCount,
          freshnessColor: model.quota?.freshness == .fresh ? .green : .orange,
          lowThreshold: 20, criticalThreshold: 5, language: model.settings.appLanguage
        )
        .padding(8).frame(width: 174, height: 54)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
          RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.10), lineWidth: 0.7))
        DualMinimalQuotaView(
          entries: entries, lowThreshold: 20, criticalThreshold: 5,
          freshness: model.quota?.freshness,
          language: model.settings.appLanguage
        ).frame(width: 36, height: 54)
        Image(
          nsImage: MenuBarDualQuotaIndicator.image(
            entries: entries, strings: AppStrings(language: model.settings.appLanguage),
            now: Date(), lowThreshold: 20, criticalThreshold: 5,
            appearance: NSAppearance(named: dark ? .darkAqua : .aqua)!))
      }
      Text("展开后 · 分别显示剩余百分比和重置时间")
        .font(.system(size: 11)).foregroundStyle(.secondary)
      FloatingPanelView(
        model: model, settings: model.settings, panelState: state,
        onHoverChanged: { _ in }, onMinimalDragChanged: { _, _ in }, onRefresh: {},
        onOpenSettings: {}, onHide: {}, onPreferredExpandedHeightChanged: { _ in }
      )
      .frame(width: 340, height: 137)
      .clipShape(RoundedRectangle(cornerRadius: 18))
      Text("默认仅每周；开启后左侧为 5 小时、右侧为每周。")
        .font(.system(size: 10)).foregroundStyle(.secondary)
    }
    .padding(24)
    .frame(width: 396, height: 344, alignment: .topLeading)
    .background(Color(nsColor: dark ? .windowBackgroundColor : .controlBackgroundColor))
    .environment(\.colorScheme, dark ? .dark : .light)
  }
}
