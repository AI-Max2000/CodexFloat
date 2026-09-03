import AppKit
import Testing

@testable import CodexFloat

@Suite("Window movement suppression and scheduling")
@MainActor
struct WindowFollowSchedulingTests {
  @Test func firstDragAndMouseUpDeliverBeforeTheirCallbacksReturn() {
    let fixture = WindowFollowFixture()
    fixture.tracker.start()
    defer { fixture.tracker.stop() }
    fixture.mouse(.leftMouseDown)
    let delivered = fixture.deliveries.count
    fixture.time += 0.001
    fixture.move(x: 3)
    fixture.mouse(.leftMouseDragged)
    // Deliberately no await/run-loop turn: the old queued Task must not return.
    #expect(fixture.deliveries.count == delivered + 1)
    #expect(fixture.deliveries.last?.window == fixture.source.window)
    fixture.time += 0.0001
    fixture.move(x: 4)
    fixture.mouse(.leftMouseUp)
    #expect(fixture.deliveries.count == delivered + 2)
    #expect(fixture.deliveries.last?.window == fixture.source.window)
  }

  @Test(arguments: [60, 120]) func hiddenMovementUsesAnIndependentLowRateClock(hertz: Int) {
    let fixture = WindowFollowFixture()
    fixture.tracker.start()
    defer { fixture.tracker.stop() }
    fixture.mouse(.leftMouseDown)
    let discoveries = fixture.source.discoveryCount
    let start = fixture.time
    fixture.source.onRead = { fixture.time += 0.002 }  // Model a 2 ms geometry query.
    for index in 1...(hertz * 2) {
      let frameTime = start + Double(index) / Double(hertz)
      fixture.time = frameTime
      fixture.move(x: CGFloat(index))
      fixture.scheduler.frame?()
      if index % (hertz / 30) == 0 {
        fixture.scheduler.motion?()
        #expect(fixture.deliveries.last?.window == fixture.source.window)
        #expect(abs((fixture.deliveries.last?.time ?? 0) - frameTime - 0.002) < 0.00001)
      }
      if index % 15 == 0 { fixture.scheduler.idle?() }
    }
    #expect(fixture.source.readCount == 61)
    #expect(fixture.tracker.isWindowMoving)
    #expect(fixture.scheduler.isDisplayLinkPaused)
    #expect(fixture.source.discoveryCount == discoveries)
    #expect(fixture.scheduler.startCount == 1, "Do not re-create clocks for each frame")
    fixture.source.onRead = nil
  }

  @Test func longDragDefersDiscoveryIncludingActivationAndScreenRequests() {
    let fixture = WindowFollowFixture()
    fixture.tracker.start()
    defer { fixture.tracker.stop() }
    fixture.mouse(.leftMouseDown)
    let discoveries = fixture.source.discoveryCount
    for index in 1...80 {
      fixture.time += 0.05
      fixture.move(x: CGFloat(index))
      fixture.mouse(.leftMouseDragged)
      fixture.tracker.refresh(selectFrontWindow: true)
      fixture.scheduler.idle?()
    }
    #expect(fixture.source.discoveryCount == discoveries)
    fixture.mouse(.leftMouseUp)
    fixture.time += 0.3
    fixture.scheduler.motion?()
    fixture.scheduler.idle?()
    #expect(fixture.source.discoveryCount == discoveries + 1)
  }

  @Test func hiddenMouseEventsAreBoundedAndMouseUpStillCommitsTheFinalPosition() {
    let fixture = WindowFollowFixture()
    fixture.tracker.start()
    defer { fixture.tracker.stop() }
    fixture.mouse(.leftMouseDown)
    fixture.move(x: 20)
    fixture.mouse(.leftMouseDragged)
    let reads = fixture.source.readCount
    for _ in 0..<100 {
      fixture.time += 0.00001
      fixture.mouse(.leftMouseDragged)
    }
    #expect(fixture.source.readCount == reads)
    fixture.move(x: 21)
    fixture.scheduler.frame?()
    #expect(fixture.source.readCount == reads, "Hidden panels do not need display-rate polling")
    fixture.scheduler.motion?()
    #expect(fixture.source.readCount == reads + 1)
    #expect(fixture.deliveries.last?.window == fixture.source.window)
    fixture.move(x: 22)
    fixture.mouse(.leftMouseUp)
    #expect(fixture.source.readCount == reads + 2)
    #expect(fixture.deliveries.last?.window == fixture.source.window)
  }

