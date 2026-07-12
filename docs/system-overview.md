# MoonParse 系统架构与使用总览

本文面向第一次接触 MoonParse 的开发者，说明仓库当前已经实现的系统边界、核心数据流、公开入口和分发方式。它回答的是“MoonParse 现在能做什么、应该从哪里接入”；更严格的包依赖约束仍以 [architecture.md](architecture.md) 为准。

## 1. 项目定位

MoonParse 是一套用 MoonBit 实现的通用语言开发基础设施。开发者提供 Grammar DSL 或完整 Language Pack，MoonParse 负责生成解析表，并把解析、增量更新、查询、Lint、Corpus 测试以及编辑器和浏览器接入串成一条链路：

```text
Grammar
  -> ParseTable
  -> GLR Runtime
  -> CST
  -> Query / Binding / Lint
  -> Language Bundle
  -> CLI / MoonBit / WASM / NPM / LSP / VS Code / Web
```

它不是 MoonBit 语言的完整编译器，也不替代类型检查器。它提供的是可复用的“语法层”和语言工具基础：同一份语法与查询配置可以用于命令行、MoonBit 程序、Node.js、浏览器、LSP 和 VS Code 扩展。

当前仓库同时包含两种使用层级：

- 单 Grammar：适合快速编译一份 `.grammar`，直接解析文本并查询 CST。
- Language Pack：适合维护一门可发布的语言，把 Manifest、Grammar、Query、Lint、Scanner 和 Corpus 一起构建成版本化 Bundle。

## 2. 总体架构

```text
语言定义层
  grammar/                 Grammar DSL、Grammar IR、校验和格式化
      |
      v
  tablegen/                LALR/GLR 表生成、冲突检测与解释
      |
      v
解析与查询层
  runtime/                 GLR 解析、恢复、CST、增量复用、Scanner 接口
      |
      v
  query/                   S-expression Query、capture、高亮、bindings
      |
      v
语言平台层
  languagepack/            Manifest、Bundle、Corpus、Lint、rewrite
      |
      v
  grammars/ + languages/   内置语法、内置 Pack、Scanner provider
      |
      v
宿主与应用层
  root / cmd / wasm        MoonBit facade、CLI、JavaScript/WASM
  lsp / website            LSP、VS Code 生成链、Playground
```

分层的关键原则是：核心 MoonBit 包不依赖网站或 LSP；文件系统、进程、浏览器和编辑器协议只存在于宿主适配层。机器可检查的依赖边界记录在 [`api/boundaries.json`](../api/boundaries.json) 中。

## 3. 各层职责

### 3.1 核心层

| 模块 | 输入 | 主要输出 | 职责 |
| --- | --- | --- | --- |
| `grammar` | Grammar DSL 或 Grammar 对象 | `Grammar`、校验诊断 | 解析语法定义，维护规则、终结符、优先级和关联性 |
| `tablegen` | `Grammar` | `ParseTable`、冲突报告 | 生成 LALR/GLR 表，解释 Shift/Reduce、Reduce/Reduce 等冲突 |
| `runtime` | `ParseTable`、源码、可选旧树和 edit | `CstNode`、增量 trace | 执行解析、错误恢复、Scanner 调用和真实节点复用 |
| `query` | Query、CST、源码、ParseTable | captures、BindingGraph、高亮范围 | 对 CST 执行结构查询，并提供 editor-facing 语义 |

`runtime` 输出的是保留源码范围、字段和恢复节点的 CST。语法错误通常会表现为可遍历的 `ERROR` 或 `MISSING` 节点；只有无法继续的运行时问题才会返回解析失败。因此调用方不能只判断 `parse()` 是否成功，还应读取树的错误摘要或遍历错误节点。

### 3.2 Language Pack 平台层

`languagepack` 把核心能力组织成可验证、可测试和可分发的语言单元。典型源码 Pack 如下：

```text
my-language/
  language-pack.json
  grammar/main.grammar
  queries/highlights.scm
  queries/locals.scm
  queries/bindings.scm
  queries/folding.scm
  queries/modules.scm
  lint/recommended.json
  corpus/basic.txt
  scanner/scanner.json
```

除 Manifest 外的资源都是可选项，实际路径由 Manifest 声明。Pack 核心不直接访问文件系统；宿主读取文件后构造 `LanguagePackSource`，所以相同校验与构建逻辑可以运行在 native、Node.js 和浏览器中。

这一层当前提供：

