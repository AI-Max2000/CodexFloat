import AppKit

/// A top-left offset in points, independent of screen origin and panel height.
struct WindowPinOffset: Codable, Equatable {
  let left: CGFloat
  let top: CGFloat

  init(panelFrame: NSRect, windowFrame: NSRect) {
    left = panelFrame.minX - windowFrame.minX
    top = windowFrame.maxY - panelFrame.maxY
  }

  var isValid: Bool { left.isFinite && top.isFinite }
}

enum WindowPinGeometry {
  static func frame(
    offset: WindowPinOffset, windowFrame: NSRect, panelSize: NSSize,
    expandedSize: NSSize, visibleFrame: NSRect
  ) -> NSRect {
    // Only the compact entry is constrained to the screen. The detail surface
    // chooses its own direction; reserving its footprint would push the entry.
    PanelPlacementGeometry.clamped(
      NSRect(
        x: windowFrame.minX + offset.left,
        y: windowFrame.maxY - offset.top - panelSize.height,
        width: panelSize.width,
        height: panelSize.height),
      to: visibleFrame)
  }
}
