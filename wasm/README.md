# wasm 模块说明

## 1. 模块定位

`wasm/` 是 MoonParse 面向 WebAssembly 宿主环境的桥接模块，负责将 `grammar/`、`tablegen/`、`runtime/` 与 `query/` 的核心能力，整理为适合浏览器、Node.js 或其他 WASM 宿主调用的导出接口。

本模块主要提供以下能力：

- 创建、释放和复用解析器句柄；
- 执行全量解析与增量解析；
- 将解析结果导出为 JSON 或 S-表达式；
- 提供可跨边界使用的语法树游标；
- 在已解析语法树上执行结构化查询与语法高亮；
- 输出编译诊断、运行时解析错误、版本信息以及可序列化的解析表数据；

## 2. 在整体系统中的位置

整体链路如下：

```text
Grammar DSL / Grammar JSON / ParseTable JSON / ParseTable Bytes
                           |
                           v
                        wasm/
                           |
                           v
               Parser Handle / Tree Handle / Query Handle
                           |
                           v
         JSON / S-expression / Cursor Navigation / Highlight Ranges
```

若从内部依赖关系来看，可理解为：

- `grammar/` 负责语法定义与校验；
- `tablegen/` 负责语法编译；
- `runtime/` 负责解析与增量更新；
- `query/` 负责查询与高亮；
- `wasm/` 负责把前述能力组织成宿主可调用的导出 API。

## 3. 架构与设计说明

`wasm/` 内部可大致分为以下几部分：


| 文件             | 主要职责                                                                                           |
| ---------------- | -------------------------------------------------------------------------------------------------- |
| `wasm.mbt`       | 聚合主要导出；负责解析器创建、全量解析、增量解析、S-表达式与兼容封装                               |
| `handles.mbt`    | 维护解析器、语法树、游标、查询的全局注册表                                                         |
| `cursor.mbt`     | 提供跨边界游标导航与节点属性查询                                                                   |
| `query.mbt`      | 查询编译与执行结果的 JSON 导出                                                                     |
| `highlight.mbt`  | 高亮范围与局部变量解析结果的 JSON 导出                                                             |
| `cst_json.mbt`   | 将`CstNode` 序列化为树形 JSON                                                                      |
| `json_util.mbt`  | JSON 拼装与字符串转义辅助                                                                          |
| `moonparse.js`   | 面向浏览器 / Node.js 的高层 ES Module 封装，含`createParserFromBytes(Uint8Array)` / `tableBytes()` |
| `moonparse.d.ts` | 高层 JS API 的 TypeScript 类型声明                                                                 |
| `moonparse.wasm` | 与高层封装同目录分发的 wasm 构建产物                                                               |
| `package.json`   | JS/TS 分发入口定义                                                                                 |
| `serve.js`       | 本地调试`moonparse.js` / `test.html` 的极简静态服务器                                              |
| `test.html`      | 浏览器侧快速验证页面                                                                               |

这种拆分使得 `wasm/` 可以在保持导出面稳定的同时，把不同类别的边界逻辑分别维护；同时将 JS/TS wrapper 与 `moonparse.wasm` 放在同一目录，也能保持默认的 `./moonparse.wasm` 相对加载路径稳定。由于宿主侧难以直接安全持有或操作 MoonBit 内部对象，本模块采用“注册表 + 整数句柄”的设计，让解析器、语法树、游标和查询对象能够跨多次调用持续存在；相比反复把整棵树完整序列化再反序列化，这一模型更适合长期复用解析器、增量解析复用旧树、按游标逐步访问节点以及缓存并重复执行查询。在接口层，本模块同时保留低层 API 与 `wasm_*` 薄封装，前者面向长期持有状态的工具集成，后者面向快速对接、调试和生态兼容，使外部工具可以用接近 `web-tree-sitter` 的方式接入而不必先理解全部底层句柄细节。跨 WASM 边界时则大量返回 JSON 字符串，因为这类结果结构清晰，浏览器与 Node.js 可以直接消费，也更适合测试、日志、调试和网络传输，同时避免宿主侧理解 MoonBit 内存布局；其代价是整树导出存在额外序列化成本，因此在高频交互场景中，句柄 + 游标通常比频繁输出完整树 JSON 更合适。

## 4. 公开能力一览

对宿主调用方而言，本模块的公开 API 大体可分为以下几组：


