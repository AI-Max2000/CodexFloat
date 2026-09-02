import AppKit
import ApplicationServices
import CoreGraphics

struct PanelPlacementRecord: Codable, Equatable {
  let normalizedLeft: Double
  let normalizedTop: Double
  let expandedWidth: Double
}

enum PanelPlacementGeometry {
  static func record(
    for frame: NSRect,
    expandedWidth: CGFloat,
    visibleFrame: NSRect
  ) -> PanelPlacementRecord {
    PanelPlacementRecord(
      normalizedLeft: min(
        1,
        max(0, (frame.minX - visibleFrame.minX) / max(1, visibleFrame.width))
      ),
      normalizedTop: min(
        1,
        max(0, (visibleFrame.maxY - frame.maxY) / max(1, visibleFrame.height))
      ),
      expandedWidth: Double(expandedWidth)
    )
  }

  static func restoredFrame(
    from record: PanelPlacementRecord,
    panelHeight: CGFloat,
    minimumWidth: CGFloat,
    maximumWidth: CGFloat,
    visibleFrame: NSRect
  ) -> NSRect {
    let width = min(maximumWidth, max(minimumWidth, CGFloat(record.expandedWidth)))
    let x = visibleFrame.minX + CGFloat(record.normalizedLeft) * visibleFrame.width
    let top = visibleFrame.maxY - CGFloat(record.normalizedTop) * visibleFrame.height
    return clamped(
      NSRect(x: x, y: top - panelHeight, width: width, height: panelHeight),
      to: visibleFrame
    )
  }

  static func initialFrame(
    panelSize: NSSize,
    visibleFrame: NSRect,
    codexWindowFrame: NSRect?,
    codexLabelFrame: NSRect?,
    windowInset: CGFloat = 12,
    labelGap: CGFloat = 10,
    titleBarInset: CGFloat = 38
  ) -> NSRect {
    let proposed: NSRect
    if let label = codexLabelFrame,
      let window = codexWindowFrame,
      window.intersects(label)
    {
      proposed = NSRect(
        x: label.maxX + labelGap,
        y: label.maxY - panelSize.height,
        width: panelSize.width,
        height: panelSize.height
      )
    } else if let window = codexWindowFrame {
      proposed = NSRect(
        x: window.minX + windowInset,
        y: window.maxY - titleBarInset - panelSize.height,
        width: panelSize.width,
        height: panelSize.height
      )
    } else {
      proposed = NSRect(
        x: visibleFrame.minX + windowInset,
        y: visibleFrame.maxY - windowInset - panelSize.height,
        width: panelSize.width,
        height: panelSize.height
      )
    }
    return clamped(proposed, to: visibleFrame)
  }

  static func clamped(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
    var result = frame
    result.size.width = min(result.width, visibleFrame.width)
    result.size.height = min(result.height, visibleFrame.height)
    result.origin.x = min(
      max(result.minX, visibleFrame.minX),
      visibleFrame.maxX - result.width
    )
    result.origin.y = min(
      max(result.minY, visibleFrame.minY),
      visibleFrame.maxY - result.height
    )
    return result
  }
}

@MainActor
enum CodexInitialPanelPlacement {
  private static let supportedBundleIdentifiers = [
    "com.openai.codex",
    "com.openai.chat",
    "com.openai.chatgpt",
  ]

  static func frame(panelSize: NSSize) -> NSRect {
    let application = runningCodexApplication()
    let windowFrame = application.flatMap { codexWindowFrame(processIdentifier: $0.processIdentifier) }
    let labelFrame = application.flatMap {
      codexLabelFrame(
        processIdentifier: $0.processIdentifier,
        expectedWindowFrame: windowFrame
      )
    }
    let screen = screen(containing: labelFrame ?? windowFrame) ?? NSScreen.main ?? NSScreen.screens.first
    let visibleFrame = screen?.visibleFrame ?? NSRect(origin: .zero, size: panelSize)
    return PanelPlacementGeometry.initialFrame(
      panelSize: panelSize,
      visibleFrame: visibleFrame,
      codexWindowFrame: windowFrame,
      codexLabelFrame: labelFrame
    )
  }

