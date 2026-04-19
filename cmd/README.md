# cmd 模块说明

## 1. 模块定位

`cmd/` 是 MoonParse 的命令行工具链模块，负责把 `grammar/`、`tablegen/`、`runtime/`、`query/` 组织成统一的命令行入口。

本模块主要提供以下能力：

- 解析全局参数与子命令参数；
- 执行 Grammar 校验、格式化、ParseTable 生成与分发产物构建；
- 执行源码解析、结构化查询、corpus 测试与内部结构 dump；
- 生成 JS/WASM 分发胶水；
- 输出统一的人类可读诊断、彩色错误信息与退出码；
- 通过平台 I/O 适配层读写文件、目录、标准输入输出和二进制表文件。

## 2. 在整体系统中的位置

从命令行使用角度看，整体链路如下：

```text
argv / stdin / files
        |
        v
     cmd/
        |
        +--> grammar/   校验与格式化 DSL
        |
        +--> tablegen/  生成 ParseTable
        |
        +--> runtime/   解析输入、生成 CST
        |
        +--> query/     执行结构化查询
        |
        v
stdout / stderr / output files / exit code
```

## 3. 公开能力一览

对调用方而言，本包最重要的公开能力如下：


| 类别          | 主要 API                                                                                                                        | 说明                                                |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| 进程入口      | `main`、`parse_args`、`Command`                                                                                                 | 解析命令行并分发到具体子命令                        |
| Grammar 诊断  | `cmd_check`、`cmd_fmt`                                                                                                          | 校验`.grammar` 文件并格式化输出                     |
| 建表与分发    | `cmd_generate`、`cmd_build`、`cmd_wasm`                                                                                         | 生成`.parse_table`、构建 build/dist 产物与 JS glue  |
| 解析与查询    | `cmd_parse`、`cmd_query`                                                                                                        | 解析输入、输出 CST、执行 S-表达式查询               |
| 调试与测试    | `cmd_dump`、`cmd_run_tests`、`cmd_clean`                                                                                        | 调试 IR/表/自动机、运行 corpus 回归、清理构建输出   |
| 统一诊断输出  | `init_reporter`、`report_*`、`report_summary`                                                                                   | 格式化错误、警告、冲突和源码片段                    |
| 平台 I/O 适配 | `read_file`、`write_file`、`read_bytes`、`write_bytes`、`make_dir`、`remove_dir_all`、`read_stdin`、`print_err`、`process_exit` | 屏蔽 native / wasm 环境差异并处理目录级构建产物输出 |

## 4. 用户如何使用

### 4.1 先理解全局参数与子命令边界

当前仓库内的 CLI 入口统一写为 `moon run cmd/main --`，支持以下子命令：

- `generate`
- `build`
- `wasm`
- `dump`
- `parse`
- `check`
- `fmt`
- `query`
- `test`
- `clean`

全局参数目前有两类：

- `--no-color`：关闭 ANSI 颜色输出；
- `-q` / `--quiet`：抑制普通信息输出，但错误和警告仍输出到 `stderr`。

这些全局参数要求出现在**子命令之前**。也就是说，推荐写法是：

```sh
moon run cmd/main -- --no-color check grammars/json.grammar
moon run cmd/main -- --quiet parse -g grammars/json.grammar sample.json
```

### 4.2 推荐的命令行工作流

对大多数命令行用户，建议采用如下顺序：

1. 用 `check` 验证语法和冲突情况；
2. 用 `fmt` 规范化 `.grammar` 文件；
3. 若要排查冲突、状态机或规约项，先用 `dump ir/table/automaton` 观察内部结构；
4. 用 `generate` 生成可复用的 `.parse_table`；
5. 用 `build` 或 `wasm` 产出可分发目录；
6. 用 `parse` 或 `query` 消费真实输入；
7. 用 `test` 跑 corpus 回归；
8. 在 CI 或重构建前，可用 `clean` 清理旧产物。

### 4.3 `check` 只做诊断，不写文件

```sh
moon run cmd/main -- check grammars/json.grammar
```

该命令会执行：

1. 读取 `.grammar` 文件；
2. 解析 DSL；
3. 执行 `validate_grammar`；
4. 生成解析表并收集冲突报告；
5. 按统一 reporter 格式输出错误、警告和汇总。

