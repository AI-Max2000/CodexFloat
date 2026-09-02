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
    // Reserve the expanded footprint so hover never changes the compact anchor
    // near a screen edge. Clamping is temporary; never overwrite the saved offset.
    let footprint = PanelPlacementGeometry.clamped(
      NSRect(
        x: windowFrame.minX + offset.left,
        y: windowFrame.maxY - offset.top - max(panelSize.height, expandedSize.height),
        width: max(panelSize.width, expandedSize.width),
        height: max(panelSize.height, expandedSize.height)),
      to: visibleFrame)
    return NSRect(
      x: footprint.minX, y: footprint.maxY - panelSize.height,
      width: panelSize.width, height: panelSize.height)
  }
}
