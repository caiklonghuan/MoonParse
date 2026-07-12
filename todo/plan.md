# MoonParse 冠军版最终可执行计划

> 状态：EXECUTION-READY v4（计划已冻结，尚未执行实现/发布动作）
> 战略基线：origin/master@68065b686857af26966f084114966c59c347a562（赛前题目基线）
> 实际施工起点：master@d8bffb8be6a9a387fdfdbb7812fdfaf66d89b06f（保留 69 个赛期提交）
> 目标模块名：caiklonghuan/MoonParse；首次公开发布前冻结，此后不得再次改名
> 唯一目标：不因时间缩减质量，把 MoonParse 做成可安装、可验证、可复现、可展示、可被第三方采用的纯 MoonBit 编辑器级增量语法引擎。
> 本文件职责：它是施工控制面，不是愿景文档。任何工作未绑定 ID、依赖、产物、验证命令和证据回执，均不得开工。
> 施工规模：78 个原子工作包；A00 core fixture 与 A01 -> A02 -> A04 -> A03 唯一发布 artifact 链；V00–V17 分阶段机器门。可以直接在当前的分支上进行开发，然后接着当前分支的时间点July 4, 2026 at 4:52 PM继续往后，基本每次过一两个小时git一次。

## 0. 最终判断与使用规则

MoonParse 的冠军定位冻结为：

> 一份声明式 Language Pack 经纯 MoonBit 编译器离线生成确定性的 .mpack；同一 .mpack 在 MoonBit、CLI、WASM 和薄 LSP 宿主中提供 lossless CST、容错诊断、真正增量更新和结构化 Query。

主链路冻结为：

~~~text
PackSource
  -> compiler.compile_pack
  -> deterministic .mpack
  -> Language
  -> Parser
  -> immutable Snapshot
  -> Node / Diagnostics / Query / ParseStats
  -> CLI / WASM / thin LSP / champion demo
~~~

### 0.1 工作分类

- CORE：冠军产品不可缺少的实现。
- EVIDENCE：证明正确性、性能、合规、贡献和跨端一致性的实现。
- ENHANCEMENT：强化生态价值，但不得绕过或复制核心。
- GATE：只有机器证据齐全才可通过的质量门。
- HUMAN：必须由项目作者使用账号、凭据或赛事材料完成的外部动作。

### 0.2 状态机

每个工作包只能处于以下状态之一：

~~~text
BACKLOG -> READY -> ACTIVE -> VERIFYING -> PASS
                                  |          |
                                  +-> FAIL   +-> 后继工作包
                                  +-> BLOCKED
~~~

- 只有 PASS 可以解锁硬依赖。
- FAIL 必须保存失败输入、命令和日志，不能通过删除用例恢复绿色。
- BLOCKED 必须写清外部依赖和解除条件。
- 非硬目标可以通过 ADR 调整；赛事硬门、公开契约和已经发布的格式不能豁免。

### 0.3 角色

- DRI-A（Author）：项目作者；负责赛事申报材料、账号凭据、双远端、mooncakes 和发布审批。
- DRI-E（Engineering）：实现负责人；负责代码、测试、基准、文档与回执。
- DRI-R（Reviewer）：独立审阅者或外部 Pack 作者；负责可用性与证据复核。

同一人可以承担 DRI-A 和 DRI-E；外部可用性测试中的 DRI-R 不能由作者自证。

### 0.4 工作包完成定义

一个工作包只有同时满足以下条件才是 PASS：

1. 依赖工作包全部 PASS。
2. 只修改声明的目标路径；额外修改必须拆包或更新本计划。
3. 实现、black-box test、必要的 white-box invariant test 同时合入。
4. 公共 API 变化先更新 spec.mbt，再实现，并审查 moon info 生成的 .mbti。
5. 运行本计划指定的验证命令，退出码为 0。
6. 在 _build/evidence/<full-commit-sha>/ 生成机器回执。
7. CI job 在同一 commit SHA 上通过。
8. 兼容性、第三方来源或用户行为变化同步更新 CHANGELOG、迁移文档或 THIRD_PARTY。

Bootstrap 例外只适用于 M0-G00、M0-H00、M0-H01、M0-G01、M0-G02：

- 它们在正式 CI/evidence runner 创建前，先用可恢复的本地 bootstrap receipt 进入 PASS。
- 第 6、7 条暂缓，不删除；两个 HUMAN 包先保存脱敏 bootstrap receipt。M0-C05 必须在同一可达历史上重新执行 V00、human receipt schema/remote fetch 与 control schema/render-determinism，并生成正式 JSON receipt。
- M0-C05 未完成补验前，M0 总 Gate 不得通过；M0 只验收发布流水线，不向 registry 发布版本。
- 除这五个 bootstrap 包外，没有任何工作包可以用本地/人工日志替代同 SHA CI。

## 1. 冻结的产品边界

### 1.0 冠军主张：不是另一个 Tree-sitter，而是 MoonBit 的可移植语法基础设施

MoonParse 的产品类别、评审口径和所有公开表述固定为：

> **面向 MoonBit 生态的纯 MoonBit、离线 Pack 驱动、跨端可复验的增量语法基础设施。**
> 它的目的不是在所有语言、所有编辑器或所有指标上替代 Tree-sitter；它让 MoonBit 项目可以不引入 C runtime、外部 callback scanner 或宿主私有语义，仍得到可分发、可验证、可增量编辑的语言能力。

这不是营销文案，而是冠军版的取舍契约。以下四个主张必须同时有实现、公开文档和对应机器证据，缺一不可：


| 不可替代点                | 必须可被评委验证的事实                                                                                                                                      | 禁止偷换成的说法                             |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| 纯 MoonBit 语义核         | Pack compiler、Pack validator、runtime parser、incremental engine、Query evaluator 的语义路径均由 MoonBit 实现；宿主只传递字节/调用稳定 API，不参与语法决策 | “有 MoonBit binding”或“宿主调用 MoonBit” |
| `.mpack` 是独立可分发 ABI | 声明式`PackSource` 离线一次编译为逐字节规范的 `.mpack`；运行时只加载/校验 Pack，绝不编译 Grammar                                                            | “导入一份生成的 C/JS grammar”              |
| 真正的编辑器增量语义      | 对同一编辑 trace，full parse、reparse、reparse_many 与 Query full/cache/incremental 的 CST、诊断和 capture 全等；`ParseStats` 只作为可见佐证，不是证明本身  | “重新全量解析但展示一个局部范围”           |
| 可移植且可复现            | 同一 Pack、输入和 trace 在 Native/WASM 得到相同 canonical digest；Pack/release 连续重建字节一致                                                             | “两个宿主各自实现一套看起来类似的解析器”   |

Tree-sitter、moonyacc、现有 MoonBit parser 和 parser combinator 是必须尊重并写明的 prior art，不是攻击对象。最终比较页只回答四个边界问题：运行时是否需要外部 native runtime、语言产物是否为可校验的 `.mpack`、编辑等价性是否有 differential 证明、跨端结果是否有同一 digest；不得宣称“全面更快”“全面更完整”或“取代”任何既有项目。Tree-sitter 单向导入只是一条迁移入口，既不是核心依赖，也不构成产品价值证明。

评委的叙事顺序固定为：**一个真实 MoonBit 文件的破损编辑 → 保持可用的 CST/Query → 可复核的增量等价性 → 同 Pack 的 Native/WASM 一致 → Pack 作者能够复用该能力**。GLR、GSS、SDK、importer 和第二语言只能在这个故事之后出现，作为实现深度或生态证据，不能抢占产品定义。

### 1.1 必须交付

- 纯 MoonBit Pack compiler、parser runtime、incremental engine 和 Query engine。
- 唯一运行时分发物 .mpack v1。
- 根包高层 API：Source、Language、Parser、Snapshot、Node、TreeCursor、TextEdit、Diagnostic、ParseStats、Query、Capture。
- compiler/ 离线 API：PackSource、PackArtifact、CompileOutput、CompileDiagnostic。
- production MoonBit Pack；JSON Pack 作为规范与差分 oracle。
- Native 与 WASM 对同一 Pack、输入和 edit trace 产生相同 canonical digest。
- CLI、WASM、三栏冠军 Demo；薄 LSP 只消费公共契约。
- Pack Author SDK、可信 Tree-sitter 单向导入、第二门真实语言和至少一次外部作者测试，作为“Pack ABI 可采用”的生态证据；它们不得改写或稀释第 1.0 节的核心主张。
- 严格 CI、真实 corpus、连续编辑 differential、Pack fuzz、性能/体积/资源证据、mooncakes 与双远端发布。

### 1.2 明确不进入冠军 v1

- Tree-sitter 双向导出。
- 任意 C/JS/Python callback scanner。
- 全功能 MoonBit 语言服务器、workspace index、跨文件 rename、formatter、completion、hover。
- 浏览器 Pack IDE、VSIX 生成器、Lint Workbench、Binding Graph UI、Tree-sitter Compare 工作台。
- 运行时 Grammar 编译、公开 ParseTable/DFA/LR item/GSS、公开 parse forest。
- C、Python、JSON5 等语言的“production”宣传；它们只能保留为 experimental fixture。
- toy lint 规则和独立 Lint 产品线。
- 多套重复 WASM integer handle/JSON 协议和仓库内长期提交的 release 二进制。

### 1.3 黄金演示

演示只保留一条路径：

~~~text
加载 moonbit.mpack
-> 打开 MoonParse 真实 .mbt 文件
-> 删除一个右括号
-> CST 仍完整，出现 ERROR/MISSING、Diagnostic 和 fix-it
-> highlights/outline 仍可用
-> 补回括号
-> 显示 reparse range、reused bytes/nodes 和延迟
-> Native/WASM digest 相同
~~~

评委在 30 秒内必须看见：

1. 错误代码仍可用。
2. 编辑只重算局部。
3. 同一个 Pack 跨端一致。
4. 所有数字可追溯到 release SHA 的原始证据。

## 2. 冻结代码起点与历史策略

### 2.1 三个不可变锚点


| 锚点                                      | 指向                                     | 用途                             |
| ----------------------------------------- | ---------------------------------------- | -------------------------------- |
| annotated tag contest-baseline-2026-04-26 | 68065b686857af26966f084114966c59c347a562 | 赛前基线与赛期贡献差异           |
| annotated tag archive-pre-mainline-69     | d8bffb8be6a9a387fdfdbb7812fdfaf66d89b06f | 永久保存 69 个赛期提交原貌       |
| branch master                             | d8bffb8 起直接向前                       | 唯一施工主线，承载本计划和所有 forward commits |

硬规则：

- 不从 origin/master 重建并逐个 cherry-pick 69 个提交。
- 直接在当前 `master@d8bffb8` 向前施工；归档或额外 worktree 只能用于恢复/审计，不能成为平行开发主线。
- 不 reset、rebase、squash、force-push 或伪造作者时间。
- 不按整个大提交 revert；按能力和目录迁移，再用新提交删除失焦部分。
- contest baseline、archive annotated tag 和正式 release tag 永久不可移动；不得用同名 branch 冒充 archive。
- 最终候选只能 fast-forward 进入远端默认分支；若平台产生 merge commit，则该 merge SHA 成为新的 candidate，必须重新走 RC，并在 registry publish 前重跑 V00–V14、V15A、V16A、V17（包含 V05A/V05B、V07A/V07B、V08A/V08B）release profile；V15B/V16B/V16C 仍按第 11 节的发布后状态执行。
- GitHub、Gitlink 默认分支和 release tag 最终必须指向同一 SHA。

### 2.1.1 Bootstrap B00：先建立可恢复归档

B00 是工作包状态机之前唯一允许的本地 bootstrap。它不修改历史内容，只解决“当前 dirty worktree 必须先可恢复”问题；施工继续在当前 `master` 上进行：

1. 在当前 worktree 外创建 ../MoonParse-preflight-d8bffb8/。
2. 使用 git diff --binary 保存全部 tracked diff。
3. 完整复制全部 6 项 dirty 资产（.gitignore、两个 README、wasm/build-info.json、docs/system-overview.md、todo/plan.md）；不能只依赖 patch 或 hash。
4. 写 manifest，记录所有 dirty 文件 hash、大小、状态和恢复目标。
5. 验证 dirty worktree 可反向应用 patch、干净 index 可正向检查该 patch，六项完整文件的 source/copy SHA-256 全部匹配。
6. 创建两个 annotated tag。
7. 不切换、不 reset 当前 `master`；直接在它上面执行 M0-G00。README、system-overview、build-info 仍留在原 worktree，直到各自工作包评审。

Bootstrap 归档在 M0-G01 验证所有文件已提交或明确迁移前不得删除。若自动化执行需要写 sibling 目录或 git refs，必须取得 DRI-A 授权。

建议命令由 DRI-A 在当前 Windows 环境执行，执行前先核对路径：

~~~powershell
git rev-parse origin/master
git rev-parse master
if (Test-Path -LiteralPath ..\MoonParse-preflight-d8bffb8) { throw 'preflight directory already exists; inspect it, never overwrite' }
New-Item -ItemType Directory ..\MoonParse-preflight-d8bffb8
git diff --binary --output=..\MoonParse-preflight-d8bffb8\tracked.patch
Copy-Item -LiteralPath .gitignore -Destination ..\MoonParse-preflight-d8bffb8\.gitignore
Copy-Item -LiteralPath README.mbt.md -Destination ..\MoonParse-preflight-d8bffb8\README.mbt.md
Copy-Item -LiteralPath README.md -Destination ..\MoonParse-preflight-d8bffb8\README.md
New-Item -ItemType Directory -Force ..\MoonParse-preflight-d8bffb8\wasm
Copy-Item -LiteralPath wasm\build-info.json -Destination ..\MoonParse-preflight-d8bffb8\wasm\build-info.json
New-Item -ItemType Directory -Force ..\MoonParse-preflight-d8bffb8\docs
Copy-Item -LiteralPath docs\system-overview.md -Destination ..\MoonParse-preflight-d8bffb8\docs\system-overview.md
New-Item -ItemType Directory -Force ..\MoonParse-preflight-d8bffb8\todo
Copy-Item -LiteralPath todo\plan.md -Destination ..\MoonParse-preflight-d8bffb8\todo\plan.md
$assetSpecs = @(
  @{ source = '.gitignore'; copy = '..\MoonParse-preflight-d8bffb8\.gitignore'; status = 'modified' },
  @{ source = 'README.mbt.md'; copy = '..\MoonParse-preflight-d8bffb8\README.mbt.md'; status = 'modified' },
  @{ source = 'README.md'; copy = '..\MoonParse-preflight-d8bffb8\README.md'; status = 'modified' },
  @{ source = 'wasm\build-info.json'; copy = '..\MoonParse-preflight-d8bffb8\wasm\build-info.json'; status = 'modified' },
  @{ source = 'docs\system-overview.md'; copy = '..\MoonParse-preflight-d8bffb8\docs\system-overview.md'; status = 'untracked' },
  @{ source = 'todo\plan.md'; copy = '..\MoonParse-preflight-d8bffb8\todo\plan.md'; status = 'previously-ignored' }
)
$manifest = foreach ($spec in $assetSpecs) {
  $sourceItem = Get-Item -LiteralPath $spec.source
  $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $spec.source).Hash.ToLowerInvariant()
  $copyHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $spec.copy).Hash.ToLowerInvariant()
  if ($sourceHash -ne $copyHash) { throw "preflight copy hash mismatch: $($spec.source)" }
  [ordered]@{
    source = $spec.source
    restore_to = $spec.source
    status = $spec.status
    bytes = $sourceItem.Length
    source_sha256 = $sourceHash
    copy_sha256 = $copyHash
  }
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 ..\MoonParse-preflight-d8bffb8\manifest.json
git apply --reverse --check ..\MoonParse-preflight-d8bffb8\tracked.patch
if ($LASTEXITCODE -ne 0) { throw 'dirty worktree reverse patch check failed' }
git apply --cached --check ..\MoonParse-preflight-d8bffb8\tracked.patch
if ($LASTEXITCODE -ne 0) { throw 'clean index forward patch check failed' }
git tag -a contest-baseline-2026-04-26 68065b686857af26966f084114966c59c347a562 -m "MoonParse OSC 2026 contest baseline"
git tag -a archive-pre-mainline-69 d8bffb8be6a9a387fdfdbb7812fdfaf66d89b06f -m "MoonParse pre-champion 69-commit archive"

$baseline = '68065b686857af26966f084114966c59c347a562'
$archive = 'd8bffb8be6a9a387fdfdbb7812fdfaf66d89b06f'
if ((git cat-file -t refs/tags/contest-baseline-2026-04-26) -ne 'tag') { throw 'baseline must be annotated tag' }
if ((git cat-file -t refs/tags/archive-pre-mainline-69) -ne 'tag') { throw 'archive must be annotated tag' }
if ((git rev-parse 'refs/tags/contest-baseline-2026-04-26^{}') -ne $baseline) { throw 'baseline tag mismatch' }
if ((git rev-parse 'refs/tags/archive-pre-mainline-69^{}') -ne $archive) { throw 'archive tag mismatch' }
git merge-base --is-ancestor $baseline $archive
if ($LASTEXITCODE -ne 0) { throw 'baseline is not archive ancestor' }
git merge-base --is-ancestor $archive master
if ($LASTEXITCODE -ne 0) { throw 'archive is not HEAD ancestor' }
git check-ignore -q todo\plan.md
if ($LASTEXITCODE -ne 1) { throw 'todo/plan.md must be visible to Git' }
~~~

上述断言全部以最终 PowerShell 进程退出 0 才可生成 bootstrap history receipt。创建远端 tag/branch 属于外部写操作，只能由 M0-H01 在作者确认后执行；计划本身不授权自动 push。

### 2.2 当前未提交资产

