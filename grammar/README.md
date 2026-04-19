# grammar 模块说明

## 1. 模块定位

`grammar/` 是 MoonParse 的语法前端模块，负责将用户编写的 Grammar DSL 或以编程方式构造的规则对象，整理为统一的 `Grammar` 语法模型，并提供以下能力：

- 将 DSL 文本解析为 `Grammar` 对象；
- 对 `Grammar` 做语义校验；
- 将 `Grammar` 序列化为 DSL 文本或 JSON；
- 从 JSON 还原 `Grammar`；
- 为下游 `tablegen/` 模块提供稳定、可检查、可序列化的输入。

本模块**不负责**以下工作：

- 不生成 LR/LALR 解析表；
- 不执行运行时文本解析；
- 不构造 CST 或 AST；
- 不处理运行时增量编辑。

换言之，`grammar/` 的职责是“定义和检查语法”，而不是“使用语法去解析源码”。

## 2. 在整体系统中的位置

整体链路如下：

```text
Grammar DSL / Builder API
          |
          v
      grammar/
          |
          v
     Grammar 对象
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

推荐理解方式如下：

- `grammar/` 解决“语法如何表示”；
- `tablegen/` 解决“语法如何编译为解析表”；
- `runtime/` 解决“解析表如何驱动真实解析”。

## 3. 架构与设计说明

本节用于说明 `grammar/` 的内部组织方式，以及当前实现中若干关键设计取舍。为保持阅读连续性，这里仅保留理解模块所必需的设计信息，不再拆出独立文档。

### 3.1 内部处理链路

`grammar/` 的内部工作流可以概括为以下链路：

```text
Grammar DSL / Builder API
       |
       v
   lexer.mbt / api.mbt
       |
       v
  TokenWithLocation[] / Grammar
       |
       v
     parser.mbt
       |
       v
      Grammar
       |
       v
    validator.mbt
       |
       +------------------> serializer.mbt
       |
       v
     tablegen/
