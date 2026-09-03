import AppKit
import CoreGraphics
import LocalStore
import QuartzCore
import Testing

@testable import CodexFloat

@Suite("Window pin geometry and settings")
struct WindowPinTests {
  @Test @MainActor func followingDefaultsOnAndUserChoicePersists() throws {
    let suite = "WindowPinSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    #expect(settings.followCodexWindow)
    var calls = 0
    settings.onWindowFollowingChange = { calls += 1 }
    settings.followCodexWindow = false
    #expect(calls == 1)
    #expect(!AppSettings(defaults: defaults).followCodexWindow)
    settings.quotaDisplayMode = .menuBar
    settings.quotaDisplayMode = .minimal
    #expect(!settings.followCodexWindow)
  }

  @Test func movementAndResizeKeepTheTopLeftOffset() {
    let window = NSRect(x: 100, y: 100, width: 800, height: 650)
    let compact = NSRect(x: 134, y: 658, width: 36, height: 54)
    let offset = WindowPinOffset(panelFrame: compact, windowFrame: window)
    for size in [
      NSSize(width: 36, height: 54), NSSize(width: 174, height: 54),
      NSSize(width: 340, height: 300),
    ] {
      let moved = WindowPinGeometry.frame(
        offset: offset, windowFrame: NSRect(x: 180, y: 50, width: 900, height: 710),
        panelSize: size, expandedSize: NSSize(width: 340, height: 300),
        visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900))
      #expect(moved.minX == 214)
      #expect(moved.maxY == 722)
      #expect(moved.size == size)
    }
  }

  @Test func screenEdgeClampingDoesNotChangeTheRememberedOffset() {
    let screen = NSRect(x: -1440, y: 180, width: 1440, height: 900)
    let original = NSRect(x: -1400, y: 200, width: 900, height: 800)
    let offset = WindowPinOffset(
      panelFrame: NSRect(x: -1370, y: 916, width: 36, height: 54),
      windowFrame: original)
    let moved = original.offsetBy(dx: 900, dy: -450)
    let expandedSize = NSSize(width: 340, height: 400)
    let compact = WindowPinGeometry.frame(
      offset: offset, windowFrame: moved,
      panelSize: NSSize(width: 36, height: 54), expandedSize: expandedSize, visibleFrame: screen)
    let expanded = PanelExpansionGeometry.resolve(
      compactFrame: compact, preferredSize: expandedSize, visibleFrame: screen)
    #expect(screen.contains(expanded.frame))
    #expect(
      PanelExpansionGeometry.compactFrame(
        in: expanded.frame, size: compact.size, direction: expanded.direction) == compact)
    let returned = WindowPinGeometry.frame(
      offset: offset, windowFrame: original,
      panelSize: NSSize(width: 36, height: 54), expandedSize: expandedSize, visibleFrame: screen)
    #expect(returned.minX == -1370)
    #expect(returned.maxY == 970)
    #expect(offset.left == 30 && offset.top == 30)
  }

  @Test func automaticAnchorTracksTheLabelAndScreenSelectionUsesThatAnchor() throws {
    let window = NSRect(x: 900, y: 100, width: 900, height: 700)
    let label = NSRect(x: 1_050, y: 740, width: 60, height: 24)
    #expect(
      WindowPinGeometry.automaticAnchorPoint(windowFrame: window, labelFrame: label)
        == NSPoint(x: 1_120, y: 764))
    #expect(
      WindowPinGeometry.automaticAnchorPoint(windowFrame: window, labelFrame: nil)
        == NSPoint(x: 912, y: 762))
    let screens = [
      NSRect(x: 0, y: 0, width: 1_000, height: 900),
      NSRect(x: 1_000, y: 0, width: 1_000, height: 900),
    ]
    #expect(
      WindowPinGeometry.screenIndex(
        containing: NSPoint(x: 1_120, y: 764), windowFrame: window,
        visibleFrames: screens) == 1)
    #expect(
      WindowPinGeometry.screenIndex(
        containing: NSPoint(x: 920, y: 764), windowFrame: window,
        visibleFrames: screens) == 0)
  }

  @Test @MainActor func oneSharedOffsetSurvivesModeChangesAndMigratesLegacyData() throws {
    let suite = "WindowPinOffsets.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = PanelPlacementStore(defaults: defaults)
    let frame = NSRect(x: 100, y: 100, width: 900, height: 600)
    let full = WindowPinOffset(
      panelFrame: NSRect(x: 130, y: 630, width: 174, height: 54), windowFrame: frame)
    let minimal = WindowPinOffset(
      panelFrame: NSRect(x: 360, y: 600, width: 36, height: 54), windowFrame: frame)
    store.saveWindowPinOffset(full, for: .standard)
    store.saveWindowPinOffset(minimal, for: .minimal)
    store.saveWindowPinOffset(full, for: .menuBar)
    let restored = PanelPlacementStore(defaults: defaults)
    #expect(restored.windowPinOffset(for: .standard) == minimal)
    #expect(restored.windowPinOffset(for: .minimal) == minimal)
    #expect(restored.windowPinOffset(for: .menuBar) == nil)
    #expect(restored.windowPinIsUserCustomized(for: .standard))
    defaults.set(Data("not json".utf8), forKey: "codexWindowPinOffsetsV1")
    #expect(restored.windowPinOffset(for: .standard) == minimal)
  }

  @Test func geometryNeedsNoTitleAndRejectsUnrelatedHiddenOrSmallWindows() throws {
    let pid: pid_t = 123
    var info: [String: Any] = [
      kCGWindowNumber as String: NSNumber(value: 20),
      kCGWindowOwnerPID as String: NSNumber(value: pid),
      kCGWindowLayer as String: NSNumber(value: 0),
      kCGWindowIsOnscreen as String: NSNumber(value: true),
      kCGWindowBounds as String: CGRect(x: -900, y: -300, width: 800, height: 600)
        .dictionaryRepresentation,
    ]
    let window = try #require(
      CodexWindowGeometry.window(from: info, processID: pid, primaryScreenTop: 900))
    #expect(window.frame == NSRect(x: -900, y: 600, width: 800, height: 600))
    #expect(CodexWindowGeometry.window(from: info, processID: 999, primaryScreenTop: 900) == nil)
    info[kCGWindowIsOnscreen as String] = NSNumber(value: false)
    #expect(CodexWindowGeometry.window(from: info, processID: pid, primaryScreenTop: 900) == nil)
    info[kCGWindowIsOnscreen as String] = NSNumber(value: true)
    info[kCGWindowLayer as String] = NSNumber(value: 25)
    #expect(CodexWindowGeometry.window(from: info, processID: pid, primaryScreenTop: 900) == nil)
    info[kCGWindowLayer as String] = NSNumber(value: 0)
    info[kCGWindowBounds as String] =
      CGRect(x: 0, y: 0, width: 200, height: 100).dictionaryRepresentation
    #expect(CodexWindowGeometry.window(from: info, processID: pid, primaryScreenTop: 900) == nil)
  }

  @Test func windowSelectionKeepsTheTargetUnlessTheUserClicksAnotherWindow() throws {
    let first = TrackedCodexWindow(
      id: 1, processID: 100, frame: NSRect(x: 0, y: 0, width: 800, height: 700))
    let second = TrackedCodexWindow(
      id: 2, processID: 100, frame: NSRect(x: 850, y: 0, width: 800, height: 700))
    #expect(
      CodexWindowSelection.choose(
        from: [second, first], preferred: first, mousePoint: nil)?.id == first.id)
    #expect(
      CodexWindowSelection.choose(
        from: [first, second], preferred: nil, mousePoint: NSPoint(x: 900, y: 300))?.id
        == second.id)
    #expect(
      CodexWindowSelection.choose(from: [second, first], preferred: nil, mousePoint: nil)?.id
        == second.id)
  }
}