在切换分支、建 worktree、清理或生成文件前，必须记录下列文件的 SHA-256、大小与 diff；禁止 checkout、clean 或 reset 丢弃：


| 文件                    | 当前状态           | 冻结处理                                                                 |
| ----------------------- | ------------------ | ------------------------------------------------------------------------ |
| .gitignore              | modified           | 与 todo/plan.md 作为 M0-G00 原子资产；完整文件进入外部 preflight archive |
| README.mbt.md           | modified           | 与 README.md、system-overview 作为同一文档资产评审                       |
| README.md               | modified           | 不单独提交悬空链接                                                       |
| docs/system-overview.md | untracked          | 保存为“当前系统快照”；新架构稳定后重写，不直接冒充终局架构             |
| wasm/build-info.json    | modified           | 仅作为生成物差异保存；由确定性 release build 重生成                      |
| todo/plan.md            | previously ignored | 本轮仅通过 .gitignore 例外纳入版本控制                                   |

可恢复内容保存在 worktree 外的 ../MoonParse-preflight-d8bffb8/；只含 hash 的 _build 回执不能替代它。M0-G01 另将不含文件正文的 manifest 复制到 _build/evidence/<sha>/history/dirty-assets.json。普通 git stash -u 不包含被忽略文件，因此在计划文件完成跟踪前不得依赖 stash。

### 2.3 69 个提交的资产处理表


| 资产簇 / 提交                                                                      | 判定                 | 迁移去向                                                                             | 工作包                                 |
| ---------------------------------------------------------------------------------- | -------------------- | ------------------------------------------------------------------------------------ | -------------------------------------- |
| 83d5fc2、a8cbc37、14bc34a：CST span、恢复 trace、回归测试                          | KEEP                 | internal/syntax、internal/engine、invariant tests                                    | M2-C14、M2-C18                         |
| 34e24f5、33f1fc5、cb0da77、cecda2a、e5c3d3d、22eedfa：locals/binding/folding/query | REWORK               | internal/query_ir、internal/query_runtime；v1 只承诺 highlights/outline/folds/locals | M2-C05、M2-C11、M2-C20、M2-C21、M3-C02 |
| bf31819、a0c28d4、fe89386、8c47154、9e844e5、c4f973e、15d7dad                      | FREEZE               | tests/fixtures/languages/experimental；不做产品宣传                                  | M0-C05                                 |
| 186719b、6790da7、8755ee7：bindings/manifest/corpus                                | REWORK               | compiler PackSource、evidence corpus manifest                                        | M1-C02、M3-C01                         |
| beb9243、7e05e5f、b2f6389、d2bdf45、999da47、02a42f9、ae8a3f3                      | REWORK               | cmd/moonparse；保留 reporter、参数与 E2E 测试                                        | M4-C01                                 |
| 0412a1e：typed errors/output                                                       | REWORK               | 根 spec.mbt 与稳定 checked errors                                                    | M1-C02、M2-C12                         |
| 7bbd412、8d0d1e0、e615cc6、8bc70b3、24fa7a9、be2c084                               | REWORK               | wasm 薄 ABI；删除重复导出与 tracked release binary                                   | M4-C02                                 |
| d3dc2e9、532c863、3f90d21                                                          | KEEP MINIMAL         | demo 基础构建、smoke 与必要视图                                                      | M4-C04                                 |
| 19c17f0、ec33f8d                                                                   | KEEP                 | .gitignore 与临时目录卫生规则，继续收紧                                              | M0-C05                                 |
| d871d41、a3497ca、610db5c、79c7988、0c05fc6                                        | SELECTIVE REWORK     | 只保留 position/edit、取消、资源释放和协议 E2E；删除 MoonBit workspace 特化          | M4-E01                                 |
| 8820e65、e4d1f8d、8b2c625                                                          | FREEZE/REPLACE       | 由本计划、ADR、RESULTS 和 release docs 取代                                          | M0-C02                                 |
| dda7320、1472ed2、edd22a2、0374737、ed419ca、70bd833                               | KEEP HISTORY         | .mbti 治理机制保留，不把快照提交当功能                                               | M0-C01、M1-C02、M2-C12                 |
| 4fc28f0、cf71c49：Pack-ready grammar/table features                                | REWORK               | internal/grammar、internal/automata；保留 precedence、reserved、alias 等语义         | M2-C04、M2-C16                         |
| 0c255ad、d96bea5：Language Pack 与 pack test                                       | HIGHEST-VALUE REWORK | compiler/、internal/pack、tools/quality                                              | M2-C03、M2-C06、M3-C01                 |
| 0afea54：Tree-sitter interop                                                       | SPLIT                | importer 重写为可信单向迁移；export 删除                                             | M5-E02                                 |
| b589b2b：Pack CLI/runtime surface                                                  | REWORK               | 文件 IO 留 CLI，编译逻辑下沉 compiler                                                | M4-C01、M5-C01                         |
| b670b5e、d8bffb8：CI/API/ABI/build tooling                                         | KEEP/REWORK          | evidence/control、tools/quality、required CI                                         | M0-C05、M1-C02、M3-C03                 |
| 1ac815f、bdc4d9f：LSP/VSIX/Web 生成 targets                                        | DROP                 | 不进入 Pack compiler 或主 CLI                                                        | M0-C05                                 |
| d1d67de、8ec20d6、ebd384c 及各宿主 lint 集成                                       | FREEZE               | v1 不进入阻塞路径；未来只可作为 Query checks 能力重审                                | post-v1                                |
| 8b18633：incremental trace                                                         | REWORK               | Snapshot.changed_ranges 与 ParseStats；删除平行 trace API                            | M2-C15、M2-C19                         |
| 0654cb1：conflict diagnostics                                                      | KEEP                 | compiler/diagnostics/conflict witness                                                | M2-C16                                 |
| 146330c：大型 Website workbench                                                    | DROP EXCEPT SHELL    | 只迁移三栏 Demo 必需视图；删除 Pack IDE/Lint/Compare/VSIX/Binding Graph              | M4-C04                                 |
| 0a48fbd 等混合 generated-artifact 提交                                             | REGENERATE           | 不整体 revert；由源码与 release job重建                                              | M0-C05、M4-C02                         |

## 3. 冻结目标架构

### 3.1 最终目录与产物落点

~~~text
MoonParse/
├─ moon.mod
├─ moon.pkg
├─ spec.mbt
├─ source.mbt
├─ language.mbt
├─ parser.mbt
├─ snapshot.mbt
├─ node.mbt
├─ query.mbt
├─ errors.mbt
├─ deprecated.mbt
│
├─ compiler/
│  ├─ moon.pkg
│  ├─ spec.mbt
│  ├─ source.mbt
│  ├─ compile.mbt
│  └─ diagnostics.mbt
│
├─ internal/
│  ├─ model/            IDs、table/query/scanner/pack IR
│  ├─ regex/            regex AST、NFA、DFA
│  ├─ grammar/          DSL parser、validator、normalize
│  ├─ automata/         canonical LR(1)、conflicts、table compression
│  ├─ query_ir/         Query parser、validation、bytecode
│  ├─ pack/             .mpack v1 encode/decode/validate/checksum
│  ├─ syntax/           green tree、source index、EditMap、red cursor
│  ├─ engine/           lexer、LR fast path、GSS、recovery、ReuseCursor
│  └─ query_runtime/    VM、incremental cache、locals
│
├─ languages/
│  ├─ json/
│  ├─ moonbit/
│  └─ showcase/         第二门真实语言；通过 G5 前不得标 production
│
├─ cmd/moonparse/
├─ wasm/
├─ adapters/lsp/
├─ demo/
├─ examples/editor_loop/
├─ tools/quality/
├─ tools/migrate/treesitter/
├─ tests/
│  ├─ consumer/
│  ├─ conformance/
│  ├─ differential/
│  ├─ malformed_pack/
│  └─ fixtures/
├─ evidence/
│  ├─ control/
│  └─ manifests/
├─ bench/
└─ docs/
   ├─ adr/
   ├─ spec/
   ├─ contest/
   └─ execution/
~~~

### 3.2 单向依赖 DAG

箭头表示“被依赖 -> 消费者”：

~~~text
internal/model -> internal/regex
internal/model + internal/regex -> internal/grammar
internal/model -> internal/query_ir
internal/model -> internal/syntax

internal/grammar + internal/regex + internal/model
  -> internal/automata

internal/model
  -> internal/pack

internal/model + internal/syntax
  -> internal/engine

internal/model + internal/query_ir + internal/syntax
  -> internal/query_runtime

internal/pack + internal/engine + internal/query_ir
  + internal/query_runtime + internal/syntax
  -> root package

internal/grammar + internal/regex + internal/automata
  + internal/query_ir + internal/pack + internal/model
  -> compiler