| 类别                 | 主要 API                                                                                                                                                           | 说明                                                              |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------- |
| 解析器生命周期       | `parser_create_from_dsl`、`parser_create_from_json`、`parser_create_from_bytes`、`parser_create_from_base64`、`parser_create_from_grammar_json`、`parser_free`     | 创建或释放解析器句柄                                              |
| 解析器元信息         | `parser_get_dsl`、`parser_diagnostics_json`、`parser_dsl_error_last`、`parser_table_to_json`、`parser_table_to_bytes`、`parser_table_to_base64`                    | 获取 DSL、编译诊断与序列化表                                      |
| 解析配置与运行时错误 | `parse_error_last`、`parse_config_set`、`parse_config_reset`                                                                                                       | 查询最近一次运行时 parse 失败原因，或调节 / 重置 GLR 错误恢复参数 |
| 语法树生命周期       | `parse_full`、`parse_incremental`、`tree_to_json`、`tree_root_sexp`、`tree_error_summary`、`tree_free`                                                             | 以句柄方式管理语法树                                              |
| 游标 API             | `cursor_new`、`cursor_goto_first_child`、`cursor_goto_next_sibling`、`cursor_goto_parent` 及各类 `cursor_node_*`                                                   | 在宿主侧逐步遍历语法树                                            |
| 查询 API             | `query_compile`、`query_compile_error_last`、`query_exec`、`query_free`                                                                                            | 编译并执行结构化查询                                              |
| 高亮 API             | `highlight_exec`、`highlight_exec_with_locals`、`highlight_names_json`                                                                                             | 在语法树上执行高亮和局部变量解析                                  |
| 兼容性薄封装         | `wasm_create_parser`、`wasm_create_parser_from_json`、`wasm_parse`、`wasm_parse_incremental`、`wasm_node_sexp`、`wasm_query`、`wasm_free_tree`、`wasm_free_parser` | 与`web-tree-sitter` 风格更接近的一次性接口                        |
| 其他工具             | `moonparse_version`                                                                                                                                                | 返回版本字符串                                                    |

## 5. 用户如何使用

### 5.1 先理解两种调用风格

`wasm/` 同时提供两类接口：

1. 低层句柄接口：调用方持有 `parser_id`、`tree_id`、`cursor_id`、`query_id` 等整数句柄，自行控制生命周期。
2. 高层便捷接口：以 `wasm_*` 命名，尽量返回 JSON 字符串并在内部做部分资源清理。

整体上，长期复用的编辑器集成、增量解析、游标遍历或查询缓存更适合使用低层句柄接口；快速完成“建 parser + parse + 得到 JSON”这类一次性动作时，则更适合使用 `wasm_*` 薄封装。

### 5.2 推荐使用流程：解析器句柄 + 语法树句柄

对大多数正式集成场景，建议采用如下流程：

1. 创建解析器句柄；
2. 使用 `parse_full()` 获取语法树句柄；
3. 通过 `tree_to_json()`、`tree_root_sexp()`、游标、查询或高亮来消费该树；
4. 在不再使用时分别释放树句柄、游标句柄、查询句柄和解析器句柄。

下面示例中的 `api` 表示“宿主侧已经拿到的 WASM 导出对象”。为避免把文档绑定到某一种 JS 加载器，以下示例不展示实例化细节，只展示接口使用方式。

```javascript
const parserId = api.parser_create_from_dsl(dsl)
if (parserId < 0) {
  throw new Error(api.parser_dsl_error_last())
}

const treeId = api.parse_full(parserId, source)
if (treeId < 0) {
  throw new Error(api.parse_error_last() || "parse failed")
}

const treeJson = api.tree_to_json(treeId)
const sexp = api.tree_root_sexp(treeId)
const summary = api.tree_error_summary(treeId)

api.tree_free(treeId)
api.parser_free(parserId)
```

这种用法的优势在于：

- 解析器可长期复用，不必每次重新编译；
- 语法树在宿主侧有稳定句柄，可继续做游标导航、查询和高亮；
- 生命周期由调用方明确控制，适合 IDE、编辑器或长期运行服务。

需要补充一点：`parse_full()` 只有在解析表损坏、参数无效等运行时异常场景下才会返回 `-1`，此时应通过 `parse_error_last()` 读取错误原因。对于普通的源码语法错误，`parse_full()` 通常仍会返回一棵带 `ERROR` / `MISSING` 节点的语法树，此时应结合 `tree_error_summary()`、游标或完整树遍历来处理。

### 5.3 解析器可以从四类语义来源创建

