# scripts 开发脚本说明

`scripts/` 是 MoonParse 的开发辅助工具包，统一通过下面的入口运行：

```bash
moon run scripts -- <subcommand> [options]
```

它主要覆盖两类需求：

- 正确性验证：随机生成输入、做单次变异、检查增量解析与全量重解析是否一致。
- 性能回归：测量 parse table 生成、解析、增量解析、序列化/反序列化的耗时和体积。

当前脚本只面向内置语法：

- `json`
- `expression`

通用帮助命令：

```bash
moon run scripts -- help
moon run scripts -- help fuzz-json
moon run scripts -- help mutate-input
```

## 快速开始

最常用的几个命令：

```bash
# 1) 跑 JSON fuzz
moon run scripts -- fuzz-json --count 1000 --seed 61093

# 2) 跑增量一致性 fuzz
moon run scripts -- fuzz-incremental --grammar both --count 200 --seed 78121

# 3) 生成一个可复现的单次变异样本
moon run scripts -- mutate-input --grammar expression --seed 42 --kind replace-token

# 4) 看解析性能
moon run scripts -- bench-parse --grammar both --runs 10

# 5) 看增量解析相对全量重解析的收益
moon run scripts -- bench-incremental --grammar json --size medium --runs 10

# 6) 看表序列化体积和序列化性能
moon run scripts -- bench-serialize --grammar both --runs 5
```

## 子命令总览

| 子命令 | 作用 | 典型场景 |
| --- | --- | --- |
| `fuzz-json` | 针对 JSON 做确定性 guided fuzz，可选继续做 mutation fuzz | 验证 JSON 语法和错误恢复稳定性 |
| `mutate-input` | 生成或接收一条输入，做一次可复现变异，并打印 edit 信息 | 本地复现某个 fuzz 样本 |
| `fuzz-incremental` | 针对 `json` / `expression` 跑单次编辑增量 fuzz | 检查增量解析结果是否等于全量重解析 |
| `bench-parse` | 测量 parse table 生成和全量解析性能 | 做 parser 性能回归 |
| `bench-incremental` | 对固定编辑场景比较增量解析 vs 全量重解析 | 评估增量收益 |
| `bench-serialize` | 测量表的序列化/反序列化耗时和体积 | 评估缓存体积和加载成本 |

## 子命令详解

### `fuzz-json`

用途：

- 生成合法 JSON 样本并验证其能稳定解析。
- 对每个样本进一步做 6 种单次变异，检查解析器不会崩溃。

命令：

```bash
moon run scripts -- fuzz-json [--seed N] [--count N] [--depth N] [--width N] [--guided-only]
```

参数：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--seed` | `61093` | 确定性随机种子，用于复现 |
| `--count` | `1000` | 生成多少个 guided base 样本 |
| `--depth` | `3` | 生成器深度 |
| `--width` | `3` | 生成器宽度 |
| `--guided-only` | 关闭 | 只验证合法 guided JSON，不做变异 fuzz |

成功输出示例：

```text
fuzz-json ok: seed=61093 samples=1000 mutation_cases=6000 recovered=1234 err=56
```

字段含义：

- `samples`：成功验证的合法 base 样本数。
- `mutation_cases`：实际执行的变异总数，通常等于 `samples * 6`。
- `recovered`：变异后解析成功，但树中出现 `ERROR` / `MISSING` 等恢复结果。
- `err`：变异后直接返回解析错误的次数。

适合什么时候用：

- 改了 JSON 语法或 runtime 恢复逻辑后，先跑一轮稳定性验证。
- 想快速看错误输入下是否会 panic 或产生空输出。

### `mutate-input`

用途：

- 生成一条合法输入，或者直接接收你给的输入。
- 对它做一次确定性单点变异。
- 打印变异位置、替换文本、原始输入和变异后输入，方便本地复现。

命令：

```bash
moon run scripts -- mutate-input --grammar json|expression [--input TEXT] [--seed N] [--kind KIND] [--depth N] [--width N]
```

参数：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--grammar` | 无 | 必填，只能是 `json` 或 `expression` |
| `--input` | 空 | 指定基础输入；不传时脚本会先生成一条合法样本 |
| `--seed` | `1` | 用于生成和变异的随机种子 |
| `--kind` | 随机 | 指定变异类型 |
| `--depth` | `3` | 仅在未传 `--input` 时生效 |
| `--width` | `3` | 仅在未传 `--input` 时生效 |

