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
    configureTransparentLayer(for: self)
    if let superview {
      // The frame view must stay transparent as well as the hosting view.
      // SwiftUI owns the rounded mask; a second AppKit corner mask changes its
      // antialiasing when the compact entry moves inside a larger backing canvas.
      configureTransparentLayer(for: superview)
    }
  }

  private func configureTransparentLayer(for view: NSView) {
    view.wantsLayer = true
    view.layerContentsRedrawPolicy = .duringViewResize
    view.layer?.backgroundColor = NSColor.clear.cgColor
    view.layer?.isOpaque = false
    view.layer?.cornerRadius = 0
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
  @Published var expansionDirection = PanelExpansionDirection()
  @Published var revealProgress: CGFloat
  @Published var menuBarPresentationProgress: CGFloat = 1
  // Applied only between transitions. Settings edits must not change a liquid
  // animation's seed halfway through its flight.
  @Published var minimalMeterAppearance = MinimalMeterAppearance()

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
  private let reduceMotionProvider: () -> Bool
  private var activePlacementMode: QuotaDisplayMode
  private var expandedSize = Size.expanded
  private var preferredExpandedHeight = Size.expanded.height
  private var collapseTask: Task<Void, Never>?
  private var hoverSettingSubscription: AnyCancellable?
  private var displayModeSubscription: AnyCancellable?
  private var minimalAppearanceSubscription: AnyCancellable?
  private var windowFollowingSubscription: AnyCancellable?
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
  private var systemFrameCorrectionTask: Task<Void, Never>?
  private var minimalDragStartFrame: NSRect?
  private var minimalDragVisibleFrame: NSRect?
  private var isDraggingMinimalBar = false
  private var suppressMinimalHoverUntilExit = false
  private var isApplyingPanelLayout = false
  private var hasLockedExpansionDirection = false
  private var userMoveIsInProgress = false
  private var userResizeIsInProgress = false
  private var pendingUserPlacement: PendingUserPlacement?
  private var codexWindow: TrackedCodexWindow?
  private var windowPinOffset: WindowPinOffset?
  private var usesAutomaticCodexAnchor = true
  private var shouldPinCurrentPositionOnNextCodexWindow = false
  private var isApplyingWindowFollow = false
  private(set) var isHiddenForCodexMovement = false
  var onVisibilityChanged: ((Bool) -> Void)?
  var onOpenSettings: (() -> Void)?
  var onRequestHide: (() -> Void)?
  var onMenuBarHoverChanged: ((Bool) -> Void)?
  var followsCodexLabelAutomatically: Bool { usesAutomaticCodexAnchor }

  private struct PendingUserPlacement {
    let frame: NSRect
    let mode: QuotaDisplayMode
    let expandedWidth: CGFloat
  }

  init(
    model: AppModel,
    placement: PanelPlacementStore = PanelPlacementStore(),
    panelStateDefaults: UserDefaults = .standard,
    reduceMotionProvider: @escaping () -> Bool = {
      NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
  ) {
    self.model = model
    self.placement = placement
    self.reduceMotionProvider = reduceMotionProvider
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
    usesAutomaticCodexAnchor = !placement.windowPinIsUserCustomized(for: activePlacementMode)
    state.minimalMeterAppearance = model.settings.minimalMeterAppearance.normalized
    isApplyingPanelLayout = true
    defer { isApplyingPanelLayout = false }

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
        initialFrame: CodexInitialPanelPlacement.frame(panelSize: collapsedSize),
        compactSize: collapsedSize
      )
    } else {
      panel.setFrame(CodexInitialPanelPlacement.frame(panelSize: Size.expanded), display: false)
    }
    expandedSize = NSSize(
      width: min(
        Size.maximumExpanded.width,
        max(
          Size.minimumExpanded.width,
          placement.preferredExpandedWidth(for: activePlacementMode, fallback: Size.expanded.width))
      ),
      height: preferredExpandedHeight
    )
    state.expandedCanvasSize = expandedSize
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
      collapsedRestingFrame = panel.frame
    } else {
      collapsedRestingFrame = PanelExpansionGeometry.compactFrame(
        in: panel.frame, size: collapsedSize, direction: .init())
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
    minimalAppearanceSubscription = model.settings.$minimalMeterAppearance.dropFirst().sink {
      [weak self] _ in
      Task { @MainActor [weak self] in self?.applyMinimalAppearance() }
    }
    windowFollowingSubscription = model.settings.$followCodexWindow.dropFirst().sink {
      [weak self] isEnabled in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.flushPendingPlacementSave()
        self.windowPinOffset = nil
        if isEnabled {
          if self.placement.windowPinOffset(for: self.activePlacementMode) != nil {
            // A real saved pin remains authoritative when follow is re-enabled.
            self.usesAutomaticCodexAnchor =
              !self.placement.windowPinIsUserCustomized(for: self.activePlacementMode)
            self.shouldPinCurrentPositionOnNextCodexWindow = false
          } else {
            // Without a saved pin, enabling follow keeps the current position
            // instead of unexpectedly snapping to an unrelated default.
            self.usesAutomaticCodexAnchor = false
            self.shouldPinCurrentPositionOnNextCodexWindow = true
          }
        } else {
          self.shouldPinCurrentPositionOnNextCodexWindow = false
          self.setCodexWindowMoving(false)
        }
        self.updateCodexWindow(self.codexWindow)
      }
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
      && !reduceMotionProvider()
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
      && !reduceMotionProvider()
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
    guard !isHiddenForCodexMovement else { return }
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
    let wasCollapsing = state.isCollapsing
    cancelSurfaceTransition()
    surfaceTransitionGeneration &+= 1
    let transitionGeneration = surfaceTransitionGeneration
    let shouldAnimate = animated && !reduceMotionProvider()
    // Resizing the backing window is not a user move. In particular, AppKit's
    // didMove/didResize callbacks must not overwrite the saved compact anchor.
    let wasApplyingLayout = isApplyingPanelLayout
    isApplyingPanelLayout = true
    defer { isApplyingPanelLayout = wasApplyingLayout }
    if shouldCollapse {
      state.expandedCanvasSize = panel.frame.size
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
          // Codex may have moved while the liquid mask was closing. Resolve the
          // live anchor here instead of jumping back to a captured first frame.
          let finalFrame = self.resolvedCollapsedRestingFrame()
          self.applyPanelFrame(finalFrame)
          self.setRevealProgress(0, expanding: false, animated: false)
          self.state.isCollapsing = false
          self.collapsedRestingFrame = finalFrame
          self.hasLockedExpansionDirection = false
          self.applyMinimalAppearance()
        }
      } else {
        setRevealProgress(0, expanding: false, animated: false)
        state.isCollapsing = false
        panel.setFrame(finalFrame, display: true, animate: false)
        collapsedRestingFrame = finalFrame
        hasLockedExpansionDirection = false
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
      let finalFrame = targetFrame(for: expandedSize)
      state.expandedCanvasSize = finalFrame.size
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
          self.applyMinimalAppearance()
        }
      } else {
        state.isCollapsing = false
        state.isExpanding = false
        state.isCollapsed = false
        setRevealProgress(1, expanding: true, animated: false)
        panel.setFrame(finalFrame, display: true, animate: false)
      }
    }
    if !shouldAnimate { applyMinimalAppearance() }
  }

  var isCollapseAnimationInFlight: Bool { state.isCollapsing }
  var isSurfaceTransitionInFlight: Bool { state.isCollapsing || state.isExpanding }
  var currentExpansionDirection: PanelExpansionDirection { state.expansionDirection }
  var compactAnchorFrame: NSRect { resolvedCollapsedRestingFrame() }

  func handleMinimalDrag(translation: CGSize, ended: Bool) {
    guard !isHiddenForCodexMovement, model.settings.quotaDisplayMode == .minimal,
      state.isCollapsed,
      !state.isCollapsing
    else { return }

    collapseTask?.cancel()
    if minimalDragStartFrame == nil {
      systemFrameCorrectionTask?.cancel()
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
    rememberWindowPin(frame: frame, userCustomized: true)
    placement.saveUserPlacement(
      panel: panel,
      mode: activePlacementMode,
      expandedWidth: expandedSize.width
    )
    applyMinimalAppearance()
  }

  func ensureVisible() {
    if menuBarAnchorFrame != nil {
      repositionBelowMenuBarAnchor()
      return
    }
    if model.settings.followCodexWindow, codexWindow != nil {
      updateCodexWindow(codexWindow)
      return
    }
    // Screen changes constrain only the entry. Details must adapt around it.
    collapsedRestingFrame = resolvedCollapsedRestingFrame()
    if state.isCollapsed && !state.isCollapsing {
      applyPanelFrame(resolvedCollapsedRestingFrame())
    } else {
      let frame = targetFrame(for: expandedSize)
      state.expandedCanvasSize = frame.size
      applyPanelFrame(frame)
    }
  }

  /// Movement suppression is not a user hide: preserve logical visibility and
  /// tracking, but remove both the rendered surface and its mouse hit target.
  /// Restoring alpha never orders a window in or changes the user's preference.
  func setCodexWindowMoving(_ moving: Bool) {
    let hidden =
      moving && model.settings.followCodexWindow
      && model.settings.quotaDisplayMode != .menuBar
    guard isHiddenForCodexMovement != hidden else { return }
    isHiddenForCodexMovement = hidden
    if hidden {
      panel.alphaValue = 0
      panel.ignoresMouseEvents = true
      collapseTask?.cancel()
      collapseTask = nil
      isApplyingWindowFollow = true
      defer { isApplyingWindowFollow = false }
      finishSurfaceTransitionIfNeeded()
      if model.settings.hoverExpansionEnabled, model.transientFeedback == nil {
        setCollapsed(true, animated: false)
      }
    } else {
      // Reapply the last geometry while still invisible: layout/feedback during
      // the drag may have temporarily prevented a position update.
      updateCodexWindow(codexWindow)
      // No slide, fade, show(), quota refresh or visibility-policy callback.
      panel.alphaValue = 1
      panel.ignoresMouseEvents = false
    }
  }

  /// Repositions both the visible canvas and resting capsule without restarting
  /// their animation. Programmatic moves never become user placement writes.
  func updateCodexWindow(_ window: TrackedCodexWindow?) {
    codexWindow = window
    if NSEvent.pressedMouseButtons & 1 == 0 { userMoveIsInProgress = false }
    guard model.settings.followCodexWindow, activePlacementMode != .menuBar,
      activePlacementMode == model.settings.quotaDisplayMode,
      let window, !isDraggingMinimalBar, !userResizeIsInProgress,
      !(userMoveIsInProgress && NSEvent.pressedMouseButtons & 1 == 1)
    else { return }
    if shouldPinCurrentPositionOnNextCodexWindow {
      shouldPinCurrentPositionOnNextCodexWindow = false
      rememberWindowPin(frame: resolvedCollapsedRestingFrame(), userCustomized: true)
    }
    if windowPinOffset == nil, !usesAutomaticCodexAnchor {
      windowPinOffset =
        placement.windowPinOffset(for: activePlacementMode)
        ?? WindowPinOffset(
          panelFrame: collapsedRestingFrame ?? panel.frame, windowFrame: window.frame)
    }
    let offset =
      windowPinOffset
      ?? WindowPinOffset(
        panelFrame: collapsedRestingFrame ?? panel.frame, windowFrame: window.frame)
    let anchor =
      usesAutomaticCodexAnchor
      ? WindowPinGeometry.automaticAnchorPoint(
        windowFrame: window.frame, labelFrame: window.codexLabelFrame)
      : WindowPinGeometry.anchorPoint(offset: offset, windowFrame: window.frame)
    let screens = NSScreen.screens
    let selectedScreen =
      WindowPinGeometry.screenIndex(
        containing: anchor, windowFrame: window.frame,
        visibleFrames: screens.map(\.visibleFrame)
      ).map { screens[$0] } ?? NSScreen.main
    guard let screen = selectedScreen else { return }
    let compact: NSRect
    if usesAutomaticCodexAnchor {
      compact = PanelPlacementGeometry.initialFrame(
        panelSize: collapsedSize, visibleFrame: screen.visibleFrame,
        codexWindowFrame: window.frame, codexLabelFrame: window.codexLabelFrame)
      windowPinOffset = WindowPinOffset(panelFrame: compact, windowFrame: window.frame)
    } else {
      compact = WindowPinGeometry.frame(
        offset: offset, windowFrame: window.frame, panelSize: collapsedSize,
        expandedSize: NSSize(width: expandedSize.width, height: preferredExpandedHeight),
        visibleFrame: screen.visibleFrame)
    }
    isApplyingWindowFollow = true
    defer { isApplyingWindowFollow = false }
    collapsedRestingFrame = compact
    let frame: NSRect
    if state.isCollapsed && !state.isCollapsing {
      frame = compact
    } else {
      frame = expansionFrame(
        compact: compact, size: expandedSize, visibleFrame: screen.visibleFrame)
      if state.expandedCanvasSize != frame.size { state.expandedCanvasSize = frame.size }
    }
    guard !frame.approximatelyEquals(panel.frame, tolerance: 0.01) else { return }
    if frame.size == panel.frame.size {
      panel.setFrameOrigin(frame.origin)
    } else {
      applyPanelFrame(frame)
    }
  }

  private func rememberWindowPin(frame: NSRect, userCustomized: Bool) {
    guard model.settings.followCodexWindow, activePlacementMode != .menuBar,
      let codexWindow
    else { return }
    let offset = WindowPinOffset(panelFrame: frame, windowFrame: codexWindow.frame)
    windowPinOffset = offset
    if userCustomized { usesAutomaticCodexAnchor = false }
    placement.saveWindowPinOffset(
      offset, for: activePlacementMode,
      userCustomized: userCustomized || !usesAutomaticCodexAnchor)
  }

  func setMenuBarAnchor(_ frame: NSRect?) {
    menuBarAnchorFrame = frame
    if frame != nil { repositionBelowMenuBarAnchor() }
  }

  func windowWillMove(_ notification: Notification) {
    guard !isApplyingWindowFollow, !isApplyingPanelLayout, activePlacementMode != .menuBar,
      NSEvent.pressedMouseButtons & 1 == 1
    else { return }
    systemFrameCorrectionTask?.cancel()
    userMoveIsInProgress = true
  }

  func windowDidMove(_ notification: Notification) {
    guard !isApplyingWindowFollow, !isApplyingPanelLayout else { return }
    guard model.settings.quotaDisplayMode != .menuBar else { return }
    guard !state.isCollapsing else { return }
    guard !isDraggingMinimalBar else { return }
    guard userMoveIsInProgress else {
      if model.settings.followCodexWindow, codexWindow != nil {
        scheduleSystemFrameCorrection()
      } else {
        synchronizeCollapsedAnchorWithCurrentPanel()
      }
      return
    }
    synchronizeCollapsedAnchorWithCurrentPanel()
    schedulePlacementSave(userCustomized: true)
    if NSEvent.pressedMouseButtons & 1 == 0 { userMoveIsInProgress = false }
  }

  func windowDidResize(_ notification: Notification) {
    guard !isApplyingWindowFollow, !isApplyingPanelLayout else { return }
    let isUserResize = userResizeIsInProgress || panel.inLiveResize
    if !state.isCollapsed, isUserResize {
      expandedSize.width = panel.frame.width
    }
    if !state.isCollapsed, isUserResize, !state.isExpanding, !state.isCollapsing {
      state.expandedCanvasSize = panel.frame.size
    }
    guard model.settings.quotaDisplayMode != .menuBar else { return }
    guard !state.isCollapsing else { return }
    guard !isDraggingMinimalBar else { return }
    guard isUserResize else {
      if model.settings.followCodexWindow, codexWindow != nil {
        scheduleSystemFrameCorrection()
      } else {
        synchronizeCollapsedAnchorWithCurrentPanel()
      }
      return
    }
    synchronizeCollapsedAnchorWithCurrentPanel()
    schedulePlacementSave(userCustomized: true)
  }

  func windowWillStartLiveResize(_ notification: Notification) {
    systemFrameCorrectionTask?.cancel()
    userResizeIsInProgress = true
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    guard activePlacementMode != .menuBar else { return }
    userResizeIsInProgress = false
    schedulePlacementSave(userCustomized: true)
  }

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    guard !state.isCollapsed else { return collapsedSize }
    return NSSize(width: frameSize.width, height: panel.frame.height)
  }

  private var collapsedSize: NSSize {
    model.settings.quotaDisplayMode == .minimal
      ? state.minimalMeterAppearance.collapsedSize
      : Size.collapsed(for: model.settings.quotaDisplayMode)
  }

  private func applyMinimalAppearance() {
    guard !isSurfaceTransitionInFlight, !isDraggingMinimalBar else { return }
    let appearance = model.settings.minimalMeterAppearance.normalized
    guard appearance != state.minimalMeterAppearance else { return }
    let compact = resolvedCollapsedRestingFrame()
    let screen = screenForCompactAnchor()?.visibleFrame
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      state.minimalMeterAppearance = appearance
      guard model.settings.quotaDisplayMode == .minimal else { return }
      let resized = NSRect(
        x: compact.minX, y: compact.maxY - collapsedSize.height,
        width: collapsedSize.width, height: collapsedSize.height)
      collapsedRestingFrame =
        screen.map { PanelPlacementGeometry.clamped(resized, to: $0) } ?? resized
      if state.isCollapsed {
        applyPanelFrame(resolvedCollapsedRestingFrame())
      } else {
        let frame = targetFrame(for: expandedSize)
        state.expandedCanvasSize = frame.size
        applyPanelFrame(frame)
      }
    }
    if model.settings.quotaDisplayMode == .minimal {
      // A user-edited size may be clamped at a screen edge. Remember that new
      // anchor too, otherwise the next host-window update or relaunch jumps.
      schedulePlacementSave(userCustomized: false)
    }
  }

  private func applyDisplayMode() {
    isApplyingPanelLayout = true
    defer { isApplyingPanelLayout = false }
    collapseTask?.cancel()
    menuBarPresentationTask?.cancel()
    menuBarPresentationTask = nil
    state.menuBarPresentationProgress = 1
    cancelSurfaceTransition()
    surfaceTransitionGeneration &+= 1
    flushPendingPlacementSave()
    systemFrameCorrectionTask?.cancel()
    minimalDragStartFrame = nil
    minimalDragVisibleFrame = nil
    isDraggingMinimalBar = false
    suppressMinimalHoverUntilExit = false
    collapsedRestingFrame = nil
    hasLockedExpansionDirection = false
    state.expansionDirection = .init()
    state.minimalMeterAppearance = model.settings.minimalMeterAppearance.normalized
    let newMode = model.settings.quotaDisplayMode
    activePlacementMode = newMode
    usesAutomaticCodexAnchor = !placement.windowPinIsUserCustomized(for: newMode)
    if newMode == .menuBar { setCodexWindowMoving(false) }
    windowPinOffset = nil
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
      collapsedRestingFrame = panel.frame
    } else {
      panel.styleMask.insert(.resizable)
      resize(to: expandedSize, animated: false)
    }
    updateCodexWindow(codexWindow)
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
    guard !state.isCollapsed, !state.isExpanding, !state.isCollapsing else { return }
    resize(to: expandedSize, animated: false)
  }

  private func resize(to size: NSSize, animated: Bool) {
    let frame = targetFrame(for: size)
    state.expandedCanvasSize = frame.size
    applyPanelFrame(frame, animated: animated)
    if menuBarAnchorFrame != nil {
      repositionBelowMenuBarAnchor()
    }
  }

  private func applyPanelFrame(_ frame: NSRect, animated: Bool = false) {
    let wasApplying = isApplyingPanelLayout
    isApplyingPanelLayout = true
    defer { isApplyingPanelLayout = wasApplying }
    panel.setFrame(frame, display: true, animate: animated)
  }

  private func targetFrame(for size: NSSize) -> NSRect {
    if menuBarAnchorFrame == nil,
      let screen = screenForCompactAnchor()
    {
      let compact = resolvedCollapsedRestingFrame()
      if size == collapsedSize { return compact }
      return expansionFrame(compact: compact, size: size, visibleFrame: screen.visibleFrame)
    }

    var proposed = panel.frame
    proposed.origin.y += proposed.height - size.height
    proposed.size = size
    return proposed
  }

  private func screenForCompactAnchor() -> NSScreen? {
    let compact = collapsedRestingFrame ?? panel.frame
    let best = NSScreen.screens.max {
      $0.visibleFrame.intersection(compact).area < $1.visibleFrame.intersection(compact).area
    }
    return best.flatMap { $0.visibleFrame.intersects(compact) ? $0 : nil } ?? NSScreen.main
  }

  private func expansionFrame(compact: NSRect, size: NSSize, visibleFrame: NSRect) -> NSRect {
    let result = PanelExpansionGeometry.resolve(
      compactFrame: compact, preferredSize: size, visibleFrame: visibleFrame,
      lockedDirection: hasLockedExpansionDirection ? state.expansionDirection : nil)
    state.expansionDirection = result.direction
    hasLockedExpansionDirection = true
    return result.frame
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
    let rememberedFrame =
      collapsedRestingFrame
      ?? PanelExpansionGeometry.compactFrame(
        in: panel.frame, size: collapsedSize, direction: state.expansionDirection)
    guard let visibleFrame = screenForCompactAnchor()?.visibleFrame else { return rememberedFrame }
    return PanelPlacementGeometry.clamped(rememberedFrame, to: visibleFrame)
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
    let compact = PanelExpansionGeometry.compactFrame(
      in: currentFrame, size: collapsedSize,
      direction: state.isCollapsed && !state.isCollapsing ? .init() : state.expansionDirection)
    collapsedRestingFrame = PanelPlacementGeometry.clamped(compact, to: visibleFrame)
  }

  private func schedulePlacementSave(userCustomized: Bool) {
    guard activePlacementMode != .menuBar else { return }
    let compact = resolvedCollapsedRestingFrame()
    rememberWindowPin(frame: compact, userCustomized: userCustomized)
    pendingUserPlacement = PendingUserPlacement(
      frame: compact,
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

  private func scheduleSystemFrameCorrection() {
    systemFrameCorrectionTask?.cancel()
    systemFrameCorrectionTask = Task { @MainActor [weak self] in
      // System window-management notifications can arrive after a synchronous
      // layout guard has ended. Correct on the next run-loop turn instead of
      // accepting that frame as a user-authored anchor.
      await Task.yield()
      guard let self, !Task.isCancelled,
        !self.userMoveIsInProgress, !self.userResizeIsInProgress,
        !self.isDraggingMinimalBar
      else { return }
      self.updateCodexWindow(self.codexWindow)
      self.systemFrameCorrectionTask = nil
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
    // A user can pause mid-drag longer than the save debounce. Keep ownership
    // until mouse-up so following cannot pull the tool out of their hand.
    userMoveIsInProgress = userMoveIsInProgress && NSEvent.pressedMouseButtons & 1 == 1
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
      initialFrame: CodexInitialPanelPlacement.frame(panelSize: collapsedSize),
      compactSize: collapsedSize
    )
    expandedSize = NSSize(
      width: min(
        Size.maximumExpanded.width,
        max(
          Size.minimumExpanded.width,
          placement.preferredExpandedWidth(for: mode, fallback: Size.expanded.width))),
      height: preferredExpandedHeight
    )
    state.expandedCanvasSize = expandedSize
    collapsedRestingFrame = panel.frame
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
