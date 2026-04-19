# MoonParse

MoonBit 编写的解析器生成器与语言工具链基础设施。当前仓库已经打通了 Grammar DSL、ParseTable 生成、GLR 运行时、增量解析、错误恢复、查询 / 高亮、WASM 桥接和 website playground 这条闭环，适合拿来做内置语法验证、浏览器集成、命令行调试和语言工具链实验。

## 当前范围

- 语法前端：Grammar DSL 解析、语义校验、DSL / JSON 序列化。
- 建表链路：LALR 解析表生成、冲突诊断、JSON / 二进制表导出。
- 运行时：GLR 全量解析、增量解析、错误恢复、外部 scanner / stateful scanner。
- 查询能力：结构化 query、capture、高亮范围和 locals 解析。
- 内置语法：`json`、`json5`、`c`、`python`、`moonbit`。
- 对外集成：根包 API、`cmd/` 命令行入口（仓库内通过 `moon run cmd/main --` 调用）、`wasm/` 宿主桥接、`website/` 文档与在线 playground。

## 构建

面向仓库使用者的常用构建入口如下：

```bash
# 构建主模块与分包
moon build

# 运行 CLI 入口
moon run cmd/main -- --help

# 构建 release wasm 产物
moon build --target wasm-gc --release --strip

# 启动 website 开发环境
Push-Location website
npm install
npm run dev
Pop-Location

# 构建 website 静态产物
Push-Location website
npm install
npm run build
Pop-Location
```

`moon build` 覆盖根包 API 与各分包；website 目录提供 `dev`、`build`、`preview` 三个前端入口；release wasm 产物用于浏览器和宿主侧集成。

## 使用方式

MoonParse 提供四种直接可用的入口：MoonBit 根包 API、通过 `moon run cmd/main --` 调用的命令行入口、可嵌入浏览器或本地宿主的 Wasm 入口，以及 website playground。

### 1. 作为 MoonBit 包使用

根包 `caiklonghuan/MoonParse` 暴露的是高层可直接调用的入口：既可以从 DSL 生成 ParseTable JSON，也可以直接调用内置语法入口。

```moonbit
import "caiklonghuan/MoonParse" @moonparse

let dsl =
  #|start expr
  #|extras [/[ \t\n\r]+/]
  #|rule expr: number ("+" number)*
  #|rule number: /[0-9]+/

let table_json = @moonparse.generate(dsl)
let expr_tree = @moonparse.parse(dsl, "1 + 2 + 3")
let json_tree = @moonparse.parse_json("{\"ok\": true}")
let py_tree = @moonparse.parse_python("def f():\n    return 1\n")

println(table_json)
println(expr_tree)
println(json_tree)
println(py_tree)
```

更细的控制面见各分包文档：Grammar 校验、ParseTable 序列化、增量解析、query、cursor 和 wasm handle 接口都在对应包里展开。

### 2. 使用命令行入口

在仓库内使用命令行工具时，统一通过 `moon run cmd/main --` 运行。

```bash
# 查看帮助
moon run cmd/main -- --help

# Grammar 校验
moon run cmd/main -- check grammars/json.grammar

# 生成 ParseTable
moon run cmd/main -- generate grammars/json.grammar -o out/json.parse_table

# 直接解析输入
moon run cmd/main -- parse -g grammars/json.grammar sample.json

# 执行 query
moon run cmd/main -- query "(pair (jstring) @key)" sample.json -g grammars/json.grammar
```

### 3. 使用 website playground

```bash
cd website
npm install
npm run dev
```

启动后打开 Vite 输出的本地地址，即可在浏览器里直接体验内置 grammar 的解析、query、高亮和树视图。

### 4. 以 Wasm 形式分发并在浏览器或本地宿主中使用

如果你的目标不是直接跑 website，而是把解析器当成可分发能力嵌入浏览器、Node.js、Electron 或其他 JS 宿主，当前推荐两条路径：

1. 分发通用运行时：发布 `wasm/moonparse.js` 与 `wasm/moonparse.wasm`，运行时再加载 `.parse_table`。
2. 分发固化语法的解析器包：先生成 `.parse_table`，再用 `cmd wasm` 生成 `parser.js` 胶水，让宿主直接 `loadParser()`。

最短的构建链路如下：

```bash
# 1) 先固化 ParseTable
moon run cmd/main -- generate grammars/json.grammar -o out/json.parse_table

# 2) 生成按语法固化的分发目录
moon run cmd/main -- wasm -t out/json.parse_table -o out/dist

# 3) 构建 MoonParse 的真实 wasm 运行时
moon build --target wasm-gc --release --strip
```

其中：