extension FloatingPanelLayoutTests {
  @Test @MainActor func systemOwnedPanelMoveIsCorrectedWithoutReplacingTheAnchor() async throws {
    try await withWindowPinFixture(mode: .minimal) { controller, _, _, window in
      controller.updateCodexWindow(window)
      let pinned = controller.compactAnchorFrame
      controller.panel.setFrameOrigin(NSPoint(x: pinned.minX + 64, y: pinned.minY))
      controller.windowDidMove(Notification(name: NSWindow.didMoveNotification))
      try await Task.sleep(for: .milliseconds(30))
      #expect(controller.compactAnchorFrame == pinned)
      #expect(controller.panel.frame == pinned)
    }
  }

  @Test @MainActor func automaticAnchorFollowsCodexLabelUntilTheUserDrags() async throws {
    try await withWindowPinFixture(mode: .minimal, userCustomized: false) {
      controller, _, _, window in
      let firstLabel = NSRect(
        x: window.frame.minX + 90, y: window.frame.maxY - 30,
        width: 54, height: 22)
      controller.updateCodexWindow(
        TrackedCodexWindow(
          id: window.id, processID: window.processID, frame: window.frame,
          codexLabelFrame: firstLabel))
      #expect(controller.panel.frame.minX == firstLabel.maxX + 10)
      let movedLabel = firstLabel.offsetBy(dx: 120, dy: 0)
      controller.updateCodexWindow(
        TrackedCodexWindow(
          id: window.id, processID: window.processID, frame: window.frame,
          codexLabelFrame: movedLabel))
      #expect(controller.panel.frame.minX == movedLabel.maxX + 10)
      controller.handleMinimalDrag(translation: CGSize(width: 20, height: 0), ended: true)
      #expect(!controller.followsCodexLabelAutomatically)
      let customized = controller.panel.frame
      controller.updateCodexWindow(
        TrackedCodexWindow(
          id: window.id, processID: window.processID, frame: window.frame,
          codexLabelFrame: firstLabel))
      #expect(controller.panel.frame == customized)
    }
  }

