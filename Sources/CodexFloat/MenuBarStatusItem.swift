import AppKit
import CodexQuotaCore

enum MenuBarStatusItemVisibility {
  static func shouldShow(for displayMode: QuotaDisplayMode) -> Bool {
    displayMode == .menuBar
  }
}

enum MenuBarStatusItemPlacement {
  // v5 migrates away from the old leftmost placement, which macOS can
  // temporarily hide when the menu bar is crowded. AppKit deletes its saved
  // position when an item is hidden, so we keep a separate copy and restore it
  // whenever menu-bar mode creates the native item again.
  static let autosaveName = "com.local.codexfloat.quota-status.native-v5"
  static let reservedTrailingSystemWidth: CGFloat = 350
  static let minimumLeadingPosition: CGFloat = 180
  static let rememberedPositionKey = "CodexFloat Remembered Menu Bar Position v1"

  static var preferredPositionKey: String {
    "NSStatusItem Preferred Position \(autosaveName)"
  }

  static func visibleDefaultPosition(for screenFrame: NSRect) -> Int {
    Int(
      max(
        screenFrame.minX + minimumLeadingPosition,
        screenFrame.maxX - reservedTrailingSystemWidth
      ).rounded()
    )
  }

  static func prepareVisiblePosition(
    defaults: UserDefaults = .standard,
    screenFrame: NSRect
  ) {
    let appKitPosition = (defaults.object(forKey: preferredPositionKey) as? NSNumber)?.intValue
    let rememberedPosition =
      (defaults.object(forKey: rememberedPositionKey) as? NSNumber)?.intValue
    let position = appKitPosition ?? rememberedPosition ?? visibleDefaultPosition(for: screenFrame)
    defaults.set(position, forKey: preferredPositionKey)
    defaults.set(position, forKey: rememberedPositionKey)
  }

  static func rememberCurrentPosition(defaults: UserDefaults = .standard) {
    guard let position = defaults.object(forKey: preferredPositionKey) as? NSNumber else {
      return
    }
    defaults.set(position.intValue, forKey: rememberedPositionKey)
  }
}

@MainActor
final class MenuBarStatusItemHoverMonitor: NSObject {
  private let onHoverChanged: (Bool) -> Void
  private weak var button: NSStatusBarButton?
  private var trackingArea: NSTrackingArea?

  init(onHoverChanged: @escaping (Bool) -> Void) {
    self.onHoverChanged = onHoverChanged
  }

  func install(on button: NSStatusBarButton) {
    if let trackingArea, let currentButton = self.button {
      currentButton.removeTrackingArea(trackingArea)
    }
    let trackingArea = NSTrackingArea(
      rect: .zero,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    button.addTrackingArea(trackingArea)
    self.button = button
    self.trackingArea = trackingArea
  }

  @objc func mouseEntered(with event: NSEvent) {
    onHoverChanged(true)
  }

  @objc func mouseExited(with event: NSEvent) {
    onHoverChanged(false)
  }
}

@MainActor
enum MenuBarStatusItemAnchor {
  static func screenFrame(for button: NSStatusBarButton) -> NSRect? {
    guard let window = button.window else { return nil }
    return window.convertToScreen(button.convert(button.bounds, to: nil))
  }
}

@MainActor
enum MenuBarQuotaIndicator {
  enum AppearanceMode: Equatable {
    case light
    case dark

    static func resolve(_ appearance: NSAppearance) -> AppearanceMode {
      appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    var hoverBackgroundAlpha: CGFloat {
      switch self {
      case .light: 0.055
      case .dark: 0.10
      }
    }
  }

  enum Layout {
    static let imageSize = NSSize(width: 26, height: 18)
    static let statusItemLength: CGFloat = 30
    static let trackFrame = NSRect(x: 1, y: 1, width: 3, height: 16)
    static let valueFrame = NSRect(x: 4, y: 8, width: 20, height: 10)
    static let countdownFrame = NSRect(x: 4, y: 0.5, width: 20, height: 7.5)
  }