- `out/dist/parser.js` 是按语法固化后的 ES Module 胶水；
- `out/json.parse_table` 是可单独缓存或分发的二进制解析表；
- `_build/wasm-gc/release/build/wasm/wasm.wasm` 是 MoonParse 的真实 wasm 运行时，通常需要复制为和宿主约定的 `moonparse.wasm` 路径。

浏览器侧如果直接加载 runtime + 解析表，可以这样接入：

```javascript
import { loadMoonParse } from "./moonparse.js"

const mp = await loadMoonParse("./moonparse.wasm")
const tableBytes = new Uint8Array(
  await fetch("./json.parse_table").then((r) => r.arrayBuffer())
)
const parser = mp.createParserFromBytes(tableBytes)
const tree = parser.parse('{"ok": true}')

console.log(tree.root.type)
console.log(tree.errorSummary())
```

Node.js / Electron 这类本地 JS 宿主则可以直接从文件系统读取：

```javascript
import { readFile } from "node:fs/promises"
import { loadMoonParse } from "./moonparse.js"

const mp = await loadMoonParse(new URL("./moonparse.wasm", import.meta.url).href)
const tableBytes = new Uint8Array(
  await readFile(new URL("./json.parse_table", import.meta.url))
)
const parser = mp.createParserFromBytes(tableBytes)
const tree = parser.parse('{"ok": true}')

console.log(tree.root.type)
console.log(tree.errorSummary())
```

如果你已经用 `moon run cmd/main -- wasm -t ...` 生成了 `parser.js`，宿主侧可以直接加载固化后的解析器：

```javascript
import { loadMoonParse } from "./moonparse.js"
import { loadParser } from "./dist/parser.js"

const mp = await loadMoonParse("./moonparse.wasm")
const parser = await loadParser(mp)
const tree = parser.parse('{"ok": true}')

console.log(tree.root.type)
```

更完整的句柄 API、增量解析、query、高亮和包装层说明见 `wasm/README.md`。

> **注意事项**
>
> - **`.grammar` 文件需要手动创建**：`generate` 命令期望读取独立的 `.grammar` DSL 文本文件，而项目中的语法定义是嵌入在 `.mbt` 源码里的（如 `grammars/json.mbt` 中的 `json_grammar` 字符串）。文档示例里的 `grammars/json.grammar` 路径实际不存在，需要用户自己从 DSL 字符串提取或直接编写。
>
> - **Windows 下 `moon run cmd/main` 无法直接使用**：默认 wasm target 缺少 `__moonbit_fs_unstable` 文件系统 API，native target 缺少 `windows.h`。实际可行的方式是先执行 `moon build --target wasm-gc`，再通过 `node run.js` 调用 CLI 命令，例如 `node run.js generate my.grammar -o out/my.parse_table`。
>
> - **`dist/parser.js` 内嵌了 parse table**：生成的 `parser.js` 已将 parse table 以 base64 形式内嵌，宿主侧无需额外携带 `.parse_table` 文件，直接 `import { loadParser } from "./dist/parser.js"` 即可。

## 仓库结构

- `grammar/`：Grammar DSL、Builder API、校验、DSL / JSON round-trip。
- `tablegen/`：增广文法、LALR 表生成、冲突诊断、词法 DFA、表序列化。
- `runtime/`：GLR 运行时、错误恢复、增量解析、外部 scanner、CST。
- `query/`：Tree-sitter 风格 query、capture、高亮、locals。
- `grammars/`：内置语法、示例输入、现成 `parse_*` 入口和测试辅助。
- `wasm/`：Parser / Tree / Cursor / Query 句柄、JSON / bytes / base64 restore、宿主桥接。
- `cmd/`：统一命令行入口，仓库内通过 `moon run cmd/main --` 调用，包括 `check`、`fmt`、`generate`、`parse`、`query`、`test`、`wasm` 等命令。
- `scripts/`：fuzz、mutation、增量一致性验证、parse / incremental / serialize benchmark。
- `typegen/`：类型安全 CST 访问器生成相关代码。
- `website/`：文档站、在线 playground、预编译表和浏览器侧胶水。

## 设计概览

MoonParse 的目标不是只做一个“能把文本 parse 出树”的演示项目，而是把 Grammar DSL、ParseTable 生成、GLR 运行时、查询、高亮、WASM 桥接和 website 展示整理成一条完整工程链。

### 当前目标

- 用 MoonBit 实现可分发的解析器工具链，而不是依赖 C / Rust 运行时。
- 让同一份 grammar 能同时服务 `moon run cmd/main --`、程序内嵌、WASM 集成和 website playground。
- 在运行时层提供真实可用的 GLR、增量解析和错误恢复，而不是只支持理想输入。
- 把 query / highlight 也纳入同一套仓库，不把“解析”和“上层工具能力”拆成两条断裂链路。