支持的变异类型：

- `delete-char`
- `delete-token`
- `replace-token`
- `scramble-bracket`
- `insert-garbage`
- `truncate-prefix`

说明：

- 解析器内部还接受 `scramble-paren` 作为别名。
- 如果不传 `--kind`，脚本会根据 `seed` 随机选一种。

输出字段：

```text
grammar: expression
base-generated: true
seed: 42
next-seed: 2027382
mutation: replace-token
start-byte: 5
old-end-byte: 8
replacement: "foo"
base: "n+n*n"
mutated: "n+foo*n"
```

字段含义：

- `base-generated`：`true` 表示基础输入由脚本生成，`false` 表示来自 `--input`。
- `next-seed`：本轮变异后的下一个种子，适合继续串联复现。
- `start-byte` / `old-end-byte` / `replacement`：可直接映射到一次 `InputEdit` 的核心三元组。

适合什么时候用：

- fuzz 失败后，想单独拿到一条最小上下文样本。
- 调试增量解析时，想清楚知道 edit 落在什么字节范围。

### `fuzz-incremental`

用途：

- 对 `json`、`expression` 或两者一起跑单次编辑 fuzz。
- 每个 base 样本都会应用 6 种变异。
- 每次变异都检查：增量解析结果是否等于全量重解析。

命令：

```bash
moon run scripts -- fuzz-incremental [--grammar json|expression|both] [--seed N] [--count N] [--depth N] [--width N]
```

参数：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--grammar` | `both` | 语法选择：`json`、`expression`、`both` |
| `--seed` | `78121` | 确定性随机种子 |
| `--count` | `1000` | 每个语法生成多少个 base 样本 |
| `--depth` | `3` | 生成器深度 |
| `--width` | `3` | 生成器宽度 |

成功输出示例：

```text
fuzz-incremental json ok: seed=78121 samples=1000 mutation_cases=6000 clean=4200 recovered=1700 err=100
fuzz-incremental expression ok: seed=78121 samples=1000 mutation_cases=6000 clean=5100 recovered=900 err=0
```

字段含义：

- `clean`：增量与全量都得到干净且一致的树。
- `recovered`：增量与全量都得到带恢复节点的同构结果。
- `err`：增量与全量都返回同一个错误结果。

适合什么时候用：

- 改了 `runtime/apply_edit`、`shift_node`、`is_reusable` 之后做回归。
- 需要批量验证单次编辑情况下的增量正确性。

### `bench-parse`

用途：

- 测量 parse table 生成耗时。
- 测量不同输入规模下的全量解析耗时。
- 测量错误输入场景下的解析耗时。
- 同时输出 table 的 JSON / 二进制大小。

命令：

```bash
moon run scripts -- bench-parse [--grammar json|expression|both] [--runs N]
```

参数：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--grammar` | `both` | 语法选择：`json`、`expression`、`both` |
| `--runs` | `10` | 每个场景采样次数 |

输出格式：

```text
bench  name=<grammar>/<scenario>  mean=…  median=…  p95=…  min=…  max=…  runs=…
size   name=<grammar>/table_size  json_bytes=…  bin_bytes=…  compression=…
```

测量场景：

- `<g>/table_gen`
- `<g>/full_parse/small`
- `<g>/full_parse/medium`
- `<g>/full_parse/large`
- `<g>/error_parse/...`
- `<g>/table_size`

适合什么时候用：

- 改了 grammar IR / tablegen / runtime 主路径后做性能回归。
- 想看某次改动是否把表大小打爆。

### `bench-incremental`

用途：

- 在固定编辑模型下比较增量解析与全量重解析。
- 输出两组耗时和一个比例值：增量耗时占全量耗时的百分比。

命令：

```bash
moon run scripts -- bench-incremental [--grammar json|expression|both] [--runs N] [--size small|medium|large]
```

