# Contributing

Codex Float is a privacy-sensitive native macOS utility. Small, focused pull requests with tests are preferred.

## Local checks

Requires macOS 14+ and Swift 6:

```bash
swift test
swift test --sanitize=address
swift build -c release -Xswiftc -warnings-as-errors
CODEX_FLOAT_UNIVERSAL=1 ./Scripts/build-app.sh
```

The regular test suite must not require a logged-in Codex account or live network access. Put account-dependent checks behind `CODEX_FLOAT_LIVE_TEST=1` and never commit captured quota values, task titles, post bodies, credentials, cookies, or local database contents.

## Product rules

- Do not read `auth.json`, chat messages, rollouts, browser cookies, or project contents.
- Normal app launch must not edit Codex configuration.
- Failed refreshes keep the last successful snapshot and must not render as zero quota.
- Tibo announcements and locally observed account changes remain separate facts.
- New UI strings require Simplified Chinese, Traditional Chinese, and English variants.
- Motion changes must keep the collapsed meter anchored and respect Reduce Motion.

## Pull requests

Explain the user-visible outcome and privacy impact, add regression coverage, and include redacted before/after captures for visual changes. Confirm that unrelated user files and preferences were not modified.

