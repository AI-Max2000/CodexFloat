import AppKit
import CodexQuotaCore
import LocalStore
import Testing

@testable import CodexFloat

@Suite("Screen-aware anchored expansion")
struct PanelExpansionTests {
  @Test func allCornersPreserveTheSeedAtEveryRevealStep() {
    for screen in [
      NSRect(x: 0, y: 80, width: 1440, height: 820),
      NSRect(x: -1512, y: -400, width: 1512, height: 950),
    ] {
      for width: CGFloat in [36, 174] {
        for left in [false, true] {
          for up in [false, true] {
            let compact = NSRect(
              x: left ? screen.maxX - width - 2 : screen.minX + 2,
              y: up ? screen.minY + 2 : screen.maxY - 56,
              width: width, height: 54)
            let result = PanelExpansionGeometry.resolve(
              compactFrame: compact, preferredSize: NSSize(width: 340, height: 300),
              visibleFrame: screen)
            #expect(result.direction == PanelExpansionDirection(growsLeft: left, growsUp: up))
            #expect(screen.contains(result.frame))
            #expect(
              PanelExpansionGeometry.compactFrame(
                in: result.frame, size: compact.size, direction: result.direction) == compact)
            let bounds = CGRect(origin: .zero, size: result.frame.size)
            for step in 0...100 {
              let rect = FloatingPanelLayout.liquidRevealRect(
                in: bounds, progress: CGFloat(step) / 100, seedSize: compact.size,
                anchoredToTrailingEdge: left, anchoredToBottomEdge: up)
              #expect(bounds.contains(rect))
              #expect((left ? rect.maxX : rect.minX) == (left ? bounds.maxX : bounds.minX))
              #expect((up ? rect.maxY : rect.minY) == (up ? bounds.maxY : bounds.minY))
              if step == 0 {
                let screenSeed = NSRect(
                  x: result.frame.minX + rect.minX, y: result.frame.maxY - rect.maxY,
                  width: rect.width, height: rect.height)
                #expect(screenSeed == compact)
              }
              if step == 100 { #expect(rect == bounds) }
            }
          }
        }
      }
    }
  }

  @Test func directionIsLockedAndOversizedContentGetsABoundedViewport() {
    let screen = NSRect(x: 0, y: 40, width: 600, height: 400)
    let compact = NSRect(x: 295, y: 205, width: 36, height: 54)
    let large = PanelExpansionGeometry.resolve(
      compactFrame: compact, preferredSize: NSSize(width: 520, height: 680), visibleFrame: screen)
    #expect(large.direction == PanelExpansionDirection(growsLeft: true, growsUp: true))
    #expect(large.frame.size == NSSize(width: 331, height: 235))
    let small = PanelExpansionGeometry.resolve(
      compactFrame: compact, preferredSize: NSSize(width: 174, height: 104),
      visibleFrame: screen, lockedDirection: large.direction)
    #expect(small.direction == large.direction)
    for result in [large, small] {
      #expect(screen.contains(result.frame))
      #expect(
        PanelExpansionGeometry.compactFrame(
          in: result.frame, size: compact.size, direction: result.direction) == compact)
    }
  }

  @Test func restoredBottomPositionUsesCompactSizeNotTheExpandedFootprint() {
    let screen = NSRect(x: -1440, y: 80, width: 1440, height: 800)
    for width: CGFloat in [36, 174] {
      let compact = NSRect(x: screen.maxX - width, y: screen.minY, width: width, height: 54)
      let record = PanelPlacementGeometry.record(
        for: compact, expandedWidth: 420, visibleFrame: screen)
      let restored = PanelPlacementGeometry.restoredFrame(
        from: record, panelHeight: 600, minimumWidth: 340, maximumWidth: 520,
        visibleFrame: screen, compactSize: compact.size)
      #expect(abs(restored.minX - compact.minX) < 0.001)
      #expect(abs(restored.minY - compact.minY) < 0.001)
      #expect(restored.size == compact.size)
      #expect(record.expandedWidth == 420)
    }
  }
}

