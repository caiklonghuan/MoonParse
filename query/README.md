# query 模块说明

## 1. 模块定位

`query/` 是 MoonParse 的结构化查询模块，负责在已经构造完成的 CST 上执行 Tree-Sitter 风格的 S-表达式模式匹配，并将命中的节点以捕获结果、高亮区间或局部变量解析结果的形式返回给调用方。

本模块主要提供以下能力：

- 将查询字符串编译为 `CompiledQuery`；
- 在 CST 上执行模式匹配，并返回捕获结果；
- 支持字段约束、捕获、交替模式、量词、锚点与后置谓词；
- 基于查询结果生成高亮区间；
- 基于 locals 查询解析局部变量引用关系；
- 提供节点类型名与节点文本提取工具。

## 2. 在整体系统中的位置

整体链路如下：

```text
Grammar DSL / Builder API
          |
          v
      grammar/
          |
          v
      tablegen/
          |
          v
      runtime/
          |
          v
         CST
          |
          v
       query/
          |
          v
captures / highlight ranges / local resolution
```

从整体分工来看，`grammar/` 负责描述语法本身，`tablegen/` 负责把语法编译为解析表，`runtime/` 负责把输入文本解析成 CST，而 `query/` 则负责从 CST 中提取结构化信息，因此它是一层典型的“语法树消费模块”。它依赖 `runtime` 的 `CstNode` 和 `tablegen` 的 `ParseTable`，但不依赖 `wasm/`，因此既可供纯 MoonBit 代码直接使用，也可被 `wasm/` 继续包装为宿主导出接口。

## 3. 架构与设计说明

`query/` 内部由多层职责配合完成查询能力：`types.mbt` 定义查询 AST、捕获结果、谓词、量词及辅助类型，`parser.mbt` 负责手写递归下降查询编译，`matcher.mbt` 负责查询执行、回溯匹配与谓词过滤，`highlight.mbt` 负责高亮区间生成与排序，`locals.mbt` 负责局部变量作用域与引用解析，`query_test.mbt` 与 `highlight_test.mbt` 则覆盖编译器、匹配器、高亮和 locals 的端到端行为。这说明 `query/` 并不是单纯的模式解析器，而是一套同时覆盖编译、执行和语义派生的完整查询子系统。

对应到文件层面，主要结构如下：

| 文件                 | 主要职责                                     |
| -------------------- | -------------------------------------------- |
| `types.mbt`          | 查询 AST、捕获结果、谓词、量词与辅助类型定义 |
| `parser.mbt`         | 手写递归下降查询编译器                       |
| `matcher.mbt`        | 查询执行引擎、回溯匹配与谓词过滤             |
| `highlight.mbt`      | 高亮区间生成与排序                           |
| `locals.mbt`         | 局部变量作用域与引用解析                     |
| `query_test.mbt`     | 编译器与匹配器端到端测试                     |
| `highlight_test.mbt` | 高亮与 locals 行为测试                       |

当前实现选择手写递归下降，而不是再引入一套新的语法定义链路，因为查询语法规模较小、错误位置需要直接按字符偏移返回、查询语言也不需要单独维护一套 Grammar DSL 与 ParseTable，同时模式语言的演进可以更直接地落在 `parser.mbt` 中。这种设计更适合查询语言这类规模较小、形态稳定且对报错可读性要求较高的子系统。

`exec()` 的外层行为是对整棵 CST 做先序 DFS，并在每个节点上尝试所有顶层模式；当某条 `NodePattern` 命中后，其子节点匹配采用“有序子序列 + 回溯”策略，要求子模式顺序保持一致，但允许跳过不相关的语义子节点，`*` 与 `+` 会先贪心收集候选，再通过回溯与后续模式共同确定最终消费位置，`extra` 子节点会被自动忽略，而字段约束、量词、交替与锚点也都通过回溯选择可行路径，尾锚点 `pattern .` 对普通子模式和带量词的最后一个子模式同样生效。这使查询语言既具备结构约束能力，又不要求把每一层 CST 辅助节点都写得极端精确。

高亮与 locals 没有直接塞进 `exec()` 主路径，而是建立在通用查询结果之上的独立层，这样可以让查询引擎本身保持通用，同时让高亮与语义增强复用同一套匹配基础设施，也让 `wasm/` 与其他调用方按需引入相应能力。因此，`query/` 既可作为结构查询引擎使用，也可作为编辑器语义层的一部分。

## 4. 公开能力一览

对大多数调用方而言，本模块最常用的公开 API 如下：


