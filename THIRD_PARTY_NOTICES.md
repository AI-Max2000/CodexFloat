# Third-party notices

Codex Float 本身从零实现，未复制下列项目的源码或素材。产品和协议调研参考了：

- [openai/codex](https://github.com/openai/codex)：Apache-2.0，App Server 公开协议与 Schema 的权威来源。
- [thrr87/codex-limits](https://github.com/thrr87/codex-limits)：MIT，JSON-RPC 连接、额度模型与协议测试思路。
- [steipete/CodexBar](https://github.com/steipete/CodexBar)：MIT，进程发现、打包、公证和更新发布思路。
- [ChenglongLi777/codex-migrate](https://github.com/ChenglongLi777/codex-migrate)：MIT，仅作为第二阶段安全迁移方案的研究来源，当前代码未集成。
- [Chloride233/tibo-reset-watch](https://github.com/Chloride233/tibo-reset-watch)：MIT，参考作者校验、确定/可能信号分离和失败退避思路；未复制其 UI 或业务代码。
- [turingism/tibo-reset-oracle](https://github.com/turingism/tibo-reset-oracle) 与 [liyoungc/codex-reset-index](https://github.com/liyoungc/codex-reset-index)：参考概率边界、证据可审计和“张力指数”思路。调研时仓库根目录未提供标准 `LICENSE` 文件，因此本项目未复制其源码、数据集或素材。
- `bob-zebedy/CodexBar`：GPL-3.0，仅做许可边界调研；本仓库未复制其代码或素材。

重置预测默认读取 [Codex Reset Monitor](https://codexreset.org/) 的公开服务端渲染主页，只保存最小化规范字段，不执行其脚本、不复制网页素材，也不上传本机额度或用户信息。源数据超过 6 小时后停止展示概率数字。页面为独立非官方服务，历史较优结果不保证未来预测准确。

选源参考 [AghDoo/codex-reset-benchmark](https://github.com/AghDoo/codex-reset-benchmark)（MIT）的公开历史快照、事件口径与共同样本方法。仓库中的复算脚本独立实现，未复制上游代码；[记录与局限](docs/qa-reset-forecast-source.md)保留了数据来源、提交版本和指标定义。

- [WhenReset API](https://whenreset.app/api/)：只读公开 `/api/forecast`，核验 `codex`、`global hard reset (banked excluded)` 目标与真实计算时间，遵守至少 5 分钟间隔。作为实验性备用，不把其自有回测与共同样本直接排序，也不把账本更新时间当预测更新时间。其早期历史部分参考 [codex-resets.com](https://codex-resets.com/)；本项目未复制其历史数据集。
- [Codex Reset 开发者接口](https://codex-reset.com/developers)：公开 `/api/forecast` 与辅助 `/api/timeline` 保留为同口径备用。失效切换始终保留实际来源 URL 和提示，不将其数字标成 Monitor 的预测；辅助里程碑请求失败不阻断有效概率。

三家只保存最小化规范字段和本机健康状态，不复制网页素材、执行远端脚本或上传账号数据。上游历史/实现可能有共用来源，不能将三个域名视为三份独立事实真值；WhenReset 不参与已完成事件基准的交叉核对投票。来源健康检测提升可用性，不构成概率校准或官方背书。

公开分发前应再次核对上游许可证、NOTICE 要求和第三方网页服务条款。
