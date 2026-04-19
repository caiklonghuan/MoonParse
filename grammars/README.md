# grammars 模块说明

## 1. 模块定位

`grammars/` 是 MoonParse 的内置语法示例层，负责提供一组可直接复用的 Grammar DSL 字符串、配套的 `parse_*` 便捷入口、S-expression 快照辅助函数、高亮查询字符串，以及若干用于测试和构造语法的小型公共片段。

本模块主要提供以下能力：

- 内置若干示例或子集语言的 Grammar DSL 常量；
- 为这些内置语法提供直接可调用的 `parse_*` 入口；
- 提供 `*_sexp` 辅助函数，便于结构快照测试；
- 提供与内置语法配套的高亮查询和 locals 查询字符串；
- 提供常见注释、空白、数字、字符串等可拼装 DSL 片段；
- 提供若干面向黑盒测试的树结构断言工具。

## 2. 架构与设计说明

### 2.1 模块内部结构

`grammars/` 内部目前主要由以下文件组成：


| 文件                                   | 主要职责                                          |
| -------------------------------------- | ------------------------------------------------- |
| `common.mbt`                           | 空白、注释、标识符、数字、字符串等可复用 DSL 片段 |
| `internal.mbt`                         | `compile_builtin_grammar()` 等共享内部编译辅助    |
| `json.mbt` / `json5.mbt`               | JSON / JSON5 内置 Grammar 与解析入口              |
| `c.mbt` / `python.mbt` / `moonbit.mbt` | C、Python、MoonBit 子集语法与解析入口             |
| `*.grammar`                            | 与公开 `*_grammar` 常量同步的 DSL 文件快照        |
| `highlights.mbt`                       | 与内置语法配套的高亮与 locals 查询字符串          |
| `sexp.mbt`                             | CST 到 tree-sitter 风格 S-expression 的导出逻辑   |
| `assert_utils.mbt`                     | 面向测试的节点、区间、树结构断言工具              |
| `*_test.mbt`                           | 各内置语法的黑盒与回归测试                        |

本模块同时暴露了可读的 DSL 常量和可直接调用的解析入口。这样做的好处是，初学者可以立刻跑通示例，进阶用户也能看到并修改底层 Grammar，文档、测试、调试三种使用方式都能复用同一套资源。对于内置语法，重复在每次 `parse_*` 时重新建表没有意义，因此选择在模块加载时编译一次，后续直接复用内部的 `ParseTable`，同时在开发期尽早暴露内置语法本身失效的问题。这是一种偏向“便捷性与稳定测试”的设计，而不是追求最小导入成本。

除了 `.mbt` 中导出的 DSL 常量外，仓库现在也把这些入口语法同步落成了真实 `.grammar` 文件，方便直接交给 CLI、脚本或外部工具使用，而不需要再从源码字符串里手工提取。

将示例语法与高亮查询放在同一个包里，是因为没有配套查询的话，很多编辑器和测试场景仍需额外配置节点命名规则。同包放置能让调用方更容易确认语法与查询的配对关系，也便于项目自身的回归测试直接围绕完整样本运行。

对于 C、Python、MoonBit 这类语言，当前的目标并不是在 `grammars/` 中完整复制官方规范，而是提供足够稳定的示例语法、有代表性的结构，以及能覆盖查询、高亮和恢复测试的核心子集。这使得 `grammars/` 更像一个项目内建样本库，而不是正式发布的完整语言前端集合。

## 3. 在整体系统中的位置

从依赖关系上看，`grammars/` 并不是主生成链路的一环，而是一层建立在现有核心模块之上的“内置内容层”：

```text
内置 Grammar DSL / 内置 Query Strings / 测试辅助
                    |
                    v
                 grammars/
          +---------+----------+
          |                    |
          v                    v
     grammar/ + tablegen/     query/
          |                    |
          v                    v
       runtime/           highlight / locals
          |
          v
   parse_* / *_sexp helpers
```

## 4. 公开能力一览

对调用方而言，本模块最常用的公开能力如下：


| 类别               | 主要 API                                                                                                                         | 说明                                                  |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| 内置 Grammar DSL   | `json_grammar`、`json5_grammar`、`c_grammar`、`python_grammar`、`moonbit_grammar`、`expression_grammar` | 提供可直接交给`grammar/` 或 `tablegen/` 的 DSL 字符串 |
| 直接解析入口       | `parse_json`、`parse_json5`、`parse_c`、`parse_python`、`parse_moonbit`、`parse_expression`               | 内部复用预编译解析表，直接返回`CstNode`               |
| 快照辅助           | `json_sexp`、`json5_sexp`、`c_sexp`、`python_sexp`、`moonbit_sexp`、`expression_sexp`                                            | 生成 tree-sitter 风格 S-expression，便于断言测试      |
| 高亮与 locals 查询 | `json_highlight_query`、`json5_highlight_query`、`c_highlight_query`、`moonbit_highlight_query`、`moonbit_locals_query`          | 与内置语法配套的查询字符串                            |
| DSL 公共片段       | `whitespace_pattern`、`horizontal_ws_pattern`、`ascii_identifier_pattern`、`c_style_extras()`、`hash_comment_extras()` 等        | 用于拼装自定义 Grammar DSL 的常用片段                 |
| 测试断言           | `assert_node_text_eq`、`assert_span_eq`、`assert_point_eq`、`assert_tree_shape_eq`、`assert_cst_invariants`                      | 面向项目内黑盒测试的稳定断言工具                      |