- Manifest、路径、Grammar、Query、Scanner、Lint 和 Corpus 的统一诊断。
- 只编译一次并同时返回 Bundle 与诊断的构建报告。
- Corpus v1/v2 批量测试和 v2 S-expression snapshot 更新。
- 配置驱动的 Lint 规则集、severity override、单目标 rewrite 和 Quick Fix 数据。
- 包含 ParseTable JSON 与二进制表的 `LanguageBundle`。
- highlights、locals、bindings、folding、modules、lint、rewrite 和 scanner capability 标记。

`grammars` 和 `languages/` 保存仓库内置语言、Canonical Pack 资源以及内置 Scanner provider。当前 JSON、Python 和 MoonBit Pack 是完整样板；其他内置 Grammar 可继续作为兼容入口使用。

### 3.3 宿主适配层

- 根包 `caiklonghuan/MoonParse`：面向 MoonBit 调用方的稳定 facade。
- `cmd/main`：`moonparse` CLI、Pack 创建/检查/测试/构建以及分发目标生成。
- `wasm`：句柄式 WASM ABI 和更安全的 JavaScript 类包装。
- Tree-sitter interop：导入/导出 `grammar.json`，以及 Playground 中目前面向 JSON 的真实解析对比。

WASM 的底层 ABI 使用整数句柄和 JSON 字符串跨越宿主边界；普通 JavaScript 调用方应优先使用 `loadMoonParse()` 返回的 `MoonParser`、`ParseTree`、`MoonQuery` 和 `MoonLanguage`，不要直接管理 ABI 句柄。

### 3.4 应用层

- LSP：把 Bundle 的解析、语义高亮、folding、document symbol、bindings、modules、workspace import、Lint 和 Quick Fix 接入标准 LSP 请求。
- VS Code：生成并打包包含 Bundle、WASM 和 LSP server 的扩展。
- Playground：浏览器中的 Pack 导入/编辑/导出、Manifest 校验、Corpus、Query 调试、Binding Graph、LR 冲突、增量 trace、Lint、Bundle/VSIX 下载、URL 分享和 Tree-sitter JSON 对比。

LSP 不内置一门语言的类型系统。跨文件导航与重命名依赖 Pack 的 `modules` Query，以及宿主提供的项目模型；例如 MoonBit provider 还会读取 `moon.work`、`moon.mod.json` 和 `moon.pkg`。

### 3.5 工程保障

仓库使用以下机制约束生成物和公开接口：

- MoonBit blackbox/whitebox 测试和 Corpus 测试。
- CLI help、TypeScript API、WASM ABI 等快照检查。
- [`schemas/`](../schemas/) 中的 Manifest、Bundle 和相关 JSON Schema。
- [`VERSION`](../VERSION) 与兼容性检查。
- 内置 Language Pack、网站资源和 LSP 资源的 freshness 检查。
- 文档链接、包依赖边界、兼容 fixture 和生成工具 smoke test。

不要手工修改带有 generated 标记的资源。生成物来源和刷新命令见 [generated-artifacts.md](generated-artifacts.md)，完整测试入口见 [testing.md](testing.md)。

## 4. 主要运行链路

### 4.1 单 Grammar 编译和解析

```text
.grammar
  -> grammar.parse_grammar
  -> grammar.validate_grammar
  -> tablegen.generate_parse_table
  -> ParseTable
  -> runtime.parse / runtime.parse_incremental
  -> CstNode
  -> query.exec
```

这条链路适合编译器前端原型、DSL、配置格式或需要直接控制 Runtime 的 MoonBit 程序。CLI 的 `check`、`generate`、`parse` 和 `query` 也是这条链路的宿主入口。

### 4.2 Language Pack 检查、测试和构建

```text
Record<relativePath, UTF-8 text>
  -> language-pack.json + resources
  -> check_pack / build_bundle_report
  -> diagnostics + optional LanguageBundle
  -> test_pack (one build, all Corpus cases)
  -> bundle_to_json
```

Pack 有 Error 时不产生可交付 Bundle；Warning 会保留在报告中，但不阻止构建。Corpus 属于源码 Pack 测试资源，不会写入运行时 Bundle。

### 4.3 Bundle 加载

Bundle 是各宿主共享的运行时契约：

```text
LanguageBundle JSON
  -> schema/version/integrity validation
  -> ParseTable + compiled Query + Scanner descriptor
  -> parse source
  -> CST
  -> highlight / bindings / modules / lint
```

