# tablegen 模块说明

## 1. 模块定位

`tablegen/` 是 MoonParse 的离线解析表编译模块，负责把 `grammar/` 产出的 `Grammar` 语法对象，编译为可供 `runtime/` 直接加载和执行的 `ParseTable`。

本模块主要提供以下能力：

- 将 `Grammar` 规范化为增广文法；
- 计算 `nullable`、`FIRST`、`FOLLOW` 等集合；
- 构建 LR 项目集族与 GOTO 转移；
- 生成 LALR(1) 解析表；
- 处理 shift/reduce、reduce/reduce 冲突，并输出诊断报告；
- 构建上下文敏感词法 DFA；
- 将最终解析表序列化为 JSON 或二进制字节流。

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
```

整体上可将 `grammar/` 理解为负责语法表示，`tablegen/` 负责语法编译，`runtime/` 负责执行编译结果；因此，`tablegen/` 是整个系统中的编译中枢，它向前依赖 `Grammar`，向后产出 `ParseTable`。

## 3. 架构与设计说明

```text
Grammar
  |
  v
normalize.mbt
  |
  v
AugmentedGrammar
  |
  +--> sets.mbt      计算 nullable / FIRST / FOLLOW
  |
  +--> items.mbt     构造 LR(0) 项目集族与 GOTO
  |
  +--> lalr.mbt      生成原始 LALR 表
  |
  +--> conflicts.mbt 按优先级、结合性与声明冲突做消解
  |
  +--> lexer.mbt     生成上下文敏感词法 DFA
  |
  +--> serialize.mbt 输出 JSON / Bytes
  |
  v