## 5. 用户如何使用

### 5.1 推荐使用流程

对大多数调用方，`grammars/` 有两种典型用法：

1. 把它当“现成语言入口”：直接调用 `parse_json()`、`parse_moonbit()` 这类函数；
2. 把它当“示例与资源仓库”：取出 `*_grammar`、`*_highlight_query` 等字符串，再交给底层模块继续处理。

如果目标只是快速演示、测试或 smoke test，优先用第一种；如果需要可配置的建表、查询或运行时策略，优先用第二种。

### 5.2 最简单的用法：直接调用 `parse_*`

```moonbit
import {
  "caiklonghuan/MoonParse/grammars" @grammars,
}

fn demo_json() -> Unit {
  let input = #|{"x": [1, 2, 3]}
  match @grammars.parse_json(input) {
    Ok(root) => println(@grammars.json_sexp(input))
    Err(err) => println("parse failed: " + err.message)
  }
}
```

这种方式的特点是：

- 不需要自己手动解析 Grammar DSL；
- 不需要自己生成 `ParseTable`；
- 适合文档示例、单元测试和最小可运行样例。

### 5.3 若需检查或改造内置语法，应使用 `*_grammar`

`grammars/` 并没有把内置语法隐藏成黑盒；相反，它把 DSL 文本本身作为公开常量导出，因此调用方可以把这些语法重新送回主链路。

```moonbit
import {
  "caiklonghuan/MoonParse/grammar" @grammar,
  "caiklonghuan/MoonParse/tablegen" @tablegen,
  "caiklonghuan/MoonParse/grammars" @grammars,
}

fn build_json_table() -> Unit {
  let grammar = match @grammar.parse_grammar(@grammars.json_grammar) {
    @grammar.Success(g) => g
    @grammar.Error(err) => {
      println(err.message)
      return
    }
  }

  let errors = @grammar.validate_grammar(grammar)
  if !errors.is_empty() {
    println("unexpected validation errors")
    return
  }

  ignore(@tablegen.generate_parse_table(grammar))
}
```

这条路径适合以下场景：

- 想检查某份内置语法到底长什么样；
- 想在内置语法基础上做局部修改；
- 想把它接到自己的 `tablegen/`、`runtime/`、`query/` 流水线里。

### 5.4 如何使用内置高亮与 locals 查询

高亮查询字符串和内置 Grammar 是配套设计的，但本模块**不会**把对应 `ParseTable` 直接公开出来。因此，若要做高亮，通常需要自行用 `*_grammar` 再建一遍表。

```moonbit
import {
  "caiklonghuan/MoonParse/grammar" @grammar,
  "caiklonghuan/MoonParse/tablegen" @tablegen,
  "caiklonghuan/MoonParse/runtime" @runtime,
  "caiklonghuan/MoonParse/query" @query,
  "caiklonghuan/MoonParse/grammars" @grammars,
}

fn moonbit_highlights(source : String) -> Unit {
  let grammar = match @grammar.parse_grammar(@grammars.moonbit_grammar) {
    @grammar.Success(g) => g
    @grammar.Error(_) => return
  }
  let table = match @tablegen.generate_parse_table(grammar) {
    Ok((t, _)) => t
    Err(_) => return
  }
  let root = match @runtime.parse(table, source) {
    Ok(r) => r
    Err(_) => return
  }
  let highlight_query = match @query.compile(@grammars.moonbit_highlight_query) {
    Ok(q) => q
    Err(_) => return
  }
  let locals_query = match @query.compile(@grammars.moonbit_locals_query) {
    Ok(q) => q
    Err(_) => return
  }

  ignore(
    @query.apply_highlights_with_locals(
      root,
      source,
      table,
      highlight_query,
      locals_query,
    ),
  )
}
```

推荐理解方式如下：

- `*_highlight_query` 是给 `query.compile()` 用的；
- 它们与对应内置 Grammar 的节点命名约定一致；
- `moonbit_locals_query` 是专门给 `apply_highlights_with_locals()` 或 `resolve_locals()` 准备的补充查询。

### 5.5 公共 DSL 片段适合拼装自己的语法

如果只是想重用一部分词法模式，而不是整份内置 Grammar，可以直接使用 `common.mbt` 暴露出来的模式片段：

