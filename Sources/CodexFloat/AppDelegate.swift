import AppKit
import Combine
import LocalStore
import SwiftUI
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.local.codexfloat",
    category: "lifecycle"
  )
  private var model: AppModel?
  private var panelController: FloatingPanelController?
  private var codexWindowTracker: CodexWindowTracker?
  private var settingsWindow: NSWindowController?
  private var activityWindow: NSWindowController?
  private var quotaWindow: NSWindowController?
  private var statusItem: NSStatusItem?
  private var statusItemHoverMonitor: MenuBarStatusItemHoverMonitor?
  private var statusItemAppearanceObservation: NSKeyValueObservation?
  private var statusMenu: NSMenu?
  private var globalHotKey: GlobalHotKey?
  private var statusCountdownTimer: Timer?
  private var feedbackPopover: NSPopover?
  private var modelSubscriptions: Set<AnyCancellable> = []
  private var userWantsPanelVisible = true
  private var menuBarDetailVisible = false
  private var menuBarHoverHideTask: Task<Void, Never>?
  private var pointerInsideStatusItem = false
  private var pointerInsideMenuBarPanel = false

  private var strings: AppStrings {
    AppStrings(language: model?.settings.appLanguage ?? .simplifiedChinese)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    logger.info("Codex Float launching")
    do {
      let store = try SQLiteStore()
      let model = AppModel(store: store)
      self.model = model
      userWantsPanelVisible = model.settings.showPanelOnLaunch
      let panelController = FloatingPanelController(model: model)
      panelController.onVisibilityChanged = { [weak self] _ in
        self?.updateStatusItem()
      }
      panelController.onOpenSettings = { [weak self] in self?.showSettings() }
      panelController.onRequestHide = { [weak self] in
        self?.handlePanelHideRequest()
      }
      panelController.onMenuBarHoverChanged = { [weak self] isHovering in
        self?.menuBarPanelHoverChanged(isHovering)
      }
      self.panelController = panelController
      codexWindowTracker = CodexWindowTracker(
        window: panelController.panel,
        onMovementChanged: { [weak panelController] moving in
          panelController?.setCodexWindowMoving(moving)
        }
      ) { [weak panelController] window in
        panelController?.updateCodexWindow(window)
      }
      configureStatusItem()
      model.settings.onGlobalHotKeyChange = { [weak self] in self?.configureGlobalHotKey() }
      model.settings.onLanguageChange = { [weak self] in self?.languageDidChange() }
      model.settings.onDisplayModeChange = { [weak self] in self?.displayModeDidChange() }
      model.settings.onForegroundVisibilityChange = { [weak self] in
        self?.applyPanelVisibilityPolicy()
      }
      model.settings.onWindowFollowingChange = { [weak self] in
        self?.applyPanelVisibilityPolicy()
      }
      observeModel(model)
      startStatusCountdownTimer()
      configureGlobalHotKey()
      observeSystemEvents()
      applyPanelVisibilityPolicy()
      model.start()
      if CommandLine.arguments.contains("--show-settings") {
        setUserWantsPanelVisible(false)
        DispatchQueue.main.async { [weak self] in
          self?.showSettings()
          self?.panelController?.hide()
        }
      }
      if let previewKind = previewFeedbackArgument {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak model] in
          guard let self, let model else { return }
          if model.settings.quotaDisplayMode != .menuBar {
            self.setUserWantsPanelVisible(true)
          }
          model.previewFeedback(previewKind)
        }
      }
      logger.info("Codex Float ready")
    } catch {
      logger.error("Startup failed: \(error.localizedDescription, privacy: .public)")
      let alert = NSAlert()
      alert.messageText = strings.text(.startupFailed)
      alert.informativeText = error.localizedDescription
      alert.alertStyle = .critical
      alert.runModal()
      NSApp.terminate(nil)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    model?.settings.onGlobalHotKeyChange = nil
    model?.settings.onLanguageChange = nil
    model?.settings.onDisplayModeChange = nil
    model?.settings.onForegroundVisibilityChange = nil
    model?.settings.onWindowFollowingChange = nil
    codexWindowTracker?.stop()
    statusCountdownTimer?.invalidate()
    menuBarHoverHideTask?.cancel()
    feedbackPopover?.close()
    statusItemHoverMonitor = nil
    statusItemAppearanceObservation = nil
    modelSubscriptions.removeAll()
    globalHotKey?.invalidate()
    model?.stop()
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    NotificationCenter.default.removeObserver(self)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if model?.settings.quotaDisplayMode == .menuBar {
      menuBarDetailVisible = true
      applyPanelVisibilityPolicy()
    } else {
      setUserWantsPanelVisible(true)
    }
    return true
  }

  @objc private func togglePanel() {
    if model?.settings.quotaDisplayMode == .menuBar {
      menuBarDetailVisible = panelController?.panel.isVisible != true
      applyPanelVisibilityPolicy()
      return
    }
    if panelController?.panel.isVisible == true {
      setUserWantsPanelVisible(false)
    } else {
      setUserWantsPanelVisible(true)
    }
  }
  @objc private func statusItemClicked() {
    guard let event = NSApp.currentEvent else {
      togglePanel()
      return
    }
    if event.type == .rightMouseUp {
      guard let button = statusItem?.button, let statusMenu else { return }
      statusMenu.popUp(
        positioning: nil,
        at: NSPoint(x: 0, y: button.bounds.minY - 4),
        in: button
      )
    } else {
      togglePanel()
    }
  }

  private func showMenuBarDetails() {
    guard model?.settings.quotaDisplayMode == .menuBar else { return }
    menuBarHoverHideTask?.cancel()
    menuBarDetailVisible = true
    applyPanelVisibilityPolicy()
  }

  private func statusItemHoverChanged(_ isHovering: Bool) {
    guard model?.settings.quotaDisplayMode == .menuBar else { return }
    pointerInsideStatusItem = isHovering
    if isHovering {
      showMenuBarDetails()
    } else {
      scheduleMenuBarDetailHide()
    }
  }

  private func menuBarPanelHoverChanged(_ isHovering: Bool) {
    pointerInsideMenuBarPanel = isHovering
    if isHovering {
      menuBarHoverHideTask?.cancel()
    } else {
      scheduleMenuBarDetailHide()
    }
  }

  private func scheduleMenuBarDetailHide() {
    menuBarHoverHideTask?.cancel()
    guard let settings = model?.settings, settings.quotaDisplayMode == .menuBar else { return }
    let delay = max(0.25, settings.hoverCollapseDelay)
    menuBarHoverHideTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard let self, !Task.isCancelled,
        !self.pointerInsideStatusItem,
        !self.pointerInsideMenuBarPanel
      else { return }
      self.menuBarDetailVisible = false
      self.applyPanelVisibilityPolicy()
    }
  }
  @objc private func refresh() { model?.refreshAll() }
  @objc private func quit() { NSApp.terminate(nil) }

  @objc private func showSettings() {
    guard let model else { return }
    if settingsWindow == nil {
      let view = SettingsView(
        model: model,
        settings: model.settings,
        onPreviewFeedback: { [weak model] kind in model?.previewFeedback(kind) },
        onExportDiagnostics: { [weak self] in self?.exportDiagnostics() }
      )
      let window = NSWindow(contentViewController: NSHostingController(rootView: view))
      window.title = "Codex Float · \(strings.text(.settings))"
      window.styleMask = [.titled, .closable]
      window.isReleasedWhenClosed = false
      window.center()
      settingsWindow = NSWindowController(window: window)
    }
    settingsWindow?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func showActivityHistory() {
    guard let model else { return }
    if activityWindow == nil {
      let window = NSWindow(
        contentViewController: NSHostingController(
          rootView: ActivityHistoryView(model: model, settings: model.settings)))
      window.title = strings.text(.activityHistoryTitle)
      window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
      window.isReleasedWhenClosed = false
      window.setContentSize(NSSize(width: 720, height: 560))
      window.center()
      activityWindow = NSWindowController(window: window)
    }
    activityWindow?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func showQuotaDetails() {
    guard let model else { return }
    if quotaWindow == nil {
      let window = NSWindow(
        contentViewController: NSHostingController(
          rootView: QuotaDetailsView(model: model, settings: model.settings)))
      window.title = strings.text(.quotaDetailsTitle)
      window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
      window.isReleasedWhenClosed = false
      window.setContentSize(NSSize(width: 700, height: 540))
      window.center()
      quotaWindow = NSWindowController(window: window)
    }
    quotaWindow?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func exportDiagnostics() {
    guard let model else { return }
    Task {
      do {
        let data = try await model.diagnosticsData()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CodexFloat-Diagnostics.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
          try data.write(to: url, options: .atomic)
        }
      } catch {
        let alert = NSAlert(error: error)
        alert.runModal()
      }
    }
  }

  @objc private func handleWake(_ notification: Notification) {
    model?.refreshAfterWakeOrShow()
    codexWindowTracker?.refresh(selectFrontWindow: true)
  }

  @objc private func handleScreensChanged(_ notification: Notification) {
    codexWindowTracker?.refresh(selectFrontWindow: true)
    panelController?.ensureVisible()
    updateStatusItem()
  }

  @objc private func handleApplicationActivated(_ notification: Notification) {
    codexWindowTracker?.refresh(selectFrontWindow: true)
    if model?.settings.quotaDisplayMode == .menuBar,
      frontmostBundleIdentifier != Bundle.main.bundleIdentifier
    {
      menuBarHoverHideTask?.cancel()
      pointerInsideStatusItem = false
      pointerInsideMenuBarPanel = false
      menuBarDetailVisible = false
    }
    applyPanelVisibilityPolicy()
    presentCurrentFeedbackIfNeeded()
  }

  @objc private func statusCountdownDidTick(_ timer: Timer) {
    updateStatusItem()
  }

  private func configureStatusItem() {
    removeStatusItem()
    guard model?.settings.quotaDisplayMode == .menuBar else { return }
    let menuBarScreenFrame =
      NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    MenuBarStatusItemPlacement.prepareVisiblePosition(screenFrame: menuBarScreenFrame)
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.autosaveName = MenuBarStatusItemPlacement.autosaveName
    statusItem.isVisible = true
    statusItem.button?.target = self
    statusItem.button?.action = #selector(statusItemClicked)
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    statusItem.button?.imagePosition = .imageLeading
    statusItem.button?.font = .systemFont(ofSize: 12, weight: .semibold)
    if let button = statusItem.button {
      let hoverMonitor = MenuBarStatusItemHoverMonitor { [weak self] isHovering in
        self?.statusItemHoverChanged(isHovering)
      }
      hoverMonitor.install(on: button)
      statusItemHoverMonitor = hoverMonitor
      statusItemAppearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) {
        [weak self] _, _ in
        Task { @MainActor [weak self] in self?.updateStatusItem() }
      }
    }
    let menu = NSMenu()
    menu.addItem(menuItem(togglePanelMenuTitle, action: #selector(togglePanel), key: ""))
    menu.addItem(menuItem(strings.text(.menuRefresh), action: #selector(refresh), key: "r"))
    menu.addItem(
      menuItem(strings.text(.menuQuotaDetails), action: #selector(showQuotaDetails), key: "u"))
    menu.addItem(
      menuItem(strings.text(.menuActivityHistory), action: #selector(showActivityHistory), key: "t")
    )
    menu.addItem(.separator())
    menu.addItem(menuItem(strings.text(.menuSettings), action: #selector(showSettings), key: ","))
    menu.addItem(
      menuItem(strings.text(.exportDiagnostics), action: #selector(exportDiagnostics), key: ""))
    menu.addItem(.separator())
    menu.addItem(menuItem(strings.text(.menuQuit), action: #selector(quit), key: "q"))
    statusMenu = menu
    self.statusItem = statusItem
    updateStatusItem()
  }

  private func updateStatusItem() {
    guard let settings = model?.settings else { return }
    let shouldShow = MenuBarStatusItemVisibility.shouldShow(for: settings.quotaDisplayMode)
    guard shouldShow else {
      removeStatusItem()
      return
    }
    guard let button = statusItem?.button else {
      configureStatusItem()
      return
    }
    statusItem?.isVisible = true

    let toolTip: String
    if let feedback = model?.transientFeedback {
      let content = feedback.localized(using: strings)
      toolTip = "\(content.title)：\(content.message)"
    } else {
      toolTip = menuBarQuotaHelp
    }
    let display = QuotaDisplayPolicy(
      snapshot: model?.quota, showFiveHour: settings.showFiveHourQuota
    )
    statusItem?.length =
      display.isDual
      ? MenuBarDualQuotaIndicator.statusItemLength : MenuBarQuotaIndicator.Layout.statusItemLength
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleNone
    if display.isDual {
      button.image = MenuBarDualQuotaIndicator.image(
        entries: display.compact, strings: strings, now: Date(),
        lowThreshold: settings.lowThreshold, criticalThreshold: settings.criticalThreshold,
        appearance: button.effectiveAppearance,
        isHighlighted: pointerInsideStatusItem || menuBarDetailVisible
      )
    } else {
      button.image = MenuBarQuotaIndicator.image(
        remainingPercent: display.compact.first?.window?.remainingPercent,
        countdown: strings.menuBarBadgeCountdown(
          to: display.compact.first?.window?.resetsAt,
          now: Date()
        ),
        lowThreshold: settings.lowThreshold,
        criticalThreshold: settings.criticalThreshold,
        appearance: button.effectiveAppearance,
        isHighlighted: pointerInsideStatusItem || menuBarDetailVisible
      )
    }
    // A slightly wider native item keeps the number, the smaller percent sign,
    // and the countdown legible without sacrificing its compact menu-bar shape.
    button.title = ""
    button.toolTip = toolTip
    button.setAccessibilityLabel(toolTip)
    updateMenuBarPanelAnchor()
    DispatchQueue.main.async { [weak self] in self?.updateMenuBarPanelAnchor() }
  }

  private func removeStatusItem() {
    feedbackPopover?.close()
    feedbackPopover = nil
    pointerInsideStatusItem = false
    panelController?.setMenuBarAnchor(nil)
    guard let statusItem else {
      statusItemHoverMonitor = nil
      return
    }
    MenuBarStatusItemPlacement.rememberCurrentPosition()
    NSStatusBar.system.removeStatusItem(statusItem)
    self.statusItem = nil
    statusItemHoverMonitor = nil
    statusItemAppearanceObservation = nil
    statusMenu = nil
  }

  private var frontmostBundleIdentifier: String? {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier
  }

  private var menuBarQuotaTitle: String {
    let display = QuotaDisplayPolicy(
      snapshot: model?.quota, showFiveHour: model?.settings.showFiveHourQuota ?? false
    )
    if display.isDual {
      return display.compact.map { $0.help(strings, now: Date()) }.joined(separator: " · ")
    }
    guard let window = display.compact.first?.window else {
      return strings.text(.menuBarQuotaUnavailable)
    }
    return strings.format(
      .menuBarQuotaTitle,
      Int(window.remainingPercent.rounded()),
      strings.menuBarCountdown(to: window.resetsAt, now: Date())
    )
  }

  private var menuBarQuotaHelp: String {
    let display = QuotaDisplayPolicy(
      snapshot: model?.quota, showFiveHour: model?.settings.showFiveHourQuota ?? false)
    guard display.compact.contains(where: { $0.window != nil }) else {
      return model?.quotaError ?? strings.text(.quotaUnavailable)
    }
    return display.compact.map { $0.help(strings, now: Date()) }.joined(separator: "\n")
  }

  private func setUserWantsPanelVisible(_ isVisible: Bool) {
    userWantsPanelVisible = isVisible
    applyPanelVisibilityPolicy()
  }

  private func applyPanelVisibilityPolicy() {
    guard let settings = model?.settings, let panelController else { return }
    let wantsPanelVisible =
      settings.quotaDisplayMode == .menuBar ? menuBarDetailVisible : userWantsPanelVisible
    let isAppFrontmost = frontmostBundleIdentifier == Bundle.main.bundleIdentifier
    let shouldShow =
      isAppFrontmost && wantsPanelVisible
      || ForegroundVisibilityPolicy.shouldShow(
        displayMode: settings.quotaDisplayMode,
        userWantsVisible: wantsPanelVisible,
        onlyWhenChatGPTIsFrontmost: settings.showOnlyWhenChatGPTIsFrontmost,
        frontmostBundleIdentifier: frontmostBundleIdentifier
      )
    // Order out before stopping the tracker: clearing movement suppression must
    // never flash a manually/foreground-hidden panel back onto the screen.
    if !shouldShow, panelController.panel.isVisible { panelController.hide() }
    // Temporary movement suppression keeps tracking; a user/policy hide stops it.
    if shouldShow, settings.followCodexWindow, settings.quotaDisplayMode != .menuBar {
      codexWindowTracker?.start()
    } else {
      codexWindowTracker?.stop()
    }
    if shouldShow {
      if settings.quotaDisplayMode == .menuBar {
        updateMenuBarPanelAnchor()
        // Re-entering while the native-reveal collapse is still in flight
        // retargets that same surface instead of letting it disappear first.
        panelController.show(expanded: true)
      } else if !panelController.panel.isVisible {
        panelController.show(expanded: false)
      }
    }
    updateStatusItem()
  }

  private func configureGlobalHotKey() {
    globalHotKey?.invalidate()
    globalHotKey = nil
    statusMenu?.items.first?.title = togglePanelMenuTitle
    guard let settings = model?.settings else { return }
    guard settings.globalHotKeyEnabled else {
      settings.setGlobalHotKeyRegistrationError(nil)
      return
    }
    do {
      globalHotKey = try GlobalHotKey(configuration: settings.globalHotKeyConfiguration) {
        [weak self] in self?.togglePanel()
      }
      settings.setGlobalHotKeyRegistrationError(nil)
    } catch {
      let detail =
        (error as? GlobalHotKeyError)?.message(language: settings.appLanguage)
        ?? error.localizedDescription
      settings.setGlobalHotKeyRegistrationError(
        strings.format(.globalHotKeyUnavailable, detail)
      )
      logger.error("全局快捷键不可用：\(error.localizedDescription, privacy: .public)")
    }
  }

  private var togglePanelMenuTitle: String {
    guard let settings = model?.settings, settings.globalHotKeyEnabled else {
      return strings.text(.menuTogglePanel)
    }
    return strings.format(.menuTogglePanelShortcut, settings.globalHotKeyConfiguration.displayName)
  }

  private func languageDidChange() {
    settingsWindow?.window?.title = "Codex Float · \(strings.text(.settings))"
    activityWindow?.window?.title = strings.text(.activityHistoryTitle)
    quotaWindow?.window?.title = strings.text(.quotaDetailsTitle)
    configureStatusItem()
    configureGlobalHotKey()
    presentCurrentFeedbackIfNeeded()
    model?.refreshAll()
  }

  private func displayModeDidChange() {
    menuBarHoverHideTask?.cancel()
    pointerInsideStatusItem = false
    pointerInsideMenuBarPanel = false
    menuBarDetailVisible = false
    feedbackPopover?.close()
    feedbackPopover = nil
    applyPanelVisibilityPolicy()
    updateStatusItem()
    presentCurrentFeedbackIfNeeded()
  }

  private func handlePanelHideRequest() {
    if model?.settings.quotaDisplayMode == .menuBar {
      menuBarHoverHideTask?.cancel()
      pointerInsideStatusItem = false
      pointerInsideMenuBarPanel = false
      menuBarDetailVisible = false
      applyPanelVisibilityPolicy()
    } else {
      setUserWantsPanelVisible(false)
    }
  }

  private func observeModel(_ model: AppModel) {
    model.settings.$showFiveHourQuota
      .dropFirst()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.updateStatusItem() }
      .store(in: &modelSubscriptions)

    model.$quota
      .combineLatest(model.$quotaError)
      .receive(on: RunLoop.main)
      .sink { [weak self] _, _ in self?.updateStatusItem() }
      .store(in: &modelSubscriptions)

    model.$transientFeedback
      .dropFirst()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.updateStatusItem()
        self?.presentCurrentFeedbackIfNeeded()
      }
      .store(in: &modelSubscriptions)
  }

  private func presentCurrentFeedbackIfNeeded() {
    guard let model,
      model.settings.quotaDisplayMode == .menuBar,
      let anchor = statusItem?.button,
      statusItem?.isVisible == true,
      anchor.window != nil,
      let feedback = model.transientFeedback
    else {
      feedbackPopover?.close()
      feedbackPopover = nil
      return
    }

    feedbackPopover?.close()
    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    popover.contentSize = NSSize(width: 350, height: 118)
    popover.contentViewController = NSHostingController(
      rootView: FeedbackBannerView(
        feedback: feedback,
        language: model.settings.appLanguage,
        isPopover: true
      )
      .padding(8)
      .frame(width: 350)
    )
    feedbackPopover = popover
    popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
  }

  private func updateMenuBarPanelAnchor() {
    guard model?.settings.quotaDisplayMode == .menuBar,
      let button = statusItem?.button
    else {
      panelController?.setMenuBarAnchor(nil)
      return
    }
    panelController?.setMenuBarAnchor(MenuBarStatusItemAnchor.screenFrame(for: button))
  }

  private func startStatusCountdownTimer() {
    statusCountdownTimer?.invalidate()
    statusCountdownTimer = Timer.scheduledTimer(
      timeInterval: 60,
      target: self,
      selector: #selector(statusCountdownDidTick),
      userInfo: nil,
      repeats: true
    )
  }

  private func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.target = self
    return item
  }

  private var previewFeedbackArgument: AppFeedbackKind? {
    guard
      let value = CommandLine.arguments.first(where: {
        $0.hasPrefix("--preview-feedback=")
      })?.split(separator: "=", maxSplits: 1).last
    else { return nil }
    switch value {
    case "tibo": return .tiboReset
    case "low": return .quotaLow
    case "critical": return .quotaCritical
    default: return nil
    }
  }

  private func observeSystemEvents() {
    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(handleWake),
      name: NSWorkspace.didWakeNotification,
      object: nil
    )
    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(handleApplicationActivated),
      name: NSWorkspace.didActivateApplicationNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleScreensChanged),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
  }
}
