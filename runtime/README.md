# runtime 模块说明

## 1. 模块定位

`runtime/` 是 MoonParse 的运行时解析模块，负责消费 `tablegen/` 生成的 `ParseTable`，并将真实输入文本解析为 `CstNode` 形式的具体语法树（CST）。

本模块主要提供以下能力：

- 基于 `ParseTable` 执行完整解析；
- 在歧义或冲突存在时，以 GLR 方式并行推进解析路径；
- 在出现语法问题时尽量执行错误恢复，并产出带 `ERROR` / `MISSING` 节点的 CST；
- 在输入发生局部变更时，基于旧树执行增量解析；
- 支持外部词法器回调参与词法识别；
- 提供 CST 不变量检查与文法覆盖率统计工具。

## 2. 在整体系统中的位置

整体链路如下：

```text
Grammar DSL / Builder API
          |
          v
      grammar/
          |
          v
       Grammar
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
```

从整体链路看，`grammar/` 负责表示语法，`tablegen/` 负责将语法编译为解析表，`runtime/` 负责让解析表在真实输入上运行并产出 CST。因此，`runtime/` 是整条链路中最靠近最终输入文本的一层。它接受的是已经编译完成的 `ParseTable`，产出的是可供后续查询、遍历、转换或调试的 CST。

## 3. 架构与设计说明

`runtime/` 内部大致可分为以下几个子层：


| 文件              | 主要职责                                                           |
| ----------------- | ------------------------------------------------------------------ |
| `runtime.mbt`     | 对外公开入口；聚合默认解析、增量解析、DSL 便捷入口与外部扫描器入口 |
| `glr.mbt`         | GLR 主引擎；负责 GSS、活跃路径维护、错误恢复、路径截尾             |
| `parser.mbt`      | 线性 LR 解析路径；用于非歧义解析、测试与基准                       |
| `incremental.mbt` | 旧树标记、可复用节点查找、增量解析入口                             |
| `lexer.mbt`       | 上下文敏感词法引擎；支持 DFA 与外部词法器联合扫描                  |
| `invariants.mbt`  | CST 结构不变量检查与增量标记检查                                   |
| `coverage.mbt`    | 解析后覆盖率统计与报告输出                                         |
| `types.mbt`       | `CstNode`、`InputEdit`、`ParseConfig`、`ParseError` 等基础类型     |

对外看似只是一个 `parse()`，内部实际上由“词法、解析、恢复、增量、诊断”几层协同完成。默认入口 `parse()` 会委托给 `glr_parse()`，而不是 `parse_linear()`；这一设计体现了本模块优先适应真实语言文法、允许冲突和歧义在运行时以并行路径保留、并优先为编辑器与工具场景产出可恢复 CST 的取向，因此它更适合承担语言工具运行时，而不只是一个“纯理论上最严格的 LR 执行器”。

`runtime/` 的词法层也不是一个对所有 token 无条件扫描的独立阶段，而是会结合当前 LR 状态或 GLR 活跃状态集合，按“当前可接受 token 集”执行扫描。这样的设计既可以避免在不合法上下文中产生无意义 token，也能让同一份词法 DFA 在不同状态下表现为上下文敏感扫描器；在 GLR 场景下，还可以通过对所有活跃路径的合法 token 取并集来保持正确性，因此这里的词法器更准确地说是“由解析上下文驱动的运行时扫描器”。

增量解析采用的是偏保守的复用策略：先对旧树按编辑区间打上 `has_changes` 标记，再在新一轮解析中尝试查找可安全复用的子树，只有在起点、状态、前瞻边界等条件都满足时才真正复用。这样做的好处是复用条件清晰、在错误编辑下更容易保持正确性，也不需要假设所有旧节点都可以轻率挪用，本模块因此更重视“复用必须可靠”，而不是“尽量多复用”。

不变量检查与覆盖率统计则被设计为独立附加层，而不是嵌入主解析循环中。这样既能让主路径保持相对清晰，不必为调试逻辑承担常态成本，也能让测试、调试和回归评估工具按需启用这些能力。这说明 `runtime/` 不只服务“把文本变成树”这一最小目标，也服务“如何验证树是合理的”以及“如何知道样例是否覆盖了文法”。

## 4. 公开能力一览

对大多数调用方而言，最常用的入口主要集中在以下几组 API：


