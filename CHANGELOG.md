# Changelog

All notable changes to Codex Float will be documented in this file.

## Unreleased

暂无尚未记录的更新。

## 2026-09-03 — 源码预览更新

发布标签：`preview-2026-09-03`。本次为源码预览，不包含已公证的正式安装包。
完整中文发布说明见 [本次更新记录](docs/releases/2026-09-03.md)。

### 窗口位置与移动显隐

- 新增默认开启的“跟随 Codex 窗口移动”设置，仅作用于完整额度和极简进度条。
- 检测到 Codex 窗口实际移动时暂时隐藏；松手且位置稳定约 120 毫秒后，在记忆的相对位置直接恢复，避免显示追赶过程。不是跨应用原生窗口绑定。
- 按住鼠标途中停顿不会闪现；聊天内拖选文字但窗口未移动时不隐藏。隐藏时不拦截鼠标点击。
- 两种形态分别记忆相对位置，支持重启和切换形态后恢复；屏幕边缘限制不会改写用户位置。
- 修复动画途中移动后的旧坐标回跳，恢复显示前再次校准最终位置；手动隐藏、前台显示规则和菜单栏模式保持原有优先级。
- 使用独立的临时检查时钟处理隐藏期间定位、迟到位置变化和遗漏的松手事件，结束后清理；目标不可用时低频等待恢复。

### 5 小时与每周额度

- 新增默认关闭的“显示 5 小时额度”开关，根据账号实际返回的窗口启用，不再按 Plus 等套餐名称硬编码。
- 开启后，完整额度与菜单栏展示两组读数和倒计时，极简形态展示双进度条；展开后分别标明周期，并自适应高度。
- 只有 5 小时窗口时显示唯一额度并解释锁定状态；没有该窗口时不展示开关，不推测或生成不存在的额度。
- 保留旧开关偏好，不影响 GPT 专项额度及通知逻辑；套餐文案使用实际账号信息。README 的新预览图明确标注为测试样本。

### 验证与隐私

- 简体中文、繁体中文、英文设置说明同步更新。
- 本地普通测试与 Address Sanitizer 全量回归均为 148 项通过；Release 警告即错误编译及本地签名结构检查通过。
- 新增窗口显隐、位置记忆、计时清理、双额度布局和设置迁移测试；原生窗口测试使用自有测试窗口，不读取真实账号。
- 原生窗口流水线测试改为有界条件等待，兼容云端 macOS 虚拟机的时钟合并；保留 48 次变化采样与全部行为断言，不以固定 3 秒采样量判定功能失败。
- 窗口跟随只读取几何信息，不增加辅助功能或屏幕录制权限，不读取聊天正文或凭证。
- 真实 Codex 拖动、实体多显示器和全屏切换仍属于人工验收范围，详见 [回归记录](docs/qa-window-pinning.md)。

## Earlier source updates

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
