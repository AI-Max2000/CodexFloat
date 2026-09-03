import AppKit

@MainActor
enum MenuBarRecoveryIndicator {
  static func image(state: QuotaRecoveryState, strings: AppStrings, appearance: NSAppearance)
    -> NSImage
  {
    NSImage(size: NSSize(width: 44, height: 18), flipped: false) { _ in
      appearance.performAsCurrentDrawingAppearance {
        let accent = state.needsRefresh ? NSColor.systemOrange : NSColor.systemRed
        NSAttributedString(
          string: state.needsRefresh ? "↻" : (state.canOpenManualReset ? "↺" : "!"),
          attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: accent,
          ]
        ).draw(in: NSRect(x: 0, y: 3, width: 10, height: 12))
        let top = state.kind == .exhausted ? "0%" : "--"
        NSAttributedString(
          string: top,
          attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
          ]
        ).draw(in: NSRect(x: 10, y: 8, width: 34, height: 10))
        let bottom: String
        if state.needsRefresh {
          bottom = strings.text(.refresh)
        } else if state.canOpenManualReset {
          bottom = strings.language == .english ? "Reset ↗" : "重置 ↗"
        } else {
          bottom = strings.language == .english ? "Usage ↗" : "用量 ↗"
        }
        NSAttributedString(
          string: bottom,
          attributes: [
            .font: NSFont.systemFont(ofSize: 7, weight: .semibold),
            .foregroundColor: accent,
          ]
        ).draw(in: NSRect(x: 10, y: 0, width: 34, height: 9))
      }
      return true
    }
  }
}