| 类别           | 主要 API                                                                                              | 说明                                             |
| -------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| 默认解析入口   | `parse`、`parse_with_config`                                                                          | 以 GLR 方式执行完整解析，支持错误恢复            |
| 便捷入口       | `parse_from_dsl`                                                                                      | 从 DSL 直接完成“建表 + 解析”，适合演示和小工具 |
| 严格线性解析   | `parse_linear`                                                                                        | 仅做单路径 LR 解析，适合非歧义文法、测试与基准   |
| 增量解析       | `parse_with_old_tree`、`parse_with_old_tree_and_config`、`parse_incremental`                          | 基于旧树与编辑描述复用未受影响子树               |
| 外部词法器     | `parse_with_external_scanner`、`parse_with_old_tree_and_external_scanner`                             | 允许调用方提供外部 token 识别逻辑                |
| 位置与编辑工具 | `bytes_to_point`、`byte_offset_to_char_col`、`apply_edit`                                             | 处理字节坐标、行列坐标与编辑标记                 |
| 诊断与校验     | `check_cst_invariants`、`check_clean_root`、`check_incremental_invariants`、`grammar_coverage_report` | 用于调试、测试与质量评估                         |
| 核心类型       | `CstNode`、`OldTree`、`InputEdit`、`ParseConfig`、`ParseError`、`Point`                               | 运行时数据模型                                   |

## 5. 用户如何使用

### 5.1 先理解几个入口之间的区别

初次使用时，最容易混淆的是 `parse`、`parse_linear` 和 `parse_from_dsl`。它们的适用场景并不相同。


| 入口                | 典型用途                          | 特点                                       |
| ------------------- | --------------------------------- | ------------------------------------------ |
| `parse`             | 正常运行时解析                    | 默认入口；内部走 GLR；尽量错误恢复         |
| `parse_with_config` | 需要调节恢复策略或 GLR 分支上限时 | 与`parse` 相同，但允许自定义 `ParseConfig` |
| `parse_linear`      | 非歧义文法、测试、基准            | 单路径 LR；不承担 GLR 并行歧义处理         |
| `parse_from_dsl`    | 快速演示、原型、测试样例          | 每次都会重新解析 DSL 并建表，不适合热路径  |

如果已经有了稳定的 `ParseTable`，建议优先使用 `parse()`；如果只是想快速验证一段 DSL 和一段输入能否跑通，可以使用 `parse_from_dsl()`；如果是在做白盒测试或性能基准，并且确信文法不会依赖 GLR 并行路径，则可以使用 `parse_linear()`。

### 5.2 最常见的使用方式：先生成 `ParseTable`，再调用 `parse`

这是生产场景下最推荐的方式。

```moonbit
import {
  "caiklonghuan/MoonParse/grammar" @grammar,
  "caiklonghuan/MoonParse/tablegen" @tablegen,
  "caiklonghuan/MoonParse/runtime" @runtime,
}

fn parse_input(dsl : String, input : String) -> Unit {
  let grammar = match @grammar.parse_grammar(dsl) {
    @grammar.Success(g) => g
    @grammar.Error(err) => {
      println("grammar parse error: " + err.message)
      return
    }
  }

  let validation = @grammar.validate_grammar(grammar)
  if !validation.is_empty() {
    for err in validation {
      println(err.to_string())
    }
    return
  }

  let table = match @tablegen.generate_parse_table(grammar) {
    Ok((table, _reports)) => table
    Err(msg) => {
      println("tablegen error: " + msg)
      return
    }
  }

  match @runtime.parse(table, input) {
    Ok(root) =>
      match @runtime.check_clean_root(root, input) {
        None =>
          println(
            "clean parse: root span = [" +
            root.start_byte.to_string() +
            ", " +
            root.end_byte.to_string() +
            ")",
          )
        Some(msg) => println("recovered parse: " + msg)
      }
    Err(err) => println("runtime error: " + err.message)
  }
}
```

一个最小的 DSL 示例：

```text
start list
extras [/[ \t\n\r]+/]
token rule ident: /[A-Za-z_][A-Za-z0-9_]*/
rule list: ident ("," ident)*
```

这个调用方式的优点在于：

- `Grammar` 解析与校验只做一次；
- `ParseTable` 可以缓存、序列化或复用；
- 运行时解析与语法编译解耦，更适合正式集成场景。

### 5.3 `parse()` 的一个关键事实：`Ok(root)` 不等于“无错误”

`runtime/` 的默认解析策略并不是“遇错立刻失败”，而是“优先产出一棵尽可能完整的 CST”。因此：

