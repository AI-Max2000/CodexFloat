# Changelog

All notable changes to Codex Float will be documented in this file.

## Unreleased

- Added an expiry carousel for extra Reset credits. It starts when the earliest credit is less
  than seven days from expiry and progressively gives the countdown more display time at the
  five-day, three-day, and one-day thresholds.
- Reworked the standard and minimal hover expansion into a continuous liquid-capsule transition.
  The collapsed content and expanded surface now share one animation clock and a fixed top-left
  anchor, so the first and final frames no longer appear to switch between separate views.
- Improved the native menu-bar quota item for both light and dark macOS appearances while keeping
  its percentage, compact refresh countdown, and hover details legible.
- Fixed expanded-panel content clipping, inconsistent animated corners, temporary white borders,
  excessive empty height, and right-side header actions being cut off during expansion.
- Kept the minimal quota meter stationary while its details open or close, and synchronized a
  user-moved expanded panel with the compact meter's remembered resting position.
- Made AppKit motion tests deterministic across CI machines with different accessibility motion
  settings, replaced timing-sensitive completion checks with bounded state polling, and retained
  regression coverage for stable anchors, monotonic transitions, and adaptive panel height.
- Established the initial macOS app source, tests, scripts, resources, and documentation baseline.
- Prevented rolling quota windows from creating repeated five-hour notifications.
- Added stable reset-cycle notification IDs and bounded notification-key retention.
- Made active feedback relocalize immediately when the app language changes.
- Improved expanded-panel information hierarchy, dynamic quota accessibility labels, text sizes,
  icon hit targets, and the minimal meter drag area.
- Added optional Universal 2 builds and a Developer ID notarization workflow.
- Made normal launch completely read-only with respect to Codex hook configuration while keeping
  older hook invocations harmless.
- Reduced idle expanded-panel work by updating long quota countdowns once per minute and reserving
  one-second updates for the final ten minutes.
- Made task monitoring adaptive: two-second status checks while work is active, with a fifteen-second
  full calibration cadence once all tracked tasks are idle.
- Added deterministic app-icon sources, configurable release metadata, DMG checksums, GitHub CI,
  signed/notarized release automation, artifact attestations, security guidance, and issue templates.
- Added isolated regression coverage for notification planning and the Carbon global-hot-key
  lifecycle, including conflicts and cleanup failures.
