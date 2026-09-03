# Changelog

All notable changes to Codex Float will be documented in this file.

## Unreleased

暂无新的未发布变更。

## 0.2.1 — 2026-09-04

发布标签：`preview-0.2.1`。本次提供 Universal 2 DMG / ZIP，采用 ad-hoc 签名，尚未经过 Apple Developer ID 签名与公证。

### 窗口定位稳定性

- 系统分辨率、全屏、Stage Manager 或屏幕参数变化导致 macOS 重排浮窗时，不再把系统生成的位置误记为用户锚点；下一运行循环会按可信偏移纠正。
- 普通校准、唤醒和显示器变化继续锁定原 Codex 窗口。只有明确切换回 Codex 或点击另一 Codex 窗口时才允许更换目标，避免多窗口层级变化造成跳位。
- 未手动摆放时，浮窗会跟随 Codex 标题区域；标题消失时回到窗口左上角。用户拖动后切换为窗口相对锚点，不再受内部侧栏布局影响。
- 完整额度和极简进度条改为共享同一个左上角锚点；旧版当前位置按当前形态迁移，不清空用户已有位置。跨屏时根据锚点所在屏幕决定归属，不再使用整个 Codex 窗口的面积占比。
- 标题定位先验证候选控件位于窗口顶部且角色为标题文本/按钮，再读取精确的 `Codex` 标签；不会遍历读取聊天内容文字。
- 定向窗口回归 32 项、普通全量回归 207 项、Address Sanitizer 全量 207 项和 Thread Sanitizer 全量 207 项均通过；Release 警告即错误构建及真实登录环境的只读连通测试通过。实体多显示器、多 Codex 窗口和真实系统全屏切换仍保留为后续人工验收项。

### 额度耗尽后的恢复入口

- 修正极简耗尽警示的外观：去掉整块画布上的红框和遮挡轨道的大感叹号，竖条/横条仅描边实际空轨道，圆环沿真实圆形描边；中心恢复原先留空的状态，不新增百分比或符号。双额度仅强调受限的周额度；较旧数据使用琥珀色提示。保留尺寸、拖动锚点和点击入口。
- 菜单栏去掉实心感叹号，改用轻量重置/刷新符号，并区分刷新提示的颜色。
- 仅在「周额度耗尽且有可用额外重置次数」时启用恢复入口：完整额度切换为 `Codex · 0%` 与明确的下一步入口；极简竖条、横条、圆环保留画布和位置，增加红色警示；菜单栏显示 `0%` 和可点击操作。展开浮层按实际内容高度显示恢复提示。
- 有额外重置时显示「去手动重置」，点击仅打开 Codex「设置 → 用量」，不调用任何兑换接口、不自动消耗次数。当前客户端没有稳定的重置区独立定位锚点，因此提供区域名称指引，不宣称已自动滚动定位到按钮。
- 新增默认开启的「周额度耗尽且有重置次数时提醒」。系统通知可打开用量设置；同一周额度耗尽跨轮询、重启、重置锚点变化去重，恢复后再次耗尽可产生新提醒。通知提交失败可重试；关闭通知不隐藏恢复入口。
- 5 小时额度单独耗尽不引导手动重置；没有可用重置次数（包括已过期或无法确认可用）时保持原有数字、倒计时和布局，不增加耗尽卡片、警示或跳转按钮。原有低额度/即将用尽阈值提醒保留。
- 两个窗口同时耗尽时仅按周额度判断；5 小时仍为零不会阻止周额度恢复后的新一轮提醒。周额度仍为零时新增可用次数，可出现恢复入口和提醒。旧数据/离线、周期刷新待确认、支出受限仍需先确认，不能据此承诺重置有效。
- 剩余不足 1% 的主要数值入口显示 `<1%`，不四舍五入为 `0%`；拒绝把非有限额度值解析为有效快照。
- 极简警示包含 36 种原生像素组合检查及 4 项 Address Sanitizer 检查。移除中心标签后新增留空像素断言，并删除原标签排版测试；重新截取受影响的 6 类情况，24 类情况共 496 张原生截图校验通过。各轮测试范围和未验证项见 [额度耗尽边界验收](docs/qa-quota-recovery.md)。