- `parse()` 返回 `Ok(root)` 时，`root` 仍然可能包含 `ERROR` 节点；
- 也可能包含由错误恢复插入的 `MISSING` 节点；
- `Err(ParseError)` 更偏向表示运行时级别的失败，例如表损坏、无法继续推进等极端情况。

因此，如果业务语义要求“只有完全干净的解析结果才算成功”，应在 `Ok(root)` 之后再执行一次：

```moonbit
match @runtime.check_clean_root(root, input) {
  None => println("clean tree")
  Some(msg) => println("tree contains recovery markers: " + msg)
}
```

这一点非常重要。若直接把 `Ok(root)` 视为“语法完全正确”，通常会在 IDE、格式化器、语法高亮或查询工具中引入误判。

### 5.4 何时使用 `parse_linear()`

`parse_linear()` 只维护一条 LR 路径。它适合以下场景：

- 文法是非歧义的，且不会依赖 GLR 分叉；
- 需要编写白盒测试，希望观察更直接的 LR 行为；
- 需要做基准测试，希望比较线性路径与 GLR 路径的差异。

示例：

```moonbit
match @runtime.parse_linear(table, input) {
  Ok(root) => println("linear parse ok: " + root.end_byte.to_string())
  Err(err) => println("linear parse failed: " + err.message)
}
```

需要注意：`parse_linear()` 并不是 `parse()` 的“更快替代品”。它在设计上更偏向测试和对照路径，不应默认替代正式运行时入口。

### 5.5 `parse_from_dsl()` 适合快速验证，不适合高频调用

如果希望从一段 DSL 直接得到解析结果，而不显式管理 `Grammar` 与 `ParseTable`，可以使用：

```moonbit
match @runtime.parse_from_dsl(dsl, input) {
  Ok(root) => println("parse ok: " + root.end_byte.to_string())
  Err(err) => println("parse failed: " + err.message)
}
```

该入口内部会执行以下流程：

1. 解析 DSL；
2. 执行 Grammar 级校验；
3. 生成 `ParseTable`；
4. 执行运行时解析。

它适合以下场景：

- 单元测试中的最小样例；
- 文档示例；
- 调试 DSL 时的快速验证；
- 小型命令行原型工具。

但应注意：

- 它每次调用都会重新建表；
- 不适合高频、低延迟解析路径；
- 它只会阻断部分 Grammar 级错误，不能替代正式构建链路中的显式校验策略。

### 5.6 如何进行增量解析

增量解析的核心思想是：给定旧输入、旧树和一次编辑描述，只重新解析受影响区域，并复用未受影响的子树。

最常见的入口是：

- `parse_with_old_tree(table, new_input, Some(old_tree), Some(edit))`

示例：

```moonbit
import {
  "caiklonghuan/MoonParse/tablegen" @tablegen,
  "caiklonghuan/MoonParse/runtime" @runtime,
}

fn reparse_after_edit(
  table : @tablegen.ParseTable,
  old_input : String,
  new_input : String,
) -> Unit {
  let old_root = match @runtime.parse(table, old_input) {
    Ok(root) => root
    Err(err) => {
      println("initial parse failed: " + err.message)
      return
    }
  }

  let old_tree : @runtime.OldTree = {
    root: old_root,
    old_input: old_input,
  }

  let edit : @runtime.InputEdit = {
    start_byte: 2,
    old_end_byte: 2,
    new_end_byte: 3,
    start_point: @runtime.bytes_to_point(
      old_input,
      0,
      { row: 0, column: 0 },
      2,
    ),
    old_end_point: @runtime.bytes_to_point(
      old_input,
      0,
      { row: 0, column: 0 },
      2,
    ),
    new_end_point: @runtime.bytes_to_point(
      new_input,
      0,
      { row: 0, column: 0 },
      3,
    ),
  }

  match
    @runtime.parse_with_old_tree(
      table,
      new_input,
      Some(old_tree),
      Some(edit),
    ) {
    Ok(root) => println("incremental parse ok: " + root.end_byte.to_string())
    Err(err) => println("incremental parse failed: " + err.message)
  }
}
```

使用增量解析时，请特别注意以下前提：

- `old_tree.root` 必须确实来自 `old_input`；
- `InputEdit` 中的字节位置必须与旧输入、新输入严格对应；
- `start_point` / `old_end_point` / `new_end_point` 也必须与字节编辑一致；
- 若旧树与旧输入不一致，或编辑坐标错误，复用判断将失去可靠性。

