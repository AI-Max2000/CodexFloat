# Codex Float 问题修复与复测结果

- 复测日期：2026-09-01
- 测试包：`dist/CodexFloat.app`
- 测试环境：macOS 15.7.9、Apple M4、arm64
- 结论：P0 与 5 个 P2 问题已经修复；仓库基线和 Universal 2 发布构建已建立。正式发布仍受 Developer ID / 公证凭据以及部分真实硬件场景补测限制。

## 解决方案与最终效果

| 原问题 | 解决方案 | 最终效果 | 状态 |
|---|---|---|---|
| 5 小时提醒重复、通知键无限增长 | 连续两次快照识别固定重置锚点；滑动窗口不再建立固定时刻提醒；周期键归一化；清理旧版键；增加 90 天 TTL 和 1,000 条上限 | 真实数据库从 3,962 条清理到 70 条；跨两个 30 秒刷新周期保持 70 条，`quota-five-hour-v2` 始终只有 1 条，旧版键为 0 | 已解决 |
| Gatekeeper / 单架构包 | 构建脚本增加 Universal 2、Hardened Runtime 和 Developer ID 参数；新增 DMG、公证、Staple、Gatekeeper 校验脚本 | 当前包已包含 `x86_64 + arm64`，包体完整性通过；因本机没有正式证书和公证凭据，当前临时签名包仍被 Gatekeeper 拒绝 | 代码完成，外部凭据待补 |
| 关键逻辑自动化不足 | 为固定/滑动重置锚点、首次观测、通知键清理上限、动态反馈语言、动态额度读屏标签补回归测试 | 测试从 76 项增加到 81 项；重置提醒规划器达到 100% 行覆盖，SQLiteStore 77.63%，反馈模型 89.35%；全目标行覆盖率为 39.48%，通知系统 API 外壳和应用生命周期仍需继续补集成覆盖 | 核心风险已覆盖，覆盖率门禁待继续 |
| 仓库无提交 | 建立 Git 基线并保留后续修复提交 | 现在可审查、回滚和追踪发布来源 | 已解决 |
| 340pt 下关键文案截断 | 头部改为两行；预计重置时间、对象独立成行；根据可见额度、任务、活动和气泡动态计算高度 | 中文、英文、1 个和 3 个额度窗口实测均完整，无大面积底部留白 | 已解决 |
| 活动反馈切换语言后不更新 | 反馈只保存语义和参数，渲染时使用当前语言与对应时区 | 同一个活动提示可在简中、繁中、英文间即时重新渲染，不需要重新触发 | 已解决 |
| 多个额度窗口读屏标签相同 | 可访问名称改为动态窗口名称 | 实测可分别读出 Codex 主窗口、GPT-5.3 主窗口和 GPT-5.3 次窗口 | 已解决 |
| 字号和点击区域过小 | 头部按钮扩大到 28×28pt；提高任务、状态和活动文字字号；极简交互区从 24pt 扩到 36pt，视觉竖条仍保持轻量 | 操作目标更易点击和拖动，极简视觉没有变成厚重卡片 | 已解决 |
| README 与产品行为不一致 | 同步菜单栏悬停、状态图、健康色、极简尺寸、提醒和发布说明 | 使用说明与当前实现一致 | 已解决 |

## 最终验证

- `swift test`：81/81 通过。
- AddressSanitizer：81/81 通过。
- ThreadSanitizer：81/81 通过。
- Live 集成：当前 Codex App Server、额度、Tibo Feed 真实读取通过。
- Release + `warnings-as-errors`：通过。
- Universal 2：`x86_64 arm64`。
- `codesign --verify --deep --strict`：通过。
- `spctl`：当前 Ad Hoc 包被拒绝；必须使用 Developer ID 签名并完成苹果公证。
- 用户偏好：复测结束后已经恢复测试前的显示形态、语言、前台显示和补充额度设置。

## 真实界面证据

- `artifacts/remediation-qa-2026-09-01/01-standard-expanded-zh-hans.png`：简体中文完整额度与自适应高度。
- `artifacts/remediation-qa-2026-09-01/05-settings-english.png`：紧凑设置窗口与英文设置。
- `artifacts/remediation-qa-2026-09-01/06-feedback-english.png`：英文重置气泡与美国太平洋时间。
- `artifacts/remediation-qa-2026-09-01/09-supplementary-accessibility.png`：三个额度窗口、自适应高度和动态读屏标签。

## 正式发布前仍需完成

1. 配置 Developer ID Application 证书和 `notarytool` Keychain Profile，运行 `Scripts/release-app.sh`。
2. 在干净的 Intel Mac 与 Apple Silicon Mac 上执行 DMG 安装和 Gatekeeper 验证。
3. 补测多显示器拔插、不同缩放比例、刘海屏拥挤菜单栏、休眠跨重置点、断网恢复和真实通知中心。
4. 补充 `NotificationCoordinator` 系统通知适配层、App Server 异常重启和应用生命周期集成测试，再设置覆盖率门禁。