参数：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--grammar` | `both` | 语法选择：`json`、`expression`、`both` |
| `--runs` | `10` | 每个场景采样次数 |
| `--size` | `medium` | base 输入大小类：`small=256B`、`medium=10KB`、`large=100KB` |

输出格式：

```text
bench  name=<g>/incremental/<edit>  ...
bench  name=<g>/full_parse/<edit>   ...
ratio  name=<g>/ratio/<edit>        inc_pct_of_full=...%
```

编辑场景：

- `insert_begin`：在开头插入一个字符。
- `insert_middle`：在中间插入一个字符。
- `insert_end`：在末尾插入一个字符。
- `replace_one`：在中间替换一个字符。
- `large_replace`：替换约 20% 输入，属于大范围破坏性编辑。

怎么解读结果：

- `inc_pct_of_full` 越小越好。
- 对 `large_replace`，增量不一定更快，这是正常情况。

### `bench-serialize`

用途：

- 测量 table 二进制序列化/反序列化性能。
- 测量 table JSON 序列化/反序列化性能。
- 对比 JSON 大小和二进制大小。

命令：

```bash
moon run scripts -- bench-serialize [--grammar json|expression|both] [--runs N]
```

参数：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--grammar` | `both` | 语法选择：`json`、`expression`、`both` |
| `--runs` | `10` | 每个场景采样次数 |

输出格式：

```text
bench  name=<g>/serialize        ...
bench  name=<g>/deserialize      ...
bench  name=<g>/table_to_json    ...
bench  name=<g>/table_from_json  ...
size   name=<g>/table_size  json_bytes=...  bin_bytes=...  compression=...x
```

说明：

- `serialize` / `deserialize` 对应二进制表。
- `table_to_json` / `table_from_json` 对应 JSON 文本。
- `compression` 表示 JSON 相比二进制大多少倍。
- 如果只想做一次单点体积回归，可以用 `--runs 1`。

## 常见工作流

### 1. 改完 runtime 后先做正确性回归

```bash
moon run scripts -- fuzz-incremental --grammar both --count 200 --seed 78121
```

建议在这些改动后优先跑：

- `runtime/` 的增量编辑逻辑
- `grammar/` / `tablegen/` 的归约行为
- `grammars/` 中内置 grammar 的规则调整

### 2. fuzz 失败后定位单个样本

第一步，保留失败时打印出的 `seed`、`grammar`、`mutation`。

第二步，用 `mutate-input` 生成同一类样本：

```bash
moon run scripts -- mutate-input --grammar json --seed 42 --kind replace-token
```

如果你已经知道基础输入，也可以直接传：

```bash
moon run scripts -- mutate-input --grammar expression --input "n+n*n" --kind delete-token --seed 42
```

### 3. 看增量解析到底值不值得

```bash
moon run scripts -- bench-incremental --grammar both --size medium --runs 10
```

重点看每个编辑场景下的：

- `incremental/<edit>`
- `full_parse/<edit>`
- `ratio/<edit>`

### 4. 追踪 parse table 体积回归

```bash
moon run scripts -- bench-serialize --grammar both --runs 1
moon run scripts -- bench-parse --grammar both --runs 1
```

适合在：

- grammar 规则大改之后
- table 编码格式调整之后
- WebAssembly 分发体积变大时

## 输出与退出码约定

输出约定：

- fuzz 类命令：成功时输出一行 `... ok: ...` 汇总；失败时打印可复现上下文。
- bench 类命令：输出 `key=value` 风格的稳定文本，适合重定向到文件做前后对比。
- `mutate-input`：输出单条样本的 edit 元数据和前后文本。

退出码约定：

- `0`：成功。
- 非 `0`：失败。
- 参数错误通常会打印 usage，并返回非零值。

## 文件分工

| 文件 | 作用 |
| --- | --- |
| `main.mbt` | 统一入口和子命令分发 |
| `fuzz_json.mbt` | JSON guided fuzz / mutation fuzz |
| `fuzz_incremental.mbt` | 增量解析一致性 fuzz |
| `mutate_input.mbt` | 共享生成器、变异器和 `mutate-input` 子命令 |
| `bench_parse.mbt` | parse table 生成和全量解析 benchmark |
| `bench_incremental.mbt` | 增量解析 vs 全量重解析 benchmark |
| `bench_serialize.mbt` | 表序列化/反序列化 benchmark |
| `bench_util.mbt` | benchmark 统计与采样基础设施 |
| `exit*.mbt` | 原生 / wasm 的进程退出适配 |