实践上，可以将 `OldTree` 理解为“旧版本语法树及其所属文本的绑定快照”。这类快照不应脱离原始输入单独保存和复用。

### 5.7 如何使用外部词法器

当文法中声明了外部 token，或者希望由调用方接管部分 token 识别逻辑时，可以使用带外部扫描器的入口。

外部扫描器类型如下：

```moonbit
type ExternalScanner = (String, Int, Array[Int]) -> (Int, Int)?
```

其含义是：

- 输入参数依次为当前完整输入、当前位置字节偏移、当前状态下允许的外部 token 集合；
- 返回 `None` 表示本次未匹配；
- 返回 `Some((tid, end_pos))` 表示识别到了一个终结符 `tid`，范围为 `[pos, end_pos)`。

一个最小示意例子如下：

```moonbit
import {
  "caiklonghuan/MoonParse/tablegen" @tablegen,
  "caiklonghuan/MoonParse/runtime" @runtime,
}

fn scanner(
  input : String,
  pos : Int,
  valid_external_tids : Array[Int],
) -> (Int, Int)? {
  let custom_tid = 7
  let mut allowed = false
  for tid in valid_external_tids {
    if tid == custom_tid {
      allowed = true
      break
    }
  }

  if allowed && pos < input.length() &&
    input[pos].to_int().to_char().unwrap() == '@' {
    Some((custom_tid, pos + 1))
  } else {
    None
  }
}

fn parse_with_scanner(
  table : @tablegen.ParseTable,
  input : String,
) -> Unit {
  match @runtime.parse_with_external_scanner(table, input, scanner) {
    Ok(root) => println("parse ok: " + root.end_byte.to_string())
    Err(err) => println("parse failed: " + err.message)
  }
}
```

需要注意：

- 外部扫描器使用的是**字节偏移**，不是字符索引；
- 只有 `valid_external_tids` 中允许的 token 才应被返回；
- 若外部扫描器与 DFA 同时匹配，运行时会按长度与规则优先级择优；
- 增量解析场景下也有对应入口 `parse_with_old_tree_and_external_scanner()`。

### 5.8 如何调节错误恢复策略

如果需要调节恢复代价或限制 GLR 活跃分支数，可以显式构造 `ParseConfig`。

```moonbit
import {
  "caiklonghuan/MoonParse/tablegen" @tablegen,
  "caiklonghuan/MoonParse/runtime" @runtime,
}

fn parse_with_custom_config(
  table : @tablegen.ParseTable,
  input : String,
) -> Unit {
  let config : @runtime.ParseConfig = {
    error_cost_per_skipped_tree: 100,
    error_cost_per_skipped_char: 1,
    error_cost_per_skipped_line: 30,
    error_cost_per_missing_tree: 110,
    error_cost_per_recovery: 500,
    max_version_count: 12,
    max_version_count_overflow: 4,
  }

  match @runtime.parse_with_config(table, input, config) {
    Ok(root) => println("parse ok: " + root.end_byte.to_string())
    Err(err) => println("parse failed: " + err.message)
  }
}
```

一般而言：

- 错误代价越高，解析器越不倾向于保留恢复路径；
- `max_version_count` 越大，GLR 分支保留越多，但成本也越高；
- 这些参数更适合调试、实验或特定语言调优，不建议在没有证据的情况下随意改动。

### 5.9 如何使用不变量检查与覆盖率统计

本模块还提供了两类非常实用的辅助能力。

第一类是不变量检查：

```moonbit
match @runtime.check_cst_invariants(root, input) {
  None => println("tree structure is valid")
  Some(msg) => println("tree invariant broken: " + msg)
}
```

如果需要确认得到的是一棵“完整覆盖输入、且不含 `ERROR` / `MISSING` 节点”的干净树，可以使用：

```moonbit
match @runtime.check_clean_root(root, input) {
  None => println("clean parse")
  Some(msg) => println("not clean: " + msg)
}
```

第二类是覆盖率统计：

```moonbit
let report = @runtime.grammar_coverage_report(
  table,
  ["a,b", "x,y,z"],
  1,
)
println(report)
```

该报告会统计：

- 每条规则命中次数；
- 每个产生式分支命中次数；
- token 命中情况；
- 错误恢复产生的 `ERROR` / `MISSING` 节点数量；
- 未命中规则与低命中分支。

如果是在做语法回归测试或样例集质量评估，这个接口很适合用来发现“哪些规则从未被样例覆盖”。

