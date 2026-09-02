import AppKit
import Combine
import SwiftUI

final class FloatingPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor
private final class FloatingPanelHostingView<Content: View>: NSHostingView<Content> {
  override var isOpaque: Bool { false }

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    configureSurfaceLayer()
  }

  func configureSurfaceLayer() {
    configureRoundedTransparentLayer(for: self)
    if let superview {
      // NSWindow owns a private frame view outside NSHostingView. Masking both
      // layers prevents that rectangular backing layer from flashing at a far corner.
      configureRoundedTransparentLayer(for: superview)
    }
  }

  private func configureRoundedTransparentLayer(for view: NSView) {
    view.wantsLayer = true
    view.layerContentsRedrawPolicy = .duringViewResize
    view.layer?.backgroundColor = NSColor.clear.cgColor
    view.layer?.isOpaque = false
    view.layer?.cornerRadius = FloatingPanelLayout.panelCornerRadius
    view.layer?.cornerCurve = .continuous
    view.layer?.masksToBounds = true
  }
}

@MainActor
final class PanelUIState: ObservableObject {
  private let defaults: UserDefaults

  @Published var isCollapsed: Bool {
    didSet { defaults.set(isCollapsed, forKey: "panelCollapsed") }
  }

  /// Keeps the fixed compact entry and final-size liquid surface alive during handoff.
  @Published var isCollapsing = false
  @Published var isExpanding = false
  @Published var expandedCanvasSize = NSSize(width: 340, height: 260)
  @Published var revealProgress: CGFloat
  @Published var menuBarPresentationProgress: CGFloat = 1