本模块支持四类解析器来源；其中“二进制 ParseTable”这一类，会根据宿主边界不同提供两种装载入口：


| 入口                                                     | 输入                                                    | 典型场景                       |
| -------------------------------------------------------- | ------------------------------------------------------- | ------------------------------ |
| `parser_create_from_dsl`                                 | Grammar DSL 文本                                        | 开发期、调试期、在线语法编辑器 |
| `parser_create_from_grammar_json`                        | `grammar_to_json()` 导出的 Grammar JSON                 | 语法模型已结构化持久化         |
| `parser_create_from_json`                                | `table_to_json()` 导出的 ParseTable JSON                | 离线建表，运行时直接回载       |
| `parser_create_from_bytes` / `parser_create_from_base64` | `serialize_table()` 导出的二进制表 / 其 Base64 传输形式 | 启动性能敏感的生产环境         |

若宿主能够直接传递 MoonBit `Bytes`，可使用 `parser_create_from_bytes()` / `parser_table_to_bytes()`。

若宿主通过 `moonparse.js` / `moonparse.d.ts` 在 JS 或 TypeScript 侧接入，则应使用高层包装器提供的 `createParserFromBytes(Uint8Array)` 与 `parser.tableBytes()`：包装层会在内部通过 `parser_create_from_base64()` / `parser_table_to_base64()` 跨过 wasm-gc 边界，但语义上仍然是“直接加载二进制表”，不会退回 JSON 中转。

例如：

```javascript
import { loadMoonParse } from "moonparse"

const mp = await loadMoonParse()
const bytes = new Uint8Array(await fetch("./parser.parse_table").then(r => r.arrayBuffer()))
const parser = mp.createParserFromBytes(bytes)
```

由 `moon run cmd/main -- wasm -t lang.parse_table` 生成的 `dist/parser.js`，现在走的就是这条“二进制表直载”路径。

若使用 DSL 创建解析器，模块内部会执行：

1. DSL 解析；
2. Grammar 级校验；
3. ParseTable 生成；
4. 冲突报告整理。

若创建失败：

- `parser_create_from_dsl()` 与 `parser_create_from_grammar_json()` 失败时，可通过 `parser_dsl_error_last()` 查看最近一次错误信息；
- `parse_full()` 与 `parse_incremental()` 返回 `-1` 时，可通过 `parse_error_last()` 查看最近一次运行时解析错误；
- `parser_diagnostics_json()` 返回的是成功建表后的冲突诊断，不是运行时 parse 错误。

示例：先从 DSL 创建，再读取冲突报告。

```javascript
const parserId = api.parser_create_from_dsl(dsl)
if (parserId < 0) {
  console.error(api.parser_dsl_error_last())
} else {
  console.log(api.parser_diagnostics_json(parserId))
}
```

### 5.4 若只需要 JSON 结果，可以使用 `wasm_*` 便捷接口

若仅需“直接拿到 JSON 结果”，而不需要长期持有树句柄，则可使用以下封装：

- `wasm_create_parser(dsl)`
- `wasm_create_parser_from_json(tableJson)`
- `wasm_parse(parserId, source)`
- `wasm_node_sexp(treeId)`
- `wasm_query(treeId, pattern)`

示例：

```javascript
const parserId = api.wasm_create_parser(dsl)
if (parserId < 0) {
  throw new Error(api.parser_dsl_error_last())
}

const json = api.wasm_parse(parserId, source)
if (!json) {
  throw new Error("parse failed")
}

api.wasm_free_parser(parserId)
```

需要注意：`wasm_parse()` 返回的是 JSON 字符串，而不是树句柄。因此，调用完成后，无法再对这次解析结果执行游标导航或增量复用。

### 5.5 如何遍历语法树：使用游标 API

若宿主侧不希望一次性反序列化整棵 JSON 树，而是希望按需遍历节点，可使用游标。

典型流程如下：

1. 先有一个有效的 `tree_id`；
2. 调用 `cursor_new(treeId)` 创建游标；
3. 使用 `cursor_goto_first_child()`、`cursor_goto_next_sibling()`、`cursor_goto_parent()` 导航；
4. 使用 `cursor_node_*` 获取当前节点属性；
5. 最后调用 `cursor_free()` 释放游标。