- MoonBit 通过 `languagepack.bundle_from_json()` 和 `parse_bundle()` 使用。
- Node.js 和浏览器通过 `loadMoonParse()` 后的 `loadBundle()` 使用。
- LSP、VS Code 和生成 Web 项目嵌入同一份 Bundle。

MoonBit 宿主可以直接加载序列化 Bundle：

```moonbit
import "caiklonghuan/MoonParse/languagepack" @languagepack

let bundle = match @languagepack.bundle_from_json(bundle_json) {
  Ok(value) => value
  Err(_) => abort("invalid LanguageBundle")
}
let root = match @languagepack.parse_bundle(bundle, "{\"answer\": 42}") {
  Ok(value) => value
  Err(diagnostic) => abort(diagnostic.message)
}
println(root.to_string())
```

需要外部 Scanner 的 Bundle 应向 `parse_bundle()` 传入相应 `scanner_provider`。

Bundle 只描述 Scanner，不自动实现 Scanner。宿主必须提供与描述符匹配的 `PackScannerProvider`；仓库内置宿主会注册已知 Scanner。未知或不受支持的 Scanner 会得到结构化诊断，而不是静默退化为错误解析结果。

### 4.4 编辑器和浏览器链路

```text
document edit
  -> UTF-16 position to UTF-8 InputEdit
  -> incremental parse
  -> new CST + optional reuse trace
  -> Query / Binding / Module / Lint refresh
  -> LSP diagnostics or Playground panels
```

普通实时解析不执行全量性能基准。只有调用增量 trace API 或打开 Playground 增量面板时，JavaScript 包装层才会额外执行一次全量 parse，并立即释放基准树。

## 5. MoonBit API

### 5.1 根包 facade

在调用方的 `moon.pkg` 中导入根包：

```moonbit
import "caiklonghuan/MoonParse" @moonparse
```

使用结构化 API 编译和解析：

```moonbit
let dsl =
  #|start document
  #|rule document: number
  #|rule number: /[0-9]+/

fn main {
  let compiled = match @moonparse.compile_dsl(dsl) {
    Ok(value) => value
    Err(error) => abort("compile failed: \{error.message}")
  }
  println("states: \{compiled.table.states}")

  let parsed = match @moonparse.parse_dsl(dsl, "42") {
    Ok(value) => value
    Err(error) => abort("parse failed: \{error.message}")
  }
  println(parsed.root.to_string())
}
```

`compile_dsl()` 返回 ParseTable、表 JSON、冲突和 Grammar validation 信息；`parse_dsl()` 返回 `CstNode` 和原始 source。旧的 `generate()`、`parse()`、`parse_json()` 等字符串便利入口仍然存在，但新代码优先使用结构化返回值。

### 5.2 底层组合 API

需要自定义校验、冲突策略或 Query 时，可以直接组合公开包：

```moonbit
import {
  "caiklonghuan/MoonParse/grammar" @grammar,
  "caiklonghuan/MoonParse/tablegen" @tablegen,
  "caiklonghuan/MoonParse/runtime" @runtime,
  "caiklonghuan/MoonParse/query" @query,
}

let grammar = match @grammar.parse_grammar(dsl) {
  Success(value) => value
  Error(error) => abort("grammar: \{error.message}")
}
let table = match @tablegen.generate_parse_table(grammar) {
  Ok((value, _conflicts)) => value
  Err(message) => abort(message)
}
let root = match @runtime.parse(table, "42") {
  Ok(value) => value
  Err(error) => abort(error.message)
}
let compiled_query = match @query.compile("(number) @value") {
  Ok(value) => value
  Err(_) => abort("query compile failed")
}
let captures = @query.exec(compiled_query, root, "42", table)
println(captures.length())
```

如果只需要稳定入口，使用根包；只有需要控制 `Grammar`、`ParseTable`、增量输入或 Query 执行细节时才直接依赖底层包。

## 6. CLI 使用

仓库内开发时使用：

```sh
moon run cmd/main -- <command>
```

安装后的 CLI 可将前缀替换为 `moonparse`。

### 6.1 Grammar 工作流

```sh
# 校验 Grammar，并检查 LR 冲突
moon run cmd/main -- check grammar/main.grammar

# 输出更完整的冲突路径、actions 和 LR items
moon run cmd/main -- check grammar/main.grammar --conflict-detail

# 生成二进制解析表
moon run cmd/main -- generate grammar/main.grammar -o parser.parse_table

# 从 Grammar、ParseTable 或 Bundle 解析
moon run cmd/main -- parse -g grammar/main.grammar input.txt --format sexp
moon run cmd/main -- parse -t parser.parse_table input.txt --format tree
moon run cmd/main -- parse -b language-bundle.json input.txt --error-summary

# 运行 S-expression Query
moon run cmd/main -- query "(function_definition) @function" input.txt -g grammar/main.grammar
moon run cmd/main -- query highlights input.txt -b language-bundle.json --json
```

