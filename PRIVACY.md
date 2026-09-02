# 隐私说明

Codex Float 的 MVP 设计为本机优先、无遥测、无广告。

## 会读取什么

- 启动本机已经安装的 `codex app-server`。
- 通过标准输入/输出调用只读方法 `account/rateLimits/read` 与 `thread/list`，接收 `account/rateLimits/updated` 通知。任务列表要求 App Server 只使用其状态数据库，应用只保留标题、线程 ID、状态和更新时间。
- 为准确区分任务状态，只读打开当前版本的 `~/.codex/thread_history_*.sqlite`，且 SQL 仅查询 `thread_turns` 表中的 `thread_id`、`turn_id`、`status`、`started_at` 与 `completed_at`。不会查询同一数据库中的消息表。正常启动不会打开或修改 `~/.codex/hooks.json`；早期版本遗留的 Hook 命令只返回空结果。
- 请求 Twiscan/Twitee 的 Tibo 公开个人页，只抽取帖子 ID、正文、发布时间、来源和原帖链接。
- 请求 `codex-reset.com` 的公开非官方预测与时间线 JSON，只保存 24/48 小时概率、置信度、更新时间、近期节奏与用户里程碑数值。
- 使用 macOS 工作区通知读取当前前台应用的 Bundle Identifier，只在本机判断是否为 ChatGPT/Codex；不读取窗口标题或页面内容，也不保存该标识。
- 在 `~/Library/Application Support/CodexFloat/state.sqlite` 保存规范化额度快照、最多 100 条帖子、24 份重置预测快照、分类结果、最近任务摘要和通知去重键。

Reset Credit 的服务端不透明 ID 不会原样落库；只保存其 SHA-256 截断摘要用于本地去重。

## 不会读取什么

- `~/.codex/auth.json` 或任何凭证文件。
- Codex 聊天正文、消息表、rollout、transcript 或项目内容。应用只读打开任务历史索引时，仅执行上文列出的 `thread_turns` 状态查询。
- 浏览器 Cookie、浏览器会话、Tibo 帖子的网页源码或媒体文件。
- 账号邮箱、姓名、账号 ID 或其他身份标识。

## 网络和通知

帖子与重置预测适配器都使用临时 `URLSession`，关闭 Cookie 和磁盘 URL 缓存。第三方来源仍会像普通网站一样看到请求 IP 和 User-Agent。额度读取由本机 Codex 完成，应用不接触登录令牌。

系统通知可在设置里整体关闭，也可分别关闭额度、Reset 过期、Tibo 活动和任务完成提醒。

## 诊断

导出的诊断只包含应用/系统版本、Codex 可执行文件的脱敏路径、数据新鲜度、记录数量（包括任务数量）、错误摘要和数据库体积。它不包含任务标题、线程 ID、账号标识、凭证、帖子正文或 Codex 内容。
