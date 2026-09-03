import AppKit
import CodexQuotaCore
import LocalStore
import Testing

@testable import CodexFloat

@Suite("Track-shaped minimal recovery emphasis")
struct MinimalRecoveryAppearanceTests {
  @Test func onlyTheAffectedWeeklyTrackReceivesEmphasis() throws {
    let weekly = RecoveryFixture.window(id: "codex:secondary")
    let fiveHour = RecoveryFixture.window(minutes: 300)
    let state = try #require(
      QuotaRecoveryState.evaluate(
        RecoveryFixture.snapshot(windows: [fiveHour, weekly]), now: RecoveryFixture.now))
    #expect(
      MinimalRecoveryEmphasis.resolve(
        entry: QuotaDisplayEntry(kind: .weekly, window: weekly), recovery: state) == .resetAvailable
    )
    #expect(
      MinimalRecoveryEmphasis.resolve(
        entry: QuotaDisplayEntry(kind: .fiveHour, window: fiveHour), recovery: state) == nil)
    #expect(MinimalRecoveryEmphasis.resolve(entry: nil, recovery: state) == nil)
    #expect(
      MinimalRecoveryEmphasis.resolve(
        entry: QuotaDisplayEntry(kind: .weekly, window: weekly), recovery: nil) == nil)
  }

  @Test func verificationAndSpendingStatesRemainDistinct() {
    let entry = QuotaDisplayEntry(kind: .weekly, window: RecoveryFixture.window())
    for kind in [QuotaRecoveryState.Kind.needsRefresh, .awaitingReset, .spendLimit] {
      let state = QuotaRecoveryState(
        kind: kind, windows: [RecoveryFixture.window()], resets: .unknown)
      #expect(
        MinimalRecoveryEmphasis.resolve(entry: entry, recovery: state)
          == (kind == .spendLimit ? .spendingLimit : .needsVerification))
    }
  }

  @Test func noResetCreditsNeverAddTrackEmphasis() {
    let entry = QuotaDisplayEntry(kind: .weekly, window: RecoveryFixture.window())
    for resets in [ResetAvailability.unavailable, .unknown] {
      let state = QuotaRecoveryState(
        kind: .exhausted, windows: [RecoveryFixture.window()], resets: resets)
      #expect(MinimalRecoveryEmphasis.resolve(entry: entry, recovery: state) == nil)
    }
  }

}

extension FloatingPanelLayoutTests {
  @Test @MainActor func minimalRecoveryPixelsStayOnTheTrackAtEveryScale() async throws {
    let suite = "MinimalRecoveryPixels.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: temporary)
    }
    let settings = AppSettings(defaults: defaults)
    settings.quotaDisplayMode = .minimal
    settings.followCodexWindow = false
    settings.showRecentTasks = false
    settings.feedEnabled = false
    settings.notificationsEnabled = false
    settings.hoverCollapseDelay = 10
    let store = try SQLiteStore(databaseURL: temporary.appendingPathComponent("fixture.sqlite"))
    for dual in [false, true] {
      settings.showFiveHourQuota = dual
      let now = Date()
      let model = AppModel(
        store: store, settings: settings,
        initialQuota: RecoveryFixture.snapshot(
          windows: [
            RecoveryFixture.window(
              remaining: 60, minutes: 300, resetAt: now.addingTimeInterval(3_600)),
            RecoveryFixture.window(id: "codex:secondary", resetAt: now.addingTimeInterval(86_400)),
          ], observedAt: now))
      for style in MinimalMeterStyle.allCases {
        for scale in [0.5, 1, 2] {
          settings.minimalMeterAppearance.style = style
          settings.minimalMeterAppearance.dimensions.scale = scale
          for dark in [false, true] {
            let controller = FloatingPanelController(
              model: model, placement: PanelPlacementStore(defaults: defaults),
              panelStateDefaults: defaults, reduceMotionProvider: { true })
            controller.panel.isReleasedWhenClosed = false
            controller.panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            controller.setCollapsed(true, animated: false)
            controller.panel.orderFrontRegardless()
            defer { controller.panel.close() }
            try await Task.sleep(for: .milliseconds(100))
            #expect(controller.panel.frame.size == settings.minimalMeterAppearance.collapsedSize)
            let view = try #require(controller.panel.contentView)
            view.layoutSubtreeIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            var red: [NSPoint] = []
            for y in 0..<bitmap.pixelsHigh {
              for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  color.alphaComponent > 0.35, color.redComponent > 0.65,
                  color.redComponent > color.greenComponent * 1.7,
                  color.redComponent > color.blueComponent * 1.7
                else { continue }
                red.append(NSPoint(x: x, y: y))
              }
            }
            #expect(!red.isEmpty)
            let minX = try #require(red.map(\.x).min())
            let maxX = try #require(red.map(\.x).max())
            let minY = try #require(red.map(\.y).min())
            let maxY = try #require(red.map(\.y).max())
            let pixelsPerPoint = CGFloat(bitmap.pixelsWide) / view.bounds.width
            let dimension = settings.minimalMeterAppearance.dimensions
            switch style {
            case .vertical:
              #expect(maxX - minX <= dimension.thickness * scale * pixelsPerPoint + 2)
            case .horizontal:
              #expect(maxY - minY <= dimension.thickness * scale * pixelsPerPoint + 2)
            case .ring:
              let diameter = dimension.length - (dual ? 3 : 0) * dimension.thickness
              let radius = diameter * scale * pixelsPerPoint / 2
              let center = NSPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
              #expect(maxX - minX <= radius * 2 + 1)
              #expect(maxY - minY <= radius * 2 + 1)
              // Reject tangent lines/rectangle corners outside the real circle.
              #expect(red.allSatisfy { hypot($0.x - center.x, $0.y - center.y) <= radius + 1 })
              // Keep the original empty center: no new percentage or symbol.
              // The 0.6pt inner strokeBorder is drawn inward from the track edge.
              let holeRadius = radius - (dimension.thickness + 0.6) * scale * pixelsPerPoint
              #expect(
                red.allSatisfy { hypot($0.x - center.x, $0.y - center.y) >= holeRadius - 1.5 })
            }
          }
        }
      }
    }
  }
}