  private static func runningCodexApplication() -> NSRunningApplication? {
    let applications = supportedBundleIdentifiers.flatMap {
      NSRunningApplication.runningApplications(withBundleIdentifier: $0)
    }
    return applications.first(where: { $0.isActive }) ?? applications.first
  }

  private static func codexWindowFrame(processIdentifier: pid_t) -> NSRect? {
    guard let rawWindows = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements],
      kCGNullWindowID
    ) as? [[String: Any]] else { return nil }

    for window in rawWindows {
      guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        == processIdentifier,
        (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
        let boundsDictionary = window[kCGWindowBounds as String] as? [String: Any],
        let quartzFrame = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
        quartzFrame.width >= 400,
        quartzFrame.height >= 240
      else { continue }
      return appKitFrame(fromQuartzFrame: quartzFrame)
    }
    return nil
  }

  /// Reads the exact label only when Accessibility access was already granted.
  /// First launch never prompts for an extra permission just to place the panel.
  private static func codexLabelFrame(
    processIdentifier: pid_t,
    expectedWindowFrame: NSRect?
  ) -> NSRect? {
    guard AXIsProcessTrusted() else { return nil }
    let application = AXUIElementCreateApplication(processIdentifier)
    guard let windows = attribute(kAXWindowsAttribute, of: application) as? [AXUIElement]
    else { return nil }

    for window in windows {
      var remaining = [window]
      var inspected = 0
      while let element = remaining.popLast(), inspected < 500 {
        inspected += 1
        if elementText(element) == "Codex",
          let quartzFrame = rectAttribute("AXFrame", of: element)
        {
          let candidate = appKitFrame(fromQuartzFrame: quartzFrame)
          if isHeaderLabel(candidate, inside: expectedWindowFrame) {
            return candidate
          }
        }
        if let children = attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] {
          remaining.append(contentsOf: children.prefix(80))
        }
      }
    }
    return nil
  }

  private static func isHeaderLabel(_ label: NSRect, inside window: NSRect?) -> Bool {
    guard let window else { return false }
    let maximumHeaderWidth = min(360, window.width * 0.45)
    return window.intersects(label)
      && label.midX <= window.minX + maximumHeaderWidth
      && label.maxY >= window.maxY - 180
  }

  private static func elementText(_ element: AXUIElement) -> String? {
    for name in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
      if let value = attribute(name, of: element) as? String,
        value.trimmingCharacters(in: .whitespacesAndNewlines) == "Codex"
      {
        return "Codex"
      }
    }
    return nil
  }

  private static func attribute(_ name: String, of element: AXUIElement) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
    else { return nil }
    return value
  }

  private static func rectAttribute(_ name: String, of element: AXUIElement) -> CGRect? {
    guard let value = attribute(name, of: element), CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgRect else { return nil }
    var rect = CGRect.zero
    return AXValueGetValue(axValue, .cgRect, &rect) ? rect : nil
  }

  private static func appKitFrame(fromQuartzFrame frame: CGRect) -> NSRect {
    let mainHeight = NSScreen.screens.first?.frame.height ?? frame.maxY
    return NSRect(
      x: frame.minX,
      y: mainHeight - frame.maxY,
      width: frame.width,
      height: frame.height
    )
  }

  private static func screen(containing frame: NSRect?) -> NSScreen? {
    guard let frame else { return nil }
    return NSScreen.screens.max { lhs, rhs in
      lhs.frame.intersection(frame).area < rhs.frame.intersection(frame).area
    }
  }
}

@MainActor
final class PanelPlacementStore {
  private struct Archive: Codable {
    var recordsByMode: [String: [String: PanelPlacementRecord]] = [:]
    var lastScreenByMode: [String: String] = [:]
  }

  private let archiveKey = "panelPlacementByScreenAndModeV2"
  private let pinArchiveKey = "codexWindowPinOffsetsV1"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func windowPinOffset(for mode: QuotaDisplayMode) -> WindowPinOffset? {
    guard mode != .menuBar,
      let data = defaults.data(forKey: pinArchiveKey),
      let offsets = try? JSONDecoder().decode([String: WindowPinOffset].self, from: data),
      let offset = offsets[mode.rawValue], offset.isValid
    else { return nil }
    return offset
  }