  @Test func draggingContentDoesNotInventWindowMovement() {
    let fixture = WindowFollowFixture()
    fixture.tracker.start()
    defer { fixture.tracker.stop() }
    fixture.mouse(.leftMouseDown)
    let delivered = fixture.deliveries.count
    for _ in 0..<120 {
      fixture.time += 1.0 / 120.0
      fixture.mouse(.leftMouseDragged)
      fixture.scheduler.frame?()
    }
    #expect(fixture.deliveries.count == delivered)
    #expect(fixture.movements.isEmpty, "Content selection must not hide the quota")
  }

  @Test func stationaryHeldMousePausesAndResumesWithoutRediscovery() {
    let fixture = WindowFollowFixture()
    fixture.tracker.start()
    defer { fixture.tracker.stop() }
    fixture.mouse(.leftMouseDown)
    let discoveries = fixture.source.discoveryCount
    fixture.time += 2
    fixture.scheduler.idle?()
    #expect(fixture.scheduler.isDisplayLinkPaused)
    #expect(fixture.source.discoveryCount == discoveries)
    fixture.move(x: 30)
    fixture.mouse(.leftMouseDragged)
    #expect(fixture.scheduler.isDisplayLinkPaused)
    #expect(fixture.scheduler.motion != nil)
    #expect(fixture.deliveries.last?.window == fixture.source.window)
    #expect(fixture.source.discoveryCount == discoveries)
  }

  @Test func unavailableWindowBacksOffAndCanFindAReplacement() {
    let fixture = WindowFollowFixture()
    fixture.tracker.start()
    defer { fixture.tracker.stop() }
    fixture.source.window = nil
    fixture.scheduler.frame?()
    #expect(fixture.scheduler.isDisplayLinkPaused)
    #expect(fixture.deliveries.last?.window == nil)
    let discoveries = fixture.source.discoveryCount
    fixture.time += 0.5
    fixture.scheduler.idle?()
    #expect(fixture.source.discoveryCount == discoveries)
    fixture.time += 0.6
    fixture.scheduler.idle?()
    #expect(fixture.source.discoveryCount == discoveries + 1)
    fixture.source.window = TrackedCodexWindow(
      id: 99, processID: 321,
      frame: NSRect(x: 400, y: 200, width: 800, height: 600))
    fixture.time += 1.1
    fixture.scheduler.idle?()
    #expect(fixture.deliveries.last?.window == fixture.source.window)
    #expect(!fixture.scheduler.isDisplayLinkPaused)
  }

  @Test func routineDiscoveryKeepsTheWindowIDAndExplicitSelectionMayReplaceIt() {
    let fixture = WindowFollowFixture()
    fixture.tracker.start()
    defer { fixture.tracker.stop() }
    #expect(fixture.source.discoveryPreferences == [nil])
    fixture.time += 1.1
    fixture.scheduler.idle?()
    #expect(fixture.source.discoveryPreferences.last == fixture.source.window?.id)
    fixture.tracker.refresh(selectFrontWindow: true)
    #expect(fixture.source.discoveryPreferences.last! == nil)
  }