```

其中：

- `lexer.mbt` 负责将 Grammar DSL 文本切分为带位置的 token；
- `parser.mbt` 负责把 token 流还原为 `Grammar` 对象；
- `validator.mbt` 负责跨规则、跨声明的语义一致性检查；
- `serializer.mbt` 负责 DSL 回显与 JSON 往返；
- `api.mbt` 提供与 DSL 等价的程序化构造入口；
- `types.mbt` 定义整个模块共享的数据结构。

### 3.2 文件职责划分


| 文件             | 主要职责                                                        | 设计意图                                                             |
| ---------------- | --------------------------------------------------------------- | -------------------------------------------------------------------- |
| `types.mbt`      | 定义`Grammar`、`Rule`、`Pattern`、`ValidationError` 等核心类型  | 统一全模块的数据模型，避免 DSL 解析、Builder API、序列化各用一套结构 |
| `api.mbt`        | 提供`Grammar::new`、`Rule::new`、`seq`、`choice` 等组合接口     | 让调用方既可写 DSL，也可直接用代码构造同一套语法模型                 |
| `lexer.mbt`      | 把 DSL 文本切分为`TokenWithLocation`                            | 将位置信息尽早保留下来，供后续错误报告使用                           |
| `parser.mbt`     | 解析 token 流，产出`Grammar` 或 `ParseError`                    | 专注处理语法结构，不承担全部全局语义判断                             |
| `validator.mbt`  | 校验规则引用、左递归、优先级、模板、`word`、`extras` 等         | 在进入下游前尽量提前暴露 Grammar 级问题                              |
| `serializer.mbt` | 提供`grammar_to_string`、`grammar_to_json`、`grammar_from_json` | 区分“面向人阅读”的 DSL 输出与“面向工具”的 JSON 输出              |

## 4. 公开能力一览

使用时通常只需要关注以下公开 API：


| 类别            | 主要 API                                                                                                                                                       | 说明                                     |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| DSL 解析        | `parse_grammar`、`parse_grammar_lenient`                                                                                                                       | 将 DSL 文本解析为`Grammar`               |
| 语义校验        | `validate_grammar`                                                                                                                                             | 检查未定义规则、左递归、优先级混用等问题 |
| DSL/JSON 序列化 | `grammar_to_string`、`grammar_to_json`、`grammar_from_json`                                                                                                    | 便于显示、持久化、工具链交互             |
| 数据结构        | `Grammar`、`Rule`、`Pattern`、`PrecDecl`                                                                                                                       | 模块核心模型                             |
| Builder API     | `Grammar::new`、`Rule::new`、`Rule::token`、`Rule::template`                                                                                                   | 以编程方式构造语法                       |
| Pattern 组合器  | `seq`、`choice`、`lit`、`re`、`ref_`、`repeat`、`plus`、`optional`、`field`、`tagged`、`not_`、`and_`、`repeat_exact`、`repeat_range`、`prec`、`alias_`、`app` | 以代码方式表达 DSL 模式                  |

## 5. 用户如何使用

### 5.1 推荐使用流程

对于绝大多数调用方，建议采用如下顺序：

1. 准备 DSL 文本，或者通过 Builder API 构造 `Grammar`。
2. 调用 `parse_grammar` 或 `parse_grammar_lenient` 获取 `Grammar`。
3. **必须**调用 `validate_grammar` 做语义校验。
4. 若校验通过，再交给 `tablegen/` 继续生成解析表。
5. 如需展示或持久化，可调用 `grammar_to_string` 或 `grammar_to_json`。

其中，第 3 步不可省略。`parse_grammar` 只负责“能否解析出语法对象”，并不保证该语法在语义上是正确或可用于后续编译的。

### 5.2 基于 DSL 文本使用

导入方式：

```moonbit
import {
  "caiklonghuan/MoonParse/grammar" @grammar,
}
```

一个最基本的使用示例如下：

```moonbit
fn load_grammar_from_dsl(dsl : String) -> Unit {
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

  let errors = @grammar.validate_grammar(grammar)
  if !errors.is_empty() {
    for err in errors {
      println(err.to_string())
    }
    return
  }

  println("grammar is valid")
}
```

一个可工作的简单 DSL 示例：

```text
start list
extras [/[ \t\n\r]+/]
token rule ident: /[a-zA-Z_][a-zA-Z0-9_]*/
rule list: ident ("," ident)*
```

该示例表达的是：

- 起始规则为 `list`；
- 空白可以在任意位置出现；
- `ident` 是一个词法规则；
- `list` 由一个或多个标识符组成，中间可带逗号分隔。

### 5.3 需要错误恢复时的使用方式

若场景是编辑器、IDE、在线语法编辑器，通常不希望在遇到第一处 DSL 错误时立即中止，此时应使用：

```moonbit
let (partial_grammar, parse_errors) = @grammar.parse_grammar_lenient(dsl)
```

其特点如下：

- 发生语法错误时不会立即停止，而是跳到下一条顶层声明继续分析；
- 会返回一个“尽力恢复后的部分 `Grammar`”；
- 同时返回全部已收集的 `ParseError`。

推荐用法：

1. 用 `parse_grammar_lenient` 收集语法层错误；
2. 对返回的部分 `Grammar` 继续调用 `validate_grammar`；
3. 将两类错误分别呈现给用户。

这种方式适合“编辑中状态”，但**不建议**直接将其结果视为可发布的正式语法定义。

### 5.4 以 Builder API 编程构造 Grammar

如果不希望直接写 DSL，也可以通过代码构造语法对象。

示例：

```moonbit
import {
  "caiklonghuan/MoonParse/grammar" @grammar,
}

fn make_identifier_list_grammar() -> @grammar.Grammar {
  @grammar.Grammar::new()
    .set_start("list")
    .add_extra(@grammar.re("[ \\t\\n\\r]+"))
    .add_rule(
      @grammar.Rule::token(
        "ident",
        @grammar.re("[a-zA-Z_][a-zA-Z0-9_]*"),
      ),
    )
    .add_rule(
      @grammar.Rule::new(
        "list",
        @grammar.seq([
          @grammar.ref_("ident"),
          @grammar.repeat(
            @grammar.seq([
              @grammar.lit(","),
              @grammar.ref_("ident"),
            ]),
          ),
        ]),
      ),
    )
}
```

在这种模式下，仍然应当执行：

```moonbit
let grammar = make_identifier_list_grammar()
let errors = @grammar.validate_grammar(grammar)
```

### 5.5 如何与下游模块衔接

若 `grammar/` 阶段已经成功，下一步通常是交给 `tablegen/`：

```moonbit
let grammar = ...
let errors = @grammar.validate_grammar(grammar)
if errors.is_empty() {
  // 交由 tablegen 继续生成 ParseTable
}
```

因此可以将 `grammar/` 理解为“下游编译链路的输入守门员”。只有在本模块已通过解析与校验后，后续生成的结果才有可解释性。

## 6. DSL 与模型的核心概念

### 6.1 Grammar

`Grammar` 表示一份完整语法，包含：

- `start`：起始规则；
- `rules`：规则名到 `Rule` 的映射；
- `precedences`：顶层优先级声明；
- `extras`：可在任意位置出现的附加 token，例如空白或注释；
- `externals`：外部词法器提供的 token 名称；
- `word`：关键字提升使用的词法规则；
- `conflicts`：显式声明的冲突组；

使用时，可以将 `Grammar` 理解为“整份语法的根对象”。通常的做法是，先建立一个空的 `Grammar`，再逐步补入起始规则、词法规则、语法规则以及附加声明。

示例：以 Builder API 组装一份最小但完整的“逗号分隔标识符列表”语法。

```moonbit
import {
  "caiklonghuan/MoonParse/grammar" @grammar,
}