`parse --format` 支持 `sexp`、`json`、`dot` 和 `tree`。`query -b` 可用 Bundle 自带的 `highlights`、`locals`、`bindings`、`folding` 或 `modules` Query。

### 6.2 Language Pack 工作流

```sh
# 创建最小 Pack
moon run cmd/main -- pack init my-language --name "My Language" --extension my

# 检查 Manifest、Grammar、Query、Lint、Scanner 和 Corpus 引用
moon run cmd/main -- pack check my-language

# 批量运行 Corpus；v2 snapshot 可显式更新
moon run cmd/main -- pack test my-language
moon run cmd/main -- pack test my-language --update

# 默认只生成 Bundle
moon run cmd/main -- pack build my-language

# 从同一次 Bundle 构建生成多个分发目标
moon run cmd/main -- pack build my-language \
  --target bundle --target moonbit --target wasm --target npm \
  --out-dir dist/my-language
```

Pack 的格式、Query capture 契约、Corpus v2 和 Scanner 细节见 [language-packs.md](language-packs.md)。

## 7. Pack 构建目标

`pack build --target` 支持以下目标；可重复传入多个目标：

| target | 产物用途 | 运行时关系 |
| --- | --- | --- |
| `bundle` | 可重新加载的 `LanguageBundle` JSON | 所有其他语言工具产物的权威语言数据 |
| `moonbit` | 可依赖的 MoonBit 包，内嵌 Bundle，并暴露加载、通用 CST parse 和 query | 使用 MoonParse `languagepack/runtime/query`；不是类型化 CST/AST codegen |
| `wasm` | 自包含的 WASM、JavaScript wrapper、Bundle 和语言入口 | 适合独立网页或 JS 宿主 |
| `npm` | 薄 NPM 语言包 | 以 `moonparse` 为 peer dependency，避免重复携带运行时 |
| `lsp` | 可安装依赖并编译的 TypeScript LSP server 工程 | 内嵌同一 Bundle 和 WASM runtime |
| `vscode` | VS Code extension 工程和生成的 VSIX | 内嵌编译后的 LSP server、Bundle 和 runtime |
| `web` | 最小 Vite Web 项目 | 用相同 Bundle 在浏览器解析和展示 |

默认输出根目录是 `dist/<pack-id>`，可用 `--out-dir` 修改。`-o/--output` 是仅输出单个 Bundle 文件的快捷方式，不用于多目标构建。

特别需要明确：当前 `moonbit` target 生成的是“内嵌 Bundle + 通用 `CstNode` API”的消费包。它不会根据 Grammar 生成每个 rule 对应的 MoonBit 类型、typed field accessor、visitor 或 AST 转换器。

## 8. JavaScript/WASM API

### 8.1 初始化与直接 Grammar 解析

```js
import { loadMoonParse } from "./moonparse.js";

const mp = await loadMoonParse("./moonparse.wasm");
const parser = mp.createParser(`
start document
rule document: number
rule number: /[0-9]+/
`);

let tree;
try {
  tree = parser.parse("42");
  console.log(tree.sexp());
  console.log(tree.errorSummary());
} finally {
  tree?.free();
  parser.free();
}
```

### 8.2 检查、构建和加载 Pack

浏览器和 Node.js 使用同一个文本文件映射：

```js
const files = {
  "language-pack.json": JSON.stringify({
    schemaVersion: 1,
    id: "example",
    name: "Example",
    version: "0.1.0",
    maturity: "experimental",
    entryRule: "document",
    extensions: [".ex"],
    compatibility: {
      minimumMoonParseVersion: "0.1.0",
      maximumMoonParseVersionExclusive: "0.2.0",
    },
    grammar: { path: "grammar/main.grammar", format: "dsl" },
    build: { allowAmbiguousConflicts: false },
  }),
  "grammar/main.grammar": `
