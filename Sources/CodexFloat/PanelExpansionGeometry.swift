import AppKit
import SwiftUI

/// Chosen once per hover cycle. A flipped reveal changes the growing corner,
/// never the screen-space rectangle of the compact entry or the text order.
struct PanelExpansionDirection: Equatable {
  var growsLeft = false
  var growsUp = false

  var alignment: Alignment {
    if growsUp { return growsLeft ? .bottomTrailing : .bottomLeading }
    return growsLeft ? .topTrailing : .topLeading
  }

  var unitPoint: UnitPoint {
    UnitPoint(x: growsLeft ? 1 : 0, y: growsUp ? 1 : 0)
  }
}

struct PanelExpansionPlacement: Equatable {
  let frame: NSRect
  let direction: PanelExpansionDirection
}

enum PanelExpansionGeometry {
  static func resolve(
    compactFrame: NSRect, preferredSize: NSSize, visibleFrame: NSRect,
    lockedDirection: PanelExpansionDirection? = nil
  ) -> PanelExpansionPlacement {
    let compact = PanelPlacementGeometry.clamped(compactFrame, to: visibleFrame)
    let right = max(compact.width, visibleFrame.maxX - compact.minX)
    let left = max(compact.width, compact.maxX - visibleFrame.minX)
    let down = max(compact.height, compact.maxY - visibleFrame.minY)
    let up = max(compact.height, visibleFrame.maxY - compact.minY)
    // Prefer the original down/right motion when it fits. If neither side fits,
    // use the larger side and scroll the content inside the bounded viewport.
    let direction =
      lockedDirection
      ?? PanelExpansionDirection(
        growsLeft: preferredSize.width > right && left > right,
        growsUp: preferredSize.height > down && up > down
      )
    let width = min(max(compact.width, preferredSize.width), direction.growsLeft ? left : right)
    let height = min(max(compact.height, preferredSize.height), direction.growsUp ? up : down)
    return PanelExpansionPlacement(
      frame: NSRect(
        x: direction.growsLeft ? compact.maxX - width : compact.minX,
        y: direction.growsUp ? compact.minY : compact.maxY - height,
        width: width, height: height
      ),
      direction: direction
    )
  }

  /// Reverse mapping after a real user drag/resize of the expanded panel.
  static func compactFrame(
    in expandedFrame: NSRect, size: NSSize, direction: PanelExpansionDirection
  ) -> NSRect {
    NSRect(
      x: direction.growsLeft ? expandedFrame.maxX - size.width : expandedFrame.minX,
      y: direction.growsUp ? expandedFrame.minY : expandedFrame.maxY - size.height,
      width: size.width, height: size.height
    )
  }
}