fn make_identifier_list_grammar() -> @grammar.Grammar {
  @grammar.Grammar::new()
    .set_start("list")
    .add_extra(@grammar.re("[ \\t\\n\\r]+"))
    .add_rule(
      @grammar.Rule::token(
        "identifier",
        @grammar.re("[a-zA-Z_][a-zA-Z0-9_]*"),
      ),
    )
    .set_word("identifier")
    .add_rule(@grammar.Rule::new("item", @grammar.ref_("identifier")))
    .add_rule(
      @grammar.Rule::new(
        "list",
        @grammar.seq([
          @grammar.field("head", @grammar.ref_("item")),
          @grammar.repeat(
            @grammar.seq([
              @grammar.lit(","),
              @grammar.field("tail", @grammar.ref_("item")),
            ]),
          ),
        ]),
      ),
    )
    .add_supertype("item")
}
```

在这个例子中：

- `set_start("list")` 指定整份语法从 `list` 开始；
- `add_extra(...)` 把空白声明为可在任意位置出现的附加 token；
- `identifier` 被声明为 token rule，并同时设置为 `word` 规则；
- `item` 把“列表项”单独建模出来，便于后续扩展为更复杂的元素结构；
- `list` 规则通过 `head + repeat(tail)` 的方式描述逗号分隔列表；
- `field("head", ...)` 与 `field("tail", ...)` 让下游更容易区分首项和后续项；
- `add_supertype("item")` 表示后续查询场景可将 `item` 视为一个可抽象使用的类别。

上例有意只展示最常用的 `start`、`rules`、`extras`、`word` `。若的语法还需要外部词法器、显式冲突组或顶层优先级声明，则可继续通过 `add_external(...)`、`add_conflict(...)`、`add_precedence(...)` 增量补入。

若更习惯写 DSL，上述 `Grammar` 也可以用接近如下的形式表达：

```text
start list
extras [/[ \t\n\r]+/]
word identifier
token rule identifier: /[a-zA-Z_][a-zA-Z0-9_]*/
rule item: identifier
rule list: head: item ("," tail: item)*
supertypes [item]
```

### 6.2 Rule

`Rule` 表示一条规则，最重要的属性有：

- `name`：规则名；
- `pattern`：规则体；
- `is_token`：是否为词法规则；
- `params`：模板参数；
- `attributes`：规则属性，例如 `Inline`、`Hide`、`Deprecated`。

需要注意：规则名若以下划线 `_` 开头，则默认视为**匿名规则**，不会作为命名节点对外暴露。

从使用角度看，`Rule` 可以分为三类：

- 普通规则：用于描述语法层结构；
- token 规则：用于描述词法层 token；
- 模板规则：用于抽象一类可复用的模式结构。

示例：分别声明普通规则、token 规则、模板规则与带属性的规则。

```moonbit
import {
  "caiklonghuan/MoonParse/grammar" @grammar,
}

let identifier_rule = @grammar.Rule::token(
  "identifier",
  @grammar.re("[a-zA-Z_][a-zA-Z0-9_]*"),
)

let expr_rule = @grammar.Rule::new(
  "expr",
  @grammar.choice([
    @grammar.ref_("identifier"),
    @grammar.lit("null"),
  ]),
)

let comma_list_rule = @grammar.Rule::template(
  "comma_list",
  ["T"],
  @grammar.seq([
    @grammar.ref_("T"),
    @grammar.repeat(
      @grammar.seq([
        @grammar.lit(","),
        @grammar.ref_("T"),
      ]),
    ),
  ]),
)

let paren_expr_rule = @grammar.Rule::new(
  "_paren_expr",
  @grammar.seq([
    @grammar.lit("("),
    @grammar.ref_("expr"),
    @grammar.lit(")"),
  ]),
).with_attribute(@grammar.RuleAttribute::Inline)
```