extension FloatingPanelLayoutTests {
  @Test @MainActor func nativeEdgeEndpointsKeepCompactPixelsAligned() async throws {
    for mode in [QuotaDisplayMode.standard, .minimal] {
      try await withEdgePanelFixture(mode: mode) { controller, _, _, _, _ in
        for dark in [false, true] {
          controller.panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
          try await Task.sleep(for: .milliseconds(30))
          let compact = controller.panel.frame
          let before = try edgePanelImage(controller)
          let beforePixels = try edgePixels(before)
          controller.setCollapsed(false, animated: true)
          // Capture without yielding, before the first animated update. The
          // backing window is already large, but its compact entry must match.
          let first = try edgePanelImage(controller)
          let seed = try #require(
            first.cropping(
              to: CGRect(
                x: first.width - before.width, y: first.height - before.height,
                width: before.width, height: before.height)))
          let seedPixels = try edgePixels(seed)
          let differences = zip(seedPixels, beforePixels).map { abs(Int($0) - Int($1)) }
          // AppKit's offscreen compositing rounds one thin-meter edge pixel
          // by up to 3/255. The opaque capsule must match exactly; the minimal
          // meter permits only four changed channels, never a positional shift.
          let matches =
            mode == .minimal
            ? differences.filter { $0 > 0 }.count <= 4 && (differences.max() ?? 0) <= 3
            : seedPixels == beforePixels
          if !matches {
            print(
              "Seed pixels \(mode), dark=\(dark): \(before.width)x\(before.height), canvas \(first.width)x\(first.height), changed channels \(differences.filter { $0 > 0 }.count), max \(differences.max() ?? 0)"
            )
            if let path = ProcessInfo.processInfo.environment["CODEX_FLOAT_EDGE_PREVIEW_DIR"] {
              let output = URL(fileURLWithPath: path, isDirectory: true)
              for (label, image) in [("before", before), ("seed", seed), ("canvas", first)] {
                let data = try #require(
                  NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try data.write(
                  to: output.appendingPathComponent("pixel-\(mode)-\(dark)-\(label).png"))
              }
            }
          }
          #expect(matches)
          let canvasPixels = try edgePixels(first)
          let canvasAlphaCount = stride(from: 3, to: canvasPixels.count, by: 4)
            .filter { canvasPixels[$0] > 0 }.count
          let seedAlphaCount = stride(from: 3, to: seedPixels.count, by: 4)
            .filter { seedPixels[$0] > 0 }.count
          #expect(
            canvasAlphaCount == seedAlphaCount,
            "No rectangular backing or white fringe outside the seed")
          try await assertEdgeTransition(controller, compact: compact)
          let expandedImage = try edgePanelImage(controller)
          let expandedPixels = try edgePixels(expandedImage)
          for x in [0, expandedImage.width - 1] {
            for y in [0, expandedImage.height - 1] {
              #expect(
                expandedPixels[(y * expandedImage.width + x) * 4 + 3] == 0,
                "Expanded rounded corners remain transparent")
            }
          }
          controller.setCollapsed(true, animated: true)
          try await assertEdgeTransition(controller, compact: compact)
          #expect(try edgePixels(edgePanelImage(controller)) == beforePixels)
        }
      }
    }
  }

  @Test @MainActor func nativeEdgeExpansionKeepsCompactAnchorThroughRepeatedCycles() async throws {
    for mode in [QuotaDisplayMode.standard, .minimal] {
      try await withEdgePanelFixture(mode: mode) { controller, _, _, _, _ in
        let screen = try #require(NSScreen.main?.visibleFrame)
        let size = controller.panel.frame.size
        for left in [false, true] {
          for up in [false, true] {
            let compact = NSRect(
              x: left ? screen.maxX - size.width - 4 : screen.minX + 4,
              y: up ? screen.minY + 4 : screen.maxY - size.height - 4,
              width: size.width, height: size.height)
            controller.panel.setFrame(compact, display: true)
            controller.windowDidMove(Notification(name: NSWindow.didMoveNotification))
            #expect(controller.panel.frame == compact)
            for _ in 0..<2 {
              controller.setCollapsed(false, animated: true)
              #expect(
                controller.currentExpansionDirection
                  == PanelExpansionDirection(
                    growsLeft: left, growsUp: up))
              try await assertEdgeTransition(controller, compact: compact)
              #expect(screen.contains(controller.panel.frame))
              controller.setCollapsed(true, animated: true)
              try await assertEdgeTransition(controller, compact: compact)
              #expect(controller.panel.frame == compact)
            }
          }
        }
      }
    }
  }

  @Test @MainActor func bottomRevealReversalAndContentChangesKeepTheSameAnchor() async throws {
    for mode in [QuotaDisplayMode.standard, .minimal] {
      try await withEdgePanelFixture(mode: mode) { controller, settings, _, _, model in
        let compact = controller.panel.frame
        controller.setCollapsed(false, animated: true)
        try await Task.sleep(for: .milliseconds(70))
        let direction = controller.currentExpansionDirection
        let canvas = controller.panel.frame
        controller.setCollapsed(true, animated: true)
        try await Task.sleep(for: .milliseconds(60))
        controller.setCollapsed(false, animated: true)
        #expect(controller.panel.frame == canvas)
        #expect(controller.currentExpansionDirection == direction)
        try await assertEdgeTransition(controller, compact: compact)
        settings.showRecentTasks = true
        settings.feedEnabled = true
        model.previewFeedback(.tiboReset)
        try await Task.sleep(for: .milliseconds(180))
        #expect(controller.currentExpansionDirection == direction)
        #expect(controller.compactAnchorFrame == compact)
        #expect(
          PanelExpansionGeometry.compactFrame(
            in: controller.panel.frame, size: compact.size, direction: direction) == compact)
        controller.setCollapsed(true, animated: false)
        #expect(controller.panel.frame == compact)
      }
    }
  }

  @Test @MainActor func draggingUpwardExpandedPanelMovesItsCompactEntryByTheSameDelta() async throws
  {
    for mode in [QuotaDisplayMode.standard, .minimal] {
      try await withEdgePanelFixture(mode: mode) { controller, _, _, _, _ in
        let compact = controller.panel.frame
        controller.setCollapsed(false, animated: false)
        let moved = controller.panel.frame.offsetBy(dx: -50, dy: 35)
        controller.panel.setFrame(moved, display: true)
        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification))
        let expected = compact.offsetBy(dx: -50, dy: 35)
        #expect(controller.compactAnchorFrame == expected)
        controller.setCollapsed(true, animated: true)
        try await assertEdgeTransition(controller, compact: expected)
        #expect(controller.panel.frame == expected)
      }
    }
  }

  @Test @MainActor func bottomPlacementSurvivesRelaunchModeChangesAndWindowFollowing() async throws
  {
    for mode in [QuotaDisplayMode.standard, .minimal] {
      try await withEdgePanelFixture(mode: mode) {
        controller, settings, defaults, placement, model in
        let compact = controller.panel.frame
        // The fixture was restored from a saved bottom-right compact rectangle.
        let relaunched = FloatingPanelController(
          model: model, placement: placement, panelStateDefaults: defaults,
          reduceMotionProvider: { true })
        defer { relaunched.panel.orderOut(nil) }
        #expect(relaunched.panel.frame == compact)
        settings.quotaDisplayMode = mode == .standard ? .minimal : .standard
        try await Task.sleep(for: .milliseconds(60))
        settings.quotaDisplayMode = mode
        try await Task.sleep(for: .milliseconds(60))
        #expect(controller.panel.frame == compact)
        settings.followCodexWindow = true
        try await Task.sleep(for: .milliseconds(30))
        let screen = try #require(NSScreen.main?.visibleFrame)
        let host = TrackedCodexWindow(
          id: 42, processID: 100,
          frame: NSRect(x: screen.minX + 30, y: screen.minY + 10, width: 700, height: 500))
        controller.updateCodexWindow(host)
        #expect(controller.panel.frame == compact)
        controller.setCollapsed(false, animated: false)
        controller.setCodexWindowMoving(true)
        let translatedHost = TrackedCodexWindow(
          id: host.id, processID: host.processID, frame: host.frame.offsetBy(dx: -30, dy: 25))
        controller.updateCodexWindow(translatedHost)
        controller.setCodexWindowMoving(false)
        let expected = compact.offsetBy(dx: -30, dy: 25)
        #expect(controller.panel.frame == expected)
        controller.setCollapsed(false, animated: false)
        #expect(controller.compactAnchorFrame == expected)
        controller.setCollapsed(true, animated: false)
        #expect(controller.panel.frame == expected)
      }
    }
  }

  @Test @MainActor func edgeExpansionNativePreview() async throws {
    guard let outputPath = ProcessInfo.processInfo.environment["CODEX_FLOAT_EDGE_PREVIEW_DIR"]
    else {
      return
    }
    let directory = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for mode in [QuotaDisplayMode.standard, .minimal] {
      try await withEdgePanelFixture(mode: mode) { controller, settings, _, _, _ in
        settings.showRecentTasks = true
        settings.feedEnabled = true
        try await Task.sleep(for: .milliseconds(80))
        for dark in [false, true] {
          controller.panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
          try await captureEdgePanel(controller, to: directory, name: "\(mode)-\(dark)-compact")
          controller.setCollapsed(false, animated: true)
          try await captureEdgePanel(controller, to: directory, name: "\(mode)-\(dark)-start")
          try await Task.sleep(for: .milliseconds(90))
          try await captureEdgePanel(controller, to: directory, name: "\(mode)-\(dark)-opening")
          try await assertEdgeTransition(controller, compact: controller.compactAnchorFrame)
          try await captureEdgePanel(controller, to: directory, name: "\(mode)-\(dark)-expanded")
          controller.setCollapsed(true, animated: true)
          try await Task.sleep(for: .milliseconds(200))
          try await captureEdgePanel(controller, to: directory, name: "\(mode)-\(dark)-closing")
          try await assertEdgeTransition(controller, compact: controller.compactAnchorFrame)
          try await captureEdgePanel(controller, to: directory, name: "\(mode)-\(dark)-returned")
        }
      }
    }
  }
}