| 类别         | 主要 API                                                                                                           | 说明                                                               |
| ------------ | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------ |
| 查询编译     | `compile`                                                                                                          | 将 S-表达式查询字符串编译为`CompiledQuery`                         |
| 查询执行     | `exec`                                                                                                             | 在 CST 上执行查询，返回`Array[CaptureResult]`                      |
| 高亮         | `apply_highlights`、`apply_highlights_with_locals`、`highlight_names`                                              | 基于查询结果生成高亮区间                                           |
| 局部变量解析 | `resolve_locals`                                                                                                   | 解析`@local.scope` / `@local.definition` / `@local.reference` 关系 |
| 节点工具     | `node_type_name`、`node_text`                                                                                      | 获取节点显示类型名与原始文本                                       |
| 核心类型     | `CompiledQuery`、`QueryPattern`、`PatternChild`、`Predicate`、`CaptureResult`、`HighlightRange`、`LocalResolution` | 查询系统的核心数据模型                                             |

## 5. 用户如何使用

### 5.1 推荐使用流程

典型使用链路如下：

1. 先通过 `runtime/` 得到 `root : CstNode` 与对应 `ParseTable`；
2. 编写查询字符串；
3. 调用 `compile()` 得到 `CompiledQuery`；
4. 调用 `exec()`、`apply_highlights()` 或 `resolve_locals()` 消费结果；
5. 视业务需要，再将结果转换为导航、高亮、提示或检查信息。

在 `query/` 中，`input` 也是必须提供的参数。原因在于：

- 字面量匹配依赖节点原文；
- `#eq?` / `#not-eq?` / `#match?` / `#not-match?` / `#any-of?` 谓词依赖捕获节点文本；
- 高亮与 locals 解析也需要原始文本辅助判断。

### 5.2 最基础的用法：编译并执行查询

```moonbit
import {
  "caiklonghuan/MoonParse/query" @query,
  "caiklonghuan/MoonParse/runtime" @runtime,
  "caiklonghuan/MoonParse/tablegen" @tablegen,
}

fn run_identifier_query(
  root : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> Unit {
  let compiled = match @query.compile("(identifier) @name") {
    Ok(q) => q
    Err(err) => {
      println(err.to_string())
      return
    }
  }

  let captures = @query.exec(compiled, root, input, table)
  for capture in captures {
    println(
      capture.capture_name +
      ": " +
      @query.node_text(capture.node, input),
    )
  }
}
```

这个例子表达的是：

- 在整棵树上进行一次先序遍历；
- 每遇到一个类型名为 `identifier` 的节点，就按 `@name` 记录一次捕获；
- 最终返回的不是“匹配树”，而是一个扁平的 `CaptureResult` 数组。

### 5.3 查询语言的核心语法

当前实现支持的查询写法主要包括以下几类：


| 语法           | 示例                                                     | 说明                               |
| -------------- | -------------------------------------------------------- | ---------------------------------- |
| 命名节点匹配   | `(identifier)`                                           | 按节点类型名匹配                   |
| 匿名字面量匹配 | `"+"`                                                    | 匹配叶节点原文                     |
| 通配符         | `_`                                                      | 匹配任意单节点                     |
| 字段约束       | `left: (identifier)`                                     | 要求命中的子节点来自指定字段       |
| 子节点捕获     | `(identifier) @lhs`                                      | 将该子模式命中节点加入捕获结果     |
| 顶层捕获       | `(call_expression) @call`                                | 将整个顶层模式命中节点加入捕获结果 |
| 交替模式       | `[(identifier) (number)]`                                | 匹配若干模式中的任一个             |
| 量词           | `(argument)*`、`(item)+`、`(type)?`                      | 作用于子节点模式                   |
| 锚点           | `. (identifier)`、`(identifier) .`                       | 约束匹配必须贴近首/末语义子节点    |
| 谓词           | `#eq?`、`#not-eq?`、`#match?`、`#not-match?`、`#any-of?` | 对捕获结果做后置过滤               |
| 注释           | `; comment`                                              | 行注释，从`;` 到行尾               |

例如：

```scheme
(binary_expression
  left: (identifier) @lhs
  right: (identifier) @rhs)
```

表示：

- 匹配一个 `binary_expression` 节点；
- 其 `left` 字段必须命中一个 `identifier`；
- 其 `right` 字段也必须命中一个 `identifier`；
- 这两个节点分别作为 `lhs` 与 `rhs` 返回。

### 5.4 如何使用谓词

