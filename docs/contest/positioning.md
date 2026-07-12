# MoonParse 冠军版定位

MoonParse 的目标不是成为另一个 Tree-sitter binding，也不是承诺在任意语言或任意基准上取代现有 parser generator。它提供的是一条由 MoonBit 自己承载的语法基础设施路径：声明式语言源离线生成确定性 `.mpack`，运行时在 Native/WASM 使用同一 Pack 完成容错 CST、增量更新与结构 Query。

评审只需要沿一条路径验证作品：打开真实 `.mbt` 文件、删掉右括号、观察 CST/Query 仍可用、补回后查看 full/reparse 等价与复用数据、比对 Native/WASM canonical digest，最后从同一 Pack 复现调用结果。

| Claim | 实现边界 | 机器证据 | Demo 画面 |
| --- | --- | --- | --- |
| 纯 MoonBit 语义核 | compiler、Pack validator、runtime parser、incremental engine、Query evaluator 不依赖 C runtime 或宿主 callback 作语法决策 | V01、V02、V03、V17 | 同一个 MoonBit 库加载 Pack 并产生 Snapshot |
| `.mpack` 分发 ABI | `PackSource` 仅在离线 compiler 阶段存在；运行时只加载并校验逐字节格式 | V03、V09、A01 | 展示 Pack fingerprint 与重建 hash |
| 真实增量等价 | full/reparse/reparse_many 与 Query full/cache/incremental 产生等价 CST、诊断和 capture | V05、V07 | 修改后显示 changed range 与 reused nodes，同时显示等价回执 |
| 跨端可复现 | 同一 Pack、输入和 trace 在 Native/WASM 生成同一 canonical digest | V06、V08、V11 | 两端 digest 并排一致 |

禁止的比较性表述：

- “全面替代 Tree-sitter”；
- “任意语言都更快/更完整”；
- “仅凭局部重算范围或 benchmark 就证明增量正确”；
- “WASM 与 Native 各自实现语义但结果看起来相近”。

Tree-sitter importer、第二门语言、Pack Author SDK 与薄 LSP 是生态采用证据；它们只能证明 Pack ABI 的可迁移性和可用性，不能替代上述四项核心证据。
