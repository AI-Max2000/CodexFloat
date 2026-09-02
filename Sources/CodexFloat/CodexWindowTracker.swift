import AppKit
import CoreGraphics
import QuartzCore

/// Window geometry only. Never requests screen capture or reads titles/content.
struct TrackedCodexWindow: Equatable {
  let id: CGWindowID
  let processID: pid_t
  let frame: NSRect
}

enum CodexWindowGeometry {
  static func appKitFrame(fromQuartz frame: CGRect, primaryScreenTop: CGFloat) -> NSRect {
    NSRect(
      x: frame.minX, y: primaryScreenTop - frame.maxY,
      width: frame.width, height: frame.height)
  }

  static func window(
    from info: [String: Any], processID: pid_t,
    primaryScreenTop: CGFloat
  ) -> TrackedCodexWindow? {
    guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID,
      (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
      (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
      let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
      let bounds = info[kCGWindowBounds as String] as? [String: Any],
      let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
      frame.width >= 400, frame.height >= 240,
      frame.minX.isFinite, frame.minY.isFinite,
      frame.width.isFinite, frame.height.isFinite
    else { return nil }
    return TrackedCodexWindow(
      id: id, processID: processID,
      frame: appKitFrame(fromQuartz: frame, primaryScreenTop: primaryScreenTop))
  }
}

@MainActor
protocol CodexWindowGeometrySource: AnyObject {
  var isCodexFrontmost: Bool { get }
  var isMouseButtonDown: Bool { get }
  func readWindow(_ window: TrackedCodexWindow) -> TrackedCodexWindow?
  func discover(preferred: TrackedCodexWindow?) -> TrackedCodexWindow?
}

@MainActor
final class CodexWindowTracker {
  private let source: any CodexWindowGeometrySource
  private let scheduler: any WindowFollowScheduling
  private let now: () -> TimeInterval
  private let onChange: (TrackedCodexWindow?) -> Void
  private let onMovementChanged: (Bool) -> Void
  private(set) var isRunning = false
  private(set) var isWindowMoving = false
  private var lastGeometryChange: TimeInterval = -.infinity
  private var runGeneration: UInt = 0
  static let movementSettleDelay: TimeInterval = 0.12
  private var target: TrackedCodexWindow?
  private var activeUntil: TimeInterval = -.infinity
  private var lastSampleTime: TimeInterval = -.infinity
  private var nextDiscovery: TimeInterval = 0
  private var mouseInteractionActive = false
  private var hasDragged = false
  private var pendingDiscovery = false

  convenience init(
    window: NSWindow, onMovementChanged: @escaping (Bool) -> Void = { _ in },
    onChange: @escaping (TrackedCodexWindow?) -> Void
  ) {
    self.init(
      source: SystemCodexWindowGeometrySource(),
      scheduler: DisplayLinkedWindowFollowScheduler(window: window),
      onMovementChanged: onMovementChanged, onChange: onChange)
  }

  init(
    source: any CodexWindowGeometrySource, scheduler: any WindowFollowScheduling,
    now: @escaping () -> TimeInterval = CACurrentMediaTime,
    onMovementChanged: @escaping (Bool) -> Void = { _ in },
    onChange: @escaping (TrackedCodexWindow?) -> Void
  ) {
    self.source = source
    self.scheduler = scheduler
    self.now = now
    self.onChange = onChange
    self.onMovementChanged = onMovementChanged
  }

  func start() {
    guard !isRunning else { return }
    isRunning = true
    runGeneration &+= 1
    let generation = runGeneration
    scheduler.start(
      onDisplayFrame: { [weak self] in
        guard let self, self.runGeneration == generation else { return }
        self.displayFrame()
      },
      onIdle: { [weak self] in
        guard let self, self.runGeneration == generation else { return }
        self.idleTick()
      },
      onMouse: { [weak self] type in
        guard let self, self.runGeneration == generation else { return }
        self.mouseEvent(type)
      })
    refresh(selectFrontWindow: true)
  }

  func stop() {
    guard isRunning else { return }
    isRunning = false
    runGeneration &+= 1
    scheduler.stop()
    if isWindowMoving {
      isWindowMoving = false
      onMovementChanged(false)
    }
    lastGeometryChange = -.infinity
    target = nil
    activeUntil = -.infinity
    lastSampleTime = -.infinity
    nextDiscovery = 0
    mouseInteractionActive = false
    hasDragged = false
    pendingDiscovery = false
  }

  func refresh(selectFrontWindow: Bool = false) {
    guard isRunning else { return }
    pendingDiscovery = pendingDiscovery || selectFrontWindow
    // Activation/screen notifications must not force an all-window scan into
    // a live drag or a system window animation. Resolve them after it settles.
    if isWindowMoving || mouseInteractionActive || now() < activeUntil {
      sampleTarget()
    } else {
      calibrate()
    }
  }

  private func mouseEvent(_ type: NSEvent.EventType) {
    guard isRunning else { return }
    switch type {
    case .leftMouseDown:
      guard source.isCodexFrontmost else { return }
      // Select once before dragging. During the drag, the window ID is locked.
      mouseInteractionActive = false
      pendingDiscovery = true
      if !isWindowMoving { calibrate() }
      mouseInteractionActive = true
      hasDragged = false
      activateDisplayLink()
    case .leftMouseDragged:
      guard mouseInteractionActive || source.isCodexFrontmost else { return }
      mouseInteractionActive = true
      activateDisplayLink()
      // Detect the first real move promptly; once invisible, 30 Hz is enough
      // to maintain the offset. Content drags alone never hide the panel.
      let interval = isWindowMoving ? 1.0 / 30.0 : 1.0 / 240.0
      if !hasDragged || now() - lastSampleTime >= interval { sampleTarget() }
      hasDragged = true
    case .leftMouseUp:
      guard mouseInteractionActive else { return }
      mouseInteractionActive = false
      hasDragged = false
      sampleTarget()  // Always commit the final position, even inside the event budget.
      if isWindowMoving { lastGeometryChange = now() }
      activateDisplayLink()
    default:
      break
    }
  }

  private func displayFrame() {
    guard isRunning, !isWindowMoving, !scheduler.isDisplayLinkPaused else { return }
    guard now() < activeUntil else {
      scheduler.isDisplayLinkPaused = true
      return
    }
    // No sleeps, self-rescheduling timers, discovery or task/queue hops here.
    sampleTarget()
  }

  private func idleTick() {
    guard isRunning else { return }
    if isWindowMoving {
      // Keep a missing/minimized target hidden until a valid window returns.
      // Never switch targets in the middle of a held drag.
      if target == nil, !source.isMouseButtonDown { calibrate() }
      return
    }
    if !source.isMouseButtonDown { mouseInteractionActive = false }
    guard now() >= activeUntil else { return }
    scheduler.isDisplayLinkPaused = true
    if mouseInteractionActive {
      // A stationary held mouse is idle, but must not allow a target switch.
      sampleTarget()
    } else {
      calibrate()
    }
  }

  private func calibrate() {
    let time = now()
    if pendingDiscovery || time >= nextDiscovery {
      let forceDelivery = pendingDiscovery
      pendingDiscovery = false
      nextDiscovery = time + 1
      let candidate = source.discover(preferred: source.isCodexFrontmost ? nil : target)
      lastSampleTime = now()
      deliver(candidate, force: forceDelivery)
    } else {
      sampleTarget()
    }
  }

  private func sampleTarget() {
    guard let target else { return }
    let sample = source.readWindow(target)
    lastSampleTime = now()
    deliver(sample)
  }

  private func deliver(_ sample: TrackedCodexWindow?, force: Bool = false) {
    let previous = target
    let changed = target != sample
    if let previous, let sample,
      previous.id == sample.id, previous.processID == sample.processID,
      previous.frame != sample.frame
    {
      lastGeometryChange = now()
      // Hide BEFORE applying the new position, never show a chasing frame.
      setWindowMoving(true)
    } else if isWindowMoving, changed, sample != nil {
      lastGeometryChange = now()
    }
    target = sample
    if changed, sample != nil { activateDisplayLink() }
    if sample == nil {
      scheduler.isDisplayLinkPaused = true
      activeUntil = -.infinity
      scheduler.setMotionCheck(nil)
    } else if isWindowMoving, previous == nil {
      startMotionCheck()
    }
    if changed || force { onChange(sample) }
  }

  private func activateDisplayLink() {
    guard target != nil, !isWindowMoving else { return }
    activeUntil = now() + 0.25
    scheduler.isDisplayLinkPaused = false
  }

  private func setWindowMoving(_ moving: Bool) {
    guard isWindowMoving != moving else { return }
    isWindowMoving = moving
    scheduler.isDisplayLinkPaused = true
    activeUntil = -.infinity
    if moving {
      startMotionCheck()
    } else {
      scheduler.setMotionCheck(nil)
    }
    onMovementChanged(moving)
  }

  private func startMotionCheck() {
    let generation = runGeneration
    scheduler.setMotionCheck { [weak self] in
      guard let self, self.isRunning, self.runGeneration == generation,
        self.isWindowMoving
      else { return }
      self.checkMovementSettled()
    }
  }

  private func checkMovementSettled() {
    sampleTarget()
    guard target != nil, !source.isMouseButtonDown else { return }
    if mouseInteractionActive { lastGeometryChange = now() }
    mouseInteractionActive = false
    hasDragged = false
    // Covers mouse-up delivery lag, missed mouse-up, and system snap animations.
    // Every late geometry change restarts the quiet period.
    if now() - lastGeometryChange >= Self.movementSettleDelay {
      setWindowMoving(false)
    }
  }
}

@MainActor
final class SystemCodexWindowGeometrySource: CodexWindowGeometrySource {
  var isCodexFrontmost: Bool {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.openai.codex"
  }

  var isMouseButtonDown: Bool { NSEvent.pressedMouseButtons & 1 == 1 }

  func readWindow(_ window: TrackedCodexWindow) -> TrackedCodexWindow? {
    guard
      let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, window.id)
        as? [[String: Any]]
    else { return nil }
    return info.first(where: {
      ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == window.id
    }).flatMap {
      CodexWindowGeometry.window(
        from: $0, processID: window.processID,
        primaryScreenTop: NSScreen.screens.first?.frame.maxY ?? 0)
    }
  }

  func discover(preferred: TrackedCodexWindow?) -> TrackedCodexWindow? {
    let applications = NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.openai.codex")
    guard let app = applications.first(where: { $0.isActive }) ?? applications.first,
      let infos = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID) as? [[String: Any]]
    else { return nil }
    let windows = infos.compactMap {
      CodexWindowGeometry.window(
        from: $0, processID: app.processIdentifier,
        primaryScreenTop: NSScreen.screens.first?.frame.maxY ?? 0)
    }
    return windows.first(where: { $0.id == preferred?.id && $0.processID == preferred?.processID })
      ?? windows.first
  }
}