退出码约定如下：

- `0`：无诊断；
- `1`：仅有警告；
- `2`：存在错误。

其中，左递归会被降级为警告，而不是致命错误，因为当前运行时 GLR 引擎可以处理这类文法。

### 4.4 `fmt` 用于 Grammar DSL 规范化

```sh
moon run cmd/main -- fmt grammars/json.grammar
moon run cmd/main -- fmt grammars/json.grammar --check
moon run cmd/main -- fmt grammars/json.grammar --stdout
```

它的行为分为三类：

- 默认模式：原地覆写文件；
- `--check`：只比较格式化结果与原文是否一致；
- `--stdout`：把格式化结果输出到标准输出，便于管道和调试。

该命令内部不是做文本层面的空白修补，而是“重新解析 DSL，再序列化为规范形式”。

### 4.5 `generate` 用于产出 ParseTable 文件

```sh
moon run cmd/main -- generate grammars/json.grammar
moon run cmd/main -- generate grammars/json.grammar -o out.parse_table
moon run cmd/main -- generate grammars/json.grammar --json
moon run cmd/main -- generate grammars/json.grammar --force
```

默认情况下，输出路径会由 `<name>.grammar` 推导为 `<name>.parse_table`。

该命令支持两种产物形式：

- 默认：二进制 `.parse_table`；
- `--json`：JSON 形式的表数据，适合调试与检查。

`--force` 会放宽阻塞条件，允许在某些本应中止的情况下继续输出产物；如果你关心表是否适合正式集成，应优先先跑一遍 `check`。

### 4.6 `build` 用于构建可分发产物目录

```sh
moon run cmd/main -- build grammars/json.grammar
moon run cmd/main -- build json.parse_table
moon run cmd/main -- build grammars/json.grammar --wasm
moon run cmd/main -- build json.parse_table -o out/build
```

该命令接受两类输入：

- `.grammar`：先执行校验和建表，再写出构建产物；
- `.parse_table`：直接复用已有表文件，不再重复建表。

默认输出目录是 `build/`，其中总会生成：

- `parser.parse_table`：二进制解析表；
- `parser.wasm`：仅在 `--wasm` 时额外输出，同样承载序列化后的表字节。

这里的 `parser.wasm` 当前只是“以 `.wasm` 扩展名分发的表产物”，并不是独立编译得到的 WebAssembly 运行时模块。若你需要真正的 wasm 二进制包，应使用仓库根目录的 `wasm/` 模块和相应构建脚本。

### 4.7 `wasm` 用于生成 JS + ParseTable 的分发目录

```sh
moon run cmd/main -- wasm -g grammars/json.grammar
moon run cmd/main -- wasm -t json.parse_table
moon run cmd/main -- wasm -g grammars/json.grammar -o out/dist
```

默认输出目录是 `dist/`，其中会生成：

- `parser.js`：ES Module 胶水代码；
- `parser.parse_table`：二进制解析表副本。

两种输入路径的区别在于：

- `-g` / `--grammar`：把 Grammar DSL 直接嵌入 `parser.js`，运行时通过 `moonparse.createParser()` 创建解析器；
- `-t` / `--table`：保留二进制 `.parse_table` 文件，同时把同一份表字节以 Base64 形式嵌入 `parser.js`；生成的 `loadParser()` 会在运行时调用 `moonparse.createParserFromBytes()`，直接反序列化二进制表。

在 `-t` 模式下，生成的 `parser.js` 还会额外导出 `tableBytes`，便于宿主侧直接拿到 `Uint8Array` 形式的解析表字节。

推荐的发布链路是：先用 `build` 固化 `parser.parse_table`，再让 `wasm -t` 或宿主侧 `moonparse.createParserFromBytes()` 直接消费这份二进制表；只有 `-g` 路径才会在运行时重新从 DSL 建表。

当前 `wasm` 子命令并不会在 `cmd/` 模块内直接编译出独立的 `parser.wasm` WebAssembly 二进制；如果你的目标是发布浏览器/Node.js 侧的真实 wasm 模块，请继续使用仓库根目录的 `wasm/` 包或 `build_dist.ps1`。

### 4.8 `dump` 用于调试内部结构