## 2026-09-03 — 介绍图与发布视觉规范

本次为文档与图片更新，**不改变 `preview-0.2.0` 的代码标签、安装包或原有校验值**。

- 沿用 0.2.0 用户确认的浅色风格，重新制作展开浮层、完整额度、极简形态、菜单栏、显示设置和双额度六张功能图。
- README 与 Release 更新图文入口；生成示意与原始界面资料分开保留，不把示例额度、任务和预测当成真实账号信息。
- 新增可复用的 [GitHub 日常发布视觉规范](docs/visual-style/README.md)、提示词模板、完整图库、生成记录及素材校验清单。

## 0.2.0 — 2026-09-03

发布标签：`preview-0.2.0`。本次新增可下载的 Universal 2 DMG / ZIP，**仅 ad-hoc 签名，未通过 Apple 公证**。完整图文说明见 [0.2.0 更新说明](docs/releases/0.2.0.md)。

### 可调节的极简样式

- 保留默认竖条，新增横条和圆环；「设置 → 极简外观」提供实时预览，支持滑块或直接输入高度 / 长度 / 直径、粗细与整体缩放，三种样式分别记忆尺寸，可单独恢复默认。
- 双额度继续独立展示：竖条左侧为 5 小时、右侧为每周；横条上方为 5 小时、下方为每周；圆环外圈为 5 小时、内圈为每周。未知数据不显示为 0%，保持原有绿黄红缓动和状态提示。
- 调整尺寸保留组件左上角，触及屏幕边缘时仅做必要避让，并保存实际位置；尺寸不会因单双额度切换改变。展开 / 收起及拖动过程中暂存设置，到动作结束后应用，避免中途改变动效首尾帧。
- 设置仍使用原有紧凑滚动窗口；简体中文、繁体中文及英语同步支持。默认竖条继续使用原来的 `36×54pt` 画布。

### 屏幕边缘展开与位置稳定

- 完整额度和极简进度条默认向右下展开；底部空间不足时向上、右侧空间不足时向左展开，不再为详情浮层提前推移收起组件。菜单栏仍在状态项下方向下展开。
- 一次展开、收起过程中锁定方向。位置记忆独立于展开画布，自动避让不再更新收起坐标；拖动展开浮层时，组件位置随同一位移更新。
- 重启、切换形态及窗口跟随按收起组件尺寸恢复位置，不再因预留展开高度而远离屏幕边缘。
- 浮层尺寸超出选定方向的可用空间时限制视口并支持内部滚动，不裁掉底部内容，不挤动组件。
- 保留液态胶囊曲线与动画时长，统一由 SwiftUI 处理圆角裁切，修复起始帧被 AppKit 再次裁切造成的边缘差异；透明背景及白边检查加入回归。
- 补充四角、负坐标屏幕、连续开合、动画反向、动态内容高度、拖动、位置恢复及明暗色首尾帧测试。验证范围见 [屏幕边缘回归记录](docs/qa-screen-edge-expansion.md)。

### 发布附件与说明

- 新增一张功能介绍图，并保留真实原生视图的固定样本截图，明确区分宣传示意与运行界面。
- README、中文更新说明、安装指南、SHA-256 校验文件同步提供；旧版标签及附件不覆盖。
- 新增 `Scripts/package-preview.sh`，支持显式生成未公证的通用预览包；正式签名公证流程保持独立。
- 本地普通测试与 Address Sanitizer 均为 166 项通过，Release 警告即错误检查通过。实体多显示器、VoiceOver 和 Intel 实机测试不包含在这些自动化结论中。

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
