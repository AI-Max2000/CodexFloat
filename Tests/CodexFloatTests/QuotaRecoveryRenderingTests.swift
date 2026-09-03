import AppKit
import CodexQuotaCore
import Foundation
import LocalStore
import SwiftUI
import Testing

@testable import CodexFloat

extension FloatingPanelLayoutTests {
  @Test @MainActor func excludedRecoveryCasesKeepOriginalPresentations() async throws {
    let suite = "RecoveryFallbackRendering.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: directory)
    }
    let store = try SQLiteStore(databaseURL: directory.appendingPathComponent("fixture.sqlite"))
    let settings = AppSettings(defaults: defaults)
    settings.showRecentTasks = false
    settings.feedEnabled = false
    settings.showResetProbability = false
    settings.followCodexWindow = false
    settings.notificationsEnabled = false
    settings.hoverCollapseDelay = 2
    let now = Date()
    for noResets in [false, true] {
      let snapshot = RecoveryFixture.snapshot(
        windows: [
          RecoveryFixture.window(minutes: 300, resetAt: now.addingTimeInterval(3_600)),
          RecoveryFixture.window(
            remaining: noResets ? 0 : 80, id: "codex:secondary",
            resetAt: now.addingTimeInterval(86_400)),
        ], count: noResets ? 0 : 2, observedAt: now)
      let model = AppModel(store: store, settings: settings, initialQuota: snapshot)
      #expect(model.quotaRecovery == nil)
      #expect(model.transientFeedback == nil)
      for language in AppLanguage.allCases {
        settings.appLanguage = language
        for showFiveHour in [false, true] {
          settings.showFiveHourQuota = showFiveHour
          for mode in [QuotaDisplayMode.standard, .minimal, .menuBar] {
            settings.quotaDisplayMode = mode
            let styles: [MinimalMeterStyle] =
              mode == .minimal ? [.vertical, .horizontal, .ring] : [.vertical]
            for style in styles {
              settings.minimalMeterAppearance.style = style
              let controller = FloatingPanelController(
                model: model, placement: PanelPlacementStore(defaults: defaults),
                panelStateDefaults: defaults, reduceMotionProvider: { true })
              controller.panel.orderFrontRegardless()
              defer { controller.panel.orderOut(nil) }
              try await Task.sleep(for: .milliseconds(60))
              let resting = controller.panel.frame
              controller.setCollapsed(false, animated: false)
              try await Task.sleep(for: .milliseconds(80))
              // The legacy height contains just the header and quota rows:
              // no recovery card, button, or extra warning space.
              let expectedHeight = max(
                104,
                FloatingPanelLayout.preferredExpandedHeight(
                  visibleQuotaWindowCount: showFiveHour ? 2 : 1,
                  showsRecentTasks: false, configuredTaskCount: 3, loadedTaskCount: 0,
                  showsFeed: false, showsResetProbability: false, feedbackHeight: 0))
              #expect(abs(controller.panel.frame.height - expectedHeight) < 1)
              if language == .simplifiedChinese, showFiveHour,
                let export = ProcessInfo.processInfo.environment["CODEX_FLOAT_RECOVERY_PREVIEW_DIR"]
              {
                let output = URL(fileURLWithPath: export, isDirectory: true)
                try FileManager.default.createDirectory(
                  at: output, withIntermediateDirectories: true)
                let view = try #require(controller.panel.contentView)
                view.layoutSubtreeIfNeeded()
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                try data.write(
                  to: output.appendingPathComponent(
                    "fallback-\(noResets ? "no-resets" : "five-hour")-\(mode.rawValue)-\(style.rawValue).png"
                  ))
              }
              if mode != .menuBar {
                controller.setCollapsed(true, animated: false)
                try await Task.sleep(for: .milliseconds(30))
                #expect(controller.panel.frame == resting)
              }
            }
          }
        }
      }
    }
  }

  @Test @MainActor func recoveryUsesAdaptiveHeightAndKeepsAllRestingAnchors() async throws {
    let suite = "RecoveryRendering.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: directory)
    }
    let store = try SQLiteStore(databaseURL: directory.appendingPathComponent("fixture.sqlite"))
    let settings = AppSettings(defaults: defaults)
    settings.showRecentTasks = false
    settings.feedEnabled = false
    settings.showResetProbability = false
    settings.followCodexWindow = false
    settings.notificationsEnabled = false
    settings.hoverCollapseDelay = 2
    let now = Date()
    let snapshot = RecoveryFixture.snapshot(
      windows: [RecoveryFixture.window(resetAt: now.addingTimeInterval(3_600))],
      count: 2, observedAt: now)
    let model = AppModel(store: store, settings: settings, initialQuota: snapshot)
    let visible = try #require(NSScreen.main?.visibleFrame)
    let exportPath = ProcessInfo.processInfo.environment["CODEX_FLOAT_RECOVERY_PREVIEW_DIR"]

    for mode in [QuotaDisplayMode.standard, .minimal, .menuBar] {
      for language in AppLanguage.allCases {
        settings.quotaDisplayMode = mode
        settings.appLanguage = language
        let recovery = try #require(model.quotaRecovery)
        let popoverHost = NSHostingView(
          rootView: QuotaRecoveryView(state: recovery, language: language, action: {})
            .padding(8).frame(width: 350).fixedSize(horizontal: false, vertical: true))
        #expect(popoverHost.fittingSize.width == 350)
        #expect(popoverHost.fittingSize.height > 90)
        #expect(popoverHost.fittingSize.height < 220)
        let styles: [MinimalMeterStyle] =
          mode == .minimal ? [.vertical, .horizontal, .ring] : [.vertical]
        for style in styles {
          settings.minimalMeterAppearance.style = style
          let controller = FloatingPanelController(
            model: model, placement: PanelPlacementStore(defaults: defaults),
            panelStateDefaults: defaults, reduceMotionProvider: { false })
          controller.panel.setFrameOrigin(NSPoint(x: visible.minX + 100, y: visible.minY + 8))
          controller.windowDidMove(Notification(name: NSWindow.didMoveNotification))
          controller.panel.orderFrontRegardless()
          defer { controller.panel.orderOut(nil) }
          try await Task.sleep(for: .milliseconds(80))
          let resting = controller.panel.frame
          controller.setCollapsed(false, animated: mode != .menuBar)
          let clock = ContinuousClock()
          let start = clock.now
          while controller.isSurfaceTransitionInFlight, start.duration(to: clock.now) < .seconds(2)
          {
            try await Task.sleep(for: .milliseconds(16))
          }
          try await Task.sleep(for: .milliseconds(100))
          #expect(!controller.isSurfaceTransitionInFlight)
          #expect(controller.panel.frame.height < 330)
          #expect(controller.panel.frame.height > 180)
          if mode != .menuBar {
            // Bottom-edge expansion grows upward, never pushes the resting seed.
            #expect(abs(controller.panel.frame.minY - resting.minY) < 1)
            controller.setCollapsed(true, animated: true)
            let collapseStart = clock.now
            while controller.isSurfaceTransitionInFlight,
              collapseStart.duration(to: clock.now) < .seconds(2)
            {
              try await Task.sleep(for: .milliseconds(16))
            }
            #expect(controller.panel.frame == resting)
          }
        }
      }
    }

    // Render production views with synthetic values, without network, account
    // reads, OS notifications, or opening the user's real Codex settings.
    if let exportPath {
      let output = URL(fileURLWithPath: exportPath, isDirectory: true)
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      for language in AppLanguage.allCases {
        for dark in [false, true] {
          settings.appLanguage = language
          let state = try #require(model.quotaRecovery)
          let content = RecoveryPreview(state: state, model: model, dark: dark)
          let hosting = NSHostingView(rootView: content)
          let frame = NSRect(x: 0, y: 0, width: 410, height: 450)
          let window = NSWindow(
            contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
          window.isReleasedWhenClosed = false
          window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
          window.contentView = hosting
          window.setFrame(frame, display: true)
          window.orderFrontRegardless()
          defer { window.orderOut(nil) }
          try await Task.sleep(for: .milliseconds(100))
          hosting.layoutSubtreeIfNeeded()
          let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
          hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
          let data = try #require(bitmap.representation(using: .png, properties: [:]))
          try data.write(
            to: output.appendingPathComponent(
              "recovery-\(language.rawValue)-\(dark ? "dark" : "light").png"))
        }
      }
    }
  }
}