start document
rule document: number
rule number: /[0-9]+/
`,
};

const checked = mp.checkPack(files);
if (!checked.ok) console.error(checked.diagnostics);

const built = mp.buildPack(files);
if (!built.ok || !built.bundleJson || !built.language) {
  throw new Error(JSON.stringify(built.diagnostics));
}

const language = built.language;
let tree;
try {
  tree = language.parse("42");
  console.log(tree.sexp());
  console.log(language.lint(tree));
} finally {
  tree?.free();
  language.free();
}

// 序列化的 Bundle 可以在另一个进程或页面重新加载。
const loaded = mp.loadBundle(built.bundleJson);
try {
  const loadedTree = loaded.parse("7");
  try {
    console.log(loadedTree.sexp());
  } finally {
    loadedTree.free();
  }
} finally {
  loaded.free();
}
```

`buildPack()` 成功时同时返回 `bundleJson` 和已注册的 `MoonLanguage`。如果调用方只保存 Bundle，也仍需释放返回的 `language`。

### 8.3 Corpus 和 Lint

```js
const report = mp.runCorpus(files);
for (const testCase of report.cases) {
  console.log(testCase.path, testCase.name, testCase.passed);
}

const language = mp.loadBundle(bundleJson);
let tree;
try {
  tree = language.parse(source);
  const diagnostics = language.lint(tree, {
    enabled: true,
    ruleSets: { "json/recommended": true },
    rules: { "json/recommended/negative-zero": "error" },
  });
  console.log(diagnostics);
} finally {
  tree?.free();
  language.free();
}
```

Lint fix 是 UTF-8 byte range 上的一条 `LintTextEdit`。应用前应确认诊断对应的 source 快照没有变化，并在编辑器宿主中完成 byte offset 到本地字符串坐标的转换。

## 9. Playground

Playground 位于 `website/`。从仓库根目录安装并启动：

```sh
npm install
npm --prefix website install
npm run build
npm --prefix website run dev
```

生产构建：

```sh
npm --prefix website run build
```

网站构建会同步权威 WASM runtime、Tree-sitter 资源和预编译语言资源。不要只复制 `website/src` 后绕开同步脚本，否则浏览器端 API 与仓库当前 ABI 可能不一致。

Playground 可以使用裸 Grammar，也可以导入目录/ZIP 形式的源码 Pack 或只读 Bundle。Source Pack 模式下可以编辑多文件项目、检查 Manifest、运行 Corpus、应用 Lint Quick Fix 并下载最新非 stale 的 Bundle/VSIX。Query、Binding Graph、LR conflict、增量 trace 和 Tree-sitter Compare 面板都是调试视图，不改变核心解析结果。

## 10. LSP 与 VS Code 接入

### 10.1 生成并启动 LSP

```sh
moon run cmd/main -- pack build languages/json \
  --target lsp --out-dir dist/json

cd dist/json/lsp
npm install
npm run build
node dist/server.js --stdio
```

`--stdio` 是编辑器启动 language server 时使用的标准传输方式。编辑器客户端负责启动进程，并按 LSP 发送 `initialize`、文档同步、definition、references、rename、codeAction 等请求。

生成的 LSP 会加载该 Pack 的 Bundle。具体能力取决于 Bundle capabilities：没有 bindings Query 就不会凭空获得 lexical resolution，没有 modules Query 或 Workspace provider 就不会获得严格的跨文件 import 语义。

### 10.2 生成并安装 VSIX

```sh
moon run cmd/main -- pack build languages/json \
  --target vscode --out-dir dist/json
```

VS Code target 会在生成目录安装依赖、编译 client/server 并运行打包流程。找到 `dist/json/vscode/` 下生成的 `.vsix` 后安装：

```sh
code --install-extension <generated-extension.vsix>
```

VSIX 内包含 language contribution、Bundle、WASM 和已编译 LSP server。TextMate grammar 当前只是最小骨架；主要语义高亮来自 Pack Query 经 LSP semantic tokens 输出。

## 11. Tree-sitter 互操作

MoonParse 可以把 Tree-sitter 的 `grammar.json` 导入为 Pack 起点，也可以把可表达的 Pack Grammar 导出为 `grammar.json`：

```sh
moon run cmd/main -- pack import-tree-sitter ../tree-sitter-example \
  --dir languages/example --id example --name "Example" --version 0.1.0

moon run cmd/main -- pack export-tree-sitter languages/example \
  -o build/example-grammar.json
```

这不是无损双向编译保证。两边的冲突、Scanner 和查询生态并不完全等价，导入后仍需执行 `pack check` 和 Corpus 测试。Playground 的 Compare 模式当前只保证 JSON 使用真实 Tree-sitter WASM 进行对比；不支持的语言会明确显示 unavailable。