```sh
moon run cmd/main -- dump ir grammars/json.grammar
moon run cmd/main -- dump table grammars/json.grammar
moon run cmd/main -- dump table json.parse_table
moon run cmd/main -- dump automaton grammars/json.grammar
```

该命令提供三个调试视图：

- `ir`：输出规范化后的 Grammar IR；
- `table`：输出 LALR 解析表 JSON；
- `automaton`：输出 LR(0) 项目集和 GOTO 跳转。

其中：

- `table` 既接受 `.grammar`，也接受 `.parse_table`；
- `automaton` 当前要求输入 `.grammar`，因为它需要重新构建项目集；
- 当你遇到 shift/reduce、reduce/reduce 或 GLR 分支问题时，`dump` 往往是第一手定位入口。

### 4.9 `parse` 支持从 Grammar 或 ParseTable 直接解析

```sh
moon run cmd/main -- parse -g grammars/json.grammar sample.json
moon run cmd/main -- parse -t json.parse_table sample.json --format json
moon run cmd/main -- parse -t json.parse_table sample.json --format dot
moon run cmd/main -- parse -g grammars/json.grammar --stdin
```

它有两种输入模式，二选一：

- `--grammar` / `-g`：现场编译 Grammar 后再解析；
- `--table` / `-t`：直接加载已有 `.parse_table`。

输出格式支持：

- `sexp`：默认的 S-expression 结构；
- `json`：树形 JSON；
- `dot`：Graphviz DOT，可继续交给 `dot -Tsvg` 渲染。

如果传入 `--tokens`，CLI 会先把 token 流打印到 `stderr`，再把树结果打印到 `stdout`；如果传入 `--error-summary`，则只输出 `ERROR` 节点摘要。

### 4.10 `query` 在命令行上执行结构化匹配

```sh
moon run cmd/main -- query "(identifier) @name" sample.txt -g grammars/lang.grammar
moon run cmd/main -- query "(identifier) @name" sample.txt -t lang.parse_table --json
moon run cmd/main -- query "(identifier) @name" sample.txt -t lang.parse_table --count
```

该命令会：

1. 先加载 Grammar 或 ParseTable；
2. 解析输入得到 CST；
3. 编译查询字符串；
4. 执行 `query.exec`；
5. 以文本、JSON 或计数形式输出结果。

其中，`--count` 输出的是“顶层匹配次数”，不是“捕获条数”。

### 4.11 `test` 用于运行 corpus 回归测试

```sh
moon run cmd/main -- test grammars/json.grammar:corpus/json.txt
moon run cmd/main -- test corpus/json.txt
```

它支持两种规格：

- `grammar.grammar:corpus.txt`：显式给出 Grammar 与语料文件；
- `corpus.txt`：自动推导同基名的 `.grammar` 文件。

当前实现会读取单个 corpus 文件，把每个测试样例解析成期望 S-expression，并与实际输出逐条比较。

### 4.12 `clean` 用于清理构建目录

```sh
moon run cmd/main -- clean
```

该命令会尝试删除以下目录：

- `generated/`
- `build/`
- `dist/`

它适合用于 CI、重构建或切换产物布局前的清理步骤。当前实现按 best-effort 方式执行，重复调用是安全的；缺失目录不会影响后续命令继续运行。

## 5. 核心概念

### 5.1 `Command` 与各类 `*Args`

`parse_args()` 不返回松散的字符串字典，而是返回强类型的 `Command` 枚举：

- `Generate(GenerateArgs)`
- `Build(BuildArgs)`
- `Wasm(WasmArgs)`
- `Dump(DumpArgs)`
- `Parse(ParseArgs)`
- `Check(CheckArgs)`
- `Fmt(FmtArgs)`
- `Query(QueryArgs)`
- `Test(TestArgs)`
- `Clean(CleanArgs)`
- `Help(String?)`
- `Version`

这意味着参数解析和命令执行之间有一层明确的“命令 AST”。调用方如果直接复用本包，也可以先消费这层强类型结果，而不是自己再做一轮字符串分支。

### 5.2 退出码是 CLI 协议的一部分

本模块中的很多命令不只是“打印消息”，还会用退出码向 shell 和 CI 传达状态。例如：

