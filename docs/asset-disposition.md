# MoonParse 资产处置与迁移边界

本文把 `master@d8bffb8` 的既有实现当作可审计资产，而不是冠军版 API 的默认承诺。任何重构必须保留本表中的保留项，任何删除必须可由该表和对应工作包解释。

| 资产 | 处置 | 冠军版去向 |
| --- | --- | --- |
| CST span、错误恢复回归、增量 trace | 保留并重构 | `internal/syntax`、`internal/engine` 与不变量测试 |
| Grammar、表生成、Pack 代码 | 选择性重构 | 声明式 `PackSource`、离线 compiler 与 `.mpack` v1 |
| Query、highlight、locals | 重构 | 统一 Query IR/VM；只承诺结构查询、highlight、outline、folds、locals |
| CLI 参数、reporter、端到端测试 | 保留接口经验，重构实现 | `cmd/moonparse`，只消费 root/compiler 公共契约 |
| WASM 句柄与 JSON 桥接 | 重构 | 唯一薄 ABI；不得持有第二套解析或 Query 语义 |
| Tree-sitter exporter、Compare Workbench | 删除 | 仅保留可信单向 importer 与 compatibility report |
| 全功能 LSP、VSIX、Workspace 特化 | 删除或降为后续 ADR | v1 仅保留薄 LSP 文档级能力 |
| Website Pack IDE、Lint/Binding/Compare 面板 | 删除，仅保留展示壳 | 离线三栏冠军 Demo |
| 已提交的 WASM/Website 二进制与预编译表 | 重新生成 | 只从 release assembly 产生，不作为源码真相 |

最终产品边界、包依赖方向和工作包映射以 [`todo/plan.md`](../todo/plan.md) 为准。本文不替代第三方来源、许可证或 release provenance；这些在 M0-C04 与后续 evidence 工作包中单独维护。