## 12. 资源生命周期与正确性注意事项

### 12.1 显式释放 JavaScript/WASM 对象

`ParseTree`、`TreeCursor`、`MoonQuery`、`MoonParser` 和 `MoonLanguage` 背后持有 WASM 句柄。长期进程中必须调用 `free()`，推荐使用 `try/finally`。释放 `MoonLanguage` 时不要再单独使用其 `parser`；释放树后也不要继续访问 cursor 或执行 Query。

### 12.2 Bundle 与 Tree 必须匹配

`highlight()`、`resolveBindings()`、`modules()` 和 `lint()` 只能接收由同一 `MoonLanguage`/parser 创建的树。跨 Bundle 混用、已经释放的 handle 或旧 runtime 创建的对象会被拒绝。

### 12.3 增量解析的所有权

增量解析需要完整、准确的 `InputEdit`，同时包含 byte range 和行列范围。JavaScript 的 `parseIncremental()` / `parseIncrementalTrace()` 成功后，不应再使用传入的旧树；新树成为后续解析和 Query 的基准。增量路径失败时应保留或重新建立明确的全量解析策略，不能把半更新状态当成有效树。

### 12.4 UTF-8 与 UTF-16

MoonParse 核心、Query capture、Lint edit 和 Bundle API 的范围以 UTF-8 byte offset 为准。JavaScript 字符串、CodeMirror 和 LSP position 通常使用 UTF-16 code unit。遇到中文、emoji 或组合字符时必须经过显式转换，不能把 byte offset 直接作为字符串下标。

### 12.5 Scanner

缩进语言、上下文词法和外部词法规则可能需要 Scanner。Pack 的 Scanner descriptor 与宿主 provider 必须同时存在；构建成功不代表任意宿主都已经实现该 Scanner。部署新 Pack 时应同时验证 native、Node/WASM、LSP 和目标网页宿主的 provider 注册。

### 12.6 错误恢复

成功返回 CST 不等于源码没有语法错误。编辑器应读取 `errorSummary()` 或 CST 中的 `ERROR`/`MISSING` 节点，并把恢复诊断与宿主异常区分开。Corpus 中也应同时声明 error summary 与结构 snapshot，避免只验证“没有抛异常”。

## 13. 当前限制

- 尚未实现类型化 CST/AST codegen。当前所有生成目标都以通用 `CstNode`、Query capture 和 Bundle 为契约。
- 不提供完整类型检查器、控制流分析或语言特定的编译器语义。
- 单文件 lexical bindings 可以由通用 Query 描述；严格跨文件语义仍取决于 Pack 的 modules capability 和 Workspace provider。
- Tree-sitter 转换不是所有 Grammar、Scanner 和 Query 的无损映射；浏览器真实对比当前只保证 JSON。
- 生成的 TextMate grammar 是最小骨架，不能替代语义高亮 Query。
- Language Pack 的 external dependency source 不会自动被核心 Bundle 获取；文件发现、缓存、取消和资源限制属于宿主职责。

这些限制是边界而不是隐式承诺。需要 typed AST、完整类型系统或复杂项目模型的语言，应在 MoonParse 语法层之上增加独立包，而不是把语言特定语义塞入通用 Runtime。

## 14. 从哪里开始

- 只想解析一种文本：从根包 `compile_dsl()/parse_dsl()` 或 CLI `check/parse` 开始。
- 要发布一门语言：阅读 [language-packs.md](language-packs.md)，建立 Pack 和 Corpus，再生成 Bundle。
- 要嵌入 Node/浏览器：使用 `loadMoonParse()` 和 `MoonLanguage`，按本文要求释放资源。
- 要接入编辑器：先验证 Pack 的 highlights/bindings/modules/lint capabilities，再生成 LSP 或 VSIX。
- 要修改核心包边界：先阅读 [architecture.md](architecture.md) 和 [api-stability.md](api-stability.md)。
- 要更新生成物或测试：阅读 [generated-artifacts.md](generated-artifacts.md) 和 [testing.md](testing.md)。

MoonParse 当前的稳定主线是：一份 Grammar/Pack 产生一个可验证 Bundle，再由多个宿主消费同一语法能力。新增应用功能时应尽量复用这条链路，避免在 CLI、WASM、LSP 和 Website 中分别维护互不兼容的语言实现。

仓库级提交前的基础验证命令是：

```sh
moon info
moon fmt --check
moon test
npm test
npm run check:docs
```