root -> languages/*
root + compiler + languages/* -> cmd/moonparse
root -> wasm
root + wasm -> adapters/lsp / demo
root + compiler + languages/* -> tools / tests / bench / examples
~~~

硬约束：

- internal/* 永远不得 import 根包、compiler、具体语言、CLI、WASM、LSP 或 Demo。
- internal/model 拥有运行期可序列化的 lexer/parser/recovery/query/scanner table 类型；internal/pack 和 internal/engine 不得 import internal/automata。
- 根包不得 import compiler 或具体语言包。
- compiler 是纯离线库，不读写文件、不读取环境变量、不读取时钟、不使用随机数。
- 具体语言包只通过 embedded .mpack 构造 Language，不访问私有表。
- WASM 只包含 runtime，不在浏览器编译 Grammar。
- CLI、WASM、LSP 和 Demo 不得重新实现 parser、diagnostic、Query 或 digest 语义。
- 任何公共签名不得出现 internal/* 类型。
- 每次 moon.pkg 依赖变化必须通过 boundary checker。

### 3.3 公共类型所有权

根包独占运行时公共类型：

~~~text
Source, ByteRange, Point, Span, TextEdit
Language, KindId, FieldId
Parser, ParseLimits, Snapshot
Node, TreeCursor, ChangedRange
Diagnostic, DiagnosticSeverity, RecoveryAction
ParseStats, Query, QueryRole, Capture
SourceError, PackError, ParseFailure, QueryError
~~~

compiler/ 独占离线公共类型：

~~~text
PackManifest, PackSource, PackArtifact
CompileOutput, CompileDiagnostic, CompileSeverity, CompileSpan
~~~

只有简单值类型允许 pub(all)。Language、Parser、Snapshot、Node、Query、PackSource 和 PackArtifact 字段必须私有或 opaque。

## 4. 冻结公共契约

### 4.1 坐标、源码与生命周期

- 内核源码统一为合法 UTF-8，Source 不可变并拥有 Bytes；`from_utf8`/`replace_utf8` 防御性复制输入，`to_bytes` 返回副本，调用方不能绕过不变量修改底层字节。
- 所有带 byte 的坐标均为 UTF-8 字节偏移。
- Range 使用半开区间 [start_byte, end_byte)。
- row 和 byte_column 从 0 开始；byte_column 是 UTF-8 字节列，不是 UTF-16 或显示列。
- CRLF 视作一个换行；单独 CR 或 LF 也各自换行。为保持 byte/Point 双射，CRLF 中间（LF 字节起点）映射到上一行 `byte_column + 1`，LF 之后才是下一行 `(row + 1, 0)`；该中间点是合法编辑边界。
- LSP UTF-16 转换只存在于 adapters/lsp。
- Language::load 在返回前完成 Pack 校验并取得不可变所有权；不得保留调用方仍可修改的 Bytes view，加载后外部 mutation 不能改变 tables/fingerprint。
- 单次 TextEdit 的旧范围属于传入 reparse 的旧 Snapshot；replacement 自带新文本。
- `reparse_many` 中 edits 按数组顺序应用：第 i 个 edit 的坐标属于应用 0..i-1 后的 Source。全部 edit 先验证，再只执行一次增量 parse；不存在“全部相对初始文档”的第二套语义。
- `reparse` 必须与单元素 `reparse_many` 逐项等价；任一 edit 失败时不产生部分 Snapshot，错误携带 edit index。
- Snapshot 不可变并强引用 Source、Language、green root 与本次已解析的资源 ceiling；后续 captures 使用该 Snapshot 的 max_query_matches，不读取可变全局配置。
- Node 强引用所属 Snapshot；Node 存活期间 text/span 永远有效。
- Parser 可以复用 scratch buffer，但同一 Parser 实例不可并发调用。
- reparse 不修改旧 Snapshot；旧 Node 的 span/text 永不变化。
- Green identity 不进入公共 API、序列化或 canonical digest。

### 4.2 根包 spec.mbt 契约

下列声明是 M1-C02 必须写入根包 spec.mbt 并通过 moon check 的最低表面；这是可复制的 MoonBit 源码，每个函数参数都必须保留名字，不能退化成 `.mbti` 的无名参数简写。实现可以增加经过审查的便利方法，但不能改变语义：

~~~moonbit
pub(all) struct ByteRange {
  start_byte : Int
  end_byte : Int
}

pub(all) struct Point {
  row : Int
  byte_column : Int
}

pub(all) struct Span {
  range : ByteRange
  start_point : Point
  end_point : Point
}

pub(all) enum QueryRole {
  Highlights
  Locals
  Folds
  Outline
}

pub(all) enum DiagnosticSeverity {
  Error
  Warning
  Information
}

pub(all) enum RecoveryAction {
  Insert(String)
  Delete(String)
  PopToSync(String)
}

pub(all) suberror SourceError {
  InvalidUtf8(Int)
  InvalidByteRange(Int, Int, Int)
  SplitUtf8CodePoint(Int)
  InvalidPoint(Int, Int)
}

pub(all) suberror PackError {
  BadMagic
  UnsupportedFormat(Int, Int)
  UnsupportedRuntimeAbi(Int, Int)
  Truncated(String)
  InvalidOffset(String)
  DuplicateSection(String)
  MissingSection(String)
  ChecksumMismatch
  LimitExceeded(String, Int, Int)
  InvalidModel(String)
}

pub(all) suberror ParseFailure {
  LanguageMismatch
  InvalidEdit(Int, Int, Int, Int)
  SplitUtf8CodePoint(Int, Int)
  InvalidLimit(String, Int, Int)
  BudgetExceeded(String, Int)
}

pub(all) suberror QueryError {
  ParseError(Int, String)
  UnknownNode(String)
  UnknownField(String)
  UnsupportedFeature(String)
  LanguageMismatch
  InvalidRange
  MatchLimitExceeded(Int)
}

declare pub type Source
declare pub type Language
declare pub type KindId
declare pub type FieldId
declare pub type Parser
declare pub type ParseLimits
declare pub type Snapshot
declare pub type Node
declare pub type TreeCursor
declare pub type TextEdit
declare pub type ChangedRange
declare pub type Diagnostic
declare pub type ParseStats
declare pub type Query
declare pub type Capture

declare pub fn Source::from_string(text : String) -> Source
declare pub fn Source::from_utf8(bytes : Bytes) -> Source raise SourceError
declare pub fn Source::byte_length(self : Self) -> Int
declare pub fn Source::to_bytes(self : Self) -> Bytes
declare pub fn Source::slice(
  self : Self,
  range : ByteRange,
) -> String raise SourceError

declare pub fn TextEdit::replace(
  start_byte~ : Int,
  old_end_byte~ : Int,
  text~ : String,
) -> TextEdit

declare pub fn TextEdit::replace_utf8(
  start_byte~ : Int,
  old_end_byte~ : Int,
  bytes~ : Bytes,
) -> TextEdit raise SourceError

declare pub fn Language::load(bytes : Bytes) -> Language raise PackError
declare pub fn Language::name(self : Self) -> String
declare pub fn Language::version(self : Self) -> String
declare pub fn Language::fingerprint(self : Self) -> String
declare pub fn Language::kind_name(
  self : Self,
  kind : KindId,
) -> String?
declare pub fn Language::kind_id(
  self : Self,
  name : String,
) -> KindId?
declare pub fn Language::field_name(
  self : Self,
  field : FieldId,
) -> String?
declare pub fn Language::field_id(
  self : Self,
  name : String,
) -> FieldId?
declare pub fn Language::query(
  self : Self,
  role : QueryRole,
) -> Query?

declare pub fn ParseLimits::editor_default() -> ParseLimits
declare pub fn ParseLimits::with_max_active_versions(
  self : Self,
  limit : Int,
) -> ParseLimits raise ParseFailure
declare pub fn ParseLimits::with_max_parser_steps(
  self : Self,
  limit : Int,
) -> ParseLimits raise ParseFailure
declare pub fn ParseLimits::with_max_tree_nodes(
  self : Self,
  limit : Int,
) -> ParseLimits raise ParseFailure
declare pub fn ParseLimits::with_max_query_matches(
  self : Self,
  limit : Int,
) -> ParseLimits raise ParseFailure
declare pub fn Parser::new(language : Language) -> Parser
declare pub fn Parser::new_with_limits(
  language : Language,
  limits : ParseLimits,
) -> Parser
declare pub fn Parser::parse(
  self : Self,
  source : Source,
) -> Snapshot raise ParseFailure
declare pub fn Parser::reparse(
  self : Self,
  previous : Snapshot,
  edit : TextEdit,
) -> Snapshot raise ParseFailure
declare pub fn Parser::reparse_many(
  self : Self,
  previous : Snapshot,
  edits : ReadOnlyArray[TextEdit],
) -> Snapshot raise ParseFailure

declare pub fn Snapshot::source(self : Self) -> Source
declare pub fn Snapshot::language(self : Self) -> Language
declare pub fn Snapshot::root(self : Self) -> Node
declare pub fn Snapshot::diagnostics(
  self : Self,
) -> ReadOnlyArray[Diagnostic]
declare pub fn Snapshot::changed_ranges(
  self : Self,
) -> ReadOnlyArray[ChangedRange]
declare pub fn Snapshot::stats(self : Self) -> ParseStats
declare pub fn Snapshot::point_at(
  self : Self,
  byte_offset : Int,
) -> Point raise SourceError
declare pub fn Snapshot::byte_at(
  self : Self,
  point : Point,
) -> Int raise SourceError
declare pub fn Snapshot::captures(
  self : Self,
  query : Query,
  within? : ByteRange,
) -> Array[Capture] raise QueryError

declare pub fn Node::kind_id(self : Self) -> KindId
declare pub fn Node::kind(self : Self) -> String
declare pub fn Node::span(self : Self) -> Span
declare pub fn Node::is_named(self : Self) -> Bool
declare pub fn Node::is_extra(self : Self) -> Bool
declare pub fn Node::is_error(self : Self) -> Bool
declare pub fn Node::is_missing(self : Self) -> Bool
declare pub fn Node::child_count(self : Self) -> Int
declare pub fn Node::named_child_count(self : Self) -> Int
declare pub fn Node::child(
  self : Self,
  index : Int,
) -> Node?
declare pub fn Node::child_by_field(
  self : Self,
  field : String,
) -> Node?
declare pub fn Node::child_by_field_id(
  self : Self,
  field : FieldId,
) -> Node?
declare pub fn Node::text(self : Self) -> String
declare pub fn Node::walk(self : Self) -> TreeCursor

declare pub fn TreeCursor::node(self : Self) -> Node
declare pub fn TreeCursor::goto_first_child(self : Self) -> Bool
declare pub fn TreeCursor::goto_next_sibling(self : Self) -> Bool
declare pub fn TreeCursor::goto_parent(self : Self) -> Bool

declare pub fn Query::compile(
  language : Language,
  source : String,
) -> Query raise QueryError
declare pub fn Capture::name(self : Self) -> String
declare pub fn Capture::node(self : Self) -> Node
declare pub fn Capture::pattern_index(self : Self) -> Int

declare pub fn Diagnostic::code(self : Self) -> String
declare pub fn Diagnostic::message(self : Self) -> String
declare pub fn Diagnostic::severity(self : Self) -> DiagnosticSeverity
declare pub fn Diagnostic::span(self : Self) -> Span
declare pub fn Diagnostic::expected(
  self : Self,
) -> ReadOnlyArray[String]
declare pub fn Diagnostic::recovery(self : Self) -> RecoveryAction?
declare pub fn Diagnostic::fix(self : Self) -> TextEdit?

declare pub fn ChangedRange::old_span(self : Self) -> Span
declare pub fn ChangedRange::new_span(self : Self) -> Span

declare pub fn ParseStats::source_bytes(self : Self) -> Int
declare pub fn ParseStats::reparsed_bytes(self : Self) -> Int
declare pub fn ParseStats::reused_bytes(self : Self) -> Int
declare pub fn ParseStats::reused_nodes(self : Self) -> Int
declare pub fn ParseStats::peak_branches(self : Self) -> Int
declare pub fn ParseStats::recovery_actions(self : Self) -> Int
~~~

Query 与 Snapshot 的 Language fingerprint 不同必须返回 QueryError::LanguageMismatch。语法错误、ERROR/MISSING 和恢复行为永远不使用 ParseFailure。

`parse` 的 `changed_ranges` 为空，`reparsed_bytes=source_bytes`、`reused_bytes=0`。`reparse_many` 的 changed ranges 始终比较最初 previous 与最终 Snapshot；空 edits 产生共享原 green root 的新 Snapshot，changed ranges 为空，`reparsed_bytes=0`。输入 edits 不得在调用期间被修改。

`Language::query(role)` 只返回 Pack 内该角色的预编译 Query；`Query::compile` 是无 I/O、确定性的同语言临时编译。`captures(within)` 可以检查覆盖 range 的祖先上下文，但只返回 Span 与半开 range 相交的 capture；不隐式去重，并统一按第 6.7 节 `CaptureOrderKey` 稳定排序。`within=None` 表示不过滤并包含 EOF 零宽节点；显式 empty range 返回空。对非空 range，普通 Span 使用标准半开相交，零宽 Span 仅在 `range.start <= pos < range.end` 时纳入。越界、逆序或切开 UTF-8 的 range 返回 QueryError::InvalidRange。

KindId 与 FieldId 内部同时携带 Language fingerprint 与 ordinal；`kind_id`/`field_id` 是名称到同语言 ID 的唯一入口。来自其他 Language 的 ID 用于 `kind_name`、`field_name` 或 `child_by_field_id` 时返回 None，不允许仅按整数误解释；字符串版 `child_by_field` 等价于先 `field_id` 再调用 ID 版。

所有 ParseLimits builder 在 `limit <= 0` 或超过第 6.6 节绝对上限时返回 `InvalidLimit(kind, value, maximum)`，不 clamp、不 wrap；ParseLimits 字段 opaque，因此 `new_with_limits` 接收到的一定是已验证值。

### 4.3 根包错误语义

~~~text
SourceError
  InvalidUtf8(byte_offset)
  InvalidByteRange(start, end, length)
  SplitUtf8CodePoint(byte_offset)
  InvalidPoint(row, byte_column)

PackError
  BadMagic
  UnsupportedFormat(major, minor)
  UnsupportedRuntimeAbi(required, actual)
  Truncated(section)
  InvalidOffset(section)
  DuplicateSection(section)
  MissingSection(section)
  ChecksumMismatch
  LimitExceeded(kind, value, limit)
  InvalidModel(code)

ParseFailure
  LanguageMismatch
  InvalidEdit(edit_index, start, end, source_length)
  SplitUtf8CodePoint(edit_index, byte_offset)
  InvalidLimit(kind, value, absolute_maximum)
  BudgetExceeded(kind, limit)

QueryError
  ParseError(byte_offset, code)
  UnknownNode(name)
  UnknownField(name)
  UnsupportedFeature(name)
  LanguageMismatch
  InvalidRange
  MatchLimitExceeded(limit)
~~~

Diagnostic message 可以改进，但 code、severity、range、recovery action 和 expected symbols 是稳定机器契约。

### 4.4 compiler/spec.mbt 契约

~~~moonbit
pub(all) enum CompileSeverity {
  Information
  Warning
  Error
}

pub(all) struct CompileSpan {
  source_name : String
  start_byte : Int
  end_byte : Int
}

declare pub type PackManifest
declare pub type PackSource
declare pub type PackArtifact
declare pub type CompileOutput
declare pub type CompileDiagnostic

declare pub fn PackManifest::new(
  name~ : String,
  version~ : String,
  license~ : String,
) -> PackManifest

declare pub fn PackManifest::with_source(
  self : Self,
  repository~ : String,
  commit~ : String,
) -> Self

declare pub fn PackSource::new(
  manifest : PackManifest,
  grammar_name~ : String,
  grammar~ : String,
) -> PackSource

declare pub fn PackSource::with_highlights(
  self : Self,
  source_name~ : String,
  query~ : String,
) -> Self
declare pub fn PackSource::with_locals(
  self : Self,
  source_name~ : String,
  query~ : String,
) -> Self
declare pub fn PackSource::with_folds(
  self : Self,
  source_name~ : String,
  query~ : String,
) -> Self
declare pub fn PackSource::with_outline(
  self : Self,
  source_name~ : String,
  query~ : String,
) -> Self
declare pub fn PackSource::with_scanner(
  self : Self,
  source_name~ : String,
  scanner~ : String,
) -> Self

declare pub fn compile_pack(source : PackSource) -> CompileOutput
declare pub fn CompileOutput::artifact(self : Self) -> PackArtifact?
declare pub fn CompileOutput::diagnostics(
  self : Self,
) -> ReadOnlyArray[CompileDiagnostic]
declare pub fn CompileOutput::has_errors(self : Self) -> Bool
declare pub fn PackArtifact::bytes(self : Self) -> Bytes
declare pub fn PackArtifact::fingerprint(self : Self) -> String
declare pub fn CompileDiagnostic::code(self : Self) -> String
declare pub fn CompileDiagnostic::message(self : Self) -> String
declare pub fn CompileDiagnostic::severity(
  self : Self,
) -> CompileSeverity
declare pub fn CompileDiagnostic::span(self : Self) -> CompileSpan?
declare pub fn CompileDiagnostic::notes(
  self : Self,
) -> ReadOnlyArray[String]
~~~

冻结语义：

- compile_pack 是纯函数。
- PackManifest/PackSource/PackArtifact 是不可变值；所有 `with_*` 返回新值，`PackArtifact::bytes` 返回副本，调用方 mutation 不得改变 artifact/fingerprint。
- 相同 PackSource 必须产生字节级相同结果。
- Error 级诊断存在时 artifact 必须为 None。
- grammar_name/source_name 是纯逻辑 UTF-8 相对路径，也是 CompileSpan.source_name 的唯一来源；API 不从文件系统推断名字。
- 诊断按逻辑 source path 的 UTF-8 bytes、start byte、code 稳定排序。
- Grammar、Query、manifest 错误全部进入 CompileDiagnostic，不返回裸字符串。
- PackSource 逻辑路径统一为正斜线；compile_pack 用 CompileDiagnostic 拒绝空路径、绝对路径、`.`/`..` segment、反斜线、NUL、重复路径和 Unicode simple-case-fold 冲突。
- 每个 QueryRole 与 scanner 最多一个逻辑文件；重复调用仍构造 PackSource，但 compile_pack 必须给出稳定 duplicate-role/path 诊断而不是 last-write-wins。
- compiler 不拥有运行时 Node、Snapshot 或 Parser。

### 4.5 `declare` 的阶段性 warning 生命周期

M1 先冻结声明、M2 再实现，因此 M1-C02/C03 到 M2-C12 之间会出现 warning 68 `declaration_unimplemented`。处理方式固定为“精确、临时、可机器撤销”，不能关闭全部 warning：

1. M1-C01 创建 `evidence/control/warning-exceptions.contract.json`，唯一允许项为 code 68，路径只能是 `spec.mbt` 与 `compiler/spec.mbt`，到期工作包固定为 M2-C12；这样 M1-C02/C03 可以在同一已冻结 exception 上并行。
2. contract 阶段的 V01/V02 仍使用 `--deny-warn`，同时只增加已由当前工具链实测有效的 `--warn-list "-68"`。
3. `declaration-scope` 扫描整个仓库；任何 allowlist 外的 `declare`、任何其他 warning code、过期 exception 或清单扩张都使 Gate 失败。
4. M2-C06 实现 compiler 声明；M2-C12 实现根声明并删除 exception 文件。删除后立即以无 `--warn-list` 的严格 V01/V02 补验。
5. PR/nightly 在 exception 未过期时可使用同一精确豁免；RC/release profile 永远拒绝 exception 文件。M2-C12 后所有 profile 都无豁免，最终仓库不保留 warning 68 exception。

contract 阶段精确命令：

~~~text
moon check --target all --deny-warn --warn-list "-68" --frozen
moon build --target all --deny-warn --warn-list "-68" --frozen
moon test --target all --deny-warn --warn-list "-68" --frozen
moon check spec.mbt compiler/spec.mbt --deny-warn --warn-list "-68" --frozen
moon check --target all --deny-warn --warn-list "-68" --frozen tests/consumer
moon run tools/quality -- declaration-scope --config evidence/control/warning-exceptions.contract.json
~~~

### 4.6 具体 Language package 契约

`caiklonghuan/MoonParse/languages/moonbit` 与 `.../languages/json` 只嵌入 A01/fixture 生成的 canonical `.mpack` bytes并依赖根 runtime，不暴露 Grammar/Table/DFA。两者公共表面固定为等价的：

~~~text
pub fn language() -> @moonparse.Language raise @moonparse.PackError
pub fn pack_fingerprint() -> String
~~~

`language()` 每次都走同一 Pack validator，可以缓存成功的 immutable Language，但不得把验证失败变成 panic；`pack_fingerprint()` 必须等于 Language.fingerprint 与分发 Pack SHA-256。README consumer 默认使用 production MoonBit package，JSON 只作规范/oracle 示例。

## 5. .mpack v1 可编码规范

完整逐字节规范最终写入 docs/spec/MPACK_V1.md；以下决定已经冻结，文档不得另起一套格式。

### 5.1 Header 与 TOC

所有多字节整数为 little-endian。v1 文件最大 64 MiB，使用 u32 offset/length。

~~~text
Header，固定 32 bytes

offset  size  field
0       8     magic = 4D 50 41 43 4B 0D 0A 1A
8       2     format_major = 1
10      2     format_minor = 0
12      2     runtime_abi = 1
14      2     flags
16      4     file_length
20      2     section_count
22      2     reserved = 0
24      4     toc_offset
28      4     payload_crc32

TOC entry，固定 12 bytes

0       2     section_kind
2       2     section_flags
4       4     offset
8       4     length
~~~

- CRC 使用 CRC-32/ISO-HDLC，覆盖 bytes[32:file_length]，包括 TOC、零填充和全部 section。
- TOC 默认紧随 Header；section payload 以 8-byte 对齐，padding 必须全 0。
- TOC entry 按 section_kind 递增；相同 kind 禁止重复。
- offset + length 使用 checked arithmetic；section 不得重叠、越界或落入 Header/TOC。
- 未知 REQUIRED section 拒绝；未知 optional section 跳过。
- section_count <= 64。
- Language fingerprint 是完整 canonical pack bytes 的 SHA-256 小写十六进制；fingerprint 不写入自身。

### 5.2 Section

必需 section：


| kind | 名称          | 内容                                                         |
| ---: | ------------- | ------------------------------------------------------------ |
|    1 | Manifest      | canonical UTF-8 JSON；名称、版本、许可证、来源、capabilities |
|    2 | Strings       | 去重 UTF-8 字符串表                                          |
|    3 | SymbolsFields | symbol、field、node schema、稳定 ID                          |
|    4 | Lexer         | DFA、valid-token metadata、lexer sub-ABI                     |
|    5 | Parser        | canonical LR(1) action/goto、productions、压缩行             |
|    6 | Recovery      | sync metadata、默认/Pack recovery policy                     |
|    7 | QueryIndex    | role/name、bytecode offset、query sub-ABI                    |

可选 section：


| kind | 名称            | 内容                                                |
| ---: | --------------- | --------------------------------------------------- |
|    8 | QueryBytecode   | 预编译 Query 程序                                   |
|    9 | ScannerBytecode | 可序列化 scanner VM 程序                            |
|   10 | DebugMap        | 仅 source range 与 conflict witness；不得含绝对路径 |

v1 section_flags 只允许 REQUIRED 和 NONE；不支持通用 section 压缩。Parse table 自身使用 row displacement、default action 和相同行去重压缩。分发层可以生成固定参数 Brotli 文件，但 Brotli bytes 不是 .mpack canonical bytes。

跨 section 约束：

- QueryIndex 必需但允许 item_count=0。
- QueryIndex item_count > 0 时 QueryBytecode 必须存在，所有 program offset/length 必须落在 QueryBytecode 内且互不重叠。
- QueryBytecode 缺失时 QueryIndex item_count 必须为 0。
- Lexer/Manifest 声明任何 nested、delimited 或 scanner capability 时 ScannerBytecode 必须存在。
- ScannerBytecode 缺失时 scanner program/state count 必须为 0，Manifest scanner capability 必须为 false。
- Manifest 使用 RFC 8785 JSON Canonicalization Scheme；只接受 UTF-8、拒绝重复 key，编码器不得依赖 Map 顺序。
- v1 header 的 runtime_abi 是精确匹配值；runtime_abi != 1 直接拒绝，不把它解释为 minimum version。

运行时 Pack 禁止包含：

- Grammar DSL/JSON 源文。
- Query 源文。
- corpus 与 snapshot。
- 重复 JSON/binary ParseTable。
- C/JS/MoonBit 宿主源码。
- 构建时间、绝对路径、随机 ID。

### 5.3 确定性与兼容

- symbol、field、production、state、query ID 来自 canonical source order，不依赖 Map 遍历。
- 所有 Map 在序列化前按 UTF-8 key bytes 排序。
- query bytecode 和 scanner bytecode 各自携带 sub-ABI。
- format major 不匹配直接拒绝；minor 只允许忽略已标 optional 的新 section。
- runtime_abi 必须精确匹配，不静默迁移。
- 格式升级必须增加 golden fixture、corrupt fixture 和迁移说明。
- 同一 PackSource 连续构建 3 次必须 byte-for-byte 相同。
- 最小 JSON Pack、完整 MoonBit Pack、截断、offset overflow、overlap、duplicate、bad CRC、unknown required 和 resource bomb 都必须有 fixture。

### 5.4 固定资源上限

~~~text
pack_bytes_max             = 67_108_864
section_count_max          = 64
string_count_max           = 1_000_000
symbol_count_max           = 262_144
parser_state_count_max     = 1_000_000
production_count_max       = 1_000_000
query_program_count_max    = 1_024
query_bytecode_bytes_max   = 16_777_216
scanner_state_count_max    = 65_536
~~~

所有 count * element_size 在分配前做溢出与上限检查；畸形 Pack 不得产生与文件大小不成比例的分配。

## 6. 核心算法冻结与 Go/No-Go

算法内部可以通过独立 ADR 优化，但不得改变本节不变量、公开语义或 canonical digest。

### 6.1 Lossless immutable green tree

Green node 不保存绝对位置、Source、parent 或 Snapshot：

~~~text
kind_id
production_id
children
field_ids
byte_width
entry_state
exit_state
lookahead_width
scanner_state_before
scanner_state_after
flags(named, extra, error, missing, fragile_left, fragile_right)
~~~

冻结规则：

- CST lossless：token、空白、换行、注释和错误文本均进入树。
- 内部节点 byte_width 等于 children 宽度之和；root byte_width 等于 Source 字节长度。
- Green 不保存 Point extent；Node span 的 Point 一律由 Snapshot 的 SourceIndex 按绝对 byte 查询，避免 CRLF 跨 child 时出现不可结合的行列计算。
- MISSING 节点宽度为 0；ERROR 节点覆盖真实跳过字节。
- v1 不做全局 hash-cons，也不使用会锚住整代旧节点的单体 snapshot arena。
- 新 Snapshot 直接共享旧 Snapshot 的 immutable green references。
- red Node 保存 Snapshot 强引用、green reference、起始 byte/point 和路径上下文。
- span 由 red view/cursor 惰性计算；编辑后禁止递归 shift green subtree。
- ERROR、MISSING、fragile 节点不成为复用候选。

Go 条件：

1. full parse、error parse、手工树均通过 lossless、width、range、field 连续性不变量。
2. reparse 后旧 Snapshot 的全部 Node span/text 不变。
3. 开头插入和中间删除后，右侧无关内部 subtree 通过内部 reference identity 证明真实共享。
4. 仅保留最新 Snapshot 的 10,000 次编辑测试中，retained green nodes 不随历史版本线性增长。

未通过以上条件前禁止实现 WASM Node API。

### 6.2 SourceIndex、TextEdit 与 EditMap

- SourceIndex 只由 UTF-8 bytes 构建，保存行起点并支持 byte <-> Point。
- 所有公开 byte offset 必须位于 UTF-8 code-point boundary。
- 对每个合法 byte boundary 必须满足 `byte_at(point_at(byte)) == byte`；对每个合法 Point 必须满足 `point_at(byte_at(point)) == point`。CRLF 中：CR 起点是上一行正常列，LF 起点是上一行再加 1 byte column，LF 后是下一行 0；在 CR/LF 中间编辑会把原 CRLF 拆开并按新 bytes 重新索引。
- TextEdit 模型固定为：old = prefix + removed + suffix；new = prefix + replacement + suffix。
- 单 edit 的 EditMap 只有 before、changed、after 三段；batch 将按顺序生成的 EditMap 组合并规范化为有序、非重叠 segment，所有旧/新坐标映射使用 checked arithmetic。
- 非法 range、越界、切开 UTF-8 code point 在进入 parser 前失败。
- CR、LF、CRLF 三个位置（前/中/后）、在 CRLF 中间插删、emoji、组合字符、中文、文件首尾、空文件、空 batch 和前序 edit 改变后序坐标必须有 black-box tests。

### 6.3 ReuseCursor 与 changed ranges

ReuseCursor 必须按旧树源码顺序单调前进，不能在每个 token 位置从 root DFS。

一个 candidate 只有同时满足以下条件才可复用：

~~~text
candidate.entry_state == current_lr_state
candidate.scanner_state_before canonical bytes == current_scanner_state canonical bytes
candidate 不含 ERROR/MISSING/fragile
candidate 原范围不与任一 normalized edit segment 相交
candidate [start, end + lookahead_width) 不与任一 normalized edit segment 相交
candidate 对应的新 Source bytes 未变化
~~~

复用后直接应用 candidate.exit_state 和 scanner_state_after，并跳过整个 subtree。insert/delete 的 byte delta 非 0 时仍必须允许复用右侧 subtree。

changed_ranges 通过新旧 green identity 和 EditMap 递归比较，输出必须：

- 按新坐标升序。
- 非重叠。
- 合并相邻且语义上不可再区分的范围。
- syntax changed_ranges 只扩大到 lexer lookahead 与 fragile/tree structural boundary，不感知 QueryRole。

Go 条件：

~~~text
incremental tree digest == full tree digest
incremental diagnostics digest == full diagnostics digest
incremental query digest == full query digest
~~~

- PR gate 20,000 次确定性连续 edit mismatch = 0。
- nightly 1,000,000 次 mismatch = 0。
- reused bytes/nodes 只能由真实共享统计，禁止按“未修改字节”估算。
- 未实现非等长编辑右侧 subtree 共享前，不得宣称“真正增量”。

### 6.4 Lexer 与可移植 scanner

v1 lexer 允许：

~~~text
literal
regex
extras
keyword remap
lexer mode
nested(open, close)
delimited(start, end, escape, allow_newline)
~~~

不允许任意宿主 callback。Scanner VM 状态必须规范序列化，至少覆盖 mode stack、nesting depth、delimiter、escape 状态和 scanner program version。

- Green 保存不可变 ScannerState 引用；ScannerState 拥有 canonical state bytes。
- state hash 只用于 interner 查找加速；安全复用最终必须逐字节比较 canonical state，不能信任可能碰撞的 fingerprint。
- Parser/old Snapshot 来自不同实例时，只要 Language fingerprint 相同，也必须通过 canonical bytes 正确比较状态。

Token 选择顺序冻结为：

1. 当前 parse state 的 valid-token set。
2. 最长 UTF-8 字节匹配。
3. 显式 lexical priority 高者。
4. literal 优先于 regex。
5. Grammar canonical 声明顺序早者。

Tree-sitter external scanner 导入只能生成明确的未实现接口和 compatibility report；不能生成看似成功但静默丢语义的 production Pack。

### 6.5 Canonical LR(1)、安全压缩与局部 GLR

- correctness oracle 是不合并的 canonical LR(1)。
- 先用 row displacement、default reduction、相同行去重压缩，不先牺牲状态正确性。
- LR(0) core 相同的状态只有在合并不产生任何新 action set、且原状态 action 行为等价时才允许合并；该优化必须独立 PR 并保留 canonical oracle。
- precedence 已唯一解决的 cell 是确定性 action。
- 多 action cell 必须由 Grammar 显式声明 conflict，否则 Pack 编译失败并输出 witness。
- 单 action cell 使用普通数组栈快路径。
- 进入歧义 cell 后使用 GSS；merge key 为 (byte_pos, lr_state, canonical scanner state)，不同栈历史通过 predecessor links 保留，不能只保留一个分支。
- reduction 按 production body length 枚举全部 GSS path。
- 不构造或公开通用 parse forest；每条 link 携带 green subtree。
- score 不是 GSS node 的属性，冻结为：

~~~text
ActiveVersion = top GSS/path reference + accumulated Score
GssLink = predecessor + green subtree + Score delta + canonical link key
~~~

canonical key 使用长度前缀二进制编码，不使用创建序号：

~~~text
GssNodeKey = u64le(byte_pos) || u32le(lr_state)
             || u32le(scanner_state_len) || scanner_state_bytes

GreenKey = type_tag || u32le(kind_id) || u64le(byte_width) || flags
           || token_text_bytes-or-child-GreenKeys

CanonicalPathKey(empty) = 0x00
CanonicalPathKey(link)  = 0x01
  || len(predecessor_path_key) || predecessor_path_key
  || action_kind || u32le(action_or_production_id)
  || len(green_key) || green_key
  || i64le(recovery_cost_delta)
  || i64le(dynamic_precedence_delta)
  || u32le(error_node_delta)
~~~

所有整数先验证非负/范围再编码；GreenKey 的 child 顺序就是源码顺序，token 使用原始 UTF-8 bytes。实现可以缓存 SHA-256 加速 interning/比较，但 hash 相同必须回退完整 canonical bytes，排序和相等性不能只信 hash。`canonical link key` 就是当前 link 的 CanonicalPathKey；predecessor canonical key 指其完整 predecessor path bytes。

- reduction 枚举 path 时累计每条 link 的 score delta；合并 GSS node 不得合并或丢弃 score 不同的 ActiveVersion。
- action/worklist 在分配任何 sequence 前，按 byte position、state、scanner state bytes、action kind、production ID、predecessor canonical key 排序。
- 分支排序稳定为：

~~~text
recovery_cost ASC
dynamic_precedence DESC
error_node_count ASC
production_id ASC
canonical_path_key ASC
~~~

Go 条件：

- JSON、expression、MoonBit clean corpus 的 canonical LR(1) 路径全部通过。
- 至少三组声明歧义 fixture 证明全部 GSS path 被保留。
- action/production/Map 构造顺序随机化后最终 digest 不变；canonical_path_key 不得来自对象地址或 Map iteration。
- Pack 重复构建的 state 与 production ID 完全相同。

### 6.6 有界错误恢复

恢复使用有界 best-first search，只允许：

~~~text
Insert(expected terminal)
Delete(actual token)
PopToSync(state/rule)
~~~

默认 cost：

~~~text
start recovery region = 20
insert token          = 10
delete token          = 10 + min(token_byte_width, 20)
pop one syntax node   = 5
~~~

规则：

- expected token 来自当前 LR cell，按 symbol ID 去重排序。
- synchronization metadata 优先使用 Grammar 显式 recover 标注；否则使用 enclosing named rule 的 FOLLOW set。
- recovery candidate 必须消费 3 个真实 token或到达 EOF 才稳定。
- Insert 产生零宽 MISSING leaf 与 insertion fix-it。
- Delete/Pop 产生覆盖真实 bytes 的 ERROR node。
- 同一 error region 只产生一个主 Diagnostic。
- 每一步必须消费输入、降低栈高或增加有上限的 missing action；否则淘汰。

ParseLimits::editor_default 冻结为：

~~~text
max_active_versions       = 64
max_recovery_frontier     = 256
max_recovery_actions      = 16 per error site
max_recovery_lookahead    = 4 real tokens
max_total_parser_steps    = min(100_000_000, max(1_000_000, saturating_mul(source_bytes, 256)))
max_query_matches         = 100_000
max_tree_depth            = 65_536
max_tree_nodes            = min(10_000_000, max(1_000_000, saturating_mul(source_bytes, 16)))
~~~

`editor_default()` 内部保存上述 min/per-byte/cap policy，不在没有 Source 时假装得到最终数值；Parser 在每次 parse/reparse 的入口用最终 source byte length 解析为本次不可变预算。`with_max_parser_steps`/`with_max_tree_nodes` 将相应 policy 替换为固定上限。

公开 builder 的绝对上限冻结为：active_versions=4,096、parser_steps=100,000,000、tree_nodes=10,000,000、query_matches=1,000,000。所有乘法先转为足够宽的非负计数并做 checked/saturating 运算，再取 min/max；不得先在 `Int` 中溢出。非正值或高于绝对上限在构造 ParseLimits 时返回 InvalidLimit；运行中耗尽已验证预算才返回 BudgetExceeded。

这些值都是计数 ceiling，不是预分配容量；数组/arena 按实际需求有界增长，任何一次 grow 都先检查剩余预算与算术溢出。

Go 条件：

- 任意 bytes fuzz 在预算内终止，不 panic、不死循环、不异常分配。
- Insert/Delete/Pop 各有 golden tree、Diagnostic、fix-it test。
- 单字符删除返回 Snapshot，而不是 ParseFailure。
- 超预算稳定返回 BudgetExceeded，不静默丢分支。
- recovery 的 incremental/full tree 与 diagnostic digest 完全一致。

### 6.7 Query IR、VM 与缓存

v1 Query 语法只支持：

~~~text
named node, anonymous token, wildcard, field, capture
alternation, ?, *, +, sibling anchor
#eq?, #not-eq?, #match?, #not-match?, #any-of?
~~~

未列出的语法必须在编译期返回 UnsupportedFeature，禁止忽略。

捕获规范顺序由唯一的 `CaptureOrderKey` 冻结：

~~~text
node.start_byte ASC
node.end_byte ASC
pattern_index ASC
capture_declaration_index ASC
match_key lexicographic ASC
node_preorder_path lexicographic ASC
~~~

`capture_declaration_index` 是 capture 在所属 pattern 源码中的 0-based 声明序；`node_preorder_path` 是从 Query 执行根到 capture node 的 child-index 序列；`match_key` 是按 pattern instruction ordinal 排序后，对每个已匹配 instruction 编码 `(instruction_ordinal, node_preorder_path)` 的长度前缀字节串。所有字段相同表示语义上重复的 capture，必须按 VM 的 canonical match enumeration 原样保留；不得用对象地址、hash-map 顺序或任务完成顺序继续打破平局。Native/WASM 必须逐项输出同一顺序。

缓存规则：

- 只有 compiler 能证明不依赖 subtree 外 sibling/ancestor 的 concrete-rooted pattern 才能按 green identity 缓存。
- 无法证明 local 的 pattern 自动降级全量执行。
- Pack 为每个 QueryRole 声明 boundary node kinds。
- query_runtime 针对当前 QueryRole 将 syntax changed range 扩到最近 boundary，再删除旧 captures 并重算；不同 QueryRole 可以得到不同失效范围。
- locals 以 scope green node 为缓存单位；scope 变化则整 scope 重算。
- Locals Query 缺少 scope/definition/reference 约定时编译失败。

Canonical query digest 包含 pattern_index、capture name、node kind、start/end byte 和 flags，不包含对象地址、GreenId 或本地化文本。

Go 条件：

- cache enabled captures 逐项等于 cache disabled full captures。
- incremental query 逐项等于新树 full query。
- Native/WASM digest mismatch = 0。
- match limit 超出时返回稳定 QueryError。

## 7. 证据控制面

### 7.1 唯一真相源

以下文件必须受版本控制：

~~~text
evidence/
  control/
    acceptance.v1.json
    proposal-contract.v1.json
    work-packages.v1.json
    thresholds.v1.json
    toolchain.lock.json
  manifests/
    corpus.v1.json
    differential.v1.json
    digest.v1.json
    benchmark.v1.json
    size.v1.json

docs/contest/
  proposal-contract.md
  acceptance-matrix.md
  contribution-report.md
  prior-art.md
~~~

所有生成证据进入：

~~~text
_build/evidence/<full-commit-sha>/
~~~

候选 A03 sealed bundle / Release 首批附件：

~~~text
moonparse-evidence-<version>.tar.zst
acceptance-prepublish-receipt.json
release-manifest.json
SHA256SUMS
~~~

V16C/V15B 后另生成 `moonparse-final-attestation-<version>.json`：它只包含 A03 manifest hash、V16B/V16C/V15B receipt hash 和最终状态，不属于 A03 payload，避免时间/发布状态自引用。最终 Release asset policy 精确允许“A03 manifest 中的 payload + 这一份 context-matched final attestation”，不允许其他追加文件。M6-G02 上传后重新下载比对字节，并重新枚举整套 asset；上传/枚举回执保存在同 SHA CI 与双远端。

禁止同时手工维护第二套赛事状态。tracked `docs/contest/acceptance-matrix.md` 只由 control JSON 生成稳定的 requirement、phase、DRI、command 和 evidence locator，不含 observed/status/SHA。动态结果只生成 `_build/evidence/<sha>/V15A|V15B/acceptance-report.json` 与 `.md`，作为 CI/Release attestation，绝不反写 tracked 文档。

### 7.2 Acceptance / Proposal 行格式

每一行至少包含：

~~~json
{
  "id": "H06",
  "source": "charter-5.3.5",
  "kind": "hard",
  "phase": "prepublish",
  "claim": "CI covers check, build and test on release SHA",
  "dri": "DRI-A",
  "commands": ["V01"],
  "ci_jobs": ["moonbit-ci"],
  "expected": {"conclusion": "success"},
  "artifact": "ci://moonbit-ci"
}
~~~

tracked acceptance/proposal JSON 只保存要求、phase 和证据定位，不保存运行状态，避免 post-publish 结果反向修改 final tag。状态与 observed 只写同 SHA 的 `_build/evidence/.../acceptance-receipt.json`。

receipt 状态只允许 UNKNOWN、RUNNING、PENDING_EXTERNAL、PASS、FAIL、BLOCKED、WAIVED。`phase` 只允许 prepublish 或 postpublish：V15A 中只有 postpublish 行可为 PENDING_EXTERNAL；hard/proposal 行永远禁止 WAIVED；V15B 中任何非 PASS 都失败。

### 7.3 必备赛事矩阵


| ID  | 要求                                                 | 核心证据                                             |
| --- | ---------------------------------------------------- | ---------------------------------------------------- |
| H00 | 7/10 前有效申报且材料对应当前仓库                    | registration-status、proposal hash、双仓 URL receipt |
| H01 | 有效 MoonBit 项目                                    | moon.mod、moon.pkg、strict check                     |
| H02 | MoonBit 为主要实现语言                               | 可复现 source-stat                                   |
| H03 | GitHub/Gitlink 公开且默认分支同 SHA                  | remote receipt                                       |
| H04 | 声明核心功能真实完成                                 | proposal promise -> API/test/CI                      |
| H05 | README 安装、使用、示例可复现                        | clean docs smoke                                     |
| H06 | CI 覆盖 check/build/test 且 release SHA 全绿         | workflow receipt                                     |
| H07 | 至少一个可运行示例                                   | examples/editor_loop E2E                             |
| H08 | 核心路径测试完整                                     | tests、coverage、differential                        |
| H09 | 已发布 mooncakes                                     | package page + clean install smoke                   |
| H10 | OSI 许可证和第三方合规                               | LICENSE、THIRD_PARTY、provenance                     |
| H11 | 仓库无明显产物污染                                   | tracked-file policy                                  |
| H12 | 贡献人、owner、申请关系合理                          | DRI-A 人工确认，不记录敏感信息                       |
| H13 | 无严重正确性/性能问题                                | corpus、fuzz、limits、bench                          |
| H14 | 申报承诺实质完成                                     | 全部 P-* PASS                                        |
| H15 | final tag、Release assets、双远端和 Demo 同 SHA/hash | V16C + release manifest                              |
| C01 | 4 月 29 日后贡献可追踪                               | baseline...release report                            |
| E01 | 相对既有 MoonBit 项目有独立价值                      | prior-art / moonyacc / parser / Tree-sitter 对比     |

申报书每个承诺必须拆成 P001、P002...，映射为：

~~~text
承诺 -> 公共 API/实现路径 -> black-box test
     -> 复现命令 -> CI job -> release artifact
~~~

若申报书与本计划不同，不得自行删除原承诺；需要差异说明和赛事方确认。

H05、H09 与 H15 固定为 postpublish：README 的源码示例在 prepublish 检查，但“完全照 README 从 registry 安装”只能由 V16B 观察。其余 H/C/E 及全部 P-* 默认 prepublish，除非赛事原文明确要求发布后才能观察且由 DRI-A/R 审批 ADR。phase 变更属于控制面变更，必须独立 PR，不能与实现或状态 receipt 同时修改。

### 7.4 Corpus manifest

corpus.v1.json 的每个输入必须记录：

~~~text
id
committed path or source URL
source repository and exact commit/tag
license and redistribution note
SHA-256
expected clean/error
expected diagnostic codes
language Pack fingerprint
include/exclude rule
~~~

集合冻结为：

1. JSON legal/illegal/Unicode/truncation/recovery oracle。
2. 当前 MoonParse 全部真实 .mbt 源码。
3. 与锁定 MoonBit 工具链对应、许可证清晰的 moonbitlang/core 子集。
4. 至少一个固定版本的真实 MoonBit 社区项目。
5. malformed、large file、deep nesting、resource bomb 专用集合。

expected=clean 的文件必须先由锁定的官方 MoonBit 工具链接受。删减 corpus 必须独立 provenance PR，不能和修 parser 的 PR 混合。

### 7.5 Differential manifest

differential.v1.json 冻结：

- generator_version。
- 固定 seed 列表。
- 每个序列的初始 source hash、Pack fingerprint 和 steps。
- 操作分布：insert、delete、replace、paste、UTF-8 multibyte、错误编辑。
- 所有位置在合法 UTF-8 boundary。
- PR profile >= 20,000 edits。
- nightly/release profile >= 1,000,000 edits。
- 至少一组 1,000 次连续编辑序列。

每步必须比较 tree、diagnostics、Query captures。失败产物必须包含 seed、初始源码、完整 edit trace、最小化样本和两种 digest。

硬阈值：

~~~text
mismatch = 0
crash = 0
timeout = 0
resource_violation = 0
unreproducible_failure = 0
~~~

### 7.6 Canonical digest v1

Digest 输入使用 canonical JSON Lines，key 顺序固定，再计算 SHA-256。

必须包含：

- digest schema、Pack fingerprint、source SHA-256。
- tree preorder 的 kind、field、flags、byte range、production identity。
- Diagnostic code、severity、range、recovery action、稳定排序的 expected symbol。
- Query role、pattern index、capture name、kind、range。

必须排除：

- object address、GreenId、WASM handle。
- timing、memory address、creation timestamp。
- 本地化 message 文本。
- 不稳定 Map iteration order。

同一 manifest 的 Native、WASM case count、schema、Pack hash 和每行 digest 必须完全相同。

### 7.7 Benchmark protocol

固定参考 profile：

~~~text
machine_id: cky-win-ultra5-v1
CPU: Intel Core Ultra 5 225H, 14 cores
RAM: 32 GiB
OS: Windows 11 x64
power: AC, best-performance profile
native: release build
wasm host: Node version from toolchain.lock.json
browser: Microsoft Edge version recorded in every receipt
warmup: 20
samples: 50
outlier policy: keep all raw samples
~~~

GitHub hosted runner 的墙钟结果只 report-only。性能硬门只在上述固定 self-hosted profile 或经独立 ADR 新增的等价 profile 上执行。

报告必须包含 10KB、100KB、1MB：

- full parse median/p95。
- local edit median/p95。
- parse + highlight median/p95。
- reused bytes/nodes。
- incremental/full ratio。
- peak RSS/heap。
- raw/Brotli WASM 与 Pack size。

候选阈值：

~~~text
100KB native local edit p95        <= 5 ms
100KB browser parse+highlight p95  <= 16 ms
eligible edits median reused bytes >= 95%
incremental/full p95 ratio         <= 0.20
10k edits RSS after/at 1k          <= 1.50
Brotli WASM + MoonBit Pack         <= 1_048_576 bytes
~~~

M1-G02 spike 后 thresholds.v1.json 必须把每项标为 HARD 或用独立 ADR 替换。阈值修改只能独立 PR，必须附旧/新 raw evidence；不能与被测优化一起修改，CI 失败不能自动更新 baseline。

### 7.8 Size 与确定性

- 同一 PackSource 在 clean process 中连续构建 3 次，.mpack 完全相同。
- WASM release 从相同 source/toolchain 构建 2 次，规范化后完全相同。
- raw size 永远记录。
- Brotli 使用 toolchain.lock.json 中 Node 版本，quality=11、lgwin=22、mode=generic。
- 目标子预算：Brotli WASM <= 716,800 bytes；Brotli moonbit.mpack <= 331,776 bytes；combined <= 1,048,576 bytes。
- 任何预算变化遵守 threshold PR 规则。

## 8. 验证命令注册表

本节命令是最终仓库必须实现并保持兼容的“质量 CLI 契约”。某命令在对应工作包之前可以不存在；工作包 PASS 时必须存在、跨平台并输出指定回执。

所有证据型 tools/quality 子命令自动读取 git full SHA，并写入 `_build/evidence/<sha>/<domain>/`。Artifact producer 只允许写 `_build/work/<producer-or-gate-id>/`；只有已验证的 A03 promote 可写 `_build/release/`。验证模式的文档 renderer 只能 `--check`，不能改 tracked 文件。

M0-C05 之后，CI 和 release 不直接散装调用本节命令，而统一执行：

~~~text
node tools/quality/run-gate.mjs <V-ID> --profile <pr|nightly|release>
~~~

run-gate 必须：

- 执行对应 V-ID 的全部内层命令并保留 stdout/stderr。
- 记录 full SHA、dirty 状态、工具链、操作系统、输入 manifest hash、开始/结束时间、退出码和 artifact hash。
- 输出 _build/evidence/<sha>/<V-ID>/receipt.json。
- 任何内层命令失败即返回非 0；不得吞错或自动更新 snapshot/threshold。
- V00/V01 等原生命令也必须由 wrapper 生成回执。
- M0-G00/G01/G02 使用 bootstrap receipt；M0-C05 建成后必须由正式 wrapper 重跑补验。

### A00：Canonical core-fixture assembly

A00 由 M2-C06 实现，只为 M2 的 parser/incremental oracle 生成最小 expression fixture，不是发布物，也不能被用于赛事能力主张：

~~~text
moon run tools/quality -- assemble-fixture-pack --source tests/fixtures/grammars/expression --out _build/work/V05A/expression.mpack
~~~

它与 compiler conformance tests 同时冻结，写入 fixture source hash、toolchain hash 与 Pack fingerprint；V05A 不依赖 production MoonBit Pack，从而不会反向依赖 M3。

### A01：Canonical Pack assembly

A01 是唯一的 production Canonical Pack artifact producer，不是独立质量 Gate；由 M3-C06 实现。正常验证与发布固定调用：

~~~text
moon run tools/quality -- assemble-pack --source languages/moonbit --out _build/work/A01/packs/moonbit.mpack
~~~

V09 的三次重建必须调用同一 `assemble-pack` 代码路径，只把 `--out` 改为 `_build/work/V09/<run>/moonbit.mpack`。A01 必须同时写 provenance.json、Pack fingerprint 和 source manifest hash；A01/V09 都只写 `_build/work/<producer-or-gate-id>/`，最终 `_build/release` 只由 A03 promote。

### A02：Canonical WASM assembly

A02 由 M4-C02 实现，V06、V08B、V11、V13 和 release Gate 在运行前显式调用：

~~~text
npm run assemble:wasm -- --pack _build/work/A01/packs/moonbit.mpack --out-dir _build/work/A02/wasm
~~~

它只消费已通过 A01 的 Pack 和同 SHA root runtime，且必须精确输出 `_build/work/A02/wasm/moonparse.wasm`、`moonparse.js`、`abi.json`、`provenance.json`；目录中出现未登记文件即失败。任何 `npm run build:release` 若保留，只能是 A02 的参数透传 wrapper，不得存在第二套 builder。

### A04：Canonical Demo assembly

A04 由 M4-C04 实现，唯一消费 A01/A02 和 tracked demo source：

~~~text
npm run assemble:demo -- --pack _build/work/A01/packs/moonbit.mpack --wasm-root _build/work/A02/wasm --out-dir _build/work/A04/demo
~~~

固定输出静态离线站点、scenario.json、asset-manifest.json 和 provenance.json；所有 URL 相对化，不能在构建时下载资源。V13 只测试 A04，A03 只复制已通过 V13 的 A04。

### A03：Canonical release-bundle assembly

A03 由 M6-C03 实现，是 V16A 和整个发布 saga 唯一认可的 bundle producer。它从只读 A01/A02/A04 输入在独立 staging 目录构建两次，先比较再 promote：

~~~text
moon run tools/quality -- assemble-release --module-manifest moon.mod --candidate HEAD --pack-root _build/work/A01/packs --wasm-root _build/work/A02/wasm --demo-root _build/work/A04/demo --media-root _build/work/M6-C05/media --evidence-root _build/evidence/<full-sha> --out _build/work/A03/a
moon run tools/quality -- assemble-release --module-manifest moon.mod --candidate HEAD --pack-root _build/work/A01/packs --wasm-root _build/work/A02/wasm --demo-root _build/work/A04/demo --media-root _build/work/M6-C05/media --evidence-root _build/evidence/<full-sha> --out _build/work/A03/b
moon run tools/quality -- artifact-compare --left _build/work/A03/a --right _build/work/A03/b
moon run tools/quality -- promote-release --from _build/work/A03/a --verified-by _build/evidence/<full-sha>/A03/receipt.json --out _build/release
~~~

固定产物树：

~~~text
_build/release/
  package/                         mooncakes 待发布源码包/manifest
  packs/moonbit.mpack
  packs/provenance.json
  wasm/moonparse.wasm
  wasm/moonparse.js
  wasm/abi.json
  wasm/provenance.json
  demo/index.html
  demo/assets/...
  demo/scenario.json
  demo/asset-manifest.json
  demo/provenance.json
  media/champion-demo.mp4
  media/provenance.json
  evidence/moonparse-evidence-<module-version>.tar.zst
  evidence/acceptance-prepublish-receipt.json
  release-manifest.json
  SHA256SUMS
~~~

hash DAG 不得自引用：`release-manifest.json` 记录 candidate full SHA、模块/Pack/ABI 版本、工具链、生成命令，以及除自身和 SHA256SUMS 外每个 payload 相对路径的 size/SHA-256；SHA256SUMS 列出全部 payload 加 release-manifest.json，明确排除自身。evidence archive 由显式 prepublish receipt allowlist 构建，只含 V00–V14、V15A、V17 及其子门，排除 A03 自身、V15B、V16*、M6-G02 和任何目录 glob 新文件。A03 必须按相对路径排序，归一化 archive timestamp/permission，拒绝 symlink、绝对路径、未列文件和 SHA 不同的 receipt；同 SHA 连续两次 staging assembly 必须字节一致。promote 只在比较 receipt PASS 后执行，且输入不位于被替换的 `_build/release` 内。

Gate 与 artifact 的依赖固定如下；`run-gate` 缺少前置 artifact、provenance 或 SHA 匹配时必须失败，不能隐式现场下载或使用旧缓存：


| Gate                            | 必须先完成                                                                          |
| ------------------------------- | ----------------------------------------------------------------------------------- |
| V05A、V07A                      | A00                                                                                 |
| V04、V05B、V07B、V08A、V09、V10 | A01                                                                                 |
| V06、V08B、V11、V12             | A01 -> A02                                                                          |
| V13                             | A01 -> A02 -> A04                                                                   |
| V15B、V16A、V16B、V16C          | A01 -> A02 -> A04 -> A03；V16A 验 bundle，V15B/V16B/V16C 只读 A03 expected SHA/hash |

### V00：历史与施工前检查

~~~text
node tools/quality/history-verify.mjs --profile <pr|release> --candidate HEAD --baseline-tag contest-baseline-2026-04-26 --baseline-sha 68065b686857af26966f084114966c59c347a562 --archive-tag archive-pre-mainline-69 --archive-sha d8bffb8be6a9a387fdfdbb7812fdfaf66d89b06f --plan todo/plan.md
~~~

预期：

- 子命令内部先断言两个 ref 的 Git object type 都是 `tag`（禁止 lightweight tag），再断言 peeled SHA 各自精确等于冻结值、baseline 是 archive 祖先、archive 是 HEAD 祖先；任何一项不符都非 0。
- 子命令内部执行 `git diff --check`，并把 baseline..HEAD 的 full SHA/author time/subject 写入 receipt；不得只打印后由人眼判断。
- 子命令把 `git check-ignore` 的“退出 1 才正确”转换成整个 verifier 的成功退出 0；被忽略、Git 错误或其他退出码都失败。
- release profile 强制 tracked/untracked worktree clean；PR profile 也必须是平台生成的 clean checkout，不接受本地 dirty 作为证据。
- history-integrity workflow 必须使用 fetch-depth: 0 并显式 fetch tags；不依赖 fresh checkout 中可能不存在的本地 champion/mainline ref。
- wrapper 输出保存到 _build/evidence/<sha>/V00/receipt.json。

CI job：history-integrity。

### V01：严格 MoonBit 工程门

~~~text
moon version --all
moon check --target all --deny-warn --frozen
moon build --target all --deny-warn --frozen
moon test --target all --deny-warn --frozen
moon fmt --check
moon info --target all --frozen
git diff --exit-code
~~~

说明：

- 明确只支持特定后端的 adapter package 使用 supported_targets；核心包必须通过 target all。
- info/fmt 在 clean CI worktree 执行，任何 diff 都失败。
- 工具链版本必须与 evidence/control/toolchain.lock.json 一致。

CI jobs：moonbit-linux、moonbit-macos、moonbit-windows、fmt-info-gate。

从 M1-C02 引入 declare 到 M2-C12 完成实现的 exception-active 阶段，只把本节的 `moon check`、`moon build`、`moon test` 三行换成第 4.5 节带 `--warn-list "-68"` 的对应命令，并追加 `declaration-scope`；version、fmt、info、clean-diff 等其余命令原样执行。`run-gate` 只有在 exception 文件 schema、路径、code 和 expiry 全部精确匹配时才可为 PR/nightly 注入该参数；RC/release 拒绝。M2-C12 之后所有 profile 必须执行上面的无豁免命令。

### V02：边界、API 与规范

~~~text
moon run tools/quality -- boundaries --config api/boundaries.json
moon check spec.mbt compiler/spec.mbt --deny-warn --frozen
moon test --target all --deny-warn tests/consumer
moon run tools/quality -- api-snapshot --check
~~~

预期：cycle=0、internal leak=0、unexpected public symbol=0、consumer failures=0。

CI jobs：architecture-gate、consumer-smoke、api-snapshot。

M1-G01 使用第 4.5 节的 contract-stage spec 与 compile-only consumer check；declare 尚未实现时禁止把 consumer test 伪装成运行通过。M2-C12 必须删除 warning exception 后重跑本节原始严格命令和真正的 consumer tests，才能进入 M2-G01。

### V03：Pack conformance 与确定性

~~~text
moon test --target all --deny-warn internal/pack compiler
moon run tools/quality -- pack-conformance --fixtures tests/malformed_pack --repeat 3
~~~

输出：

~~~text
pack-conformance/report.json
pack-conformance/hashes.json
pack-conformance/failures/
~~~

预期：round-trip mismatch=0、repeat mismatch=0、malformed accepted=0、panic=0。

CI jobs：pack-conformance、pack-determinism。

### V04：Corpus

前置 artifact：A01，且 Pack provenance 的 full SHA 必须等于 Gate SHA。

~~~text
moon run tools/quality -- corpus-verify --manifest evidence/manifests/corpus.v1.json --pack _build/work/A01/packs/moonbit.mpack
~~~

输出：corpus/report.json。

预期：manifest coverage=100%、clean rate=100%、unexpected diagnostic=0、crash/timeout=0。

CI job：corpus-gate。

### V05：连续编辑 Differential

#### V05A：core fixture（M2 解环门）

前置 artifact：A00；只证明 parser、recovery、incremental 与 Query 核心等价，不产生 production 能力主张。

~~~text
moon run tools/quality -- differential --manifest evidence/manifests/differential-core.v1.json --pack _build/work/V05A/expression.mpack --profile pr
~~~

预期：至少 20,000 次固定种子单/batch edit；tree/diagnostic/query mismatch、crash、timeout、resource violation 全部为 0。

#### V05B：production MoonBit Pack

前置 artifact：A01，且所有 full/incremental oracle 消费同一 Pack fingerprint。

~~~text
moon run tools/quality -- differential --manifest evidence/manifests/differential.v1.json --pack _build/work/A01/packs/moonbit.mpack --profile pr
~~~

nightly/release 将 `--profile` 替换为 nightly 或 release。输出：differential/core/report.json 或 differential/production/report.json、失败 edit trace 与 minimized fixtures。

预期：PR 至少 20,000 次，nightly/release 至少 1,000,000 次固定种子单/batch edit；所有 mismatch、crash、timeout、resource violation 为 0。

CI jobs：differential-core-pr、differential-production-pr、differential-nightly、differential-release。

### V06：Canonical digest 与跨端一致

前置 artifact：A01 -> A02；Native 与 WASM 必须记录同一 Pack fingerprint 和 candidate SHA。

~~~text
moon run tools/quality -- digest-native --manifest evidence/manifests/digest.v1.json --pack _build/work/A01/packs/moonbit.mpack

node tools/quality/digest-wasm.mjs --manifest evidence/manifests/digest.v1.json --pack _build/work/A01/packs/moonbit.mpack --wasm-root _build/work/A02/wasm

moon run tools/quality -- digest-compare --left native --right wasm
~~~

输出：digest/native.jsonl、digest/wasm.jsonl、digest/compare.json。

预期：case/schema/Pack hash 相同，digest mismatch=0。

CI job：cross-backend-digest。

### V07：Fuzz、对抗输入与资源上限

#### V07A：core fixture（M2 解环门）

~~~text
moon run tools/quality -- pack-fuzz --profile pr --fixtures tests/malformed_pack
moon run tools/quality -- parser-adversarial --manifest evidence/manifests/differential-core.v1.json --pack _build/work/V05A/expression.mpack --profile pr
moon run tools/quality -- query-adversarial --pack _build/work/V05A/expression.mpack --profile pr
~~~

#### V07B：production MoonBit Pack

~~~text
moon run tools/quality -- pack-fuzz --profile <nightly|release> --fixtures tests/malformed_pack --seed-pack _build/work/A01/packs/moonbit.mpack
moon run tools/quality -- parser-adversarial --manifest evidence/manifests/corpus.v1.json --pack _build/work/A01/packs/moonbit.mpack --profile <nightly|release>
moon run tools/quality -- query-adversarial --pack _build/work/A01/packs/moonbit.mpack --profile <nightly|release>
~~~

输出 fuzz/core/<domain>/report.json 或 fuzz/production/<domain>/report.json 与可复现 minimized 样本。预期：panic=0、hang=0、out-of-budget success=0、unbounded allocation=0；同一 seed/toolchain 可逐字节复现失败输入。

CI jobs：fuzz-core-pr、fuzz-production-nightly、fuzz-production-release、resource-limit-gate。

### V08：Benchmark

#### V08A：Native/core（M3）

~~~text
moon run tools/quality -- benchmark-native --manifest evidence/manifests/benchmark.v1.json --pack _build/work/A01/packs/moonbit.mpack --profile cky-win-ultra5-v1 --warmup 20 --samples 50
~~~

#### V08B：WASM/browser（M4）

前置 artifact：A01 -> A02。

~~~text
node tools/quality/benchmark-wasm.mjs --manifest evidence/manifests/benchmark.v1.json --pack _build/work/A01/packs/moonbit.mpack --wasm-root _build/work/A02/wasm --profile cky-win-ultra5-v1 --warmup 20 --samples 50
~~~

输出：benchmark/native.json、benchmark/wasm.json 和全部 raw samples。

CI jobs：benchmark-report、benchmark-reference-gate。

### V09：Pack size 与 artifact reproducibility

前置 producer：A01；三次构建必须清空各自输出目录，并使用同一 source manifest 与 toolchain lock。

~~~text
moon run tools/quality -- assemble-pack --source languages/moonbit --out _build/work/V09/a/moonbit.mpack
moon run tools/quality -- assemble-pack --source languages/moonbit --out _build/work/V09/b/moonbit.mpack
moon run tools/quality -- assemble-pack --source languages/moonbit --out _build/work/V09/c/moonbit.mpack

moon run tools/quality -- artifact-compare --left _build/work/V09/a --right _build/work/V09/b
moon run tools/quality -- artifact-compare --left _build/work/V09/a --right _build/work/V09/c

node tools/quality/size-check.mjs --manifest evidence/manifests/size.v1.json --component pack --artifact-root _build/work/V09/a
~~~

输出：determinism/report.json、size/report.json、SHA256SUMS。

预期：三份 canonical Pack mismatch=0，Pack HARD size budget 通过。本 Gate 不依赖 CLI 或 WASM。

CI jobs：pack-artifact-determinism、pack-size-gate。

### V10：CLI E2E

前置 artifact：A01。

~~~text
moon test --target native --deny-warn cmd/moonparse
moon run cmd/moonparse -- pack check languages/moonbit
moon run cmd/moonparse -- pack test languages/moonbit
moon run cmd/moonparse -- parse --pack _build/work/A01/packs/moonbit.mpack tests/fixtures/moonbit/smoke.mbt
moon run cmd/moonparse -- verify --manifest evidence/manifests/digest.v1.json
~~~

预期：exit-code snapshot、stdout schema、digest 与根 API 一致。

CI job：cli-e2e。

### V11：WASM/JS E2E

前置 artifact：A01 -> A02；测试只能消费 A02 输出，不得另建第二套 JS/WASM facade。

~~~text
moon test --target wasm-gc --deny-warn wasm
npm run assemble:wasm -- --pack _build/work/A01/packs/moonbit.mpack --out-dir _build/work/V11/a
npm run assemble:wasm -- --pack _build/work/A01/packs/moonbit.mpack --out-dir _build/work/V11/b
moon run tools/quality -- artifact-compare --left _build/work/V11/a --right _build/work/V11/b
moon run tools/quality -- artifact-compare --left _build/work/A02/wasm --right _build/work/V11/a
node wasm/test/smoke.mjs --pack _build/work/A01/packs/moonbit.mpack --artifact-root _build/work/A02/wasm
node wasm/test/resource-lifecycle.mjs --pack _build/work/A01/packs/moonbit.mpack --artifact-root _build/work/A02/wasm
node tools/quality/size-check.mjs --manifest evidence/manifests/size.v1.json --component wasm-and-pack --pack-root _build/work/A01/packs --wasm-root _build/work/A02/wasm
~~~

预期：ABI snapshot 无意外变化、double-free/use-after-free=0、handle leak=0、两次 WASM build 规范化后相同、WASM 与 combined HARD size budget 通过。

CI jobs：wasm-build、wasm-e2e、wasm-abi。

### V12：薄 LSP 协议 E2E

~~~text
npm --prefix adapters/lsp ci
npm --prefix adapters/lsp run build
npm --prefix adapters/lsp run test:e2e -- --runtime-root ../../_build/work/A02/wasm --pack ../../_build/work/A01/packs/moonbit.mpack
~~~

必须覆盖 UTF-16/UTF-8 转换、连续 document version、incremental edit、取消、资源释放、semantic tokens、symbols、folding、highlight 与文档内 navigation。

预期：协议失败=0；diagnostics/symbols/highlights digest 与 CLI/WASM 相同。

CI job：lsp-e2e。

### V13：Champion Demo

前置 artifact：A01 -> A02 -> A04；在线预览与离线 smoke 必须消费同一 A04 candidate artifact，A03 后续逐字节复制它。

~~~text
npm --prefix demo ci
npm --prefix demo test
npm run assemble:demo -- --pack _build/work/A01/packs/moonbit.mpack --wasm-root _build/work/A02/wasm --out-dir _build/work/A04/demo
node demo/test/smoke-release.mjs --artifact-root _build/work/A04/demo
moon run tools/quality -- demo-rehearsal --scenario demo/scenarios/champion.v1.json --artifact-root _build/work/A04/demo
~~~

预期：Demo 只加载 A04 artifact；离线模式可运行；黄金路径全部断言通过；A04 provenance 与 A01/A02 同 SHA。

CI jobs：demo-build、demo-e2e、demo-release-smoke。

### V14：Pack SDK、迁移与外部采用

~~~text
moon run tools/quality -- sdk-smoke --template templates/language-pack --publish-mode dry-run

moon run tools/migrate/treesitter -- verify --manifest evidence/manifests/treesitter-import.v1.json

moon run tools/quality -- showcase-language --pack languages/showcase

moon run tools/quality -- usability-receipt --input evidence/external/pack-author-v1.json
~~~

预期：新仓库 init/check/test/build/publish-dry-run 全流程通过；3 个真实 grammar compatibility report 完整；第二语言通过同一质量门；外部反馈问题闭环。除 DRI-A 另行批准的隔离测试 namespace 外，V14 不写公共 registry。

CI jobs：sdk-smoke、treesitter-import、showcase-language、usability-receipt。

### V15：赛事控制矩阵

M0-C05 只执行下列 bootstrap control 检查，它不是 V15A/B，也不判断尚未实现的能力状态：

~~~text
node tools/bootstrap/validate-control.mjs --acceptance evidence/control/acceptance.v1.json --proposal evidence/control/proposal-contract.v1.json
moon run tools/quality -- control validate-schema --acceptance evidence/control/acceptance.v1.json --proposal evidence/control/proposal-contract.v1.json
moon run tools/quality -- control render --acceptance evidence/control/acceptance.v1.json --proposal evidence/control/proposal-contract.v1.json --out _build/work/M0-C05/a.md
moon run tools/quality -- control render --acceptance evidence/control/acceptance.v1.json --proposal evidence/control/proposal-contract.v1.json --out _build/work/M0-C05/b.md
moon run tools/quality -- artifact-compare --left _build/work/M0-C05/a.md --right _build/work/M0-C05/b.md
~~~

该检查只允许 schema/provenance/render determinism 结论，不得生成“acceptance PASS”或冒充 release receipt。

#### V15A：prepublish control gate

~~~text
moon run tools/quality -- control verify --phase prepublish --acceptance evidence/control/acceptance.v1.json --proposal evidence/control/proposal-contract.v1.json

moon run tools/quality -- control render --acceptance evidence/control/acceptance.v1.json --proposal evidence/control/proposal-contract.v1.json --check docs/contest/acceptance-matrix.md
~~~

预期：所有 prepublish hard/proposal 行 PASS；postpublish 行精确为 PENDING_EXTERNAL；UNKNOWN、FAIL、BLOCKED、WAIVED 均为 0；renderer diff=0，Gate 不修改 tracked 文件。

#### V15B：final control gate

~~~text
moon run tools/quality -- control verify --phase final --acceptance evidence/control/acceptance.v1.json --proposal evidence/control/proposal-contract.v1.json --context _build/evidence/<full-sha>/release/release-context.json --expected-release _build/release/release-manifest.json

moon run tools/quality -- control render --acceptance evidence/control/acceptance.v1.json --proposal evidence/control/proposal-contract.v1.json --check docs/contest/acceptance-matrix.md
~~~

预期：包括 H09/H15 在内的全部 hard/proposal 行 PASS；PENDING_EXTERNAL 和其他非 PASS 状态为 0。两个 phase 都只把 observed/status 写入 evidence receipt，不改 tracked control JSON。

CI jobs：contest-control-prepublish、contest-control-final。

### V16：Artifact preflight 与 post-publish smoke

M6-H01 写入不可变 `_build/evidence/<sha>/release/release-context.json`，字段固定为 candidate SHA、从 A03 读取的 module/version（首发目标 caiklonghuan/MoonParse@1.0.0）、RC tag、expected final tag、A03 artifact object ID 与 release-manifest SHA-256。V16A/B/C 与 V15B 的 clean jobs 必须从 M6-H01 上传的不可变 A03 CI/RC artifact 恢复 `_build/release`，先核对 context；禁止从当前 workspace 重新组装一个“看起来相同”的 expected 文件。final GitHub Release 发布后改从同一 A03 asset 下载，并要求 hash 不变。

#### V16A：本地/RC artifact preflight

只验证本地/RC artifact，不访问尚未发布的 registry：

~~~text
moon run tools/quality -- release-preflight --context _build/evidence/<full-sha>/release/release-context.json --evidence-root _build/evidence --artifact-root _build/release

moon run tools/quality -- install-smoke --artifact _build/release/package --expected _build/release/release-manifest.json --example examples/editor_loop
~~~

#### V16B：Registry install smoke

只能在 registry publish 成功后、final tag 创建前执行：

~~~text
moon run tools/quality -- install-smoke --registry mooncakes --context _build/evidence/<full-sha>/release/release-context.json --expected _build/release/release-manifest.json --readme README.mbt.md --exact-readme-commands --example examples/editor_loop
~~~

#### V16C：Final remote verification

在 final tag、Release、双远端和 Demo 均发布后执行：

~~~text
moon run tools/quality -- remote-release-verify --context _build/evidence/<full-sha>/release/release-context.json --expected _build/release/release-manifest.json
~~~

预期：

- V16A：A03 manifest 完整；candidate SHA、artifact provenance、Pack/WASM/package hash、示例结果一致。
- V16B：mooncakes 下载内容、Pack fingerprint 和示例 digest 与 candidate artifact 相同。
- V16C：双远端、final tag、Release asset 和 Demo 指向相同 SHA/hash。

CI jobs：release-preflight-artifact、postpublish-install-smoke、verify-remotes。

### V17：仓库卫生、来源、文档与贡献报告

~~~text
moon run tools/quality -- repo-hygiene --policy evidence/control/repository-policy.v1.json

moon run tools/quality -- provenance --third-party THIRD_PARTY.md --corpus evidence/manifests/corpus.v1.json

moon run tools/quality -- docs-smoke --mode source --readme README.mbt.md --example examples/editor_loop

moon run tools/quality -- contribution-report --baseline 68065b686857af26966f084114966c59c347a562 --head HEAD

moon run tools/quality -- source-stat --policy evidence/control/language-policy.v1.json

moon run tools/quality -- coverage --config evidence/control/coverage.v1.json --profile release
~~~

输出：repository/report.json、provenance/report.json、docs/report.json、contribution/report.json、source-stat/report.json、coverage/report.json 与 raw coverage。

预期：undeclared binary/source/corpus=0、broken source-mode code block/link=0、tracked cache/build artifact=0；source mode 执行全部非 registry README 命令并静态校验唯一安装命令，exact registry 安装由 V16B 完成；赛期贡献报告可从 git history 重建；source-stat 排除 generated/vendor 后 MoonBit 是主要实现语言且每个排除项有来源；root/compiler 与 internal/{pack,syntax,engine,query_runtime} 行覆盖各 >= 90%，全 MoonBit 非生成源码 >= 80%。coverage 是缺口门，不替代 differential/fuzz。

CI jobs：repo-hygiene、provenance-gate、docs-example、contribution-report、source-language-gate、coverage-gate。

## 9. 原子工作包

计划冻结时，M0-G00 状态为 READY，其余工作包均为 BACKLOG。M0-G02 创建 tracked `evidence/control/work-packages.v1.json` 后，它成为唯一“定义源”，只保存依赖/目标/命令，不保存动态 status。状态由 control reducer 从同 SHA/可达历史的 immutable receipts 计算到 `_build/evidence/<sha>/control/work-package-state.json`；因此 postpublish PASS/FROZEN 永远不反写 final tag。本节定义也不随状态更新而改写。

### 9.0 工作包执行协议

M0-C05 之后，每个非 HUMAN 工作包唯一入口是：

~~~text
node tools/quality/run-work-package.mjs <WORK-PACKAGE-ID> --profile <pr|nightly|release>
~~~

`work-packages.v1.json` 对本节每一行逐项保存 `id/class/hard_deps/target_globs/commands/gates/evidence_path/ci_job`。runner 必须：

1. 校验 hard deps 的 PASS receipt 可达且属于当前分支历史；未满足时不执行。
2. 校验当前 diff 只命中 target_globs；越界文件使工作包 FAIL，不能自动扩 scope。
3. 按 JSON 数组原序执行精确命令；表中写 Vxx 时展开第 8 节注册命令，写 targeted tests 时展开该包冻结的 package selector/fixture manifest。
4. 执行适用的 strict check、targeted black-box/white-box tests、`moon info`/API diff、格式和 provenance 检查；contract warning 例外只按第 4.5 节。
5. 写 `_build/evidence/<sha>/work-packages/<ID>/receipt.json`，包含 command argv、exit code、input/output hash、target diff、依赖 receipt hash 和 CI URL。
6. 本地 PASS 只进入 VERIFYING；同 SHA required CI PASS 后 control 工具才把状态转为 PASS。

HUMAN 包由 DRI-A 执行明确的外部动作，再用 `node tools/quality/record-human-gate.mjs <ID> --input <redacted-receipt.json>` 校验 schema、SHA/hash 与前置依赖；工具不得接收或保存 token、cookie、邮件正文、身份证明等秘密。M0-G00/H00/H01/G01/G02 在 runner 建成前使用第 0.4 节 bootstrap 例外，M0-C05 必须补验。

### M0：历史、资格与可信工程地基


| ID     | Class       | DRI | Hard deps                   | 目标路径/产物                                                                                          | 验收                                                                                                                                                        |
| ------ | ----------- | --- | --------------------------- | ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| M0-G00 | GATE        | E   | 无                          | .gitignore、todo/plan.md                                                                               | bootstrap visibility assertion PASS；本文件提交到当前 `master`                                                                                              |
| M0-H00 | HUMAN       | A   | M0-G00                      | evidence/external/platform-readiness.v1.json、registration-status receipt                              | 7/10 前有效申报/参赛资格、proposal hash/仓库 URL 对应；GitHub Actions、Gitlink、mooncakes、publish environment、reference runner 均可用且无敏感信息         |
| M0-H01 | HUMAN       | A   | M0-H00,M0-G00               | GitHub/Gitlink 的 contest/archive annotated tags、master                                               | 经作者批准 push；两个远端 fresh clone 均可 fetch 两 tag/branch且 peeled SHA 一致；不移动冻结 ref                                                            |
| M0-G01 | GATE        | A+E | M0-G00,M0-H01               | 三个不可变锚点、dirty-assets/bootstrap history receipt                                                 | 第 2.1.1 节断言 PASS；C05 后 V00 正式补验                                                                                                                   |
| M0-G02 | GATE        | A+E | M0-G00,M0-H00               | evidence/control、proposal contract、prior-art、tools/bootstrap/validate-control.mjs                   | proposal hash/仓库 URL 与 registration receipt 一致；bootstrap schema PASS；不要求尚未实现的 acceptance 行 PASS                                             |
| M0-C01 | CORE        | E   | M0-G00                      | 最新稳定工具链、moon.mod、toolchain.lock、模块元数据                                                   | V01；repository/description/keywords/license 完整                                                                                                           |
| M0-C02 | EVIDENCE    | E   | M0-G00                      | tests/characterization；记录当前 parser/pack/query 行为                                                | V01 targeted；golden/black-box tests PASS                                                                                                                   |
| M0-C03 | CORE        | E   | M0-C02                      | README/claims 收敛、asset disposition 文档                                                             | V17 docs-smoke；不再宣称未达 production 的能力                                                                                                              |
| M0-C07 | EVIDENCE    | E+R | M0-C03                      | `docs/contest/positioning.md`、`docs/contest/prior-art.md`、`evidence/control/differentiation.v1.json` | 第 1.0 节四项差异逐项绑定“实现路径→机器 Gate→Demo 画面”；Tree-sitter/moonyacc/现有 MoonBit parser 的来源、许可证与边界准确；无全面替代/全面性能优越主张 |
| M0-C04 | CORE        | E+A | M0-G00                      | LICENSE、THIRD_PARTY、生成物/语料来源、仓库卫生                                                        | V17 provenance/repo-hygiene PASS                                                                                                                            |
| M0-C05 | EVIDENCE    | E   | M0-C01,M0-C02,M0-C04        | 三平台 CI、evidence CLI skeleton、artifact naming、工程侧 bootstrap 补验                               | V00/V01/control schema/render-determinism 与 H00/H01 receipt schema PASS；外部 remote fetch 在 M0-G01 复验；同 SHA jobs 全绿                              |
| M0-C06 | EVIDENCE    | A+E | M0-H00,M0-C03,M0-C04,M0-C05 | `moon publish --dry-run --frozen`、protected environment、rollback drill                               | dry-run/package placeholder/release receipt schema/权限失败路径 PASS；不得调用 V16 或制造公开版本                                                           |
| M0-E01 | EVIDENCE    | E   | M0-G00                      | corpus 来源、许可证、hash 初稿                                                                         | corpus manifest schema + provenance PASS                                                                                                                    |
| M0-E02 | ENHANCEMENT | A   | M0-G02                      | 至少 2 名外部 Pack 作者候选、测试说明与隐私边界                                                        | 招募记录存在；不含敏感信息                                                                                                                                  |

M0 出口：G0 receipt。此时没有 A01/A02/A04/A03，禁止发布 0.y.z 或声称 API/Pack 可安装；只交付可审计的 CI、控制面和 publish dry-run。

### M1：契约、格式与算法决策冻结


| ID     | Class    | DRI | Hard deps                                        | 目标路径/产物                                                                    | 验收                                                                                                                                         |
| ------ | -------- | --- | ------------------------------------------------ | -------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| M1-C01 | CORE     | E   | M0-C01,M0-C07                                    | docs/spec/ARCHITECTURE.md、api/boundaries.json、warning-exceptions.contract.json | 目录/DAG/类型所有权与第 3 节及第 1.0 节一致；语义核/宿主/导入器边界可机械检查；warning exception 精确为 code 68/two spec paths/M2-C12 expiry |
| M1-C02 | CORE     | E   | M1-C01                                           | 根 spec.mbt、API semantics、error codes                                          | 带名参数源码可编译；contract-stage V02 与 declaration-scope PASS                                                                             |
| M1-C03 | CORE     | E   | M1-C01                                           | compiler/spec.mbt                                                                | 带名参数源码可编译；compile_pack 纯函数契约与 diagnostics contract PASS                                                                      |
| M1-C04 | CORE     | E   | M1-C01                                           | docs/spec/MPACK_V1.md、golden/corrupt fixture 设计                               | header/TOC/section 与第 5 节逐字节一致                                                                                                       |
| M1-C05 | CORE     | E   | M0-C02,M1-C01                                    | docs/spec/ALGORITHMS.md、ADR-001..006、spike reports                             | green/LR1/GLR/recovery/incremental/query 各有 ADOPT/ADJUST/REJECT                                                                            |
| M1-C06 | CORE     | E   | M1-C02,M1-C03                                    | docs/spec/QUERY_V1.md、SCANNER_V1.md                                             | v1 语法、bytecode/scanner sub-ABI、fallback 规则冻结                                                                                         |
| M1-C07 | EVIDENCE | E   | M0-C05                                           | evidence manifests、thresholds、coverage/language policy、toolchain profiles     | 所有 JSON schema PASS；coverage/source-stat exclusions 有理由；命令注册表可被 control 工具读取                                               |
| M1-G01 | GATE     | E+R | M1-C01,M1-C02,M1-C03,M1-C04,M1-C05,M1-C06,M1-C07 | contract-freeze receipt                                                          | V02 + spec review；核心名称/坐标/ABI 不再变                                                                                                  |
| M1-G02 | GATE     | E+R | M0-H00,M1-C05,M1-C07                             | threshold-freeze ADR                                                             | 第 7.7/7.8 每项由 CANDIDATE 变 HARD 或有独立替代 ADR                                                                                         |

M1 之后任何公开契约变化必须先修改 spec/ADR，并视影响提升软件版本、format、runtime ABI 或 sub-ABI。

### M2：纯 MoonBit 核心实现


| ID     | Class | DRI | Hard deps                                                                                                                                          | 目标路径/产物                                                                 | 验收                                                                                                         |
| ------ | ----- | --- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| M2-C01 | CORE  | E   | M1-G01                                                                                                                                             | internal/model、所有 moon.pkg、依赖骨架                                       | V02；无 cycle/internal leak                                                                                  |
| M2-C02 | CORE  | E   | M2-C01                                                                                                                                             | root Source/TextEdit、internal/syntax/source_index                            | `moon test --target all internal/syntax`；UTF-8/CRLF/point-range PASS                                        |
| M2-C03 | CORE  | E   | M2-C01,M1-C04                                                                                                                                      | internal/pack codec/validator/checksum；只依赖 model                          | V03 round-trip/corrupt/determinism PASS                                                                      |
| M2-C04 | CORE  | E   | M2-C01,M1-C05                                                                                                                                      | internal/grammar、internal/regex：DSL parse、normalize、symbol/production IDs | grammar golden、regex automata oracle、stable source-order IDs PASS                                          |
| M2-C05 | CORE  | E   | M2-C01,M1-C06                                                                                                                                      | internal/query_ir parser/validator/bytecode                                   | Query v1 compile golden、stable bytecode PASS                                                                |
| M2-C06 | CORE  | E   | M2-C03,M2-C05,M2-C16,M1-C03                                                                                                                        | compiler facade                                                               | pure compile、logical-path validation/diagnostic order、duplicate role、artifact determinism PASS            |
| M2-C07 | CORE  | E   | M2-C02                                                                                                                                             | internal/syntax green token/node、arena、interner                             | lossless bytes、width invariant、hash collision 与 structural sharing tests PASS                             |
| M2-C14 | CORE  | E   | M2-C02,M2-C07                                                                                                                                      | internal/syntax red Node、TreeCursor、Span                                    | parent/child/field/text、Point 映射、旧 Snapshot lifetime tests PASS                                         |
| M2-C15 | CORE  | E   | M2-C02,M2-C14                                                                                                                                      | internal/syntax EditMap composition、ChangedRange                             | insert/delete/replace/batch 顺序坐标、checked mapping 与 old/new span golden PASS                            |
| M2-C16 | CORE  | E   | M2-C04                                                                                                                                             | internal/automata canonical LR(1)、conflict witness、safe compression         | unmerged oracle、stable IDs、声明/未声明 conflict、compression differential PASS                             |
| M2-C08 | CORE  | E   | M2-C01,M2-C16                                                                                                                                      | internal/engine lexer、ScannerState/VM、valid-token filtering                 | longest-match/priority/UTF-8/scanner-state canonical bytes tests PASS；运行时不 import automata              |
| M2-C17 | CORE  | E   | M2-C07,M2-C08,M2-C16                                                                                                                               | internal/engine deterministic LR array-stack fast path                        | clean JSON/expression corpus、lossless CST、oracle action trace PASS                                         |
| M2-C09 | CORE  | E   | M2-C17                                                                                                                                             | internal/engine GSS local GLR                                                 | 全 path reduction、merge key、stable score/order、三组歧义 fixtures PASS                                     |
| M2-C18 | CORE  | E   | M2-C09                                                                                                                                             | internal/engine bounded recovery                                              | cost/step/node bounds、termination、ERROR/MISSING/diagnostic recovery golden PASS                            |
| M2-C10 | CORE  | E   | M2-C15,M2-C18                                                                                                                                      | internal/engine ReuseCursor、candidate index/validation                       | entry/scanner/lookahead/bytes/fragile 五类拒绝测试与 reuse oracle PASS                                       |
| M2-C19 | CORE  | E   | M2-C06,M2-C10,M2-C17,M2-C18                                                                                                                        | incremental parse/reparse_many driver、ParseStats、A00                        | 单/batch edit、非等长右侧真实 sharing、full-vs-inc tree/diagnostic 等价、V05A PR PASS                        |
| M2-C11 | CORE  | E   | M2-C05,M2-C14                                                                                                                                      | internal/query_runtime full Query VM                                          | captures 顺序、predicate、range、match limit 与 full oracle PASS                                             |
| M2-C20 | CORE  | E   | M2-C11,M2-C15                                                                                                                                      | Query result cache、dependency index                                          | cache hit/miss、role boundary expansion、full-vs-cache captures 等价 PASS                                    |
| M2-C21 | CORE  | E   | M2-C19,M2-C20                                                                                                                                      | incremental Query invalidation/recompute                                      | full/cache/incremental captures 逐项全等；无重复/漏失 capture PASS                                           |
| M2-C12 | CORE  | E   | M2-C03,M2-C06,M2-C18,M2-C19,M2-C21                                                                                                                 | 根 Language/Parser/Snapshot/Node/Query facade；删除 warning exception         | batch/error/limit/KindId/FieldId consumer tests；无`--warn-list` 的 V01/V02 PASS；.mbti 不出现 internal 类型 |
| M2-C13 | CORE  | E   | M2-C06,M2-C12                                                                                                                                      | deprecated.mbt、旧 API migration、旧 package 收敛                             | 旧字符串 API 不在 README；兼容测试/删除版本明确                                                              |
| M2-G01 | GATE  | E+R | M2-C01,M2-C02,M2-C03,M2-C04,M2-C05,M2-C06,M2-C07,M2-C08,M2-C09,M2-C10,M2-C11,M2-C12,M2-C13,M2-C14,M2-C15,M2-C16,M2-C17,M2-C18,M2-C19,M2-C20,M2-C21 | runtime-core receipt                                                          | V01、V02、V03、V05A(PR)、V07A(PR) 全 PASS                                                                    |

M2 每个算法优化必须保留“关闭优化”的 oracle 路径，供 differential 使用；不得在同一 PR 同时重写正确性结构和性能优化。

### M3：真实语言与压倒性证据


| ID     | Class    | DRI | Hard deps                                                      | 目标路径/产物                                                                        | 验收                                                                              |
| ------ | -------- | --- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| M3-C01 | EVIDENCE | E   | M0-E01,M2-C06                                                  | corpus/differential/digest manifests 完整化                                          | provenance 100%，所有 hash 固定                                                   |
| M3-C02 | CORE     | E   | M2-G01                                                         | languages/json                                                                       | JSON legal/illegal/Unicode/recovery oracle + V03 PASS                             |
| M3-C03 | EVIDENCE | E   | M2-C12,M2-C21                                                  | canonical digest v1 工具                                                             | native repeatability、schema golden PASS                                          |
| M3-C04 | EVIDENCE | E   | M2-C19,M3-C01,M3-C02,M3-C03,M3-C06                             | production deterministic edit generator/minimizer                                    | V05B PR + nightly mismatch=0                                                      |
| M3-C05 | EVIDENCE | E   | M2-C03,M2-C18,M2-C21,M3-C06                                    | production Pack/parser/query fuzz                                                    | V07B nightly + release PASS                                                       |
| M3-C06 | CORE     | E   | M2-G01,M3-C02                                                  | production languages/moonbit、A01 assemble-pack、_build/work/A01/packs/moonbit.mpack | 不允许 ambiguous-conflict 放行；A01 provenance/SHA 完整；Pack build deterministic |
| M3-C07 | EVIDENCE | E   | M3-C01,M3-C06                                                  | MoonParse/core/community 真实 MoonBit corpus                                         | V04 clean=100%；错误集符合诊断                                                    |
| M3-C08 | EVIDENCE | E   | M1-G02,M3-C06,M3-C07                                           | Native benchmark 与 Pack size/repro harness                                          | V08A、V09 reference profile PASS                                                  |
| M3-C09 | EVIDENCE | E   | M2-G01,M3-C07                                                  | 10k edit memory soak、limits/adversarial suite                                       | V07B release；RSS/retained-node 门 PASS                                           |
| M3-G01 | GATE     | E+R | M3-C01,M3-C02,M3-C03,M3-C04,M3-C05,M3-C06,M3-C07,M3-C08,M3-C09 | Native/core evidence bundle v1                                                       | V03、V04、V05B、V07B、V08A、V09 release profile 全 PASS                           |

M3 的 evidence harness 从此验证所有 adapter 与 enhancement；任何宿主不得用自己的结果规范代替。

### M4：薄适配器与冠军体验


| ID     | Class       | DRI | Hard deps                          | 目标路径/产物                                                         | 验收                                                        |
| ------ | ----------- | --- | ---------------------------------- | --------------------------------------------------------------------- | ----------------------------------------------------------- |
| M4-C01 | CORE        | E   | M2-G01,M3-C06                      | cmd/moonparse：pack init/check/test/build/inspect、parse/query/verify | A01 + V10；逻辑只调用 root/compiler                         |
| M4-C02 | CORE        | E   | M2-G01,M3-C06                      | wasm 高层 ABI、唯一 JS facade、resource manager、A02 assemble:wasm    | A02 只消费 A01 与同 SHA runtime；V11；不含 Grammar compiler |
| M4-C03 | EVIDENCE    | E   | M3-G01,M4-C01,M4-C02               | Native/WASM cross-backend suite                                       | V06 mismatch=0                                              |
| M4-C04 | CORE        | E   | M3-G01,M4-C02,M4-C03               | demo 三栏 UI、固定 scenario、A04 离线 artifact、录屏脚本              | V13；30 秒黄金路径 PASS；A04 可被 A03 原样收录              |
| M4-E01 | ENHANCEMENT | E   | M2-C12,M2-C21,M4-C02               | adapters/lsp 薄宿主                                                   | V12；无 MoonBit workspace 特化                              |
| M4-G01 | GATE        | E+R | M4-C01,M4-C02,M4-C03,M4-C04,M4-E01 | product-loop receipt                                                  | V06、V08B、V10、V11、V12、V13；clean machine demo PASS      |

LSP 只提供 diagnostics、semantic tokens、outline、folding、document highlight 和文档内 navigation。任何 workspace/completion/formatter 功能必须另开 post-v1 ADR。

### M5：生态采用与第三方证明


| ID     | Class       | DRI | Hard deps                          | 目标路径/产物                                           | 验收                                                                                                                                  |
| ------ | ----------- | --- | ---------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| M5-C01 | CORE        | E   | M1-G01,M4-C01                      | templates/language-pack、Pack Author SDK、tested README | V14 sdk-smoke；全新仓库端到端 PASS                                                                                                    |
| M5-E01 | ENHANCEMENT | A+R | M0-E02,M5-C01                      | 外部作者可用性测试与问题闭环                            | 一名未参与开发者完成 init/test/build/publish-dry-run；receipt PASS                                                                    |
| M5-E02 | ENHANCEMENT | E   | M2-C06,M3-G01                      | tools/migrate/treesitter 单向 importer                  | 3 个真实 grammar compatibility report；支持的语义进入 Pack、未支持项以稳定诊断显式报告；无静默丢失，且 importer 不进入 runtime 依赖图 |
| M5-E03 | ENHANCEMENT | E   | M5-C01,M3-G01                      | languages/showcase 第二门非玩具语言                     | corpus/query/bench/license 与 MoonBit 同质量门                                                                                        |
| M5-C02 | EVIDENCE    | E   | M5-E01,M5-E02,M5-E03               | docs/contest/ecosystem-evidence.md                      | 每个主张链接到 Pack/release/receipt                                                                                                   |
| M5-G01 | GATE        | E+R | M5-C01,M5-C02,M5-E01,M5-E02,M5-E03 | ecosystem receipt                                       | V14 全 PASS；外部采用非作者自证                                                                                                       |

Tree-sitter import、第二语言和 LSP 是增强线，可以并行，但不能阻塞更低层核心持续集成；最终“冠军版”仍要求它们在 M6 汇合并通过。它们的唯一论证职责是证明 `.mpack` 的可移植性和作者体验，绝不把 MoonParse 描述成 Tree-sitter 的替身或兼容层。

### M6：RC、正式发布与决赛交付


| ID     | Class    | DRI   | Hard deps            | 目标路径/产物                                                                                               | 验收                                                                                                              |
| ------ | -------- | ----- | -------------------- | ----------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| M6-C01 | EVIDENCE | E     | M3-G01,M4-G01,M5-G01 | RESULTS.md、README 5 分钟路径、contribution/prior-art/acceptance 文档                                       | 所有数字来自同候选 SHA evidence；第 1.0 节四项主张逐项链接实现/Gate/Demo；按下方 authoring 命令生成并提交矩阵     |
| M6-C02 | CORE     | E+A   | M4-G01,M5-G01        | semver/deprecation/security/contribution/release docs；旧 Pack 迁移演练                                     | maintenance audit + migration PASS                                                                                |
| M6-C05 | EVIDENCE | E+A   | M6-C01,M6-C02        | 最终 tracked RESULTS、5–7 分钟答辩稿/录屏脚本、固定输入/hash；_build/work/M6-C05/media 离线视频/provenance | 所有 tracked 内容在候选入默认分支前提交；视频只引用同 candidate SHA，hash 冻结后供 A03 收录                       |
| M6-H00 | HUMAN    | A+E   | M0-H00,M6-C05        | candidate fast-forward 到 GitHub/Gitlink 默认分支、remote receipt                                           | 两默认分支精确等于 frozen candidate SHA；若平台产生新 merge SHA 则退回 PREPARED、重跑证据                         |
| M6-G01 | GATE     | A+E+R | M6-H00               | prepublish acceptance/proposal matrix                                                                       | 所有 V00–V14/V17 receipt 同默认分支 SHA；V15A prepublish 全 PASS、postpublish 全 PENDING_EXTERNAL                |
| M6-C03 | EVIDENCE | E     | M6-G01,M6-C05        | A03、package、evidence archive、release-manifest、SHA256SUMS                                                | 同 SHA assembly 两次字节一致；A03 candidate 等于双默认分支；V16A 输入齐全                                         |
| M6-H01 | HUMAN    | A+E   | M6-C03               | v1.0.0-rc.N annotated tag、draft prerelease、A03 assets、immutable release-context                          | 经作者批准创建；context/tag/artifact SHA 一致；V16A PASS，状态 RC_VERIFIED                                        |
| M6-H02 | HUMAN    | A+E   | M0-H00,M6-H01        | protected mooncakes publish、V16B registry install receipt                                                  | 只发布 context 中 module/version；下载 hash/digest 等于 A03；状态 POST_PUBLISH_VERIFIED                           |
| M6-H03 | HUMAN    | A+E   | M6-H02               | context expected final annotated tag、GitHub Release、A03 assets                                            | final tag=RC SHA；Release 下载后 manifest/payload hash 一致；状态 RELEASE_PUBLISHED                               |
| M6-H04 | HUMAN    | A+E   | M6-H03               | Gitlink final tag、A03 Demo deploy、离线备份、V16C                                                          | 双远端/tag/default/Release/Demo/backup 全部匹配 context；状态 FINAL_VERIFIED                                      |
| M6-G03 | GATE     | A+E+R | M6-H04               | V15B final acceptance receipt/report                                                                        | hard/proposal 全 PASS，PENDING_EXTERNAL=0；不改 tracked 文件                                                      |
| M6-G02 | GATE     | A+E+R | M6-G03,M6-C05        | champion-final receipt、postpublish final attestation/upload receipt                                        | 全 Gate 同 SHA PASS；attestation 绑定 A03+V15B/V16B/V16C，上传后下载 hash 一致；状态转 FROZEN 且不改 tracked 文件 |

M6-C01 的受控 authoring 命令是：

~~~text
moon run tools/quality -- control render --acceptance evidence/control/acceptance.v1.json --proposal evidence/control/proposal-contract.v1.json --out docs/contest/acceptance-matrix.md
~~~

生成结果必须经过评审并提交；renderer 的 tracked 输出不得包含时间戳、绝对路径或当前 SHA 等易变字段。后续 V15A/V15B 只执行 `--check`。

## 10. 依赖关系与并行策略

核心夺冠链：

~~~text
M0 history/engineering
  -> M1 contract freeze
    -> M2 runtime/compiler
      -> M3 evidence + MoonBit Pack
        -> M4 CLI/WASM/Demo
          -> M6 release
~~~

并行前移：

~~~text
M0-E01 corpus/provenance ---------------------> M3
M0-E02 external recruitment -> M5-C01 --------> M5
M1 API/Query contract -> thin LSP ------------> M4-E01
M1 Pack + M2 compiler -> Tree-sitter import --> M5-E02
M3 evidence harness -> validates every adapter/enhancement
M4-G01 + M5-G01 ------------------------------> M6-G01
~~~

禁止的伪并行：

- WASM/LSP/Demo 先复制尚未稳定的核心语义。
- 为赶 UI 先引入第二套 JSON tree 或 Query evaluator。
- 在 differential harness 之前优化 incremental/cache。
- 在 Pack ABI 冻结之前发布稳定 v1。
- 把外部作者测试留到所有开发完成后才招募。

## 11. 发布顺序与不可回滚 Saga

### 11.1 两种正式发布对象

1. 1.0.0-rc.N：M0–M5 全部门、M6 tracked 交付和 A03 完成后的冠军候选；任何源码/配置/tracked 文档变化必须产生新 RC。
2. 1.0.0：必须与最终通过的 RC 指向同一 commit；若 SHA 变化则重新 RC。

M0 只做 publish dry-run，不发布 0.y.z，避免在 API/Pack/WASM 尚不存在时制造不可撤回的 registry 历史。若 registry 不支持 prerelease 语义，不猜测；RC 可以只作为不可变 GitHub draft prerelease，registry 仅发布最终 1.0.0，具体方式由 DRI-A 在 release ADR 中确认。

### 11.2 状态机

~~~text
PREPARED
-> RC_TAGGED
-> RC_VERIFIED
-> REGISTRY_PUBLISHED
-> POST_PUBLISH_VERIFIED
-> FINAL_TAGGED
-> RELEASE_PUBLISHED
-> MIRRORED
-> FINAL_VERIFIED
-> CONTROL_VERIFIED
-> FROZEN
~~~

每一步写入 release-receipt.json。

### 11.3 正式流程

1. 完成 M6-C01/C02/C05；所有 tracked 代码、配置、RESULTS、答辩稿和录屏脚本已提交，候选 worktree clean，模块版本已是 1.0.0。
2. 在该 SHA 生成 A00/A01/A02/A04，执行 V00–V14 与 V17 release profile；V05A/V05B、V07A/V07B、V08A/V08B 均显式 PASS，nightly receipt 也是同 SHA。此时不执行 V15B/V16*。
3. M6-H00 仅以 fast-forward 将候选送入 GitHub/Gitlink 默认分支。若平台生成新 merge SHA，立即返回 PREPARED，在新 SHA 重做第 1–2 步。
4. 两默认分支精确等于 candidate 后执行 V15A：所有 prepublish 行 PASS，H05/H09/H15 等 postpublish 行 PENDING_EXTERNAL；M6-G01 核对全部 prepublish receipt 同 SHA。
5. 执行 A03 两次；比较 payload、release-manifest 和 SHA256SUMS 后 promote 唯一 canonical bundle。A03 candidate SHA 必须等于两个默认分支。
6. 创建不可变 v1.0.0-rc.N annotated tag 和 draft GitHub prerelease，上传 A03 assets。
7. 从 A03 RC artifact 在全新环境执行 V16A：安装、parse、edit、Query、Demo smoke；PASS 后状态才进入 RC_VERIFIED。至此 registry publish 的完整前置门闭合。
8. 若任何代码、配置、tracked 文档或证据输入变化，返回 PREPARED 并产生新 RC；不得创建 final tag。
9. M6-H02 的受保护 publish environment 从已验证 RC SHA 执行 `moon publish --frozen --manifest-path _build/release/package/moon.mod`；人工 approval 绑定 release-context，日志脱敏且命令只允许一次。随后执行 V16B，从 mooncakes 全新 moon add，按 A03 manifest 核对 package/Pack fingerprint 与示例 digest，状态进入 POST_PUBLISH_VERIFIED。
10. 只有 V16B PASS 后，M6-H03 才创建并推送 v1.0.0 final tag、发布 GitHub Release并上传 A03 payload；全部对象必须指向同一 RC SHA。
11. M6-H04 同步 Gitlink final tag，Demo 只部署 A03 demo bytes并验证离线备份；执行 V16C 后进入 FINAL_VERIFIED。
12. M6-G03 执行 V15B 后进入 CONTROL_VERIFIED；此时双远端/default branch/tag/release/Demo 与全部 acceptance/proposal 行必须匹配 A03，但尚不写 FROZEN。
13. M6-G02 核对 V00–V14、V15A、V15B、V16A、V16B、V16C、V17（含 V05A/V05B、V07A/V07B、V08A/V08B）为同一 SHA，生成不自引用的 final attestation，上传后重新下载核 hash；完成才写为 FROZEN。

失败处理：

- REGISTRY_PUBLISHED 前：停止，不移动 RC tag；修复后产生新 RC。
- REGISTRY_PUBLISHED 后：不得删除/覆盖已发布版本；若 post-publish 失败，放弃为该 SHA 创建 final tag并发布 patch 版本。
- FINAL_TAGGED 后：只允许同 SHA 重试外部步骤；任何内容修复必须发布更高 patch。
- 不通过 force-push 或改 tag 伪装同一 release。
- GitHub、Gitlink、mooncakes 是跨系统 saga，不宣称事务原子性。

## 12. 每次 PR 的强制规则

1. PR 标题必须含工作包 ID，例如 M2-C06。
2. 一个 PR 只推进一个原子目标。
3. 描述中列出 hard deps、目标路径、验证命令和 evidence path。
4. 公共 API 先改 spec.mbt；Pack/Query/scanner ABI 先改对应 spec 与 golden。
5. black-box test 默认；white-box 只验证内部不变量。
6. Snapshot 更新必须人工审查，不允许 CI 自动接受。
7. 优化 PR 必须保留 oracle 路径并附前后 raw benchmark。
8. threshold、corpus、实现三者不得在同一 PR 同时改变。
9. generated artifact 必须有生成命令、source SHA 和 reproducibility check。
10. 不混入无关格式化、批量重命名或网站改动。
11. 完成前运行目标工作包命令；合并前 required CI 必须是同 SHA。
12. 对用户、兼容或来源有影响时更新 CHANGELOG、migration、THIRD_PARTY。

## 13. 第一批施工队列

在不执行外部 push/publish 的前提下，启动顺序固定如下：

1. Bootstrap B00：在 worktree 外保存可恢复 dirty archive，从 d8bffb8 创建 sibling champion/mainline worktree。
2. M0-G00：在 champion worktree 只引入 .gitignore 与 todo/plan.md，确认计划可跟踪。
3. M0-H00：先核验报名资格、申报材料 hash 和外部平台。
4. M0-H01 与 M0-G02 并行：经作者批准推送冻结 refs；同时把已核验申报承诺拆成 control schema。
5. M0-G01：核对远端可 fetch 的锚点、champion branch 和 dirty-assets recoverability。
6. M0-C01：升级并锁定 MoonBit/Node/browser 工具链，迁移 moon.mod，补模块元数据。
7. M0-C02：为当前可复用资产建立 characterization tests，先记录行为再迁移。
8. M0-C04 与 M0-E01 并行：完成第三方、生成物、corpus 的来源与许可证清单。
9. M0-C05：建立严格三平台 CI、gate wrapper 与 bootstrap 补验；M0-C06 只做 publish dry-run。
10. M1-C01：先写 Architecture、boundary config 与临时 warning exception。
11. M1-C02/C03/C04/C05 并行：写根/compiler spec、Pack 规格与算法 spike。
12. M1-C06 在 C02/C03 后冻结 Query/scanner sub-ABI；M1-C07 并行冻结 evidence manifests。
13. M1-G01/G02：冻结契约和阈值；随后才创建 internal/* 新实现骨架。
14. M2 按依赖表逐个 PR 前进，不从 adapter 或 UI 倒逼核心契约。

### 13.1 开工前需要 DRI-A 提供或确认的外部输入

- 实际提交给赛事方的申报书原文或 PDF。
- 不含个人信息的有效报名/参赛资格状态、提交时间证明、申报书 SHA-256，以及赛事记录中的 GitHub/Gitlink URL。
- GitHub 默认分支设置与可用仓库权限。
- Gitlink 仓库 URL、默认分支和同步方式。
- mooncakes 账号、目标模块名是否已有历史发布、publish 权限。
- 可用于固定性能门的机器是否长期可复现。
- 至少两名外部 Pack 作者候选的联系与隐私授权。

这些输入只会阻塞对应 HUMAN/GATE 工作包，不授权工程执行者猜测凭据、代发远端、删除 release 或修改赛事材料。

### 13.2 模块名最终确认

本计划以当前模块名 caiklonghuan/MoonParse 为冻结候选。M0-C01 必须查询 mooncakes 与现有用户状态：

- 若没有既有发布或冲突，正式冻结 caiklonghuan/MoonParse。
- 若发现另一个已公开模块名或历史消费者，M0-C01 进入 BLOCKED，由 DRI-A 作一次性 ADR；禁止实现过程中自行改变大小写或路径。
- 第一个公开 RC 或 registry 版本发布之后，模块名不得再改变。

## 14. 最终交付清单

### 14.1 技术核心

- [ ]  根包 spec.mbt 与 compiler/spec.mbt 通过检查，公开 .mbti 无 internal 类型。
- [ ]  .mpack v1 有逐字节规范、golden、corrupt、determinism 和 compatibility tests。
- [ ]  Green tree 无绝对位置，CST lossless，旧 Snapshot 永不被 reparse 修改。
- [ ]  reparse/reparse_many 单/batch edit 语义唯一，EditMap composition、CRLF/UTF-8 边界和 changed ranges 有 black-box golden。
- [ ]  非等长编辑可真实共享右侧 subtree。
- [ ]  canonical LR(1) oracle、局部 GLR、GSS path 和 bounded recovery 全部有机器门。
- [ ]  错误输入返回可查询 Snapshot；只有非法 Pack/edit/资源上限是 checked failure。
- [ ]  Query full/cache/incremental 一致，Native/WASM canonical digest 一致。

### 14.2 工程与赛事硬门

- [ ]  7/10 前有效申报/参赛资格、proposal hash 和双仓 URL 已由无敏感信息 receipt 核验。
- [ ]  GitHub/Gitlink 公开，默认分支与 tag 指向同一 release SHA。
- [ ]  MoonBit 为主要实现语言，赛期贡献从 contest baseline 可重建。
- [ ]  Linux/macOS/Windows 的 strict check/build/test、fmt、info、consumer、docs 全绿。
- [ ]  README 的 5 分钟安装、parse、edit、Query 示例在 clean environment 通过。
- [ ]  LICENSE、THIRD_PARTY、corpus/generated provenance 完整。
- [ ]  mooncakes 正式包和 post-publish install smoke 通过。
- [ ]  仓库没有 out/cache/临时文件和未声明 release binary 污染。
- [ ]  acceptance 与 proposal hard rows 全部 PASS。

### 14.3 正确性、性能与资源证据

- [ ]  固定 MoonBit corpus clean rate 100%。
- [ ]  PR 20,000、nightly/release 1,000,000 edits 零 mismatch。
- [ ]  Pack/parser/query fuzz 零 panic、hang、越界和不可复现失败。
- [ ]  10KB/100KB/1MB raw benchmark、机器、工具链、SHA 和 samples 完整。
- [ ]  thresholds.v1.json 的 HARD 性能和 size 门全部通过。
- [ ]  10k edit 内存不随历史 Snapshot 线性增长。
- [ ]  核心 package coverage >= 90%、全 MoonBit 非生成源码 >= 80%，所有排除项有理由。
- [ ]  每个 README/RESULTS 数字可追到同 SHA artifact。

### 14.4 产品与生态

- [ ]  `positioning.md` 与 `prior-art.md` 明确 MoonParse 的四项可验证差异；不使用“取代 Tree-sitter / 全面更快 / 全面更完整”之类不可证明的比较性承诺。
- [ ]  评委可沿“真实 `.mbt` 破损编辑 → CST/Query 可用 → full/inc 等价回执 → Native/WASM 同 digest → `.mpack` 作者复用”一条路径理解全部产品价值；算法、importer 和第二语言不抢占这一叙事。
- [ ]  production MoonBit Pack 和 JSON oracle 通过全部门。
- [ ]  CLI 与 WASM 只消费稳定核心；无第二套语义。
- [ ]  薄 LSP 通过协议与 digest E2E，无 MoonBit workspace 硬编码。
- [ ]  三栏 Demo、离线 release、固定 scenario 和录屏均可用。
- [ ]  Pack Author SDK 在全新仓库完成 init/check/test/build/publish-dry-run。
- [ ]  3 个真实 Tree-sitter grammar 生成可信 compatibility report。
- [ ]  第二门真实语言通过同一 Pack/runtime/query/evidence 门。
- [ ]  至少一个外部作者独立完成 Pack 流程并闭环问题。

### 14.5 发布与答辩

- [ ]  v1.0.0 与最终 RC 指向同一 SHA。
- [ ]  release saga 状态为 FROZEN，release-receipt.json 完整。
- [ ]  A03/Release 包含 Pack、WASM/JS/ABI、Demo、离线视频、SHA256SUMS、prepublish evidence；postpublish final attestation 已上传并回读验 hash。
- [ ]  RESULTS.md 只列已验证事实，不混入目标或 roadmap。
- [ ]  5–7 分钟答辩只讲生态缺口、一份 Pack、核心算法、真实编辑、数据和采用。
- [ ]  30 秒黄金路径至少完整演练三次；现场故障可切离线视频。
- [ ]  已准备“为何不是 moonyacc / Tree-sitter binding、增量如何证明、恢复如何终止、来源如何合规”的证据页。

## 15. 第一名质量门

最终版本必须同时满足：

1. 技术不可替代：纯 MoonBit、确定性 .mpack、lossless 容错、真正增量、Query 跨端一致。
2. 工程无短板：严格 CI、稳定契约、兼容、合规、真实 corpus、资源上限、可复现发布。
3. 生态可采用：第三方作者能创建 Pack，真实第二语言和迁移工具证明非 MoonBit 特化。
4. 展示有压倒性：错误代码仍可用、编辑只重算局部、同一 Pack 跨端一致，实时数字与 release 证据吻合；评委不必先理解 GLR、GSS 或 Tree-sitter 才能理解作品价值。

任何一项未 PASS，状态只能是“继续实现”，不能提前称为冠军版完成。

第一名不是功能数量之和，而是一个评委可以独立安装、运行、破坏、编辑、测量、复现并验证的深闭环；更进一步，这个闭环必须清楚回答：**为什么它只能由 MoonParse 以这种纯 MoonBit + Pack ABI + 增量等价 + 跨端复现的组合来完成。**
