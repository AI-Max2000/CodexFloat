# Third-party notices

Codex Float 本身从零实现，未复制下列项目的源码或素材。产品和协议调研参考了：

- [openai/codex](https://github.com/openai/codex)：Apache-2.0，App Server 公开协议与 Schema 的权威来源。
- [thrr87/codex-limits](https://github.com/thrr87/codex-limits)：MIT，JSON-RPC 连接、额度模型与协议测试思路。
- [steipete/CodexBar](https://github.com/steipete/CodexBar)：MIT，进程发现、打包、公证和更新发布思路。
- [ChenglongLi777/codex-migrate](https://github.com/ChenglongLi777/codex-migrate)：MIT，仅作为第二阶段安全迁移方案的研究来源，当前代码未集成。
- [Chloride233/tibo-reset-watch](https://github.com/Chloride233/tibo-reset-watch)：MIT，参考作者校验、确定/可能信号分离和失败退避思路；未复制其 UI 或业务代码。
- [turingism/tibo-reset-oracle](https://github.com/turingism/tibo-reset-oracle) 与 [liyoungc/codex-reset-index](https://github.com/liyoungc/codex-reset-index)：参考概率边界、证据可审计和“张力指数”思路。调研时仓库根目录未提供标准 `LICENSE` 文件，因此本项目未复制其源码、数据集或素材。
- `bob-zebedy/CodexBar`：GPL-3.0，仅做许可边界调研；本仓库未复制其代码或素材。

重置预测功能在运行时读取 `https://codex-reset.com/api/forecast` 与 `https://codex-reset.com/api/timeline` 的公开 JSON。它们是独立非官方数据源，本项目只保存最小化规范字段，并在超过 6 小时后停止展示概率数字。

公开分发前应再次核对上游许可证、NOTICE 要求和第三方网页服务条款。