```javascript
const treeId = api.parse_full(parserId, source)
const cursorId = api.cursor_new(treeId)

console.log(api.cursor_node_type(cursorId))
console.log(api.cursor_node_child_count(cursorId))

if (api.cursor_goto_first_child(cursorId) === 1) {
  console.log(api.cursor_node_type(cursorId))
  console.log(api.cursor_node_field(cursorId))
  console.log(api.cursor_node_text(cursorId))
}

api.cursor_free(cursorId)
api.tree_free(treeId)
```

这里有几点需要特别注意：

- 游标导航函数返回的是 `1` 或 `0`，而不是布尔值；
- `cursor_node_text()` 返回当前节点对应的原始切片；
- `cursor_node_field()` 返回的是该节点在父节点中的字段名，无字段名时返回空串；
- `cursor_node_start_byte()` / `cursor_node_end_byte()` 是更适合宿主处理编辑与切片的稳定位置。

### 5.6 如何做增量解析

本模块提供两层增量接口：

- 低层接口 `parse_incremental(...)`：显式传入 `12` 个位置参数；
- 便捷接口 `wasm_parse_incremental(parserId, source, oldTreeId, changesJson)`：将编辑信息打包为 JSON 字符串。

对大多数宿主调用方，建议优先使用 `wasm_parse_incremental()`，因为它更接近浏览器或编辑器侧常见的“变更对象”传递方式。

`changes_json` 需要至少包含以下字段：

- `start_byte`
- `old_end_byte`
- `new_end_byte`
- `start_row`
- `start_col`
- `old_end_row`
- `old_end_col`
- `new_end_row`
- `new_end_col`

示例：

```javascript
const parserId = api.wasm_create_parser(dsl)
const oldTreeId = api.parse_full(parserId, "ab")

const changes = JSON.stringify({
  start_byte: 1,
  old_end_byte: 2,
  new_end_byte: 2,
  start_row: 0,
  start_col: 1,
  old_end_row: 0,
  old_end_col: 2,
  new_end_row: 0,
  new_end_col: 2,
})

const newTreeJson = api.wasm_parse_incremental(parserId, "ad", oldTreeId, changes)
if (!newTreeJson) {
  throw new Error(api.parse_error_last() || "incremental parse failed")
}
```

使用时请特别留意两个行为：

- `parse_incremental()` 返回的是新的 `tree_id`，因此调用方需要自行管理旧树和新树的释放；
- `wasm_parse_incremental()` 返回的是 JSON 字符串，并且会在内部消费旧树句柄与新树句柄，不再把新树继续留给宿主侧复用。

若编辑器集成希望在多次增量更新之间反复复用最新树，应优先使用低层 `parse_incremental()`，而不是一次性 `wasm_parse_incremental()`。

### 5.7 如何调节 GLR 错误恢复参数

`parse_full()` 与 `parse_incremental()` 现在都会读取一份全局的 `ParseConfig`。宿主可通过以下两个导出函数修改它：

- `parse_config_set(...)`：按位置参数覆盖当前配置；
- `parse_config_reset()`：将配置恢复为默认值。

`parse_config_set(...)` 一共接收 7 个整数参数，顺序如下：

1. `error_cost_per_skipped_tree`
2. `error_cost_per_skipped_char`
3. `error_cost_per_skipped_line`
4. `error_cost_per_missing_tree`
5. `error_cost_per_recovery`
6. `max_version_count`
7. `max_version_count_overflow`

其中，某个位置传 `-1` 表示“保留当前值不修改”。示例：

```javascript
api.parse_config_set(
  -1,  // error_cost_per_skipped_tree
  -1,  // error_cost_per_skipped_char
  50,  // error_cost_per_skipped_line
  90,  // error_cost_per_missing_tree
  400, // error_cost_per_recovery
  8,   // max_version_count
  -1,  // max_version_count_overflow
)

const treeId = api.parse_full(parserId, source)

api.parse_config_reset()
```

需要注意两点：

- 该配置是 wasm 模块级别的全局配置，不是某个 `parser_id` 私有的配置；
- 它只影响后续的 `parse_full()` / `parse_incremental()` 调用，不会 retroactive 地改变已生成的语法树。

若通过 `wasm/moonparse.js` 的高层封装接入，则可使用更友好的对象式 API：`setParseConfig({...})`、`resetParseConfig()` 与 `parseErrorLast()`。

### 5.8 如何执行查询与高亮

若目标是“在已经解析出的树上做结构化匹配”，应使用查询 API。

查询的典型流程如下：