## 6. 运行时核心概念

### 6.1 `CstNode`

`CstNode` 是本模块最核心的数据结构。它同时承担：

- 叶节点；
- 内部节点；
- `ERROR` 节点；
- `MISSING` 节点；
- extras 节点（如空白、注释）。

理解 `CstNode` 时，建议重点关注以下字段：

- `symbol`：叶节点时是终结符，内部节点时是非终结符；
- `children`：子节点列表；
- `field_names`：与 `children` 等长，对应语法中声明的字段名；
- `start_byte` / `end_byte`：字节范围；
- `start_point` / `end_point`：行列坐标；
- `extra`：是否为 extras 节点；
- `is_missing`：是否为恢复时插入的虚拟缺失节点；
- `is_error`：是否为错误节点；
- `has_changes`：增量编辑后，该节点是否位于编辑影响区域。

对于大多数上层工具而言，最常见的遍历策略是：

1. 根据 `children` 判断是否为内部节点；
2. 根据 `extra` 过滤空白和注释；
3. 根据 `is_error` / `is_missing` 判断当前结果是否来自错误恢复；
4. 根据 `field_names` 建立更稳定的语义访问路径。

### 6.2 `Point`

`Point` 表示 0-based 的行列坐标，其 `column` 是**Unicode 代码点偏移**，不是 UTF-8 字节偏移。

这意味着：

- `start_byte` / `end_byte` 适合用于底层切片和编辑计算；
- `Point` 更适合用于展示、定位或与编辑器集成；
- 若已经有一个“某行上的字节列”，可以通过 `byte_offset_to_char_col()` 转换为字符列。

### 6.3 `OldTree` 与 `InputEdit`

这两个类型共同支撑增量解析：

- `OldTree` 绑定“旧 CST 根节点 + 旧输入文本”；
- `InputEdit` 描述一次从旧输入到新输入的局部修改。

`InputEdit` 同时保存：

- 字节起止范围；
- 旧文本上的结束点；
- 新文本上的结束点。

这样的设计是为了让运行时既能做字节级复用判定，也能在必要时修正行列坐标。

### 6.4 `ParseConfig`

`ParseConfig` 用于调节两类行为：

- 错误恢复代价；
- GLR 活跃路径截尾策略。

它并不是“语法配置”，而是“运行时策略配置”。因此，只有在确实需要调优恢复行为、控制分支规模或做实验比较时，才需要接触它。

### 6.5 `ParseError`

`ParseError` 是公开的运行时错误类型，但它的使用语义需要特别澄清：

- 它并不等价于“输入里存在语法错误”；
- 普通语法错误更多通过 `ERROR` / `MISSING` 节点体现在 `CstNode` 中；
- `ParseError` 更接近“运行时未能给出可接受解析结果”的信号。

因此，调用方在处理结果时，应优先区分两层含义：

1. 是否拿到了 `Result::Ok(root)`；
2. 这棵 `root` 是否是一棵干净树。

## 7. 使用时需要特别注意的事项

- `parse()` 的 `Ok(root)` 不表示输入没有语法问题；如需严格成功判定，应继续调用 `check_clean_root()`。
- `parse_from_dsl()` 是便捷入口，不应替代正式的“Grammar 校验 + 建表缓存 + 运行时解析”链路。
- `parse_linear()` 只适合非歧义或测试场景，不应默认作为生产解析入口。
- 增量解析中的 `OldTree` 必须与 `old_input` 一一对应，`InputEdit` 的字节与点位也必须严格一致。
- `Point.column` 是 Unicode 代码点列，不是字节列；不要将它直接当作 UTF-8 偏移使用。
- 外部扫描器返回的是字节范围，且只应返回当前上下文允许的外部 token。
- 若语法声明了 extras，CST 中通常会出现 `extra=true` 的节点；上层遍历时应决定是否过滤它们。
- 覆盖率报告会重新对样例集执行解析，因此在大样本集上应注意额外成本。

## 8. 适用场景总结

`runtime/` 特别适合以下几类场景：

- 语言服务器中的实时解析；
- 编辑器中的错误恢复与增量更新；
- 需要保留 CST 精确位置信息的语法工具；
- 语法测试框架、覆盖率统计与结构一致性校验工具；
- 需要把“语法定义”与“运行时执行”解耦的嵌入式解析器。

如果将整个 MoonParse 看作一条完整链路，那么 `runtime/` 正是把离线编译结果转化为在线解析能力的最后一层执行引擎。