ParseTable
```


| 文件            | 主要职责                                | 设计意图                                      |
| --------------- | --------------------------------------- | --------------------------------------------- |
| `normalize.mbt` | 将`Grammar` 展开为 `AugmentedGrammar`   | 把高阶 Pattern 统一降到更适合自动机构造的形式 |
| `sets.mbt`      | 计算`nullable`、`FIRST`、`FOLLOW`       | 为 closure、lookahead、规约分析提供数学基础   |
| `items.mbt`     | 构造 LR 项目集、闭包与 GOTO             | 形成状态机骨架                                |
| `lalr.mbt`      | 从项目集和 GOTO 生成原始 LALR 解析表    | 得到尚未消解冲突的 action / goto              |
| `conflicts.mbt` | 处理 shift/reduce 与 reduce/reduce 冲突 | 让优先级、结合性、显式冲突声明真正影响结果    |
| `lexer.mbt`     | 构建上下文敏感词法 DFA                  | 让词法扫描与 LR 状态保持联动                  |
| `serialize.mbt` | JSON / 二进制序列化与反序列化           | 提供表落盘与跨进程交换能力                    |
| `tablegen.mbt`  | 一键编排整个流程                        | 为调用方提供稳定的单入口                      |

`tablegen/` 的处理链路从 `normalize.mbt` 开始，先把 `Grammar` 统一展开为 `AugmentedGrammar`，将高阶 Pattern、别名、字段和前瞻等 DSL 特性提前下沉到扁平数据模型中；`sets.mbt` 基于这一标准形计算 `nullable`、`FIRST`、`FOLLOW`，为 closure、lookahead 和规约分析提供基础；`items.mbt` 与 `lalr.mbt` 负责构造 LR 项目集、GOTO 和原始 LALR 表，形成状态机骨架；`conflicts.mbt` 将优先级、结合性和显式冲突声明落实为最终动作选择；`lexer.mbt` 构建受 LR 状态约束的上下文敏感词法 DFA，并把 `valid_tokens` 与解析状态直接联动；`serialize.mbt` 负责 JSON 与二进制落盘；`tablegen.mbt` 则把整个流水线编排成稳定的一键入口。整体设计上，模块选择“规范化先行”，是为了让后续算法始终围绕统一数据模型工作，而不必直接处理高阶 Pattern；同时保留 `generate_parse_table()` 这一默认入口和分阶段 API，以兼顾常规调用、调试、可视化与研究型工具；编译结果将 `ConflictReport` 与 `ParseTable` 分离，便于独立消费诊断信息；`LexerDfa` 直接注入最终 `ParseTable`，从而让运行时加载一个统一数据结构即可完成词法与语法联动。

## 4. 公开能力一览

对大多数调用方而言，最常用的入口只有一个：

- `generate_parse_table(grammar)`

其余 API 主要面向调试、分析、可视化工具或自定义编译流水线。


| 类别         | 主要 API                                                                     | 说明                                             |
| ------------ | ---------------------------------------------------------------------------- | ------------------------------------------------ |
| 一键编译入口 | `generate_parse_table`                                                       | 从`Grammar` 一步生成最终 `ParseTable` 与冲突报告 |
| 规范化       | `augment_grammar`                                                            | 将高阶 Pattern 展开为增广 CFG                    |
| 集合计算     | `nullable`、`first_set`、`first_seq`、`follow_set`                           | 供分析和表构造使用                               |
| LR 自动机    | `closure`、`goto_set`、`build_item_sets`、`build_goto_map`                   | 构造 LR 项目集族与状态转移                       |
| LALR 表构造  | `build_lalr_table`、`resolve_conflicts`                                      | 生成并消解冲突                                   |
| 词法 DFA     | `build_lexer_dfa`                                                            | 基于终结符定义和 LR 状态构建上下文敏感词法器     |
| 序列化       | `table_to_json`、`table_from_json`、`serialize_table`、`deserialize_table`   | 解析表落盘与回读                                 |
| 核心类型     | `AugmentedGrammar`、`ParseTable`、`Production`、`ConflictReport`、`LexerDfa` | 贯穿编译过程的关键数据结构                       |

## 5. 用户如何使用

### 5.1 推荐使用流程

对于绝大多数调用方，建议采用如下流程：

1. 使用 `grammar/` 构造或解析得到 `Grammar`。
2. 视调用方策略决定是否先调用 `validate_grammar`。
3. 调用 `generate_parse_table` 生成 `ParseTable`。
4. 检查冲突报告 `ConflictReport`。
5. 视需要将表序列化为 JSON 或二进制。
6. 将序列化结果交给 `runtime/` 或工具链下游使用。

其中，第 2 步需要特别说明：`tablegen.generate_parse_table()` **不会自动调用** `grammar.validate_grammar()`。如果构建链路要求先做 Grammar 级诊断，应由调用方自己决定校验策略。

### 5.2 一键生成 ParseTable

这是最常见的使用方式。

```moonbit
import {
  "caiklonghuan/MoonParse/grammar" @grammar,
  "caiklonghuan/MoonParse/tablegen" @tablegen,
}

fn compile_list_grammar(dsl : String) -> Unit {
  let grammar = match @grammar.parse_grammar(dsl) {
    @grammar.Success(g) => g
    @grammar.Error(err) => {
      println(
        "grammar parse error: " +
        err.message +
        " at " +
        err.location.line.to_string() +
        ":" +
        err.location.column.to_string(),
      )
      return
    }
  }

  let (table, reports) = match @tablegen.generate_parse_table(grammar) {
    Ok(result) => result
    Err(msg) => {
      println("tablegen error: " + msg)
      return
    }
  }

  println("states = " + table.states.to_string())
  println("productions = " + table.productions.length().to_string())
  println("conflict reports = " + reports.length().to_string())
}
```

一个可工作的最小 DSL 示例：

```text
start list
extras [/[ \t\n\r]+/]
rule list: item ("," item)*
rule item: /[A-Za-z_][A-Za-z0-9_]*/
```

这个例子表达的是：

- `list` 是起始规则；
- 空白可在任意位置出现；
- `item` 是一个基于正则的终结符规则；
- `list` 由一个或多个逗号分隔的 `item` 组成。

### 5.3 若需要 Grammar 级校验，如何接在 `tablegen` 之前

如果场景是 CLI、CI 或正式构建，一般建议先执行 Grammar 级校验，再决定是否继续表编译。

```moonbit
import {
  "caiklonghuan/MoonParse/grammar" @grammar,
  "caiklonghuan/MoonParse/tablegen" @tablegen,
}