1. 使用 `query_compile(pattern)` 得到 `query_id`；
2. 若失败，通过 `query_compile_error_last()` 读取 JSON 形式的错误对象；
3. 使用 `query_exec(queryId, treeId)` 执行查询；
4. 使用 `query_free(queryId)` 释放查询句柄。

```javascript
const queryId = api.query_compile("(identifier) @name")
if (queryId < 0) {
  console.error(api.query_compile_error_last())
} else {
  console.log(api.query_exec(queryId, treeId))
  api.query_free(queryId)
}
```

若只需要一次性查询，也可以使用：

```javascript
const capturesJson = api.wasm_query(treeId, "(identifier) @name")
```

高亮接口在用法上与查询相似，但它返回的是高亮范围数组 JSON：

```javascript
const hlQueryId = api.query_compile(highlightPattern)
const rangesJson = api.highlight_exec(hlQueryId, treeId)
console.log(api.highlight_names_json())
api.query_free(hlQueryId)
```

若还需要做“局部变量作用域 + 高亮”联合处理，则应调用：

```javascript
const rangesJson = api.highlight_exec_with_locals(hlQueryId, localsQueryId, treeId)
```

### 5.9 `tree_to_json()`、`tree_root_sexp()`、`tree_error_summary()` 与 `parse_error_last()` 的区别

这几个接口的用途不同：

- `tree_to_json(treeId)`：返回完整树的 JSON 表示，适合宿主侧反序列化或直接传递；
- `tree_root_sexp(treeId)`：返回 Tree-Sitter 风格的 S-表达式，适合调试、测试对比和快照；
- `tree_error_summary(treeId)`：返回简短状态摘要，典型值如 `ok`、`error:行:列`、`invalid`。
- `parse_error_last()`：仅在 `parse_full()` / `parse_incremental()` 返回 `-1` 时用于读取最近一次运行时错误，不用于描述普通源码语法错误。

其中，`tree_error_summary()` 只适合作为快速状态探测，不应替代完整的错误诊断或树遍历；`parse_error_last()` 则更像是“fatal error channel”，与树级错误摘要不是一个层面的信息。

## 6. 边界模型与核心概念

### 6.1 句柄是宿主与 GC 对象之间的桥

由于宿主侧无法直接安全持有 MoonBit 的内部 GC 对象，本模块采用“整数句柄 + 全局注册表”的设计。对调用方而言，应把所有 `*_id` 都视为“受生命周期约束的临时引用”。

在当前实现中：

- `>= 1` 通常表示有效句柄；
- `-1` 常用于表示创建或解析失败；
- 空字符串 `""`、空数组字符串 `"[]"`、`0` 等返回值通常表示无效输入或失败降级。

因此，调用方不应假设所有错误都会以异常形式抛出，而应显式检查返回值。

### 6.2 `Parser`、`Tree`、`Cursor`、`Query` 是四类不同资源

宿主侧通常会同时接触四类对象：

- `parser_id`：已编译解析表与编译诊断；
- `tree_id`：解析结果树、对应原始输入以及表快照；
- `cursor_id`：树上的当前位置和回溯路径；
- `query_id`：已编译的查询对象。

这四者的生命周期彼此独立。尤其需要注意的是，`tree_id` 内部保存了输入与表快照，因此后续游标遍历、查询、高亮并不要求原始 parser 仍然存活。

### 6.3 JSON 字符串是跨边界的主要交换格式

本模块大量使用 JSON 字符串作为跨边界输出，原因在于：

- 宿主语言易于消费；
- 不需要额外共享复杂内存布局；
- 适合调试和网络传输；
- 与查询结果、高亮范围、诊断信息这类结构化结果天然匹配。

这也意味着：若追求最低序列化成本，应优先选择句柄 + 游标模式，而不是频繁调用完整树 JSON 导出。

## 7. 适用场景总结

`wasm/` 特别适合以下场景：

- 浏览器内语法解析与结构化展示；
- 编辑器或 IDE 中的实时语法树更新；
- 基于 WebAssembly 的查询、高亮和代码浏览工具；
- 需要将 MoonParse 嵌入 JS / WASM 宿主环境的在线分析器；
- 需要在“轻量集成”和“长期状态复用”之间自由切换的语言工具。

如果将 MoonParse 的其他模块视为内部能力层，那么 `wasm/` 可以看作其面向宿主世界的稳定接口层：它并不创造新的解析能力，但决定了这些能力能否以可管理、可集成、可调试的方式真正落地。