  @Test @MainActor func fullAndMinimalModesShareOneTopLeftAnchor() async throws {
    try await withWindowPinFixture(mode: .minimal) { controller, settings, _, window in
      controller.updateCodexWindow(window)
      let minimal = controller.compactAnchorFrame
      settings.quotaDisplayMode = .standard
      try await Task.sleep(for: .milliseconds(50))
      controller.updateCodexWindow(window)
      let standard = controller.compactAnchorFrame
      #expect(standard.minX == minimal.minX)
      #expect(standard.maxY == minimal.maxY)
      settings.quotaDisplayMode = .minimal
      try await Task.sleep(for: .milliseconds(50))
      controller.updateCodexWindow(window)
      #expect(controller.compactAnchorFrame == minimal)
    }
  }

  @Test @MainActor func nativeHiddenWindowPipelineKeepsTheSampledOffset()
    async throws
  {
    try await withWindowPinFixture(mode: .minimal) { controller, _, _, seed in
      // This is an owned fixture window, never the protected Codex main app.
      let host = NSPanel(
        contentRect: seed.frame, styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered, defer: false)
      host.isReleasedWhenClosed = false
      host.orderFrontRegardless()
      defer { host.orderOut(nil) }
      // Let WindowServer register the newly-created fixture before measuring
      // following; discovery retries before it exists are not drag-path scans.
      try await Task.sleep(for: .milliseconds(80))
      let source = NativeWindowGeometryFixtureSource(host: host)
      let scheduler = DisplayLinkedWindowFollowScheduler(window: controller.panel)
      var offsets: [WindowPinOffset] = []
      var latencies: [TimeInterval] = []
      let tracker = CodexWindowTracker(
        source: source, scheduler: scheduler,
        onMovementChanged: { controller.setCodexWindowMoving($0) }
      ) { window in
        controller.updateCodexWindow(window)
        guard let window else { return }
        offsets.append(
          WindowPinOffset(panelFrame: controller.panel.frame, windowFrame: window.frame))
        if let began = source.sampleBegan { latencies.append(CACurrentMediaTime() - began) }
      }
      tracker.start()
      defer { tracker.stop() }
      let clock = ContinuousClock()
      let start = clock.now
      // Hosted macOS VMs coalesce timers and WindowServer updates. This checks
      // eventual delivery/geometry, not a minimum FPS or wall-clock benchmark.
      // Keep all 48 changed samples and fail within a bounded eight seconds.
      while latencies.count < 48, start.duration(to: clock.now) < .seconds(8) {
        try await Task.sleep(for: .milliseconds(10))
      }
      #expect(latencies.count >= 48)
      #expect(controller.isHiddenForCodexMovement)
      #expect(controller.panel.alphaValue == 0)
      let expected = try #require(offsets.first)
      #expect(
        offsets.allSatisfy {
          abs($0.left - expected.left) < 0.5 && abs($0.top - expected.top) < 0.5
        })
      #expect(
        source.discoverySamples.allSatisfy { $0 == 0 },
        "Discovery is permitted before the first sample, never during a held drag")
      source.shouldMove = false
      source.isMouseButtonDown = false
      let releaseTime = clock.now
      while controller.isHiddenForCodexMovement,
        releaseTime.duration(to: clock.now) < .seconds(2)
      {
        try await Task.sleep(for: .milliseconds(20))
      }
      #expect(!controller.isHiddenForCodexMovement)
      #expect(controller.panel.alphaValue == 1)
      #expect(!controller.panel.ignoresMouseEvents)
      #expect(scheduler.isDisplayLinkPaused)
      if !latencies.isEmpty {
        let sorted = latencies.sorted()
        let mean = latencies.reduce(0, +) / Double(latencies.count) * 1000
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))] * 1000
        print(
          String(
            format:
              "Owned-window follow fixture: %d samples, query+apply mean %.3f ms, p95 %.3f ms",
            latencies.count, mean, p95))
      }
    }
  }

  @Test @MainActor func windowPinFollowsDuringBothLiquidTransitionsWithoutJumpingBack() async throws
  {
    for mode in [QuotaDisplayMode.standard, .minimal] {
      try await withWindowPinFixture(mode: mode) { controller, settings, placement, window in
        controller.updateCodexWindow(window)
        let resting = controller.panel.frame
        let originalPin = placement.windowPinOffset(for: mode)
        controller.setCollapsed(false, animated: true)
        try await Task.sleep(for: .milliseconds(55))
        controller.updateCodexWindow(window.shifted(dx: 60, dy: -25))
        #expect(abs(controller.panel.frame.minX - resting.minX - 60) < 1)
        #expect(abs(controller.panel.frame.maxY - resting.maxY + 25) < 1)
        try await waitForPinTransition(controller)
        controller.setCollapsed(true, animated: true)
        try await Task.sleep(for: .milliseconds(55))
        controller.updateCodexWindow(window.shifted(dx: 110, dy: -45))
        try await waitForPinTransition(controller)
        #expect(controller.panel.frame == resting.offsetBy(dx: 110, dy: -45))
        #expect(
          placement.windowPinOffset(for: mode) == originalPin,
          "Automatic following must not change the saved user offset")
        let last = controller.panel.frame
        controller.updateCodexWindow(nil)
        #expect(controller.panel.frame == last)
        controller.updateCodexWindow(window.shifted(dx: 130, dy: -55))
        #expect(controller.panel.frame == resting.offsetBy(dx: 130, dy: -55))
        settings.followCodexWindow = false
        try await Task.sleep(for: .milliseconds(30))
        controller.updateCodexWindow(window)
        #expect(controller.panel.frame == resting.offsetBy(dx: 130, dy: -55))
      }
    }
  }

  @Test @MainActor func windowPinRemembersDraggedMinimalOffsetAndIgnoresMenuBar() async throws {
    try await withWindowPinFixture(mode: .minimal) { controller, settings, placement, window in
      controller.updateCodexWindow(window)
      let original = controller.panel.frame
      controller.handleMinimalDrag(translation: CGSize(width: 40, height: 20), ended: false)
      let dragging = controller.panel.frame
      controller.updateCodexWindow(window.shifted(dx: 10, dy: 0))
      #expect(controller.panel.frame == dragging, "Do not fight a user dragging the tool")
      controller.handleMinimalDrag(translation: CGSize(width: 40, height: 20), ended: true)
      let pinned = try #require(placement.windowPinOffset(for: .minimal))
      #expect(
        pinned
          == WindowPinOffset(
            panelFrame: original.offsetBy(dx: 40, dy: -20),
            windowFrame: window.frame.offsetBy(dx: 10, dy: 0)))
      controller.updateCodexWindow(window.shifted(dx: 90, dy: 20))
      #expect(controller.panel.frame == dragging.offsetBy(dx: 80, dy: 20))
      settings.followCodexWindow = false
      try await Task.sleep(for: .milliseconds(25))
      let detached = controller.panel.frame
      controller.updateCodexWindow(window.shifted(dx: 120, dy: 30))
      #expect(controller.panel.frame == detached)
      settings.followCodexWindow = true
      try await Task.sleep(for: .milliseconds(25))
      #expect(controller.panel.frame == dragging.offsetBy(dx: 110, dy: 30))
      settings.quotaDisplayMode = .menuBar
      try await Task.sleep(for: .milliseconds(50))
      let menuFrame = controller.panel.frame
      controller.updateCodexWindow(window.shifted(dx: 180, dy: 0))
      #expect(controller.panel.frame == menuFrame)
      settings.quotaDisplayMode = .minimal
      try await Task.sleep(for: .milliseconds(50))
      #expect(controller.panel.frame == dragging.offsetBy(dx: 170, dy: 0))
      #expect(placement.windowPinOffset(for: .minimal) == pinned)
    }
  }

  @Test @MainActor func movementHidesBothModesWithoutChangingVisibilityOrSavedOffsets() async throws
  {
    for mode in [QuotaDisplayMode.standard, .minimal] {
      try await withWindowPinFixture(mode: mode) { controller, _, placement, window in
        controller.updateCodexWindow(window)
        let resting = controller.panel.frame
        let originalPin = placement.windowPinOffset(for: mode)
        var visibilityEvents: [Bool] = []
        controller.onVisibilityChanged = { visibilityEvents.append($0) }
        controller.setCollapsed(false, animated: true)
        try await Task.sleep(for: .milliseconds(40))
        controller.setCodexWindowMoving(true)
        #expect(controller.isHiddenForCodexMovement)
        #expect(controller.panel.isVisible, "Temporary suppression must not stop the tracker")
        #expect(controller.panel.alphaValue == 0)
        #expect(controller.panel.ignoresMouseEvents, "Invisible windows must not intercept clicks")
        #expect(!controller.isSurfaceTransitionInFlight)
        controller.updateCodexWindow(window.shifted(dx: 60, dy: -25))
        controller.handleHover(true)
        #expect(!controller.isSurfaceTransitionInFlight)
        // A late layout adjustment must be corrected before alpha is restored.
        controller.panel.setFrameOrigin(
          NSPoint(x: controller.panel.frame.minX + 12, y: controller.panel.frame.minY))
        controller.setCodexWindowMoving(false)
        #expect(!controller.isHiddenForCodexMovement)
        #expect(controller.panel.alphaValue == 1)
        #expect(!controller.panel.ignoresMouseEvents)
        #expect(controller.panel.frame == resting.offsetBy(dx: 60, dy: -25))
        #expect(visibilityEvents.isEmpty)
        #expect(placement.windowPinOffset(for: mode) == originalPin)
        // Settling must not revive a panel explicitly hidden in the meantime.
        controller.setCodexWindowMoving(true)
        controller.hide()
        controller.setCodexWindowMoving(false)
        #expect(!controller.panel.isVisible)
        #expect(visibilityEvents == [false])
        #expect(controller.panel.alphaValue == 1)
      }
    }
  }

  @Test @MainActor func disabledFollowingAndMenuBarCannotInheritInvisibleState() async throws {
    try await withWindowPinFixture(mode: .minimal) { controller, settings, _, window in
      controller.updateCodexWindow(window)
      controller.setCodexWindowMoving(true)
      settings.followCodexWindow = false
      try await Task.sleep(for: .milliseconds(30))
      #expect(!controller.isHiddenForCodexMovement)
      controller.setCodexWindowMoving(true)
      #expect(controller.panel.alphaValue == 1)
      #expect(!controller.panel.ignoresMouseEvents)
      settings.followCodexWindow = true
      try await Task.sleep(for: .milliseconds(30))
      controller.setCodexWindowMoving(true)
      #expect(controller.panel.alphaValue == 0)
      settings.quotaDisplayMode = .menuBar
      try await Task.sleep(for: .milliseconds(30))
      controller.setCodexWindowMoving(true)
      #expect(!controller.isHiddenForCodexMovement)
      #expect(controller.panel.alphaValue == 1)
      #expect(!controller.panel.ignoresMouseEvents)
    }
  }

  @Test @MainActor func movementPreservesExpandedModeWhenHoverExpansionIsDisabled() async throws {
    try await withWindowPinFixture(mode: .standard) { controller, settings, _, window in
      settings.hoverExpansionEnabled = false
      try await Task.sleep(for: .milliseconds(30))
      controller.setCollapsed(false, animated: false)
      controller.updateCodexWindow(window)
      let expanded = controller.panel.frame
      controller.setCodexWindowMoving(true)
      controller.updateCodexWindow(window.shifted(dx: 45, dy: -20))
      controller.setCodexWindowMoving(false)
      #expect(controller.panel.frame == expanded.offsetBy(dx: 45, dy: -20))
      #expect(!controller.isSurfaceTransitionInFlight)
    }
  }
}

