# Codex Float GitHub feature infographic prompts: settings and quota windows

Created: 2026-09-03

Method: built-in ImageGen, one initial call per asset and one targeted correction for quota windows. Original screenshots remain unchanged. These are conceptual function illustrations, not live-account captures. No application code, README, Git, release, or memory changes are in scope.

Privacy: Published prompts preserve their full wording except local absolute input paths, which have been normalized to repository-relative paths. Source identifiers are relative to the generated-image store and do not expose the local account name.

Approved style reference: `docs/Images/codex-float-0.2.0-feature.png`

## 05 Settings — exact generation prompt

```text
Use case: infographic-diagram
Asset type: evergreen Codex Float GitHub feature infographic.
Input images: Image 1 is the approved STYLE REFERENCE (docs/Images/codex-float-0.2.0-feature.png); Image 2 is the OLD FUNCTION-CONTENT REFERENCE (docs/Images/codex-float-display-settings.png). Create a completely redrawn feature infographic, preserve only documented feature content from Image 2. Do not reproduce cropped screenshot edges.
Canvas: exactly 1536 × 1024 pixels, landscape, 64 px safe margin on every side.
Primary request: A clean premium native macOS editorial infographic in the same visual family as Image 1. Warm off-white #FAF9F6 background; graphite #202527 typography; muted green #60A05A accent; light gray segmented-control tracks and fine dividers; restrained near-flat illustration. Generous whitespace, precise typographic hierarchy, no heavy shadows, no gradients, no 3D, no OpenAI logo.
Typography and composition: At top center small brand text "Codex Float" with the small descriptor "功能介绍". Below is the large bold Chinese headline "三种显示形态，随时切换"; below it a lighter medium-size subtitle "在设置里，找到适合你的桌面方式". Center a single large clean conceptual settings panel within fine light-gray border. It is a functional illustration, not an exact screenshot.
Central panel content: First row left label "显示形态"; beside it exactly three evenly spaced segmented options with simple thin-line native icons and verbatim labels "完整额度", "极简进度条", "菜单栏额度". Middle option selected using white inset and muted-green accent. The complete-quota icon is a small panel with two short lines, minimal-progress icon is a small vertical meter, menu-bar icon is a small simple menu bar. Exactly one fine divider. Second row label "鼠标移入时自动展开" with one green toggle in ON state at far right. Do not add any other rows, toggles, controls, settings, drag handles, or resizing controls.
Below the panel: three evenly spaced concise feature labels, with modest line icons if needed: "快捷键可编辑" / "三种界面语言" / "分别记住位置".
Bottom exact disclosure: "功能示意图 · 数据为示例 · 非真实账号截图".
Text rules: Every quoted Chinese string must be rendered exactly and readably, with clear modern Chinese sans-serif typography. No typos, no repeated labels, no extra copy, no invented feature claims, no version number, no system requirements, no preview/release status. Maintain ample space around the panel and footer.
```

Original content reference: `docs/Images/codex-float-display-settings.png`

Destination: `docs/Images/github-style-v1/05-settings.png`

Generation source: `generated_images/01a06370-884e-7a23-91f4-771fd505242a/exec-cd64589d-a162-4366-9c64-5d7108d823de.png`.

QA: 1536 × 1024 PNG; all requested Chinese labels and disclosure are readable and correct. Exactly three display-form options, middle selected; exactly one hover-expansion toggle; no invented controls, account claims, or version stamp. First attempt selected. Minor deviation: brand ink begins approximately 59 px from the top, just inside the requested 64 px safety margin.

## 06 Quota windows — exact generation prompt

```text
Use case: infographic-diagram
Asset type: evergreen Codex Float GitHub feature infographic.
Input images: Image 1 is the approved STYLE REFERENCE (docs/Images/codex-float-0.2.0-feature.png); Image 2 is the OLD FUNCTION-CONTENT REFERENCE (docs/Images/codex-float-quota-windows.png). Create a completely redrawn feature infographic in the approved style. Use only the safe verified function content described below, not Image 2 account names or actual example times.
Canvas: exactly 1536 × 1024 pixels, landscape, 64 px safe margin on every side.
Primary request: A clean premium native macOS editorial infographic in the same visual family as Image 1. Warm off-white #FAF9F6 background; graphite #202527 typography; muted green #60A05A accent; light gray tracks and thin dividers; restrained near-flat native UI illustration. Generous whitespace and clear hierarchy. No heavy shadows, no gradients, no 3D, no OpenAI logo.
Typography and composition: At top center small brand text "Codex Float" and the small descriptor "功能介绍". Below is the large bold Chinese headline "双额度分开看，不再混淆"; below it a lighter medium-size subtitle "5 小时与每周额度，各有自己的节奏". Center a single large simple quota panel with TWO clean stacked quota rows. A fine divider separates the rows.
First row: left title "5 小时额度"; right value "剩余 75%". Below, one long horizontal light-gray quota track with green fill covering EXACTLY THREE QUARTERS (75%) of the full track length, and the remaining ONE QUARTER clearly gray. Below the track use the exact caption "各自显示刷新时间".
Second row: left title "每周额度"; right value "剩余 25%". Below, a same-length horizontal light-gray quota track with green fill covering EXACTLY ONE QUARTER (25%) of the full track length, and remaining THREE QUARTERS gray. Below the track use the exact caption "各自显示刷新时间".
Important proportional geometry: Both quota tracks have identical total width and start/end positions. The first fill is exactly three times as long as the second fill. Green starts at the left edge of each track. Make the 75% and 25% visual fractions mathematically unambiguous.
Keep the main focus on these two rows only; omit any additional meter illustrations, rings, alternate horizontal display styles, or other app shapes. The horizontal bars inside the quota rows are ordinary quota tracks, not a separate minimal display style.
Below the main panel present two restrained capability statements: "仅在账号实际返回两个窗口时显示" and "设置 → 额度显示 → 显示 5 小时额度".
Bottom exact disclosure: "功能示意图 · 数据为示例 · 非真实账号截图".
Text rules: Every quoted Chinese string must be rendered exactly and readably with modern Chinese sans-serif typography. No invented dates, countdowns, or refresh times. Do not imply fixed refresh times for all sliding windows. No Free/Plus/Pro labels, no account entitlements, no claim of free availability to all accounts. No version number, system requirements, release status, additional feature claims, extra copy, repeated headings, or watermark.
```