```moonbit
import {
  "caiklonghuan/MoonParse/grammars" @grammars,
}

fn demo_patterns() -> Unit {
  let extras = @grammars.c_style_extras()
  let ident = @grammars.ascii_identifier_pattern
  let num = @grammars.c_number_pattern
  println(extras + " / " + ident + " / " + num)
}
```

这类导出特别适合：

- 写教学示例；
- 写实验性 DSL；
- 避免在多份语法里重复手写相同的注释和数字正则。

### 5.6 `*_sexp` 和 `assert_*` 主要面向测试

`json_sexp()`、`moonbit_sexp()` 这类函数本质上是“解析 + 结构化字符串输出”的组合，最适合快照测试或稳定结构断言。

配套的 `assert_tree_shape_eq()`、`assert_span_eq()`、`assert_cst_invariants()` 等函数，则用于在项目内黑盒测试里做更明确、更稳定的断言，而不是依赖临时打印输出。

## 6. 核心概念

### 6.1 内置 Grammar 常量


本模块的第一类核心对象，是一组直接公开的 DSL 字符串常量。例如：

- `json_grammar`
- `json5_grammar`
- `c_grammar`
- `python_grammar`
- `moonbit_grammar`
- `expression_grammar`

这些常量的意义在于：

- 它们本身就是项目可读的语言样本；
- 它们可作为 `grammar/` 与 `tablegen/` 的现成输入；
- 它们让“内置语法”始终保持可检查、可修改、可序列化，而不是隐藏在二进制资产中。

### 6.2 `parse_*` 是预编译表之上的便捷入口

每个 `parse_*` 函数背后都对应一个在模块内部通过 `compile_builtin_grammar()` 预编译的 `ParseTable`。这意味着：

- 调用方不必每次重新建表；
- 用起来像“现成解析器”；
- 但公开面仍保持为 `runtime.parse()` 风格的 `Result[CstNode, ParseError]`。

需要注意的是，这些预编译表是模块内部实现细节，并不会作为公开值导出。

### 6.3 高亮与 locals 查询是“配套资源”，不是独立语法系统

`json_highlight_query`、`moonbit_highlight_query`、`moonbit_locals_query` 这类导出，本质上都是与对应 Grammar 配套的查询资源。它们依赖以下前提：

- 节点命名必须与对应内置语法一致；
- 调用方传给 `query/` 的 `ParseTable` 应来自匹配的 Grammar；
- 查询规则只覆盖当前内置语法已建模的那部分节点。

因此，它们更适合用作“配套素材”，而不是独立于语法版本的通用查询标准。


### 6.5 `assert_*` 是测试友好的稳定断言工具

这些断言工具刻意保持行为简单、失败方式直接，适合测试场景：

- `assert_node_text_eq`：检查节点原文；
- `assert_span_eq`：检查字节区间；
- `assert_point_eq`：检查点位；
- `assert_tree_shape_eq`：检查结构化 S-expression；
- `assert_cst_invariants`：做面向恢复树的轻量不变量检查。

它们不是运行时库 API 的替代品，而是测试支持层的一部分。

## 7. 使用时需要特别注意的事项

- `parse_*` 入口适合快速使用，但不会公开内部 `ParseTable`；如果还要做高亮、locals、运行时配置或自定义外部词法器，应从 `*_grammar` 自行重新建表。
- 导入 `grammars/` 可能触发多份内置 Grammar 的预编译，这对示例和测试很方便，但不一定适合所有极端启动性能场景。
- `json_grammar` 更接近完整、稳定的标准样例；`c_grammar`、`python_grammar`、`moonbit_grammar` 则明确是实用核心子集，不应默认视为对应语言的完整规范实现。
- `*_highlight_query` 与对应内置 Grammar 的节点命名是耦合的；如果改过 Grammar，却继续用原查询，结果很可能不再匹配。
- `parse_moonparse_dsl()` 只验证 Grammar DSL 的词法/语法层可接受性，不替代 `grammar.validate_grammar()` 的语义校验。
- `*_sexp` 主要面向结构快照和测试断言，它会省略很多匿名终结符，因此不应把它当作完整树导出协议。
- `assert_*` 会直接 `panic()` 以便测试快速失败，不适合作为生产环境错误处理 API。

## 8. 适用场景总结

`grammars/` 特别适合以下场景：

- 快速拿到一份可运行的内置语法做演示或 smoke test；
- 为 `runtime/` 与 `query/` 编写端到端示例与回归测试；
- 复用现成的高亮查询、locals 查询和常见词法模式；
- 研究 MoonParse 自己的 Grammar DSL 自举能力；
- 在文档和教学场景中提供“开箱即用”的语言样本。

如果目标是“定义自己的正式语言前端”，那么 `grammars/` 更适合作为参考样本和起点，而不是终点。