@MainActor
private final class NativeWindowGeometryFixtureSource: CodexWindowGeometrySource {
  let host: NSWindow
  private let initialFrame: NSRect
  private let geometry = SystemCodexWindowGeometrySource()
  private var phase: CGFloat = 0
  var discoveryCount = 0
  var discoverySamples: [Int] = []
  var reads = 0
  var sampleBegan: TimeInterval?
  var shouldMove = true
  var isCodexFrontmost: Bool { false }
  var isMouseButtonDown = true

  init(host: NSWindow) {
    self.host = host
    initialFrame = host.frame
  }

  func discover(preferred: TrackedCodexWindow?) -> TrackedCodexWindow? {
    discoveryCount += 1
    discoverySamples.append(reads)
    sampleBegan = nil
    return geometry.readWindow(
      TrackedCodexWindow(
        id: CGWindowID(host.windowNumber),
        processID: ProcessInfo.processInfo.processIdentifier, frame: host.frame))
  }

  func readWindow(_ window: TrackedCodexWindow) -> TrackedCodexWindow? {
    reads += 1
    if shouldMove {
      phase += 0.1
      host.setFrameOrigin(NSPoint(x: initialFrame.minX + sin(phase) * 30, y: initialFrame.minY))
    }
    sampleBegan = CACurrentMediaTime()
    return geometry.readWindow(window)
  }
}