  struct PercentageParts {
    let digits: NSAttributedString
    let digitsGlyphFrame: NSRect
    let symbol: NSAttributedString?
    let symbolFrame: NSRect?
  }

  static func percentageParts(
    remainingPercent: Double?,
    color: NSColor = .labelColor,
    paragraphStyle: NSParagraphStyle? = nil,
    shadow: NSShadow? = nil
  ) -> PercentageParts {
    guard let remainingPercent else {
      return PercentageParts(
        digits: NSAttributedString(
          string: "--",
          attributes: textAttributes(
            font: .monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold),
            color: color,
            paragraphStyle: paragraphStyle,
            shadow: shadow
          )
        ),
        digitsGlyphFrame: .zero,
        symbol: nil,
        symbolFrame: nil
      )
    }

    let value = Int(min(100, max(0, remainingPercent)).rounded())
    let usesThreeDigits = value >= 100
    let digitFont = NSFont.monospacedDigitSystemFont(
      ofSize: usesThreeDigits ? 6.5 : 8.5,
      weight: .semibold
    )
    let digits = NSAttributedString(
      string: String(value),
      attributes: textAttributes(
        font: digitFont,
        color: color,
        paragraphStyle: paragraphStyle,
        shadow: shadow
      )
    )
    let symbol = NSAttributedString(
      string: "%",
      attributes: textAttributes(
        font: .systemFont(ofSize: usesThreeDigits ? 3.5 : 4.2, weight: .semibold),
        color: color,
        paragraphStyle: nil,
        shadow: shadow
      )
    )
    let digitsSize = digits.size()
    let digitsGlyphFrame = NSRect(
      x: Layout.valueFrame.midX - digitsSize.width / 2,
      y: Layout.valueFrame.midY - digitsSize.height / 2,
      width: digitsSize.width,
      height: digitsSize.height
    )
    let symbolSize = symbol.size()
    let desiredSymbolX = digitsGlyphFrame.maxX + 0.7
    let symbolX = min(Layout.imageSize.width - symbolSize.width, desiredSymbolX)
    let symbolY = Layout.valueFrame.maxY - symbolSize.height - 0.3
    return PercentageParts(
      digits: digits,
      digitsGlyphFrame: digitsGlyphFrame,
      symbol: symbol,
      symbolFrame: NSRect(origin: NSPoint(x: symbolX, y: symbolY), size: symbolSize)
    )
  }

  static func image(
    remainingPercent: Double?,
    countdown: String,
    lowThreshold: Double,
    criticalThreshold: Double,
    appearance: NSAppearance? = nil,
    isHighlighted: Bool = false
  ) -> NSImage {
    let size = Layout.imageSize
    let drawingAppearance = appearance ?? NSApp.effectiveAppearance
    let appearanceMode = AppearanceMode.resolve(drawingAppearance)
    let remaining = min(100, max(0, remainingPercent ?? 0))
    let components = remainingPercent.map {
      QuotaMeterPalette.components(
        remainingPercent: $0,
        lowThreshold: lowThreshold,
        criticalThreshold: criticalThreshold
      )
    }
    let fillColor =
      components.map {
        NSColor(
          calibratedRed: $0.red,
          green: $0.green,
          blue: $0.blue,
          alpha: 1
        )
      } ?? NSColor.systemGray

    return NSImage(size: size, flipped: false) { _ in
      drawingAppearance.performAsCurrentDrawingAppearance {
        if isHighlighted {
          NSColor.labelColor.withAlphaComponent(appearanceMode.hoverBackgroundAlpha).setFill()
          NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5),
            xRadius: 5,
            yRadius: 5
          ).fill()
        }

        let trackRect = Layout.trackFrame
        NSColor.secondaryLabelColor.withAlphaComponent(0.24).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: 1.5, yRadius: 1.5).fill()