- `check`：`0 = ok`，`1 = warnings`，`2 = errors`；
- `generate` / `build` / `wasm`：`0 = ok`，`1 = warnings`，`2 = 致命错误`；
- `dump`：`0 = 输出成功`，`2 = 加载、建表或反序列化失败`；
- `fmt --check`：`0 = 已规范化`，`1 = 未规范化`，`2 = 致命错误`；
- `parse`：`0 = 无 ERROR 节点`，`1 = 树中存在 ERROR 节点`，`2 = 运行时失败`；
- `test`：`0 = 全部通过`，`1 = 有用例失败`，`2 = 加载或编译失败`；
- `clean`：按 best-effort 方式执行，正常情况下返回 `0`。

因此，不应只依赖文本输出判断命令是否成功，尤其是在脚本和自动化流水线中。

### 5.3 `reporter` 统一了 stdout 与 stderr 的职责

本模块显式区分两类输出：

- `print_info()`：写到 `stdout`，承载主要结果；
- `print_err()`、`print_warning()`、`report_*()`：写到 `stderr`，承载诊断和调试信息。

这使得如下用法可预测：

- `moon run cmd/main -- parse ... > tree.sexp` 只抓取主结果；
- 错误信息、token 流、冲突报告不会混进结果文件；
- `--quiet` 只影响普通信息，不会吞掉错误和警告。

### 5.4 `load_table_from_grammar` 与 `load_table_from_file`

`parse`、`query`、`test`，以及 `build` / `wasm` / `dump table` 这几类命令共享两条装载路径：

- 从 `.grammar` 现场编译；
- 从 `.parse_table` 直接反序列化。

这两种路径分别对应“开发调试方便”和“运行时复用稳定产物”两种场景。若你频繁解析同一种语言输入，通常应优先使用预生成的 `.parse_table`。

## 6. 架构与设计说明

`cmd/` 目前主要由以下文件组成：


| 文件                                      | 主要职责                                    |
| ----------------------------------------- | ------------------------------------------- |
| `main/main.mbt`                           | 进程入口、版本与帮助分发、子命令调度        |
| `main/args.mbt`                           | 手写参数解析器、强类型命令结构、帮助文本    |
| `main/cmd_check.mbt`                      | Grammar 校验与冲突诊断                      |
| `main/cmd_fmt.mbt`                        | Grammar DSL 规范化格式化                    |
| `main/cmd_generate.mbt`                   | ParseTable 生成与输出                       |
| `main/cmd_build.mbt`                      | 构建 build/ 分发目录                        |
| `main/cmd_wasm.mbt`                       | 构建 dist/ 分发目录与 JS 胶水               |
| `main/cmd_dump.mbt`                       | 输出 IR、ParseTable JSON 与 LR 自动机       |
| `main/cmd_parse.mbt`                      | 输入解析、CST 输出、token 与错误摘要        |
| `main/cmd_query.mbt`                      | 查询编译、执行与结果格式化                  |
| `main/cmd_run_tests.mbt`                  | corpus 文件解析与回归测试执行               |
| `main/cmd_clean.mbt`                      | 清理 generated/、build/、dist/              |
| `main/cmd_util.mbt`                       | 共享 JSON/S-expression/DOT 导出与表加载工具 |
| `main/reporter.mbt`                       | 统一错误、警告、源码片段和彩色输出          |
| `main/io.mbt`                             | I/O 抽象外观                                |
| `main/io_native.mbt` / `main/io_wasm.mbt` | native / wasm 平台实现                      |
| `main/cmd_wbtest.mbt`                     | 参数解析和路径推导的白盒测试                |

## 7. 适用场景总结

`cmd/` 特别适合以下场景：

- 在终端中调试 Grammar、ParseTable 和 CST 输出；
- 构建 `build/`、`dist/` 目录并交给上层脚本或发布流程消费；
- 在 CI 中做语法校验、格式检查、建表与 corpus 回归；
- 快速验证查询模式、树结构和错误恢复行为；
- 在冲突、自动机状态或规约行为异常时查看 `dump` 输出；
- 为文档、示例和脚本提供稳定的命令行入口。

如果你的目标是“把 MoonParse 嵌入编辑器、浏览器或长期运行服务”，则更适合直接使用库模块或 `wasm/`，而不是把 `cmd/` 当作嵌入式 API。