extension TrackedCodexWindow {
  fileprivate func shifted(dx: CGFloat, dy: CGFloat) -> TrackedCodexWindow {
    TrackedCodexWindow(id: id, processID: processID, frame: frame.offsetBy(dx: dx, dy: dy))
  }
}

@MainActor private func waitForPinTransition(_ controller: FloatingPanelController) async throws {
  let clock = ContinuousClock()
  let start = clock.now
  while controller.isSurfaceTransitionInFlight, start.duration(to: clock.now) < .seconds(2) {
    try await Task.sleep(for: .milliseconds(16))
  }
  #expect(!controller.isSurfaceTransitionInFlight)
}

@MainActor private func withWindowPinFixture(
  mode: QuotaDisplayMode,
  userCustomized: Bool = true,
  body: (FloatingPanelController, AppSettings, PanelPlacementStore, TrackedCodexWindow) async throws
    -> Void
) async throws {
  let suite = "WindowPinPanel.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer {
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: directory)
  }
  let visible = try #require(NSScreen.main?.visibleFrame)
  let window = TrackedCodexWindow(
    id: 12, processID: 100,
    frame: NSRect(x: visible.minX + 50, y: visible.maxY - 550, width: 800, height: 500))
  let placement = PanelPlacementStore(defaults: defaults)
  placement.saveUserPlacement(
    frame: NSRect(
      x: window.frame.minX + 35,
      y: window.frame.maxY - 38 - 54, width: 340, height: 54), mode: mode, expandedWidth: 340)
  if userCustomized {
    placement.saveWindowPinOffset(
      WindowPinOffset(
        panelFrame: NSRect(
          x: window.frame.minX + 35,
          y: window.frame.maxY - 38 - 54, width: 340, height: 54),
        windowFrame: window.frame),
      for: mode)
  }
  let settings = AppSettings(defaults: defaults)
  settings.quotaDisplayMode = mode
  settings.showRecentTasks = false
  settings.feedEnabled = false
  settings.showResetProbability = false
  settings.hoverCollapseDelay = 2
  let model = AppModel(
    store: try SQLiteStore(databaseURL: directory.appendingPathComponent("fixture.sqlite")),
    settings: settings)
  let controller = FloatingPanelController(
    model: model, placement: placement,
    panelStateDefaults: defaults, reduceMotionProvider: { false })
  // No live account, tracker, notifications or app-server in fixture tests.
  controller.panel.orderFrontRegardless()
  defer { controller.panel.orderOut(nil) }
  try await Task.sleep(for: .milliseconds(80))
  try await body(controller, settings, placement, window)
}
