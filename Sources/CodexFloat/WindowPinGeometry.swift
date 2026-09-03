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

struct WindowPinPreference: Codable, Equatable {
  let offset: WindowPinOffset
  let userCustomized: Bool
}

enum WindowPinGeometry {
  static func anchorPoint(offset: WindowPinOffset, windowFrame: NSRect) -> NSPoint {
    NSPoint(
      x: windowFrame.minX + offset.left,
      y: windowFrame.maxY - offset.top)
  }

  static func automaticAnchorPoint(windowFrame: NSRect, labelFrame: NSRect?) -> NSPoint {
    if let labelFrame, windowFrame.intersects(labelFrame) {
      return NSPoint(x: labelFrame.maxX + 10, y: labelFrame.maxY)
    }
    return NSPoint(x: windowFrame.minX + 12, y: windowFrame.maxY - 38)
  }

  static func screenIndex(
    containing anchor: NSPoint, windowFrame: NSRect, visibleFrames: [NSRect]
  ) -> Int? {
    visibleFrames.firstIndex(where: { $0.contains(anchor) })
      ?? visibleFrames.indices.max {
        visibleFrames[$0].intersection(windowFrame).area
          < visibleFrames[$1].intersection(windowFrame).area
      }
  }

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