这个示例分别说明了：

- `Rule::token(...)` 用于声明可直接参与词法识别的 token 规则；
- `Rule::new(...)` 用于声明普通语法规则；
- `Rule::template(...)` 用于声明可带参数的模板规则，后续需通过 `app(...)` 或 DSL 中的 `name[...]` 实例化；
- `with_attribute(...)` 用于在规则上附加 `Inline`、`Hide`、`Deprecated` 等属性；
- 以 `_` 开头的 `_paren_expr` 会被视为匿名规则，即便它仍然是一个完整的 `Rule` 对象。

若需要把模板规则实际用起来，可以在别的规则中写：

```moonbit
let args_rule = @grammar.Rule::new(
  "args",
  @grammar.app("comma_list", [@grammar.ref_("expr")]),
)
```

### 6.3 Pattern

`Pattern` 是规则体的统一表达。常用形式包括：

- `RuleRef`：规则引用；
- `Literal`：字面量；
- `Regex`：正则；
- `Seq` / `Choice`：序列 / 分支；
- `Repeat` / `Plus` / `Optional`：重复；
- `Field`：命名字段；
- `Prec`：内联优先级；
- `Alias`：节点别名；
- `RuleApp`：模板规则实例化。

`Pattern` 可以理解为“规则右侧的结构表达式”。无论在 DSL 中写的是字面量、分支、重复、字段还是优先级包装，最终都会映射成某种 `Pattern`。

常见 DSL 写法与 Builder API 的对应关系如下：


| DSL 写法                      | 对应 Pattern 组合器                            |
| ----------------------------- | ---------------------------------------------- |
| `identifier`                  | `ref_("identifier")`                           |
| `"+"`                         | `lit("+")`                                     |
| `/\d+/`                       | `re("\\d+")`                                   |
| `a b c`                       | `seq([ref_("a"), ref_("b"), ref_("c")])`       |
| `a                            | b`                                             |
| `item*`                       | `repeat(ref_("item"))`                         |
| `item+`                       | `plus(ref_("item"))`                           |
| `item?`                       | `optional(ref_("item"))`                       |
| `lhs: expr`                   | `field("lhs", ref_("expr"))`                   |
| `prec.left(1, expr "+" expr)` | `prec(1, @grammar.PrecKind::Left, seq([...]))` |
| `alias("number", value)`      | `alias_("number", ref_("value"))`              |
| `comma_list[expr]`            | `app("comma_list", [ref_("expr")])`            |

示例：用多个 `Pattern` 组合出“函数调用 + 一元表达式”这两类结构。

```moonbit
import {
  "caiklonghuan/MoonParse/grammar" @grammar,
}

let call_pattern = @grammar.seq([
  @grammar.field("callee", @grammar.ref_("identifier")),
  @grammar.lit("("),
  @grammar.optional(
    @grammar.field(
      "arguments",
      @grammar.app("comma_list", [@grammar.ref_("expr")]),
    ),
  ),
  @grammar.lit(")"),
])

let unary_pattern = @grammar.prec(
  10,
  @grammar.PrecKind::Right,
  @grammar.seq([
    @grammar.choice([
      @grammar.lit("!"),
      @grammar.lit("-"),
    ]),
    @grammar.ref_("expr"),
  ]),
)

let boolean_literal_pattern = @grammar.choice([
  @grammar.alias_("boolean", @grammar.lit("true")),
  @grammar.alias_("boolean", @grammar.lit("false")),
])
```

这个例子分别体现了：

- `seq(...)` 适合表达有顺序约束的结构；
- `field(...)` 可为关键子结构命名，便于后续查询与下游使用；
- `optional(...)` 可表示参数列表可省略；
- `app(...)` 可把模板规则实例化到具体类型上；
- `prec(...)` 可为一元或二元表达式附加内联优先级；
- `alias_(...)` 可在不改变底层匹配结构的前提下，为节点提供对外显示名称。

## 7. 序列化与持久化使用方式

### 7.1 回显为 DSL 文本

```moonbit
let text = @grammar.grammar_to_string(grammar)
```

适用场景：

- 调试打印；
- 在工具中展示语法；
- 将 Builder API 构造的语法重新输出为 DSL 形式。

### 7.2 序列化为 JSON