@MainActor func assertEdgeTransition(
  _ controller: FloatingPanelController, compact: NSRect
) async throws {
  let clock = ContinuousClock()
  let start = clock.now
  let direction = controller.currentExpansionDirection
  while controller.isSurfaceTransitionInFlight, start.duration(to: clock.now) < .seconds(2) {
    #expect(controller.compactAnchorFrame == compact)
    #expect(controller.currentExpansionDirection == direction)
    #expect(
      PanelExpansionGeometry.compactFrame(
        in: controller.panel.frame, size: compact.size, direction: direction) == compact)
    try await Task.sleep(for: .milliseconds(8))
  }
  #expect(!controller.isSurfaceTransitionInFlight)
  #expect(controller.compactAnchorFrame == compact)
}

@MainActor func captureEdgePanel(
  _ controller: FloatingPanelController, to directory: URL, name: String
) async throws {
  let view = try #require(controller.panel.contentView)
  view.layoutSubtreeIfNeeded()
  let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
  view.cacheDisplay(in: view.bounds, to: bitmap)
  let data = try #require(bitmap.representation(using: .png, properties: [:]))
  try data.write(to: directory.appendingPathComponent("\(name).png"))
}

@MainActor func edgePanelImage(_ controller: FloatingPanelController) throws -> CGImage {
  let view = try #require(controller.panel.contentView)
  view.layoutSubtreeIfNeeded()
  let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
  view.cacheDisplay(in: view.bounds, to: bitmap)
  return try #require(bitmap.cgImage)
}