Original content reference: `docs/Images/codex-float-quota-windows.png`

Destination: `docs/Images/github-style-v1/06-quota-windows.png`

First generated source: `generated_images/01a06370-884e-7a23-91f4-771fd505242a/exec-b570b0d1-ddad-4af6-b2e9-ef17d08b24a2.png`.

First-pass QA: 1536 × 1024; all requested Chinese readable and correct; quota fill proportions approximately 79% and 26%, not sufficiently aligned with 75% / 25%. One targeted ImageGen correction requested below; no deterministic raster editing used.

### 06 Exact correction prompt (attempt 2 of 2)

```text
Use case: precise-object-edit
Image 1 is the EDIT TARGET, a Codex Float feature infographic. Make one precise proportional correction to the two quota-track green fills, preserving everything else: same 1536 × 1024 canvas, same background, typography, exact Chinese text, panel positions, icons, border geometry, bar outer dimensions, gray tracks, footnote, and all spacing.
The current top green fill is too long (about 79%), and the current bottom fill is slightly too long (about 26%). They must visually and mathematically equal 75% and 25%.
Coordinates in this 1536 × 1024 image: BOTH tracks start at x=210 and end at x=1322, so total length is 1112 pixels. Top track has y=419 to 462. Correct its green fill to end at x=1044, yielding 834 green pixels and 278 gray pixels, exactly 75% / 25%. Bottom track has y=657 to 696. Correct its green fill to end at x=488, yielding 278 green pixels and 834 gray pixels, exactly 25% / 75%. Retain natural small rounded ends but align the visual green boundaries exactly at those positions. Do NOT change track x start/end, label values, or overall layout.
All text must remain perfectly unchanged, including "双额度分开看，不再混淆", "5 小时与每周额度，各有自己的节奏", "剩余 75%", "剩余 25%", "各自显示刷新时间", "仅在账号实际返回两个窗口时显示", "设置 → 额度显示 → 显示 5 小时额度", and "功能示意图 · 数据为示例 · 非真实账号截图".
Change ONLY the fill endpoint positions. No new content, no new shapes, no versions, no logo, no resizing/cropping.
```

Superseded review candidate: `generated_images/01a06370-884e-7a23-91f4-771fd505242a/exec-d5bbcce4-ddde-4b89-bbb3-0c176da1e478.png`.

Candidate QA: 1536 × 1024 PNG; Chinese wording and disclosure correct. A read-only pixel scan found 78.78% / 25.81% instead of exact 75% / 25%, so the candidate was not accepted as a quantitative diagram. The worker stopped after two attempts. The coordinator chose a non-numeric conceptual illustration below. Top brand margin is approximately 40px, rather than the 64px design target; no content is clipped.

## Final conceptual revision

Final source: `generated_images/01a0563a-41bd-7380-9479-ca2f5f3867c6/exec-30a5de6b-05a8-433a-870f-a4f4530c7dfe.png`. Built-in ImageGen edit, 1536 × 1024. Both percentage callouts replaced with “剩余额度”; the 5-hour / weekly window labels and actual-account condition remain. Final visual check: wording, separate windows, settings entry, disclosure, no mismatched numeric percentage claim and no clipping. Shapes are illustrative, not quantitative charts.

```text
Edit this existing infographic with ONE precise text correction only. Replace BOTH right-aligned labels '剩余 75%' and '剩余 25%' with the same text '剩余额度'. Keep all other text, two quota rows, all green fills and gray tracks, colors, shapes, spacing, background, headings, settings-entry note and disclosure unchanged. This is a conceptual feature diagram rather than a numeric chart. Do not change the row names '5 小时额度' and '每周额度'; those are time-window durations and must remain. No percentage numbers should remain. Preserve 1536x1024 dimensions and exact visual style.
```
