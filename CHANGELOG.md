# Changelog

All notable changes to Codex Float will be documented in this file.

## Unreleased

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
