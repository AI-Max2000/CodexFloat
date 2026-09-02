# Codex Float GitHub 图组：展开与完整额度

## Provenance

- Generated with built-in `image_gen` only. No CLI/API fallback, SVG, HTML, or programmatic image editing.
- Output intent: project-bound functional feature diagrams, not real account screenshots.
- Date: 2026-09-03.
- Approved style input: `docs/Images/codex-float-0.2.0-feature.png`.
- Old shape/content hierarchy inputs: `docs/Images/codex-float-expanded.png`, `docs/Images/codex-float-compact.png`. Both source screenshots were preserved unchanged.
- Final expanded output: `docs/Images/github-style-v1/01-expanded.png`, 1536 × 1024.
- Expanded final generation source: `generated_images/01a0636f-9887-7901-a8dc-115a9b3e67d9/exec-c870133b-aed9-4433-a30f-b5002267e6c2.png` (relative to Codex data directory).
- Expanded discarded first attempt: `generated_images/01a0636f-9887-7901-a8dc-115a9b3e67d9/exec-1424cd84-686d-4ec3-a6a5-cda3db25f6ad.png`.
- Final compact output: `docs/Images/github-style-v1/02-compact.png`, 1536 × 1024.
- Compact final generation source: `generated_images/01a0636f-9887-7901-a8dc-115a9b3e67d9/exec-123e0827-4437-4dd7-a832-f80010490adf.png`.
- Attempts: expanded 2; compact 1. Exactly 2 selected PNG assets copied into the project.

## Visual QA

- Chinese title, subtitle, task labels, capability labels, and example-data disclosure manually inspected in both full generated outputs.
- Expanded diagram uses generic task names A/B/C; no real task titles, account identifiers, live prediction values, dates, version labels, or reset promises.
- Expanded capability labels are outside the illustrated product panel; mouse cursor is separate from the rounded panel.
- Compact capsule contains remaining percentage, extra reset count, and countdown only; no progress bar added.
- Compact secondary outline card and cursor show hover, without a click arrow.
- No clipping observed. ImageGen approximate geometry is retained: intended 64 px safe margin is visually generous but not guaranteed pixel-exact; footer text reaches approximately 55 px from the bottom. The illustrated 75% track is approximate, not a pixel-measured account visualization.
- No app code, README, git metadata, release, or memory changes performed by this subtask.

## Expanded initial prompt (exact)

```text
Use case: infographic-diagram
Asset type: project-bound evergreen GitHub product feature illustration, PNG, 1536x1024 landscape, 3:2.
Primary request: Redesign the supplied old Codex Float expanded panel screenshot as a polished Chinese feature infographic. Use Image 1 only as the approved visual style reference and Image 2 only for the expanded panel's basic shape and information hierarchy. This is a newly illustrated functional diagram, not a screenshot. Remove ALL original task names, account details, dates, model plan information, live prediction values, and version numbers.
Style/medium: closely match Image 1's restrained macOS editorial typography and flat feature-illustration treatment: warm off-white #FAF9F6 background, dark graphite #202527 sans-serif type, quiet gray tracks and dividers, muted green #60A05A with amber and muted red only for small status dots. Delicate rounded outlined panels, no heavy shadows, no gradients, no 3D, no decorative texture, no official OpenAI logo.
Composition: generous whitespace and 64 px safe margins. Small centered top brand "Codex Float", small centered category "功能介绍", large bold centered Chinese headline "悬停展开，信息尽在眼前", then one brief subtitle "额度、任务与重置消息，一起看清". Below, one coherent large horizontally centered expanded rounded macOS-like panel, a subtle outline pointer near its upper-left implying hover. The panel itself should remain visually dominant, not a permanent expanded sidebar, with no unrelated UI.
Panel contents: header "Codex" on the left, "剩余 75%" on the right. Under it a quiet gray progress track exactly three-quarters filled muted green. A thin divider. Section label "最近任务", then exactly three well-spaced generic task rows: green dot plus "示例任务 A" on left, "已完成" on right; amber dot plus "示例任务 B" on left, "进行中" on right; muted red dot plus "示例任务 C" on left, "需处理" on right. Thin divider beneath tasks. Two simple smaller rows exactly "重置概率：仅供参考" and "Tibo 重置消息：等待验证".
Lower section: three concise capability labels with small gray line icons and fine vertical separators, matching the bottom capability band of Image 1: "任务状态可见", "点击进入聊天", "高度随内容变化". Do not add explanations.
Footer exact: "功能示意图 · 数据为示例 · 非真实账号截图".
Text must be clean, sharp, legible Simplified Chinese, rendered verbatim with no extra characters. All UI values are intentionally illustrative. Avoid invented capabilities, testimonials, real account information, specific live reset claims, dates, probabilities, permanent sidebar, menus, toggles, settings switches, app-window toolbar decorations, watermarks, version numbers.
```

