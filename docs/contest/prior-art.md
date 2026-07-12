# MoonParse 的 prior art 与边界

MoonParse 明确承认并尊重已有 MoonBit 解析生态。此表用于说明差异化边界，不评价其他项目优劣；许可证、复用材料和精确版本将在 `THIRD_PARTY.md` 与 provenance manifest 中冻结。

| 项目 | 已有能力 | MoonParse 不重复承诺 | MoonParse 的独立交付 |
| --- | --- | --- | --- |
| [tonyfettes/tree_sitter](https://mooncakes.io/docs/tonyfettes/tree_sitter) | Tree-sitter 的 MoonBit binding、增量 Tree API 与语言 binding | 不把 C runtime binding 包装成“纯 MoonBit parser” | 纯 MoonBit 语义核、离线 `.mpack` ABI、无 callback scanner 的跨端确定性 |
| [moonbitlang/moonyacc](https://github.com/moonbitlang/moonyacc) | MoonBit 的 LR(1) parser generator | 不把“能生成 LR 表”当作差异化本身 | 可分发 Pack、lossless 容错 CST、编辑 trace 的增量等价和 Query 跨端 digest |
| [moonbitlang/parser](https://github.com/moonbitlang/parser) | MoonBit 语言解析实现 | 不声称替代 MoonBit 语言前端 | 多语言 Pack runtime 的公共 ABI 与编辑器级增量能力 |

Tree-sitter 单向 importer 的输出只能是：受支持语义生成 Pack，未支持语义生成稳定、可阅读的 compatibility report。它不得静默降级，也不得成为运行时依赖。