@MainActor private struct RecoveryPreview: View {
  let state: QuotaRecoveryState
  let model: AppModel
  let dark: Bool
  var strings: AppStrings { AppStrings(language: model.settings.appLanguage) }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Codex Float · 额度耗尽处理").font(.system(size: 17, weight: .bold))
      Text("原生视图测试 · 固定样本，非真实账号数据")
        .font(.system(size: 10)).foregroundStyle(.secondary)
      HStack(spacing: 24) {
        CompactQuotaRecoveryView(state: state, language: model.settings.appLanguage, action: {})
          .padding(8).frame(width: 174, height: 54)
          .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        Image(
          nsImage: MenuBarRecoveryIndicator.image(
            state: state, strings: strings,
            appearance: NSAppearance(named: dark ? .darkAqua : .aqua)!)
        )
        .padding(8).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
      }
      QuotaRecoveryView(state: state, language: model.settings.appLanguage, action: {})
      QuotaRecoveryView(
        state: QuotaRecoveryState(kind: .needsRefresh, windows: state.windows, resets: .unknown),
        language: model.settings.appLanguage, action: {})
      Spacer(minLength: 0)
    }
    .padding(24)
    .frame(width: 410, height: 450, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
    .environment(\.colorScheme, dark ? .dark : .light)
  }
}