## Expanded targeted refinement prompt (exact)

Input 1 was the generated expanded first attempt; input 2 was the approved style anchor.

```text
Use case: infographic-diagram
Edit target: Image 1 is the generated expanded feature infographic. Image 2 is the approved style reference. Make one targeted layout refinement to Image 1 while preserving ALL of its text verbatim, the warm off-white/graphite/green style, and the expanded-panel content.
Output: PNG, 1536x1024, landscape 3:2.
Layout changes only: enforce at least 64 px safe margins around every element including the top brand and bottom footer. Move the top brand downward as needed. Preserve a generous header hierarchy. Reduce the main panel height enough to move the three capability icons and labels OUTSIDE and BELOW the expanded panel in a clean separate bottom row. The actual rounded expanded panel must end immediately after the two reset-information rows, not include any capability band. Replace the speech-bubble-like notch at the panel upper-left with a separate small outline mouse cursor near the panel upper-left, indicating hover without touching or altering the rounded rectangular outline. Keep the progress track exactly three-quarters filled green so it accurately illustrates 75%.
Keep all exact copy: "Codex Float", "功能介绍", "悬停展开，信息尽在眼前", "额度、任务与重置消息，一起看清", "Codex", "剩余 75%", "最近任务", "示例任务 A", "已完成", "示例任务 B", "进行中", "示例任务 C", "需处理", "重置概率：仅供参考", "Tibo 重置消息：等待验证", "任务状态可见", "点击进入聊天", "高度随内容变化", "功能示意图 · 数据为示例 · 非真实账号截图".
Do not add new UI, settings, switches, account information, dates, probabilities, version numbers, heavy shadows, gradients, 3D or logos. Preserve correct Simplified Chinese.
```

## Compact prompt (exact)

```text
Use case: infographic-diagram
Asset type: project-bound evergreen GitHub product feature illustration, PNG, 1536x1024 landscape, 3:2.
Primary request: Redesign the supplied old Codex Float compact capsule screenshot as a polished Chinese feature infographic. Image 1 is ONLY the approved visual style reference. Image 2 is ONLY the shape and information layout reference for the compact capsule. This is a functional illustration, not a real account screenshot. Never reproduce the old background or any account identifier.
Style/medium: match Image 1's restrained, premium, flat macOS editorial feature-illustration treatment and clear bold sans-serif Simplified Chinese typography. Warm off-white #FAF9F6 background, dark graphite #202527 main type, quiet gray dividers and capsule fill, muted green #60A05A accent and small status dot, muted teal for extra reset text. Generous whitespace, low saturation, delicate outlines, no heavy shadows, no 3D, no gradients, no textures, no official OpenAI logo.
Composition: 64 px safe margins for ALL content. Small centered top brand "Codex Float", small centered category "功能介绍", large bold centered headline "完整额度，一眼掌握", then one brief gray subtitle "剩余百分比、刷新倒计时与额外重置". Under the heading, one centered large compact rounded horizontal capsule. Make the capsule the clear hero, faithfully like Image 2, and do not stretch it into a full panel.
Hero capsule exact content: a small green dot at left, first row bold dark text "Codex 剩余 75%" followed on the same row by smaller muted teal text "1 次额外重置". Second row beneath, left-aligned with Codex, smaller gray text "5 天 7 时". Capsule must contain ONLY these items. Absolutely NO progress bar, meter, sparkline, buttons, menu, toggle, date, plan label, or added text within the compact capsule.
Beneath the capsule, show a small subtle outlined arrow-shaped mouse cursor hovering at the edge of a much smaller pale outline expanded-card silhouette. The silhouette contains ONLY a few very light gray placeholder lines, no readable invented UI. Accompany it with the label "悬停查看详情". This is a secondary quiet illustration of hover, NOT a click action, no directional arrow from capsule to card, no click rays, no plus sign.
Lower feature band: three concise dark capability labels with simple gray line icons and subtle vertical separators, matching Image 1's lower strip treatment: "剩余额度", "刷新倒计时", "额外重置次数". Keep all labels outside the capsule. Avoid crossing callout lines and visual clutter.
Footer exact: "功能示意图 · 数据为示例 · 非真实账号截图".
Render every supplied text string verbatim in clean, legible Simplified Chinese with no extra characters. No version number. No testimonials, no live reset claims, no dates, no invented capabilities or switches. This image should visually belong to the same calm feature-documentation series as Image 1.
```