当前实现支持五类后置谓词：

- `#eq? @capture "literal"`
- `#not-eq? @capture "literal"`
- `#match? @capture "regex"`
- `#not-match? @capture "regex"`
- `#any-of? @capture "a" "b" "c"`

示例：仅匹配文本恰好为 `add` 的标识符。

```scheme
(identifier) @name
#eq? @name "add"
```

示例：仅匹配全小写标识符。

```scheme
(identifier) @name
#match? @name "^[a-z]+$"
```

示例：排除文本为 `self` 的标识符。

```scheme
(identifier) @name
#not-eq? @name "self"
```

示例：匹配不以 `_` 开头的标识符。

```scheme
(identifier) @name
#not-match? @name "^_"
```

示例：仅匹配若干给定关键字之一。

```scheme
(identifier) @kw
#any-of? @kw "if" "else" "while"
```

在语义上，谓词总是归属到它之前最近的一条顶层模式。也就是说，若一个查询文件中有多条模式，则每条模式会维护自己的一组谓词，而不是全局共享一组过滤条件。

### 5.5 如何理解 `exec()` 的返回结果

`exec()` 的返回类型是：

```moonbit
Array[CaptureResult]
```

这意味着查询结果是“按捕获展开后的扁平列表”，而不是“按模式分组后的树状结构”。若需知道哪些捕获来自同一次顶层匹配，可使用 `match_id` 进行分组。

示例：按 `match_id` 理解结果。

```moonbit
for capture in captures {
  println(
    "match=" +
    capture.match_id.to_string() +
    ", capture=" +
    capture.capture_name,
  )
}
```

这里有一个很容易忽略的事实：

- 某个模式即使匹配成功，如果没有任何 `@capture`，`exec()` 仍可能返回空数组；
- `match_id` 只会在顶层模式真正命中时递增；
- 顶层捕获 `(pattern) @name` 与子节点捕获 `(child) @name` 都会进入同一个 `match_id` 组。

### 5.6 高级用法：交替、量词与锚点

若查询需要表达更灵活的结构，可使用交替、量词与锚点。

交替模式示例：

```scheme
[(identifier) (number_literal)] @atom
```

表示匹配 `identifier` 或 `number_literal` 任一节点，并统一作为 `atom` 捕获。

量词示例：

```scheme
(argument_list (argument)*)
```

表示 `argument_list` 下可以有零个或多个 `argument` 子节点。

这里的量词匹配遵循“按顺序扫描语义子节点并尽量多匹配”的语义：

- 命中的子节点相对顺序必须保持；
- 中间允许跳过不相关的语义子节点；
- `*` / `+` 会贪心地收集尽可能多的命中项，再通过回溯与后续模式协同决定最终结果。

锚点示例：

```scheme
(call_expression . (identifier) @callee)
```

表示 `identifier` 必须出现在该节点的第一个语义子节点位置，不允许在它之前跳过其他语义子节点。

再例如：

```scheme
(tuple (identifier) @last .)
```

表示被捕获的 `identifier` 必须是最后一个语义子节点。

若最后一个子模式带量词，尾锚点同样生效。例如：

```scheme
(tuple (identifier)+ @item .)
```

表示最后这一段量词匹配结束后，后面不能再有剩余语义子节点。

### 5.7 如何做高亮查询

`query/` 不只用于结构化搜索，也可直接生成高亮区间。

```moonbit
import {
  "caiklonghuan/MoonParse/query" @query,
  "caiklonghuan/MoonParse/runtime" @runtime,
  "caiklonghuan/MoonParse/tablegen" @tablegen,
}

fn build_highlights(
  root : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> Unit {
  let hq = match @query.compile(
    #|(number_literal) @number
    #|(string_literal) @string
  ) {
    Ok(q) => q
    Err(err) => {
      println(err.to_string())
      return
    }
  }

  let ranges = @query.apply_highlights(root, input, table, hq)
  for range in ranges {
    println(
      range.highlight_name +
      " [" +
      range.start_byte.to_string() +
      ", " +
      range.end_byte.to_string() +
      ")",
    )
  }
}
```

这里的关键点是：

- 高亮名来自捕获名本身，例如 `@number` 会生成 `highlight_name = "number"`；
- 返回值会按 `start_byte` 升序排列；
- 零宽的非错误节点不会被转成高亮区间；
- `@local.*` 系列捕获会在普通高亮输出中被过滤掉。

如需枚举系统内置支持的高亮名称，可使用：