### 主链路

```text
Grammar DSL / Builder API
          |
          v
      grammar/
          |
          v
   Grammar model / validation
          |
          v
      tablegen/
          |
          v
      ParseTable
          |
          v
      runtime/
          |
          v
        CST
      /     \
     v       v
 query/    wasm/
             |
             v
  cmd/main / website/
```

### 包边界


| 包          | 角色             | 主要输入                           | 主要输出                            |
| ----------- | ---------------- | ---------------------------------- | ----------------------------------- |
| `grammar/`  | 语法前端         | DSL 文本 / Builder API             | `Grammar`、校验结果、DSL / JSON     |
| `tablegen/` | 建表层           | `Grammar`                          | `ParseTable`、冲突诊断、序列化产物  |
| `runtime/`  | 解析运行时       | `ParseTable`、源码、旧树、编辑描述 | CST、恢复结果、增量重解析结果       |
| `query/`    | 查询 / 高亮层    | CST、query 模式                    | captures、高亮范围、locals          |
| `grammars/` | 内置语法层       | 预置 grammar / query               | 现成`parse_*` / `highlight_*` 入口  |
| `wasm/`     | 跨边界适配层     | DSL / JSON / bytes / builtin id    | parser/tree/query/cursor handle API |
| `cmd/`      | 命令行编排层     | 文件、stdin、参数                  | 诊断、ParseTable 产物、查询输出     |
| `scripts/`  | 开发验证层       | 内置语法、随机种子、样本输入       | fuzz / mutation / benchmark 结果    |
| `website/`  | 文档与在线集成层 | wasm、预编译表、示例 grammar       | docs、playground、浏览器胶水        |
| `typegen/`  | 类型化访问器生成 | grammar 形状信息                   | 类型安全 CST 访问器代码             |

这套边界的关键点是：

- `grammar/` 只解决“语法如何表示与校验”，不直接负责运行时 parse。
- `tablegen/` 只解决“如何把 grammar 编译成可执行表”，不持有上层宿主逻辑。
- `runtime/` 只消费 ParseTable 和输入，不依赖 website 或命令行入口。
- `wasm/` 不重新实现解析逻辑，只把底层对象整理成跨边界可用接口。

### 关键数据流

```text
语法作者路径
write DSL
  -> parse_grammar / validate_grammar
  -> generate_parse_table
  -> dump / diagnostics / serialize
```

```text
运行时解析路径
ParseTable + source
  -> runtime.parse / parse_incremental
  -> CST
  -> query / highlight / cursor / summary
```

```text
WASM / website 路径
release wasm + precompiled table
  -> loadMoonParse()
  -> createParserFromJson(..., builtinId)
  -> parse / parseIncremental
  -> tree / query / highlight in browser
```

### website 与分发约束

当前 website 采用“预编译表优先”的思路：

- `website/src/data/languagePresets.js` 提供内置 grammar 定义。
- `website/src/data/precompiledTables.js` 提供预编译表缓存。
- `website/public/moonparse.wasm` 提供实际浏览器运行时。

当 runtime / wasm 或内置 grammar 发生变化时，分发路径需要同步执行：

1. 使用 `_build/wasm-gc/release/build/wasm/wasm.wasm` 作为最新 wasm 产物来源。
2. 同步复制到 `wasm/moonparse.wasm` 和 `website/public/moonparse.wasm`。
3. 重新运行 `node scripts/precompile-grammars.mjs` 更新预编译表。
4. 执行 `npm run build` 验证 website 产物。

## 进阶命令

下面这些命令更适合需要导出产物、构建分发目录或运行开发脚本的场景：

```bash
# 构建可分发目录
moon run cmd/main -- build grammars/json.grammar -o out/build

# 生成 JS + ParseTable 分发目录
moon run cmd/main -- wasm -g grammars/json.grammar -o out/dist

# 查看开发脚本帮助
moon run scripts -- help
```

上面的命令都以仓库内直接运行方式给出，可以直接复制执行。

## 文档导航。

- [grammar/README.md](grammar/README.md)：Grammar DSL 与前端模型。
- [tablegen/README.md](tablegen/README.md)：建表链路与冲突处理。
- [runtime/README.md](runtime/README.md)：运行时、恢复、增量解析。
- [query/README.md](query/README.md)：查询与高亮模型。
- [wasm/README.md](wasm/README.md)：WASM 宿主接口。
- [cmd/README.md](cmd/README.md)：命令行工作流，仓库内统一通过 `moon run cmd/main --` 调用。
- [scripts/README.md](scripts/README.md)：fuzz 和 benchmark。
