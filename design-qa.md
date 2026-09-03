# Design QA — compact reset-count trailing inset

## Scope

- Reference: the user-provided compact quota screenshot for this correction.
- Current light capture: `docs/Images/codex-float-0.2.2-compact-light.png`
- Current dark capture: `docs/Images/codex-float-0.2.2-compact-dark.png`
- Compared state: standard compact quota, two-digit percentage, one-digit reset count.

## Findings

- P0: none.
- P1: none.
- P2: none.
- P3: the compact width grows from 174 pt to 188 pt; this is intentional and remains visually compact.

## Verification

- The reset label no longer touches or crosses the rounded clipping boundary.
- The right edge keeps a 12 pt safety inset, larger than the 8 pt leading inset.
- Light and dark native-material captures preserve the same hierarchy and spacing.
- Height remains 54 pt; the countdown baseline and top-left expansion anchor are unchanged.

final result: passed