func edgePixels(_ image: CGImage) throws -> Data {
  let context = try #require(
    CGContext(
      data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  return Data(bytes: try #require(context.data), count: image.width * image.height * 4)
}

@MainActor func withEdgePanelFixture(
  mode: QuotaDisplayMode,
  appearance: MinimalMeterAppearance = MinimalMeterAppearance(),
  body: @MainActor (
    FloatingPanelController, AppSettings, UserDefaults, PanelPlacementStore, AppModel
  ) async throws -> Void
) async throws {
  let suite = "EdgePanel.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer {
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: directory)
  }
  let store = try SQLiteStore(databaseURL: directory.appendingPathComponent("fixture.sqlite"))
  let now = Date()
  let windows = QuotaDisplayFixture.windows.map { window in
    RateLimitWindow(
      id: window.id, limitID: window.limitID, limitName: nil, windowName: window.windowName,
      usedPercent: window.usedPercent, windowDurationMinutes: window.windowDurationMinutes,
      resetsAt: window.resetsAt.map {
        now.addingTimeInterval($0.timeIntervalSince(QuotaDisplayFixture.now))
      },
      reachedType: nil)
  }
  try await store.save(
    snapshot: QuotaSnapshot(
      planType: "plus", windows: windows, resetCreditCount: 0, resetCredits: [],
      creditBalance: nil, hasCredits: nil, spendControlReached: nil, observedAt: now))
  let settings = AppSettings(defaults: defaults)
  settings.quotaDisplayMode = mode
  settings.minimalMeterAppearance = appearance
  settings.followCodexWindow = false
  settings.showRecentTasks = false
  settings.feedEnabled = false
  settings.showResetProbability = false
  settings.hoverCollapseDelay = 10
  let visible = try #require(NSScreen.main?.visibleFrame)
  let size = mode == .minimal ? appearance.collapsedSize : NSSize(width: 174, height: 54)
  let compact = NSRect(
    x: visible.maxX - size.width - 4, y: visible.minY + 4, width: size.width, height: size.height)
  let placement = PanelPlacementStore(defaults: defaults)
  placement.saveUserPlacement(frame: compact, mode: mode, expandedWidth: 340)
  let model = AppModel(store: store, settings: settings)
  await model.loadCache()
  let controller = FloatingPanelController(
    model: model, placement: placement, panelStateDefaults: defaults,
    reduceMotionProvider: { false })
  controller.panel.orderFrontRegardless()
  defer { controller.hide() }
  try await Task.sleep(for: .milliseconds(80))
  #expect(controller.panel.frame == compact)
  try await body(controller, settings, defaults, placement, model)
}