  @Test func stopCancelsClocksAndOldCallbacksCannotMoveThePanel() {
    let fixture = WindowFollowFixture()
    fixture.tracker.start()
    fixture.tracker.start()
    #expect(fixture.scheduler.startCount == 1)
    let oldFrame = fixture.scheduler.frame
    let oldIdle = fixture.scheduler.idle
    let oldMouse = fixture.scheduler.mouse
    let deliveries = fixture.deliveries.count
    let reads = fixture.source.readCount
    fixture.tracker.stop()
    fixture.tracker.stop()
    #expect(fixture.scheduler.stopCount == 1)
    #expect(
      fixture.scheduler.frame == nil && fixture.scheduler.idle == nil
        && fixture.scheduler.mouse == nil)
    fixture.move(x: 300)
    oldFrame?()
    oldIdle?()
    oldMouse?(.leftMouseDragged)
    fixture.tracker.refresh(selectFrontWindow: true)
    #expect(fixture.deliveries.count == deliveries)
    #expect(fixture.source.readCount == reads)
    fixture.tracker.start()
    #expect(fixture.scheduler.startCount == 2)
    #expect(fixture.deliveries.last?.window == fixture.source.window)
    fixture.tracker.stop()
  }

  @Test func idleAndOtherApplicationsDoNotKeepTheDisplayLinkRunning() {
    let fixture = WindowFollowFixture()
    fixture.tracker.start()
    defer { fixture.tracker.stop() }
    fixture.time += 0.3
    fixture.scheduler.frame?()
    #expect(fixture.scheduler.isDisplayLinkPaused)
    fixture.source.isCodexFrontmost = false
    let reads = fixture.source.readCount
    let deliveries = fixture.deliveries.count
    fixture.scheduler.mouse?(.leftMouseDown)
    fixture.scheduler.mouse?(.leftMouseDragged)
    #expect(fixture.source.readCount == reads)
    #expect(fixture.deliveries.count == deliveries)
    #expect(fixture.scheduler.isDisplayLinkPaused)
  }

  @Test func hidesBeforeRepositioningAndStaysHiddenUntilReleaseAndStableGeometry() {
    let fixture = WindowFollowFixture()
    fixture.tracker.start()
    defer { fixture.tracker.stop() }
    fixture.mouse(.leftMouseDown)
    #expect(fixture.movements.isEmpty)
    fixture.move(x: 10)
    fixture.mouse(.leftMouseDragged)
    #expect(Array(fixture.events.suffix(2)) == ["hide", "position"])
    for _ in 0..<10 {
      fixture.time += 0.3
      fixture.scheduler.motion?()
      #expect(fixture.tracker.isWindowMoving, "A pause with the mouse held must not flash")
    }
    fixture.mouse(.leftMouseUp)
    fixture.time += 0.08
    fixture.scheduler.motion?()
    #expect(fixture.tracker.isWindowMoving)
    // WindowServer may report a late final move or a snap after mouse-up.
    fixture.move(x: 35)
    fixture.scheduler.motion?()
    fixture.time += 0.08
    fixture.scheduler.motion?()
    #expect(fixture.tracker.isWindowMoving)
    fixture.time += 0.05
    fixture.scheduler.motion?()
    #expect(!fixture.tracker.isWindowMoving)
    #expect(fixture.movements == [true, false])
    #expect(fixture.events.last == "restore")
    #expect(fixture.deliveries.last?.window == fixture.source.window)
    #expect(fixture.scheduler.motion == nil)
    #expect(fixture.scheduler.isDisplayLinkPaused)
  }

  @Test func missedMouseUpAndProgrammaticMovementBothSettleWithoutDisplayFrames() {
    for mouseDriven in [false, true] {
      let fixture = WindowFollowFixture()
      fixture.tracker.start()
      if mouseDriven { fixture.mouse(.leftMouseDown) }
      fixture.move(x: 20)
      fixture.scheduler.frame?()
      #expect(fixture.tracker.isWindowMoving)
      fixture.source.isMouseButtonDown = false  // No mouse-up callback arrives.
      fixture.scheduler.motion?()
      fixture.time += 0.13
      fixture.scheduler.motion?()
      #expect(!fixture.tracker.isWindowMoving)
      #expect(fixture.movements == [true, false])
      fixture.tracker.stop()
    }
  }

  @Test func missingTargetStaysHiddenAndReplacementMustSettleBeforeRestoring() {
    let fixture = WindowFollowFixture()
    fixture.tracker.start()
    defer { fixture.tracker.stop() }
    fixture.mouse(.leftMouseDown)
    fixture.move(x: 20)
    fixture.mouse(.leftMouseDragged)
    fixture.source.window = nil
    fixture.mouse(.leftMouseUp)
    fixture.time += 2
    fixture.scheduler.motion?()
    fixture.scheduler.idle?()
    #expect(fixture.tracker.isWindowMoving)
    #expect(fixture.movements == [true])
    #expect(fixture.scheduler.motion == nil, "Missing windows only need idle recovery")
    fixture.source.window = TrackedCodexWindow(
      id: 99, processID: 321, frame: NSRect(x: 400, y: 200, width: 800, height: 600))
    fixture.time += 1.1
    fixture.scheduler.idle?()
    #expect(fixture.tracker.isWindowMoving)
    fixture.time += 0.13
    fixture.scheduler.motion?()
    #expect(fixture.movements == [true, false])
    #expect(fixture.deliveries.last?.window == fixture.source.window)
  }

  @Test func stoppingAndRestartingInvalidatesEveryOldMovementCallback() {
    let fixture = WindowFollowFixture()
    fixture.tracker.start()
    fixture.mouse(.leftMouseDown)
    fixture.move(x: 20)
    fixture.mouse(.leftMouseDragged)
    let oldMotion = fixture.scheduler.motion
    let oldFrame = fixture.scheduler.frame
    let oldMouse = fixture.scheduler.mouse
    let oldIdle = fixture.scheduler.idle
    fixture.tracker.stop()
    #expect(fixture.movements == [true, false])
    #expect(fixture.scheduler.motion == nil)
    fixture.tracker.start()
    let reads = fixture.source.readCount
    let deliveries = fixture.deliveries.count
    fixture.move(x: 50)
    oldMotion?()
    oldFrame?()
    oldMouse?(.leftMouseDragged)
    oldIdle?()
    #expect(fixture.source.readCount == reads)
    #expect(fixture.deliveries.count == deliveries)
    #expect(!fixture.tracker.isWindowMoving)
    fixture.tracker.stop()
  }
}