```moonbit
let names = @query.highlight_names
```

### 5.8 如何做 locals 解析与“局部变量高亮”

`query/` 还支持通过专门的 locals 查询，将引用节点标记为“是否绑定到某个局部定义”。

locals 查询通常使用以下约定捕获名：

- `@local.scope`
- `@local.definition`
- `@local.reference`

示例：

```scheme
(block) @local.scope
(identifier) @local.definition
(identifier) @local.reference
```

执行：

```moonbit
let locals_query = match @query.compile(locals_query_src) {
  Ok(q) => q
  Err(err) => {
    println(err.to_string())
    return
  }
}

let resolution = @query.resolve_locals(root, input, table, locals_query)
if resolution.is_local_ref(42) {
  println("node at start_byte=42 is a local reference")
}
```

若已具备一份普通高亮查询，还可直接调用：

```moonbit
let ranges = @query.apply_highlights_with_locals(
  root,
  input,
  table,
  highlight_query,
  locals_query,
)
```

在这种模式下，被识别为局部引用的高亮项会被追加 `.local` 后缀，例如：

- `variable` → `variable.local`
- `variable.parameter` → `variable.parameter.local`

### 5.9 `node_type_name()` 与 `node_text()` 适合做什么

这两个工具函数虽然简单，但很常用：

- `node_type_name(node, table)`：返回查询匹配所用的节点类型名；
- `node_text(node, input)`：返回节点覆盖的原始文本切片。

其中，`node_type_name()` 会优先尊重别名信息，因此它更贴近查询语言中实际书写的节点名，而不是简单暴露底层符号编号。

## 6. 查询语言与核心概念

### 6.1 `CompiledQuery`

`CompiledQuery` 表示一次查询编译的结果。它内部包含：

- 多条顶层模式；
- 每条顶层模式各自关联的一组谓词。

这意味着一个查询字符串完全可以是“多条模式并列”的，而不是只能写一条：

```scheme
(function_definition) @fn
(class_definition) @class
```

这两条模式会独立匹配、独立编号，但最终结果仍合并到同一个 `Array[CaptureResult]` 中返回。

### 6.2 `QueryPattern` 与 `PatternChild`

`QueryPattern` 是查询模式 AST，当前主要有四种变体：

- `NodePattern`
- `AnonPattern`
- `Wildcard`
- `Alternation`

而 `PatternChild` 则是对子节点约束的包装，它把以下信息集中在一起：

- 字段约束；
- 子模式；
- 捕获名；
- 量词；
- 首尾锚点。

因此，`PatternChild` 可以理解为“一个子位置上应满足的完整匹配条件”，而不是简单的“子节点类型名”。

### 6.3 `Predicate`

当前实现支持五类谓词：

- `Eq(capture_name, literal)`
- `NotEq(capture_name, literal)`
- `Match(capture_name, regex)`
- `NotMatch(capture_name, regex)`
- `AnyOf(capture_name, values)`

它们都是后置过滤条件。也就是说，只有在模式本身已经命中后，谓词才会检查捕获文本；若谓词不通过，则这次顶层匹配整体失效。

### 6.4 `CaptureResult`

`CaptureResult` 是查询执行后的核心结果类型，它记录：

- `match_id`：该捕获属于哪一次顶层模式命中；
- `capture_name`：捕获名称；
- `node`：命中的 CST 节点。

它本身并不拷贝文本内容。若调用方需要文本，应通过 `node_text(capture.node, input)` 动态获取。

### 6.5 `HighlightRange` 与 `LocalResolution`

这两类结果分别面向不同场景：

- `HighlightRange` 面向编辑器高亮渲染；
- `LocalResolution` 面向局部变量解析与语义增强。

`HighlightRange` 保存的是区间、点位与高亮名；`LocalResolution` 则按 `start_byte` 建立引用是否为本地变量的映射。因此它们都不是“通用查询结果”的替代品，而是查询能力在特定应用场景下的进一步加工结果。

## 7. 适用场景总结

`query/` 特别适合以下场景：

- 在 CST 上提取定义、引用、调用点等结构信息；
- 做语法高亮与语义高亮；
- 做局部变量引用识别与简单作用域分析；
- 做代码导航、lint、语法规则检查与结构化统计；
- 在不引入额外 AST 层的前提下，直接消费运行时 CST。

如果说 `runtime/` 负责把文本变成树，那么 `query/` 负责把“树里的结构意义”提取出来。它是 MoonParse 从“能解析”走向“能消费解析结果”的关键一层。