fn compile_with_validation(grammar : @grammar.Grammar) -> Unit {
  let validation = @grammar.validate_grammar(grammar)
  let fatal_errors : Array[@grammar.ValidationError] = []
  let warnings : Array[@grammar.ValidationError] = []

  for err in validation {
    match err.kind {
      @grammar.ValidationErrorKind::DirectLeftRecursion(_)
      | @grammar.ValidationErrorKind::IndirectLeftRecursion(_) =>
        warnings.push(err)
      _ => fatal_errors.push(err)
    }
  }

  if !fatal_errors.is_empty() {
    for err in fatal_errors {
      println(err.to_string())
    }
    return
  }

  let (_table, reports) = match @tablegen.generate_parse_table(grammar) {
    Ok(result) => result
    Err(msg) => {
      println("tablegen error: " + msg)
      return
    }
  }

  println("warnings = " + warnings.length().to_string())
  println("conflicts = " + reports.length().to_string())
}
```

这里之所以把左递归单独降级处理，是因为当前命令行生成流程也采用了相似策略：GLR 运行时可以处理一部分左递归文法，因此“是否把左递归视为致命错误”是调用方策略，而不是 `tablegen/` 的硬编码决定。

### 5.4 如何处理冲突报告

`generate_parse_table()` 的返回值中，第二项是 `Array[ConflictReport]`。这不是附带信息，而是编译产物诊断的一部分。

示例：按严重级别打印冲突信息。

```moonbit
import {
  "caiklonghuan/MoonParse/tablegen" @tablegen,
}

fn print_conflict_reports(reports : Array[@tablegen.ConflictReport]) -> Unit {
  for report in reports {
    let level = match report.severity {
      @tablegen.ConflictSeverity::Warn(_) => "warn"
      @tablegen.ConflictSeverity::Ambiguous(_) => "ambiguous"
      @tablegen.ConflictSeverity::DynamicConflict(_) => "dynamic"
      @tablegen.ConflictSeverity::Declared(_) => "declared"
    }
    println(
      level +
      " conflict at state=" +
      report.state.to_string() +
      " terminal=" +
      report.terminal.to_string(),
    )
  }
}
```

这些严重级别的典型含义如下：

- `Warn`：编译期已用优先级或结合性成功消解，但仍值得报告；
- `Ambiguous`：无法在编译期完全消解，需要 GLR 并行保留路径；
- `DynamicConflict`：依赖 `prec.dynamic` 之类的运行时动态优先级机制；
- `Declared`：该冲突已被文法显式声明为预期歧义。

### 5.5 高级用法：分阶段观察编译流水线

如果目标不是“直接拿到最终解析表”，而是研究内部过程、做可视化或编写调试工具，则可以按子阶段调用。

```moonbit
import {
  "caiklonghuan/MoonParse/grammar" @grammar,
  "caiklonghuan/MoonParse/tablegen" @tablegen,
}

fn inspect_pipeline(grammar : @grammar.Grammar) -> Unit {
  let aug = @tablegen.augment_grammar(grammar)
  let item_sets = @tablegen.build_item_sets(aug)
  let goto_map = @tablegen.build_goto_map(aug, item_sets)
  let raw_table = @tablegen.build_lalr_table(aug, item_sets, goto_map)
  let (resolved_table, reports) = @tablegen.resolve_conflicts(raw_table, aug)
  let dfa = @tablegen.build_lexer_dfa(aug, resolved_table)

  println("nonterminals = " + aug.nonterminals.length().to_string())
  println("terminals = " + aug.terminals.length().to_string())
  println("item sets = " + item_sets.length().to_string())
  println("raw states = " + raw_table.states.to_string())
  println("reports = " + reports.length().to_string())
  println("lexer dfa states = " + dfa.states.length().to_string())
}
```

需要注意：这类低层 API 主要面向分析和调试。若目标是产出完整可交付的 `ParseTable`，默认应优先使用 `generate_parse_table()`，因为最终成品表还需要补入 `terminal_names`、`extras`、`external_token_ids`、`word_token`、`keyword_map` 等运行时元数据。

### 5.6 序列化与回读

若已经得到 `ParseTable`，可以选择两种持久化形式：

- JSON：可读、便于检查、适合诊断与调试；
- 二进制：更紧凑、适合实际落盘与运行时加载。

示例：表的 JSON / 二进制序列化与回读。

```moonbit
import {
  "caiklonghuan/MoonParse/tablegen" @tablegen,
}