extension FloatingPanelLayoutTests {
  @Test @MainActor func nativeSettlementClockRunsWhileWindowIsInvisibleAndCleansUp() async throws {
    let window = NSPanel(
      contentRect: NSRect(x: 100, y: 200, width: 180, height: 54),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let scheduler = DisplayLinkedWindowFollowScheduler(window: window)
    defer {
      scheduler.stop()
      window.orderOut(nil)
    }
    window.orderFrontRegardless()
    window.alphaValue = 0
    window.ignoresMouseEvents = true
    scheduler.start(onDisplayFrame: {}, onIdle: {}, onMouse: { _ in })
    var checks = 0
    scheduler.setMotionCheck { checks += 1 }
    let clock = ContinuousClock()
    let start = clock.now
    while checks < 3, start.duration(to: clock.now) < .seconds(2) {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(checks >= 3)
    scheduler.setMotionCheck(nil)
    let settledChecks = checks
    try await Task.sleep(for: .milliseconds(100))
    #expect(checks == settledChecks)
    scheduler.setMotionCheck { checks += 1 }
    scheduler.stop()
    try await Task.sleep(for: .milliseconds(100))
    #expect(checks == settledChecks)
  }

  @Test @MainActor func nativeDisplayLinkDeliversFramesAndStopsCleanly() async throws {
    let window = NSPanel(
      contentRect: NSRect(x: 150, y: 200, width: 180, height: 54),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 54))
    let scheduler = DisplayLinkedWindowFollowScheduler(window: window)
    defer {
      scheduler.stop()
      window.orderOut(nil)
    }
    window.orderFrontRegardless()
    var frames = 0
    scheduler.start(onDisplayFrame: { frames += 1 }, onIdle: {}, onMouse: { _ in })
    scheduler.isDisplayLinkPaused = false
    let clock = ContinuousClock()
    let start = clock.now
    while frames < 3, start.duration(to: clock.now) < .seconds(3) {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(frames >= 3, "The native clock must actually deliver display-linked callbacks")
    scheduler.isDisplayLinkPaused = true
    let pausedFrames = frames
    try await Task.sleep(for: .milliseconds(80))
    #expect(frames == pausedFrames)
    scheduler.stop()
    scheduler.stop()
    try await Task.sleep(for: .milliseconds(80))
    #expect(frames == pausedFrames)
  }
}

@MainActor
private final class WindowFollowFixture {
  var time: TimeInterval = 100
  let source = FakeWindowGeometrySource()
  let scheduler = FakeWindowFollowScheduler()
  var deliveries: [(window: TrackedCodexWindow?, time: TimeInterval)] = []
  var movements: [Bool] = []
  var events: [String] = []
  lazy var tracker = CodexWindowTracker(
    source: source, scheduler: scheduler,
    now: { [weak self] in self?.time ?? 0 },
    onMovementChanged: { [weak self] moving in
      self?.movements.append(moving)
      self?.events.append(moving ? "hide" : "restore")
    },
    onChange: { [weak self] window in
      guard let self else { return }
      deliveries.append((window, time))
      events.append("position")
    })

  func mouse(_ type: NSEvent.EventType) {
    source.isMouseButtonDown = type != .leftMouseUp
    scheduler.mouse?(type)
  }

  func move(x: CGFloat) {
    guard let window = source.window else { return }
    source.window = TrackedCodexWindow(
      id: window.id, processID: window.processID,
      frame: NSRect(x: 100 + x, y: 200, width: 800, height: 600))
  }
}

@MainActor
private final class FakeWindowGeometrySource: CodexWindowGeometrySource {
  var window: TrackedCodexWindow? = TrackedCodexWindow(
    id: 12, processID: 123,
    frame: NSRect(x: 100, y: 200, width: 800, height: 600))
  var isCodexFrontmost = true
  var isMouseButtonDown = false
  var discoveryCount = 0
  var discoveryPreferences: [CGWindowID?] = []
  var readCount = 0
  var onRead: (() -> Void)?

  func discover(preferred: TrackedCodexWindow?) -> TrackedCodexWindow? {
    discoveryCount += 1
    discoveryPreferences.append(preferred?.id)
    return window
  }

  func readWindow(_ target: TrackedCodexWindow) -> TrackedCodexWindow? {
    readCount += 1
    onRead?()
    guard window?.id == target.id, window?.processID == target.processID else { return nil }
    return window
  }
}

@MainActor
private final class FakeWindowFollowScheduler: WindowFollowScheduling {
  var isDisplayLinkPaused = true
  var startCount = 0
  var stopCount = 0
  var frame: (@MainActor () -> Void)?
  var idle: (@MainActor () -> Void)?
  var mouse: (@MainActor (NSEvent.EventType) -> Void)?
  var motion: (@MainActor () -> Void)?

  func setMotionCheck(_ callback: (@MainActor () -> Void)?) { motion = callback }

  func start(
    onDisplayFrame: @escaping @MainActor () -> Void, onIdle: @escaping @MainActor () -> Void,
    onMouse: @escaping @MainActor (NSEvent.EventType) -> Void
  ) {
    startCount += 1
    frame = onDisplayFrame
    idle = onIdle
    mouse = onMouse
    isDisplayLinkPaused = true
  }

  func stop() {
    stopCount += 1
    isDisplayLinkPaused = true
    frame = nil
    idle = nil
    mouse = nil
    motion = nil
  }
}