  init(defaults: UserDefaults = .standard, initiallyCollapsed: Bool) {
    self.defaults = defaults
    isCollapsed = initiallyCollapsed
    revealProgress = initiallyCollapsed ? 0 : 1
    defaults.set(initiallyCollapsed, forKey: "panelCollapsed")
  }
}

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
  @MainActor private enum Motion {
    // Direction 14: the surface and its content share one fixed anchor and
    // damped liquid-capsule curve, with a slightly quicker reverse roll-up.
    static let expansionDuration = FloatingPanelLayout.hoverExpansionDuration
    static let collapseDuration = LiquidCapsuleMotion.collapseDuration
  }

  private enum Size {
    static let expanded = NSSize(width: 340, height: 260)
    static let minimumExpanded = NSSize(width: 340, height: 104)
    static let maximumExpanded = NSSize(width: 520, height: 680)

    static func collapsed(for mode: QuotaDisplayMode) -> NSSize {
      switch mode {
      case .standard:
        NSSize(
          width: FloatingPanelLayout.collapsedWidth,
          height: FloatingPanelLayout.collapsedHeight
        )
      case .minimal:
        NSSize(
          width: FloatingPanelLayout.minimalCollapsedWidth,
          height: FloatingPanelLayout.minimalCollapsedHeight
        )
      case .menuBar:
        NSSize(
          width: FloatingPanelLayout.collapsedWidth,
          height: FloatingPanelLayout.collapsedHeight
        )
      }
    }
  }

  let panel: FloatingPanel
  private let model: AppModel
  private let state: PanelUIState
  private let placement: PanelPlacementStore
  private var activePlacementMode: QuotaDisplayMode
  private var expandedSize = Size.expanded
  private var preferredExpandedHeight = Size.expanded.height
  private var collapseTask: Task<Void, Never>?
  private var hoverSettingSubscription: AnyCancellable?
  private var displayModeSubscription: AnyCancellable?
  private var feedbackSubscription: AnyCancellable?
  private var feedbackPresentationIsActive = false
  private var feedbackPresentationWasCollapsed = false
  private var menuBarAnchorFrame: NSRect?
  private var collapsedRestingFrame: NSRect?
  private var surfaceTransitionGeneration: UInt = 0
  private var surfaceTransitionCompletion: (@MainActor () -> Void)?
  private var surfaceTransitionTask: Task<Void, Never>?
  private var menuBarPresentationTask: Task<Void, Never>?
  private var placementSaveTask: Task<Void, Never>?
  private var minimalDragStartFrame: NSRect?
  private var minimalDragVisibleFrame: NSRect?
  private var isDraggingMinimalBar = false
  private var suppressMinimalHoverUntilExit = false
  private var isAligningStandardCollapsedFrame = false
  private var userMoveIsInProgress = false
  private var userResizeIsInProgress = false
  private var pendingUserPlacement: PendingUserPlacement?
  var onVisibilityChanged: ((Bool) -> Void)?
  var onOpenSettings: (() -> Void)?
  var onRequestHide: (() -> Void)?
  var onMenuBarHoverChanged: ((Bool) -> Void)?

  private struct PendingUserPlacement {
    let frame: NSRect
    let mode: QuotaDisplayMode
    let expandedWidth: CGFloat
  }

  init(
    model: AppModel,
    placement: PanelPlacementStore = PanelPlacementStore(),
    panelStateDefaults: UserDefaults = .standard
  ) {
    self.model = model
    self.placement = placement
    activePlacementMode = model.settings.quotaDisplayMode
    state = PanelUIState(
      defaults: panelStateDefaults,
      initiallyCollapsed: model.settings.hoverExpansionEnabled
    )
    panel = FloatingPanel(
      contentRect: NSRect(origin: .zero, size: Size.expanded),
      styleMask: [.borderless, .nonactivatingPanel, .resizable],
      backing: .buffered,
      defer: false
    )
    super.init()

    panel.delegate = self
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    // AppKit shadows use the rectangular NSWindow frame while SwiftUI draws a
    // rounded transparent surface. Resizing the two shapes independently leaves
    // a white rectangular fringe, so separation is provided by the SwiftUI border.
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isMovableByWindowBackground = model.settings.quotaDisplayMode != .menuBar
    panel.animationBehavior = .utilityWindow
    panel.minSize = Size.minimumExpanded
    panel.maxSize = Size.maximumExpanded

    let root = FloatingPanelView(
      model: model,
      settings: model.settings,
      panelState: state,
      onHoverChanged: { [weak self] isHovering in self?.handleHover(isHovering) },
      onMinimalDragChanged: { [weak self] translation, ended in
        self?.handleMinimalDrag(translation: translation, ended: ended)
      },
      onRefresh: { [weak model] in model?.refreshAll() },
      onOpenSettings: { [weak self] in self?.onOpenSettings?() },
      onHide: { [weak self] in self?.onRequestHide?() },
      onPreferredExpandedHeightChanged: { [weak self] height in
        self?.applyPreferredExpandedHeight(height)
      }
    )
    let hosting = FloatingPanelHostingView(rootView: root)
    // The controller owns the window frame. NSHostingView's default sizing
    // options can otherwise propagate SwiftUI's unbounded maximum height back
    // into a resizable NSPanel and stretch it to the full visible screen.
    hosting.sizingOptions = []
    hosting.autoresizingMask = [.width, .height]
    hosting.configureSurfaceLayer()
    panel.contentView = hosting
    if activePlacementMode != .menuBar {
      placement.restore(
        panel: panel,
        mode: activePlacementMode,
        defaultSize: Size.expanded,
        minimumWidth: Size.minimumExpanded.width,
        maximumWidth: Size.maximumExpanded.width,
        initialFrame: CodexInitialPanelPlacement.frame(panelSize: Size.expanded)
      )
    } else {
      panel.setFrame(CodexInitialPanelPlacement.frame(panelSize: Size.expanded), display: false)
    }
    expandedSize = NSSize(
      width: min(Size.maximumExpanded.width, max(Size.minimumExpanded.width, panel.frame.width)),
      height: Size.expanded.height
    )
    state.expandedCanvasSize = expandedSize
    preferredExpandedHeight = Size.expanded.height
    if state.isCollapsed {
      panel.styleMask.remove(.resizable)
      if model.settings.quotaDisplayMode == .minimal {
        panel.isMovableByWindowBackground = false
      }
      var frame = panel.frame
      frame.origin.y += frame.height - collapsedSize.height
      frame.size = collapsedSize
      panel.setFrame(frame, display: false)
      placement.clampToAvailableScreens(panel: panel)
      alignStandardCollapsedFrameIfNeeded()
      collapsedRestingFrame = panel.frame
    } else {
      resize(to: expandedSize, animated: false)
    }

    hoverSettingSubscription = model.settings.$hoverExpansionEnabled.dropFirst().sink {
      [weak self] isEnabled in
      Task { @MainActor [weak self] in self?.applyHoverMode(isEnabled) }
    }
    displayModeSubscription = model.settings.$quotaDisplayMode.dropFirst().sink {
      [weak self] _ in
      Task { @MainActor [weak self] in self?.applyDisplayMode() }
    }
    feedbackSubscription = model.$transientFeedback.dropFirst().sink { [weak self] feedback in
      Task { @MainActor [weak self] in self?.applyFeedback(feedback) }
    }
  }

  func show(expanded: Bool = false) {
    menuBarPresentationTask?.cancel()
    menuBarPresentationTask = nil
    if model.transientFeedback != nil, model.settings.quotaDisplayMode != .menuBar {
      setCollapsed(false, animated: false)
    } else if expanded {
      setCollapsed(false, animated: false)
    } else if model.settings.hoverExpansionEnabled, !pointerIsInsidePanel {
      setCollapsed(true, animated: false)
    }
    ensureVisible()
    let shouldRevealFromMenuBar =
      model.settings.quotaDisplayMode == .menuBar
      && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    if shouldRevealFromMenuBar, !panel.isVisible {
      var transaction = Transaction(animation: nil)
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        state.menuBarPresentationProgress = 0
      }
    }
    panel.orderFrontRegardless()
    if shouldRevealFromMenuBar, state.menuBarPresentationProgress < 1 {
      // Commit the zero-height mask once before starting the reveal; mutating
      // both values in the same run-loop turn lets SwiftUI coalesce away the
      // first visible frame.
      menuBarPresentationTask = Task { @MainActor [weak self] in
        await Task.yield()
        guard let self, !Task.isCancelled, self.panel.isVisible else { return }
        withAnimation(
          LiquidCapsuleMotion.animation(expanding: true, reduceMotion: false)
        ) {
          self.state.menuBarPresentationProgress = 1
        }
        self.menuBarPresentationTask = nil
      }
    } else if !shouldRevealFromMenuBar {
      state.menuBarPresentationProgress = 1
    }
    onVisibilityChanged?(true)
    model.refreshAfterWakeOrShow()
  }

  func hide() {
    collapseTask?.cancel()
    finishSurfaceTransitionIfNeeded()
    menuBarPresentationTask?.cancel()
    let shouldCollapseIntoMenuBar =
      model.settings.quotaDisplayMode == .menuBar
      && panel.isVisible
      && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    guard shouldCollapseIntoMenuBar else {
      panel.orderOut(nil)
      state.menuBarPresentationProgress = 1
      onVisibilityChanged?(false)
      return
    }
    withAnimation(
      LiquidCapsuleMotion.animation(expanding: false, reduceMotion: false)
    ) {
      state.menuBarPresentationProgress = 0
    }
    menuBarPresentationTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(LiquidCapsuleMotion.collapseDuration))
      guard let self, !Task.isCancelled else { return }
      self.panel.orderOut(nil)
      var transaction = Transaction(animation: nil)
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        self.state.menuBarPresentationProgress = 1
      }
      self.menuBarPresentationTask = nil
    }
    onVisibilityChanged?(false)
  }

  func toggleVisibility() {
    panel.isVisible ? hide() : show()
  }

  func handleHover(_ isHovering: Bool) {
    if model.settings.quotaDisplayMode == .menuBar {
      onMenuBarHoverChanged?(isHovering)
      return
    }
    guard model.settings.hoverExpansionEnabled else {
      return
    }
    collapseTask?.cancel()
    if isHovering {
      guard !isDraggingMinimalBar else { return }
      if model.settings.quotaDisplayMode == .minimal, state.isCollapsed {
        guard !suppressMinimalHoverUntilExit else { return }
        setCollapsed(false)
      } else {
        setCollapsed(false)
      }
    } else if model.transientFeedback == nil {
      suppressMinimalHoverUntilExit = false
      guard !isDraggingMinimalBar else { return }
      scheduleCollapse()
    }
  }

  private func applyHoverMode(_ isEnabled: Bool) {
    collapseTask?.cancel()
    guard model.settings.quotaDisplayMode != .menuBar else { return }
    if model.transientFeedback != nil {
      setCollapsed(false)
      return
    }
    if isEnabled {
      if !pointerIsInsidePanel { scheduleCollapse() }
    } else {
      setCollapsed(false)
    }
  }

  private func scheduleCollapse() {
    collapseTask?.cancel()
    guard model.transientFeedback == nil else { return }
    let delay = max(0.1, model.settings.hoverCollapseDelay)
    collapseTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard let self, !Task.isCancelled, self.panel.isVisible, !self.pointerIsInsidePanel else {
        return
      }
      self.setCollapsed(true)
    }
  }

  func setCollapsed(_ shouldCollapse: Bool, animated: Bool = true) {
    guard state.isCollapsed != shouldCollapse else { return }
    flushPendingPlacementSave()
    let wasExpanding = state.isExpanding
    let wasCollapsing = state.isCollapsing
    cancelSurfaceTransition()
    surfaceTransitionGeneration &+= 1
    let transitionGeneration = surfaceTransitionGeneration
    let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    if shouldCollapse {
      state.expandedCanvasSize = panel.frame.size
      if !wasExpanding { expandedSize = panel.frame.size }
      state.isExpanding = false
      state.isCollapsing = shouldAnimate
      state.isCollapsed = true
      panel.styleMask.remove(.resizable)
      if model.settings.quotaDisplayMode == .minimal {
        panel.isMovableByWindowBackground = false
      }
      let finalFrame = resolvedCollapsedRestingFrame()
      if shouldAnimate {
        beginSurfaceTransition(
          targetProgress: 0,
          expanding: false,
          duration: Motion.collapseDuration,
          generation: transitionGeneration
        ) { [weak self] in
          guard let self else { return }
          self.panel.setFrame(finalFrame, display: true, animate: false)
          self.setRevealProgress(0, expanding: false, animated: false)
          self.state.isCollapsing = false
          self.collapsedRestingFrame = finalFrame
        }
      } else {
        setRevealProgress(0, expanding: false, animated: false)
        state.isCollapsing = false
        panel.setFrame(finalFrame, display: true, animate: false)
        collapsedRestingFrame = finalFrame
      }
    } else {
      if !wasCollapsing { collapsedRestingFrame = panel.frame }
      panel.isMovableByWindowBackground = model.settings.quotaDisplayMode != .menuBar
      if model.settings.quotaDisplayMode == .menuBar {
        panel.styleMask.remove(.resizable)
      } else {
        panel.styleMask.insert(.resizable)
      }
      panel.minSize = Size.minimumExpanded
      panel.maxSize = Size.maximumExpanded
      expandedSize.height = preferredExpandedHeight
      state.expandedCanvasSize = expandedSize
      let finalFrame = targetFrame(for: expandedSize)
      if shouldAnimate {
        // Direction 14 uses one final-size surface and animates only its liquid
        // clipping boundary. This prevents the expanded hierarchy from being
        // laid out against a different window width on every display frame.
        panel.setFrame(finalFrame, display: true, animate: false)
        state.isCollapsing = false
        state.isExpanding = true
        state.isCollapsed = false
        beginSurfaceTransition(
          targetProgress: 1,
          expanding: true,
          duration: Motion.expansionDuration,
          generation: transitionGeneration
        ) { [weak self] in
          guard let self else { return }
          self.setRevealProgress(1, expanding: true, animated: false)
          self.state.isExpanding = false
        }
      } else {
        state.isCollapsing = false
        state.isExpanding = false
        state.isCollapsed = false
        setRevealProgress(1, expanding: true, animated: false)
        panel.setFrame(finalFrame, display: true, animate: false)
      }
    }
  }

  var isCollapseAnimationInFlight: Bool { state.isCollapsing }
  var isSurfaceTransitionInFlight: Bool { state.isCollapsing || state.isExpanding }

  func handleMinimalDrag(translation: CGSize, ended: Bool) {
    guard model.settings.quotaDisplayMode == .minimal,
      state.isCollapsed,
      !state.isCollapsing
    else { return }

    collapseTask?.cancel()
    if minimalDragStartFrame == nil {
      isDraggingMinimalBar = true
      suppressMinimalHoverUntilExit = true
      minimalDragStartFrame = panel.frame
      minimalDragVisibleFrame =
        NSScreen.screens.first(where: {
          $0.visibleFrame.intersects(panel.frame)
        })?.visibleFrame ?? NSScreen.main?.visibleFrame
    }
    guard let startFrame = minimalDragStartFrame,
      let visibleFrame = minimalDragVisibleFrame
    else { return }

    let frame = FloatingPanelLayout.draggedFrame(
      from: startFrame,
      translation: translation,
      visibleFrame: visibleFrame
    )
    panel.setFrame(frame, display: true, animate: false)
    guard ended else { return }

    collapsedRestingFrame = frame
    minimalDragStartFrame = nil
    minimalDragVisibleFrame = nil
    isDraggingMinimalBar = false
    placement.saveUserPlacement(
      panel: panel,
      mode: activePlacementMode,
      expandedWidth: expandedSize.width
    )
  }

  func ensureVisible() {
    if menuBarAnchorFrame != nil {
      repositionBelowMenuBarAnchor()
      return
    }
    placement.clampToAvailableScreens(panel: panel)
  }

  func setMenuBarAnchor(_ frame: NSRect?) {
    menuBarAnchorFrame = frame
    if frame != nil { repositionBelowMenuBarAnchor() }
  }

  func windowWillMove(_ notification: Notification) {
    guard activePlacementMode != .menuBar,
      NSEvent.pressedMouseButtons & 1 == 1
    else { return }
    userMoveIsInProgress = true
  }

  func windowDidMove(_ notification: Notification) {
    guard model.settings.quotaDisplayMode != .menuBar else { return }
    guard !state.isCollapsing else { return }
    guard !isDraggingMinimalBar else { return }
    alignStandardCollapsedFrameIfNeeded()
    synchronizeCollapsedAnchorWithCurrentPanel()
    if userMoveIsInProgress || NSEvent.pressedMouseButtons & 1 == 1 {
      schedulePlacementSave()
    }
  }

  func windowDidResize(_ notification: Notification) {
    if !state.isCollapsed { expandedSize = panel.frame.size }
    if !state.isCollapsed, !state.isExpanding, !state.isCollapsing {
      state.expandedCanvasSize = panel.frame.size
    }
    guard model.settings.quotaDisplayMode != .menuBar else { return }
    guard !state.isCollapsing else { return }
    guard !isDraggingMinimalBar else { return }
    synchronizeCollapsedAnchorWithCurrentPanel()
    if userResizeIsInProgress || panel.inLiveResize {
      schedulePlacementSave()
    }
  }

  func windowWillStartLiveResize(_ notification: Notification) {
    userResizeIsInProgress = true
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    guard activePlacementMode != .menuBar else { return }
    userResizeIsInProgress = false
    schedulePlacementSave()
  }

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    guard !state.isCollapsed else { return collapsedSize }
    return NSSize(width: frameSize.width, height: preferredExpandedHeight)
  }

  private var collapsedSize: NSSize {
    Size.collapsed(for: model.settings.quotaDisplayMode)
  }

  private func applyDisplayMode() {
    collapseTask?.cancel()
    menuBarPresentationTask?.cancel()
    menuBarPresentationTask = nil
    state.menuBarPresentationProgress = 1
    cancelSurfaceTransition()
    surfaceTransitionGeneration &+= 1
    flushPendingPlacementSave()
    minimalDragStartFrame = nil
    minimalDragVisibleFrame = nil
    isDraggingMinimalBar = false
    suppressMinimalHoverUntilExit = false
    collapsedRestingFrame = nil
    let newMode = model.settings.quotaDisplayMode
    activePlacementMode = newMode
    if newMode == .menuBar {
      panel.isMovableByWindowBackground = false
      panel.styleMask.remove(.resizable)
      if state.isCollapsed { setCollapsed(false, animated: false) }
      return
    }
    menuBarAnchorFrame = nil
    restoreFloatingPlacement(for: newMode)
    let shouldCollapse = model.settings.hoverExpansionEnabled && model.transientFeedback == nil
    state.isCollapsing = false
    state.isExpanding = false
    state.isCollapsed = shouldCollapse
    setRevealProgress(
      shouldCollapse ? 0 : 1,
      expanding: !shouldCollapse,
      animated: false
    )
    panel.isMovableByWindowBackground =
      newMode == .standard || !shouldCollapse
    if shouldCollapse {
      panel.styleMask.remove(.resizable)
      let frame = targetFrame(for: collapsedSize)
      panel.setFrame(frame, display: true, animate: false)
      alignStandardCollapsedFrameIfNeeded()
      collapsedRestingFrame = panel.frame
    } else {
      panel.styleMask.insert(.resizable)
      resize(to: expandedSize, animated: false)
    }
    if model.transientFeedback != nil {
      setCollapsed(false, animated: false)
      return
    }
  }

  private func applyFeedback(_ feedback: AppFeedback?) {
    if feedback != nil {
      if !feedbackPresentationIsActive {
        feedbackPresentationIsActive = true
        feedbackPresentationWasCollapsed = state.isCollapsed
      }
      guard model.settings.quotaDisplayMode != .menuBar, panel.isVisible else { return }
      collapseTask?.cancel()
      setCollapsed(false, animated: false)
      panel.orderFrontRegardless()
      return
    }

    guard feedbackPresentationIsActive else { return }
    feedbackPresentationIsActive = false
    guard feedbackPresentationWasCollapsed,
      model.settings.hoverExpansionEnabled,
      model.settings.quotaDisplayMode != .menuBar,
      panel.isVisible,
      !pointerIsInsidePanel
    else { return }
    setCollapsed(true, animated: false)
  }

  private var pointerIsInsidePanel: Bool {
    panel.frame.contains(NSEvent.mouseLocation)
  }

  private func applyPreferredExpandedHeight(_ height: CGFloat) {
    let clampedHeight = min(
      Size.maximumExpanded.height,
      max(Size.minimumExpanded.height, height)
    )
    guard abs(preferredExpandedHeight - clampedHeight) > 0.5 else { return }
    preferredExpandedHeight = clampedHeight
    expandedSize.height = clampedHeight
    guard !state.isCollapsed, !state.isExpanding else { return }
    state.expandedCanvasSize = expandedSize
    resize(to: expandedSize, animated: false)
  }

  private func resize(to size: NSSize, animated: Bool) {
    let frame = targetFrame(for: size)
    panel.setFrame(frame, display: true, animate: animated)
    if menuBarAnchorFrame != nil {
      repositionBelowMenuBarAnchor()
    } else {
      ensureVisible()
    }
  }

  private func targetFrame(for size: NSSize) -> NSRect {
    if menuBarAnchorFrame == nil,
      let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) })
        ?? NSScreen.main
    {
      return FloatingPanelLayout.anchoredResizeFrame(
        currentFrame: panel.frame,
        targetSize: size,
        visibleFrame: screen.visibleFrame
      )
    }

    var proposed = panel.frame
    proposed.origin.y += proposed.height - size.height
    proposed.size = size
    return proposed
  }

  private func setRevealProgress(
    _ progress: CGFloat,
    expanding: Bool,
    animated: Bool
  ) {
    guard animated else {
      var transaction = Transaction(animation: nil)
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        state.revealProgress = progress
      }
      return
    }
    withAnimation(
      LiquidCapsuleMotion.animation(expanding: expanding, reduceMotion: false)
    ) {
      state.revealProgress = progress
    }
  }

  private func beginSurfaceTransition(
    targetProgress: CGFloat,
    expanding: Bool,
    duration: TimeInterval,
    generation: UInt,
    completion: @escaping @MainActor () -> Void
  ) {
    surfaceTransitionCompletion = completion
    surfaceTransitionTask = Task { @MainActor [weak self] in
      // Commit the exact endpoint layout once before the animated mask starts.
      // Otherwise AppKit's resize and SwiftUI's first interpolated frame can be
      // coalesced, making the motion appear to skip its first frame.
      await Task.yield()
      guard let self,
        !Task.isCancelled,
        self.surfaceTransitionGeneration == generation
      else { return }
      self.setRevealProgress(targetProgress, expanding: expanding, animated: true)
      try? await Task.sleep(
        for: .seconds(duration + LiquidCapsuleMotion.completionSettleBuffer)
      )
      guard !Task.isCancelled,
        self.surfaceTransitionGeneration == generation
      else { return }
      self.finishSurfaceTransitionIfNeeded()
    }
  }

  private func finishSurfaceTransitionIfNeeded() {
    guard let completion = surfaceTransitionCompletion else { return }
    cancelSurfaceTransition()
    completion()
  }

  private func cancelSurfaceTransition() {
    surfaceTransitionTask?.cancel()
    surfaceTransitionTask = nil
    surfaceTransitionCompletion = nil
  }

  private func resolvedCollapsedRestingFrame() -> NSRect {
    let rememberedFrame = collapsedRestingFrame ?? targetFrame(for: collapsedSize)
    let visibleFrame =
      NSScreen.screens.first(where: {
        $0.visibleFrame.intersects(rememberedFrame)
      })?.visibleFrame ?? NSScreen.main?.visibleFrame
    guard let visibleFrame else { return rememberedFrame }
    let resizedFrame = FloatingPanelLayout.anchoredResizeFrame(
      currentFrame: rememberedFrame,
      targetSize: collapsedSize,
      visibleFrame: visibleFrame
    )
    guard model.settings.quotaDisplayMode == .standard else { return resizedFrame }
    return FloatingPanelLayout.standardCollapsedAnchorFrame(
      currentFrame: resizedFrame,
      expandedSize: NSSize(width: expandedSize.width, height: preferredExpandedHeight),
      visibleFrame: visibleFrame
    )
  }

  private func alignStandardCollapsedFrameIfNeeded() {
    guard model.settings.quotaDisplayMode == .standard,
      state.isCollapsed,
      !isAligningStandardCollapsedFrame
    else { return }
    let currentFrame = panel.frame
    let screen =
      NSScreen.screens.max { lhs, rhs in
        lhs.visibleFrame.intersection(currentFrame).area
          < rhs.visibleFrame.intersection(currentFrame).area
      } ?? NSScreen.main
    guard let visibleFrame = screen?.visibleFrame else { return }
    let alignedFrame = FloatingPanelLayout.standardCollapsedAnchorFrame(
      currentFrame: currentFrame,
      expandedSize: NSSize(width: expandedSize.width, height: preferredExpandedHeight),
      visibleFrame: visibleFrame
    )
    guard !alignedFrame.approximatelyEquals(currentFrame) else { return }
    isAligningStandardCollapsedFrame = true
    panel.setFrame(alignedFrame, display: true, animate: false)
    isAligningStandardCollapsedFrame = false
  }

  private func synchronizeCollapsedAnchorWithCurrentPanel() {
    let currentFrame = panel.frame
    let screen =
      NSScreen.screens.max { lhs, rhs in
        lhs.visibleFrame.intersection(currentFrame).area
          < rhs.visibleFrame.intersection(currentFrame).area
      } ?? NSScreen.main
    guard let visibleFrame = screen?.visibleFrame else {
      collapsedRestingFrame = currentFrame
      return
    }
    collapsedRestingFrame = FloatingPanelLayout.anchoredResizeFrame(
      currentFrame: currentFrame,
      targetSize: collapsedSize,
      visibleFrame: visibleFrame
    )
  }

  private func schedulePlacementSave() {
    guard activePlacementMode != .menuBar else { return }
    pendingUserPlacement = PendingUserPlacement(
      frame: panel.frame,
      mode: activePlacementMode,
      expandedWidth: expandedSize.width
    )
    placementSaveTask?.cancel()
    placementSaveTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(160))
      guard let self, !Task.isCancelled else { return }
      self.flushPendingPlacementSave()
    }
  }

  private func flushPendingPlacementSave() {
    placementSaveTask?.cancel()
    placementSaveTask = nil
    guard let pendingUserPlacement else {
      userMoveIsInProgress = false
      return
    }
    placement.saveUserPlacement(
      frame: pendingUserPlacement.frame,
      mode: pendingUserPlacement.mode,
      expandedWidth: pendingUserPlacement.expandedWidth
    )
    self.pendingUserPlacement = nil
    userMoveIsInProgress = false
  }

  private func restoreFloatingPlacement(for mode: QuotaDisplayMode) {
    let restoreSize = NSSize(
      width: Size.expanded.width,
      height: preferredExpandedHeight
    )
    placement.restore(
      panel: panel,
      mode: mode,
      defaultSize: restoreSize,
      minimumWidth: Size.minimumExpanded.width,
      maximumWidth: Size.maximumExpanded.width,
      initialFrame: CodexInitialPanelPlacement.frame(panelSize: restoreSize)
    )
    expandedSize = NSSize(
      width: min(Size.maximumExpanded.width, max(Size.minimumExpanded.width, panel.frame.width)),
      height: preferredExpandedHeight
    )
    state.expandedCanvasSize = expandedSize
  }

  private func repositionBelowMenuBarAnchor() {
    guard let anchorFrame = menuBarAnchorFrame,
      let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchorFrame) })
        ?? NSScreen.main
    else { return }
    let size = NSSize(
      width: max(Size.minimumExpanded.width, expandedSize.width),
      height: preferredExpandedHeight
    )
    let frame = FloatingPanelLayout.menuBarExpandedFrame(
      anchorFrame: anchorFrame,
      panelSize: size,
      visibleFrame: screen.visibleFrame
    )
    panel.setFrame(frame, display: true)
  }
}

extension NSRect {
  fileprivate func approximatelyEquals(_ other: NSRect, tolerance: CGFloat = 0.5) -> Bool {
    abs(minX - other.minX) < tolerance
      && abs(minY - other.minY) < tolerance
      && abs(width - other.width) < tolerance
      && abs(height - other.height) < tolerance
  }
}