fn roundtrip_table(table : @tablegen.ParseTable) -> Unit {
  let json = @tablegen.table_to_json(table)
  let bytes = @tablegen.serialize_table(table)

  let from_json = match @tablegen.table_from_json(json) {
    Ok(t) => t
    Err(msg) => {
      println("table_from_json failed: " + msg)
      return
    }
  }

  let from_bytes = match @tablegen.deserialize_table(bytes) {
    Ok(t) => t
    Err(msg) => {
      println("deserialize_table failed: " + msg)
      return
    }
  }

  println("json states = " + from_json.states.to_string())
  println("binary states = " + from_bytes.states.to_string())
}
```

## 6. 核心概念

### 6.1 AugmentedGrammar

`AugmentedGrammar` 是 `Grammar` 经过规范化与增广后的中间表示。它是 `tablegen/` 内部所有核心算法的输入基础。

它至少包含以下关键内容：

- `terminals`：终结符名称到 `TerminalId` 的映射；
- `nonterminals`：非终结符名称到 `NonTerminalId` 的映射；
- `productions`：扁平化后的产生式序列；
- `terminal_patterns`：终结符词法定义；
- `extras`：可在任意 LR 状态出现的附加 token；
- `prec_table`：顶层 precedence 声明对应的优先级表；
- `word_token`：关键字提升对应的通用单词 token；
- `declared_conflicts`：显式声明的冲突组。

使用上，可以把它理解为“进入算法前的标准化 CFG”。

```moonbit
let aug = @tablegen.augment_grammar(grammar)
println("productions = " + aug.productions.length().to_string())
println("terminals = " + aug.terminals.length().to_string())
println("nonterminals = " + aug.nonterminals.length().to_string())
```

### 6.2 ParseTable

`ParseTable` 是 `tablegen/` 的最终核心产物，也是 `runtime/` 的直接输入。

它包含：

- `action`：`(state, terminal) -> [Action]`；
- `goto_table`：`(state, nonterminal) -> state`；
- `productions`：完整产生式列表；
- `lexer_dfa`：上下文敏感词法 DFA；
- `symbol_metadata`：非终结符元数据；
- `terminal_patterns` / `terminal_names`：词法定义与反查表；
- `extras` / `external_token_ids` / `word_token` / `keyword_map`：运行时所需辅助信息。

使用上，可以把 `ParseTable` 理解为“运行时可执行解析器的只读数据镜像”。

```moonbit
let (table, _reports) = match @tablegen.generate_parse_table(grammar) {
  Ok(result) => result
  Err(_msg) => panic()
}
println("states = " + table.states.to_string())
println("productions = " + table.productions.length().to_string())
println("dfa states = " + table.lexer_dfa.states.length().to_string())
```

### 6.3 Production

`Production` 表示一条扁平化产生式，典型字段包括：

- `head`：产生式头部非终结符；
- `body`：产生式体；
- `prec` / `assoc`：优先级与结合性；
- `rule_name`：来源规则名；
- `lookahead`：由 `!p` / `&p` 提取出的前瞻约束；
- `alias_name`：经 `alias(...)` 指定的对外别名。

它最适合在调试 normalize、冲突消解和运行时规约行为时阅读。

### 6.4 ConflictReport

`ConflictReport` 是编译诊断结果，不属于语法树或运行时数据本体，但对调用方决策非常重要。

它至少说明：

- 冲突出现在第几个 LR 状态；
- 是由哪个 lookahead 终结符触发；
- 当前格子里有哪些候选动作；
- 编译器将其归类为哪种严重级别。

如果场景是 IDE 诊断、命令行编译器或解析表调试工具，应优先消费这一结构，而不是只盯着 `ParseTable.action` 的最终结果。

### 6.5 LexerDfa

`LexerDfa` 并不是一个与语法无关的普通扫描器，而是一个**受 LR 状态约束的上下文敏感词法器**。

其中最关键的是：

- `states`：词法 DFA 状态集合；
- `start`：起始词法状态；
- `valid_tokens`：每个 LR 状态下当前允许出现的 token 集合。

这意味着 `tablegen` 中的词法构建，不是简单地“为整个语言做一个全局 DFA”，而是将词法层与语法层联动起来，以减少歧义和无效扫描。

## 7. 使用时需要特别注意的事项

### 7.1 `generate_parse_table()` 不会自动做 Grammar 级校验

它只检查最基本的入口条件，例如：

- 语法不能为空；
- 必须声明 `start`；
- `start` 规则必须存在。

若还需要检查：

- 未定义规则；
- 非法 regex；
- `extras` 中的非终结符；
- 模板参数不匹配；
- `word` / `token rule` 约束；

这些都应在调用 `tablegen` 之前，由 `grammar.validate_grammar()` 负责。

### 7.2 并不是所有校验错误都必须一刀切阻塞编译

当前项目的命令行生成流程会把直接/间接左递归降级为警告，而不是强制阻塞。这是因为 GLR 运行时对某些左递归文法是可处理的。

因此，建议调用方根据自身场景定义策略，而不要假定“`validate_grammar()` 有结果就一定不能继续编译”。

### 7.3 默认优先使用 `generate_parse_table()`

除非明确需要观测中间状态，否则不建议手工拼接以下流水线：

- `augment_grammar`
- `build_item_sets`
- `build_goto_map`
- `build_lalr_table`
- `resolve_conflicts`
- `build_lexer_dfa`

原因是最终可交付的 `ParseTable` 还需要补齐若干运行时字段，单靠这些中间阶段函数并不能自动得到完整成品表。

### 7.4 冲突报告非空，不等于表不可用

需要根据 `ConflictSeverity` 具体判断：

- `Warn`：通常可继续；
- `Declared`：表示预期歧义，通常可继续；
- `DynamicConflict`：是否接受，取决于运行时策略；
- `Ambiguous`：往往意味着需要显式容忍 GLR 歧义，很多正式构建链路会选择阻塞。

因此，调用方应把“是否允许继续输出表”作为策略层决策，而不是把“有无报告”当成唯一条件。

### 7.5 JSON 与二进制各有用途

- `table_to_json()`：适合调试、可视化、快照测试、诊断输出；
- `serialize_table()`：适合真正落盘、交给 runtime 加载、减少体积。

如果只是想“看懂表长什么样”，优先用 JSON；如果目标是做实际编译产物分发，优先用二进制。

### 7.6 `ParseTable` 是运行时协议，而不只是编译中间值

一旦将 `ParseTable` 交给 `runtime/`，其中的 `lexer_dfa`、`keyword_map`、`terminal_names`、`extras`、`external_token_ids` 等字段都会参与真实解析行为。

因此，不建议对成品表做随意手工篡改，除非完全理解运行时消费协议。

## 8. 适合哪些调用场景

本模块尤其适合以下场景：

- 构建 MoonParse 语法文件对应的离线解析表；
- 编写 parser 生成器 CLI；
- 做 LR / LALR 教学、项目集可视化或冲突分析工具；
- 生成可序列化、可缓存、可部署的运行时解析产物；
- 在 IDE 或 Web 工具中展示 grammar 编译结果和冲突信息。

若需求是“直接解析一段源码得到 CST”，则应继续使用 `runtime/`，而不是停留在 `tablegen/` 层。