  func saveWindowPinOffset(_ offset: WindowPinOffset, for mode: QuotaDisplayMode) {
    guard mode != .menuBar, offset.isValid else { return }
    var offsets = defaults.data(forKey: pinArchiveKey).flatMap {
      try? JSONDecoder().decode([String: WindowPinOffset].self, from: $0)
    } ?? [:]
    offsets[mode.rawValue] = offset
    if let data = try? JSONEncoder().encode(offsets) {
      defaults.set(data, forKey: pinArchiveKey)
    }
  }

  @discardableResult
  func restore(
    panel: NSWindow,
    mode: QuotaDisplayMode,
    defaultSize: NSSize,
    minimumWidth: CGFloat,
    maximumWidth: CGFloat,
    initialFrame: NSRect
  ) -> Bool {
    let archive = readArchive()
    let modeRecords = archive.recordsByMode[mode.rawValue] ?? [:]
    let lastScreenID = archive.lastScreenByMode[mode.rawValue]
    let record = lastScreenID.flatMap { modeRecords[$0] }
      ?? modeRecords.sorted(by: { $0.key < $1.key }).first?.value

    guard let record else {
      let visibleFrame = bestScreen(for: initialFrame)?.visibleFrame
        ?? NSScreen.main?.visibleFrame
        ?? initialFrame
      panel.setFrame(PanelPlacementGeometry.clamped(initialFrame, to: visibleFrame), display: false)
      return false
    }

    let screen = NSScreen.screens.first(where: { screenID($0) == lastScreenID })
      ?? NSScreen.main
      ?? NSScreen.screens.first
    guard let screen else { return false }
    panel.setFrame(
      PanelPlacementGeometry.restoredFrame(
        from: record,
        panelHeight: defaultSize.height,
        minimumWidth: minimumWidth,
        maximumWidth: maximumWidth,
        visibleFrame: screen.visibleFrame
      ),
      display: false
    )
    return true
  }

  func saveUserPlacement(
    panel: NSWindow,
    mode: QuotaDisplayMode,
    expandedWidth: CGFloat
  ) {
    saveUserPlacement(frame: panel.frame, mode: mode, expandedWidth: expandedWidth)
  }

  func saveUserPlacement(
    frame: NSRect,
    mode: QuotaDisplayMode,
    expandedWidth: CGFloat
  ) {
    guard mode != .menuBar, let screen = bestScreen(for: frame) else { return }
    let identifier = screenID(screen)
    var archive = readArchive()
    var modeRecords = archive.recordsByMode[mode.rawValue] ?? [:]
    modeRecords[identifier] = PanelPlacementGeometry.record(
      for: frame,
      expandedWidth: expandedWidth,
      visibleFrame: screen.visibleFrame
    )
    archive.recordsByMode[mode.rawValue] = modeRecords
    archive.lastScreenByMode[mode.rawValue] = identifier
    if let data = try? JSONEncoder().encode(archive) {
      defaults.set(data, forKey: archiveKey)
    }
  }

  func clampToAvailableScreens(panel: NSWindow) {
    if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
      if let target = bestScreen(for: panel.frame) {
        panel.setFrame(
          PanelPlacementGeometry.clamped(panel.frame, to: target.visibleFrame),
          display: true
        )
      }
      return
    }
    guard let main = NSScreen.main ?? NSScreen.screens.first else { return }
    panel.setFrame(
      PanelPlacementGeometry.clamped(panel.frame, to: main.visibleFrame),
      display: true
    )
  }

  private func readArchive() -> Archive {
    guard let data = defaults.data(forKey: archiveKey),
      let archive = try? JSONDecoder().decode(Archive.self, from: data)
    else { return Archive() }
    return archive
  }

  private func screenID(_ screen: NSScreen) -> String {
    if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
      return number.stringValue
    }
    return screen.localizedName
  }

  private func bestScreen(for frame: NSRect) -> NSScreen? {
    NSScreen.screens.max { lhs, rhs in
      lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
    } ?? NSScreen.main
  }
}

extension NSRect {
  var area: CGFloat { max(0, width) * max(0, height) }
}