        if remaining > 0 {
          let fillHeight = max(2, trackRect.height * remaining / 100)
          let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: trackRect.width,
            height: fillHeight
          )
          fillColor.setFill()
          NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5).fill()
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let percentage = percentageParts(
          remainingPercent: remainingPercent,
          color: .labelColor,
          paragraphStyle: paragraph,
          shadow: nil
        )
        percentage.digits.draw(in: Layout.valueFrame)
        if let symbol = percentage.symbol, let symbolFrame = percentage.symbolFrame {
          symbol.draw(in: symbolFrame)
        }
        (countdown as NSString).draw(
          in: Layout.countdownFrame,
          withAttributes: [
            .font: NSFont.systemFont(ofSize: 6.3, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
          ]
        )
      }
      return true
    }
  }

  private static func textAttributes(
    font: NSFont,
    color: NSColor,
    paragraphStyle: NSParagraphStyle?,
    shadow: NSShadow?
  ) -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
    ]
    if let paragraphStyle { attributes[.paragraphStyle] = paragraphStyle }
    if let shadow { attributes[.shadow] = shadow }
    return attributes
  }
}

/// Two named readings in one native item. Fixed slots prevent 9 → 100 or
/// countdown changes from shifting the item or its hover anchor.
@MainActor
enum MenuBarDualQuotaIndicator {
  static let textWidth: CGFloat = 42
  static let imageSize = NSSize(width: 100, height: 18)
  static let statusItemLength: CGFloat = 104

  static func cellFrame(at index: Int) -> NSRect {
    NSRect(x: CGFloat(index) * 52, y: 0, width: 48, height: 18)
  }

  static func image(
    entries: [QuotaDisplayEntry],
    strings: AppStrings,
    now: Date,
    lowThreshold: Double,
    criticalThreshold: Double,
    appearance: NSAppearance,
    isHighlighted: Bool = false
  ) -> NSImage {
    NSImage(size: imageSize, flipped: false) { _ in
      appearance.performAsCurrentDrawingAppearance {
        if isHighlighted {
          NSColor.labelColor.withAlphaComponent(
            MenuBarQuotaIndicator.AppearanceMode.resolve(appearance).hoverBackgroundAlpha
          ).setFill()
          NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: imageSize), xRadius: 5, yRadius: 5
          ).fill()
        }
        for (index, entry) in entries.prefix(2).enumerated() {
          let cell = cellFrame(at: index)
          let track = NSRect(x: cell.minX + 1, y: 1, width: 3, height: 16)
          NSColor.secondaryLabelColor.withAlphaComponent(0.24).setFill()
          NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
          if let remaining = entry.window?.remainingPercent, remaining > 0 {
            let components = QuotaMeterPalette.components(
              remainingPercent: remaining,
              lowThreshold: lowThreshold,
              criticalThreshold: criticalThreshold
            )
            NSColor(
              calibratedRed: components.red, green: components.green,
              blue: components.blue, alpha: 1
            ).setFill()
            NSBezierPath(
              roundedRect: NSRect(
                x: track.minX, y: 1, width: 3, height: max(2, 16 * remaining / 100)),
              xRadius: 1.5, yRadius: 1.5
            ).fill()
          }
          let paragraph = NSMutableParagraphStyle()
          paragraph.alignment = .center
          let value = "\(entry.shortLabel(strings)) \(entry.percentage)"
          (value as NSString).draw(
            in: NSRect(x: cell.minX + 6, y: 8, width: textWidth, height: 10),
            withAttributes: [
              .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .semibold),
              .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
            ]
          )
          (entry.compactCountdown(strings, now: now) as NSString).draw(
            in: NSRect(x: cell.minX + 6, y: 0, width: textWidth, height: 8),
            withAttributes: [
              .font: NSFont.systemFont(ofSize: 6.3, weight: .medium),
              .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph,
            ]
          )
        }
      }
      return true
    }
  }
}