```moonbit
let json = @grammar.grammar_to_json(grammar)
let restored = @grammar.grammar_from_json(json)
```

适用场景：

- 工具链间传输；
- 缓存中间产物；
- 与外部工具交换 Grammar 描述。

## 8. 使用时需要特别注意的事项

### 8.1 `parse_grammar` 通过，不等于 Grammar 可用

这是最重要的一点。

`parse_grammar` 只是把 DSL 文本解析成对象，以下问题通常要到 `validate_grammar` 才会报告：

- 起始规则未定义；
- 引用了不存在的规则；
- 左递归；
- 不可达规则；
- 正则表达式非法；
- `extras`、`word`、`token rule`、`template` 等约束被破坏。

因此，在对接 `tablegen/` 前，**必须调用 `validate_grammar`**。

### 8.2 `parse_grammar` 与 `parse_grammar_lenient` 的使用边界不同

- `parse_grammar`：适用于命令行编译、CI、正式构建；遇到首个语法错误即返回失败。
- `parse_grammar_lenient`：适用于编辑器和交互场景；允许在部分错误存在时继续工作。

若的目标是“构建最终可发布的语法”，应优先使用前者。

### 8.3 不要混用两套优先级机制

本模块支持两种优先级写法：

- 顶层 `precedence ...` 声明；
- 内联 `prec(...)` / `prec.left(...)` / `prec.right(...)`。

当前校验规则要求二者**二选一**。若混用，`validate_grammar` 会报告 `MixedPrecSystems`。

### 8.4 `extras` 只能放终结符模式

`extras` 只适合放空白、注释、单字符这类“可独立扫描”的模式。

允许的类型仅限：

- `Literal`
- `Regex`
- `AnyChar`

若在 `extras` 中放入非终结符引用或复杂语法组合，会被校验报错。

### 8.5 `token rule` 不能随意引用普通语法规则

`token rule` 属于词法层规则，校验器会禁止其引用非 token 规则。

因此：

- 若一个规则承担词法职责，应使用 `token rule` 或 `Rule::token`；
- 若它需要引用语法层结构，则不应建模为 token rule。

### 8.6 `word` 应指向一个合法的 token rule

`word` 用于关键字提升场景。使用时应确保：

- 该规则已声明；
- 该规则是 token rule；
- 其含义确实适合作为“单词级别”的词法单位。

否则校验阶段会给出错误。

### 8.7 模板规则必须通过实例化使用

若规则定义了参数，例如 `rule pair[A, B]: ...`，则它是模板规则。

这类规则：

- 不能像普通规则那样直接 `ref_` / 直接引用；
- 必须通过 `app(...)` 或 DSL 中的 `name[...]` 方式实例化；
- 参数个数必须与模板声明一致。

### 8.8 前瞻断言仅在特定位置有效

`!p` 与 `&p` 的使用受运行时约束。当前实现要求它们出现在序列尾部，否则可能在后续阶段被忽略，并由校验器发出告警：

- `LookaheadNonTailAssertion`
- `LookaheadMixedAssertions`

因此，不建议将其作为常规组织手段大范围使用，而应将其视为局部约束语法。

### 8.9 JSON 往返不会保留源码位置信息

`grammar_to_json` / `grammar_from_json` 可以完成结构往返，但不会保留 `Rule.location` 之类的源码位置数据。

这意味着：

- JSON 更适合中间表示和持久化；
- 若需要精确诊断 DSL 中的原始行列位置，应保留原始 DSL 或在解析阶段保存错误信息；
- 使用 Builder API 或 JSON 还原得到的 `Grammar`，其部分位置信息通常为空。

### 8.10 重复定义规则时，映射中只会保留后一次写入结果

`Grammar.rules` 是名称到规则的映射，因此同名规则后写入者会覆盖前者。模块会通过 `duplicate_rule_names` 和 `validate_grammar` 报告重复定义，但在运行时对象中并不会保留全部重复版本。

因此，若是做“保留所有原始定义”的编辑器功能，不应只依赖最终 `Grammar.rules`。

## 9. 适合哪些调用场景

本模块尤其适合以下场景：

- 编写和加载 MoonParse 的 Grammar DSL；
- 构建语法编辑器、语法检查器、语法预览工具；
- 为 `tablegen/` 提供经过校验的标准输入；
- 在工具链中缓存、交换、显示 Grammar 中间表示。

若是“把某段源码解析成语法树”，则应继续使用 `tablegen/` 与 `runtime/`，而不是停留在 `grammar/` 层。
