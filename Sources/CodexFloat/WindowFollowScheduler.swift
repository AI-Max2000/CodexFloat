import AppKit
import QuartzCore

@MainActor
protocol WindowFollowScheduling: AnyObject {
  var isDisplayLinkPaused: Bool { get set }
  func start(
    onDisplayFrame: @escaping @MainActor () -> Void, onIdle: @escaping @MainActor () -> Void,
    onMouse: @escaping @MainActor (NSEvent.EventType) -> Void)
  func setMotionCheck(_ callback: (@MainActor () -> Void)?)
  func stop()
}

/// Production event delivery is synchronous on the main run loop.
/// Hidden windows may stop receiving display-link callbacks, so settling uses
/// a separate, temporary clock. It is removed as soon as movement ends.
@MainActor
final class DisplayLinkedWindowFollowScheduler: WindowFollowScheduling {
  private weak var window: NSWindow?
  private var displayLink: CADisplayLink?
  private var idleTimer: Timer?
  private var motionTimer: Timer?
  private var mouseMonitor: Any?
  private var screenObserver: NSObjectProtocol?
  private let displayTarget = DisplayLinkTarget()

  init(window: NSWindow) { self.window = window }

  var isDisplayLinkPaused: Bool {
    get { displayLink?.isPaused ?? true }
    set { displayLink?.isPaused = newValue }
  }

  func start(
    onDisplayFrame: @escaping @MainActor () -> Void, onIdle: @escaping @MainActor () -> Void,
    onMouse: @escaping @MainActor (NSEvent.EventType) -> Void
  ) {
    guard displayLink == nil, let window else { return }
    displayTarget.onFrame = onDisplayFrame
    let link = window.displayLink(
      target: displayTarget, selector: #selector(DisplayLinkTarget.tick(_:)))
    displayLink = link
    updateFrameRateRange()
    link.isPaused = true
    link.add(to: .main, forMode: .common)
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.updateFrameRateRange() }
    }
    // AppKit guarantees global monitor handlers run on the main thread. There
    // is no Task hop: the first drag is sampled and applied before returning.
    mouseMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
    ) { event in
      MainActor.assumeIsolated { onMouse(event.type) }
    }
    let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
      MainActor.assumeIsolated { onIdle() }
    }
    timer.tolerance = 0.025
    idleTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func stop() {
    setMotionCheck(nil)
    displayLink?.invalidate()
    displayLink = nil
    displayTarget.onFrame = nil
    idleTimer?.invalidate()
    idleTimer = nil
    if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    mouseMonitor = nil
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    screenObserver = nil
  }

  func setMotionCheck(_ callback: (@MainActor () -> Void)?) {
    motionTimer?.invalidate()
    motionTimer = nil
    guard let callback else { return }
    let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { _ in
      MainActor.assumeIsolated { callback() }
    }
    timer.tolerance = 0.003
    motionTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func updateFrameRateRange() {
    let maximum = Float(max(1, window?.screen?.maximumFramesPerSecond ?? 60))
    displayLink?.preferredFrameRateRange = CAFrameRateRange(
      minimum: min(60, maximum), maximum: maximum, preferred: maximum)
  }
}

@MainActor
private final class DisplayLinkTarget: NSObject {
  var onFrame: (@MainActor () -> Void)?
  @objc func tick(_ link: CADisplayLink) { onFrame?() }
}
