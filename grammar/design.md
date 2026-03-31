# Grammar Parser 设计文档

## 概述
Grammar Parser 是 MoonParse 的核心组件，负责解析用户定义的 Grammar DSL（Domain Specific Language），将其转换为内部数据结构 `Grammar`，供 Parser Generator 生成解析器。目标是支持 95% 典型语言语法定义能力（表达式、语句、控制结构、注释、标记、优先级），同时保持实现简单。

## 设计思路：文本 DSL + MoonBit AST
- 以"文本 DSL"作为用户面输入（类 Tree-Sitter 形式）
- 内部可以有"MoonBit 结构化配置"作为中间表示，便于代码生成

### 为什么采用文本 DSL
- 直观、易读，用户可以快速定义语法规则
- 与 Tree-Sitter 相似，便于迁移已有语法定义
- 可建立文档、示例、文本编辑器高亮支持

### 何时考虑非文本（例如 JS 或 MoonBit 代码）
- 若希望更强可编程性，可以提供额外接口：由 MoonBit 代码构建 Grammar 对象
- 初期先做文本 DSL，后续做 JSON/MoonBit DSL 转换层即可

## Grammar DSL 语法规范（当前实现）
### 规则结构
- `rule <name>: <pattern>`：定义一个命名节点规则
- `rule _<name>: <pattern>`：定义一个匿名节点规则（`_` 前缀，`is_named = false`）
- `start <name>`：指定起始规则（可选）

### 模式元素
| 语法 | Pattern 变体 | 说明 |
|------|-------------|------|
| `name` | `RuleRef(name)` | 规则引用 |
| `"str"` | `Literal(str)` | 字符串字面量 |
| `/re/` | `Regex(re)` | 正则表达式 |
| `.` | `AnyChar` | 任意单个字符 |
| `p*` | `Repeat(p)` | 零或多次 |
| `p+` | `Plus(p)` | 一或多次 |
| `p?` | `Optional(p)` | 零或一次 |
| `p{n}` | `RepeatRange(p, n, n)` | 精确重复 n 次 |
| `p{n,m}` | `RepeatRange(p, n, m)` | 重复 n 到 m 次 |
| `A B C` | `Seq([A,B,C])` | 序列 |
| `A \| B` | `Choice([A,B])` | 选择 |
| `(p)` | 分组（括号内的 Pattern） | 提升优先级 |
| `@label p` | `Tagged(label, p)` | 语义标签/节点命名 |
| `field: p` | `Field(field, p)` | 命名字段 |
| `!p` | `Not(p)` | 负向前瞻（不消耗输入） |
| `&p` | `And(p)` | 正向前瞻（不消耗输入） |
| `prec(n, p)` | `Prec(n, Nonassoc, p)` | 内联无结合性优先级 |
| `prec.left(n, p)` | `Prec(n, Left, p)` | 内联左结合优先级 |
| `prec.right(n, p)` | `Prec(n, Right, p)` | 内联右结合优先级 |
| `prec.dynamic(n, p)` | `Prec(n, Dynamic, p)` | 内联动态优先级 |

### 注释
- 行注释：`// ...`
- 块注释：`/* ... */`

### 顶层优先级声明
```
precedence left   plus, minus   // 左结合
precedence right  power         // 右结合
precedence nonassoc lt, gt      // 无结合性
precedence dynamic dyn_rule     // 动态（运行时决定）
```
顶层声明与内联 `prec(n, p)` 两套机制并存，前者作用于规则引用，后者标注模式片段。

## 语法规则例子
```
// 基础语法示例
start program
rule program: statement*

rule statement: if_stmt | assign_stmt | expr_stmt

rule if_stmt: "if" "(" expression ")" statement ("else" statement)?

rule assign_stmt: identifier "=" expression ";"

rule expr_stmt: expression ";"

rule expression: additive
rule additive: multiplicative ( ("+" | "-") multiplicative )*
rule multiplicative: primary ( ("*" | "/") primary )*
rule primary: number | identifier | "(" expression ")"

rule number: /\d+(\.\d+)?/
rule identifier: /[a-zA-Z_]\w*/

// 高级语法示例（包含新功能）
start program
rule program: @program statement*

rule statement: 
  | @if_stmt "if" "(" @condition expression ")" @then statement ("else" @else statement)?
  | @assign identifier "=" @value expression ";"
  | @expr expression ";"

// 优先级声明
precedence left plus, minus
precedence left star, slash
precedence right power

rule expression: additive
rule additive: multiplicative ( (plus | minus) multiplicative )*
rule multiplicative: power ( (star | slash) power )*
rule power: primary (power primary)*
rule primary: number | identifier | "(" expression ")"

rule plus: "+"
rule minus: "-"
rule star: "*"
rule slash: "/"
rule power: "**"

rule number: /\d+(\.\d+)?/
rule identifier: /[a-zA-Z_]\w*/
```

## 内部数据结构（MoonBit - 实际实现）

```moonbit
/// 优先级结合性
pub(all) enum PrecKind { Left | Right | Nonassoc | Dynamic }

/// 顶层 precedence 声明
pub(all) struct PrecDecl {
  level : Int           // 层级编号（1 起，越大越高）
  kind  : PrecKind
  rules : Array[String] // 该层包含的规则名
}

/// Pattern 表示语法规则中的模式（15 个变体）
pub(all) enum Pattern {
  RuleRef(String)                    // 规则引用
  Literal(String)                    // 字面量 "str"
  Regex(String)                      // 正则 /re/
  AnyChar                            // 任意字符 .
  Choice(Array[Pattern])             // 选择 A | B
  Seq(Array[Pattern])                // 序列 A B
  Repeat(Pattern)                    // 零或多次 p*
  Plus(Pattern)                      // 一或多次 p+
  Optional(Pattern)                  // 零或一次 p?
  RepeatRange(Pattern, Int, Int)     // 区间重复 p{n,m}
  Tagged(String, Pattern)            // 语义标签 @label p
  Field(String, Pattern)             // 命名字段 field: p
  Not(Pattern)                       // 负向前瞻 !p
  And(Pattern)                       // 正向前瞻 &p
  Prec(Int, PrecKind, Pattern)       // 内联优先级 prec(n, p)
}

/// Rule 表示一条语法规则
pub(all) struct Rule {
  name     : String
  pattern  : Pattern
  is_named : Bool   // false 表示匿名节点（规则名以 _ 开头定义）
}

/// Grammar 表示整个语法定义
pub(all) struct Grammar {
  mut start    : String?          // 起始规则（可选）
  rules        : Map[String, Rule]
  precedences  : Array[PrecDecl]  // 顶层优先级声明（按声明顺序）
}
```

## 文件结构（grammar/ 包）

| 文件 | 职责 |
|------|------|
| `types.mbt` | AST 类型层：`Pattern`、`Rule`、`Grammar`、`PrecKind`、`PrecDecl`；`pattern_to_string()` |
| `lexer.mbt` | 词法层：`tokenize()`，产出 `TokenWithLocation`；内含 `SourceLocation` |
| `parser.mbt` | 解析层：`parse_grammar()` 递归下降；`ParseError`、`ParseResult[T]` |
| `validator.mbt` | 校验层：`validate_grammar()`；`ValidationError`、`ValidationErrorKind` |
| `serializer.mbt` | 序列化层：`grammar_to_string()`、`grammar_to_json()` |

## 解析流程（实际实现）
1. **词法分析（`lexer.mbt`）**
   - Token 类型：`Identifier` / `StringLiteral` / `RegexLiteral` / `Symbol` / `Keyword`
   - 关键字：`rule` `start` `precedence` `left` `right` `nonassoc` `dynamic` `prec`
   - 符号：`: | * + ? ( ) @ ! & . { } ,`
   - 跳过空白、行注释 `//`、块注释 `/* */`
   - 每个 Token 携带 `SourceLocation { line, column }`

2. **语法分析（`parser.mbt`）——递归下降，优先级从低到高**
   - `parse_grammar`：顶层，分发 `rule` / `start` / `precedence` 语句
   - `parse_rule`：解析 `rule [_]name: pattern`，设置 `is_named`
   - `parse_pattern`：处理 `A | B | C`（最低优先级）
   - `parse_sequence`：处理 `A B C`
   - `parse_unary`：处理后缀 `* + ? {n,m}` 及前缀 `! &`
   - `parse_primary`：原子——规则引用、字面量、正则、`.`、`(p)`、`@label`、`field:`、`prec(...)`
   - `parse_prec_decl`：顶层 `precedence kind rules...` 声明
   - 错误时返回 `ParseResult::Error(ParseError)` 含位置信息，不 abort

3. **语义校验（`validator.mbt`）**
   - 收集全部错误，不提前短路
   - 检查项（按序）：
     1. `start` 规则存在性 → `UndefinedStartRule`
     2. 所有 `RuleRef` 引用完整性 → `UndefinedRule`
     3. 直接左递归（`first_rule_refs` + DFS）→ `DirectLeftRecursion`
     4. 间接左递归（DFS 环检测）→ `IndirectLeftRecursion(cycle)`
     5. 可达性分析（BFS from start，仅在声明了 start 时）→ `UnreachableRule`

4. **序列化（`serializer.mbt`）**
   - `grammar_to_string()` → DSL 文本，输出可被 `parse_grammar` 重新解析（round-trip）
   - `grammar_to_json()` → JSON 字符串，完整表达所有字段和 Pattern 变体

## API 设计（当前实现）

### 核心解析
```moonbit
pub fn parse_grammar(dsl : String) -> ParseResult[Grammar]
// ParseResult[T] = Success(T) | Error(ParseError)
// ParseError = { message: String, location: SourceLocation }
// SourceLocation = { line: Int, column: Int }
```

### 语义校验
```moonbit
pub fn validate_grammar(grammar : Grammar) -> Array[ValidationError]
// 返回所有错误，空数组表示通过
// ValidationError = { rule: String, kind: ValidationErrorKind }
// ValidationErrorKind:
//   UndefinedRule(String)
//   UndefinedStartRule(String)
//   DirectLeftRecursion(String)
//   IndirectLeftRecursion(Array[String])  // 环路径
//   UnreachableRule(String)
pub fn ValidationError::to_string(self) -> String
```

### 序列化
```moonbit
pub fn grammar_to_string(grammar : Grammar) -> String  // → DSL 文本（可重新解析）
pub fn grammar_to_json(grammar : Grammar) -> String    // → JSON 字符串
```

### 辅助
```moonbit
pub fn pattern_to_string(pattern : Pattern) -> String
pub fn Pattern::to_string(self : Pattern) -> String
```

### 计划中（未实现）
- `from_json(json: String) -> ParseResult[Grammar]`：从 JSON 反序列化（当前只有序列化方向）
- `generate_parser(grammar: Grammar) -> String`：从 Grammar 生成解析器代码（stub 存在于 generator/ 包）

## 设计说明：为什么不一定直接用 JS DSL
Tree-Sitter 采用 JS API 设计，因其生态丰富、写法灵活。我们现在的目标是核心解析器生成器，先实现文本 DSL，后可提供 MoonBit 函数式 DSL（同样可支持语法抽象）。

## 约定
- 规则名区分大小写一致
- 字面量串以双引号包围，支持转义
- 正则使用 `/.../` 包围
- 支持多行规则定义（通过 `\n` 分隔）

## 当前实现状态

### 已完成
- ✅ **1.1 Pattern 扩展**：15 个变体（Plus、Not、And、AnyChar、Field、RepeatRange、Prec 全部实现）
- ✅ **1.2 节点可见性**：`Rule.is_named`，`_name` 前缀约定
- ✅ **1.3 Grammar 校验器**：`validate_grammar()`，5 项语义检查
- ✅ **1.4 优先级/结合性**：`PrecKind`、`PrecDecl`、`Prec` Pattern 变体、顶层声明 + 内联语法
- ✅ **1.6 Grammar 序列化**：`grammar_to_string()`（DSL 文本 round-trip）、`grammar_to_json()`
- ✅ **词法位置信息**：所有 Token 携带 `SourceLocation { line, column }`
- ✅ **解析错误报告**：`ParseResult[T]` + `ParseError` 含位置信息

### 待实现
- ❌ **1.5 externals 声明**：外部符号（如词法 token）的显式声明机制
- ❌ **JSON 反序列化**：`from_json()` 从 JSON 构建 Grammar（当前只有序列化方向）
- ❌ **解析器代码生成**：`generate_parser()` 从 Grammar 输出 MoonBit 解析器代码
- ❌ **左递归变换**：自动将左递归规则转换为迭代形式（目前只检测，不修复）
- ❌ **增量解析**：基于 `ParseState` 的增量更新（runtime/ 包为 stub）

## 测试覆盖（31 个测试，全部通过）

| 测试文件 | 测试内容 |
|---------|---------|
| `grammar_test.mbt` | 表格驱动解析、错误场景、pattern_to_string round-trip、位置精度、is_named |
| `parser_test.mbt` | 解析正确性、错误处理、错误位置、is_named、优先级声明（4 种 kind）、prec 错误路径 |
| `types_test.mbt` | pattern_to_string 所有 15 个变体 |
| `validator_test.mbt` | 合法语法、start 不存在、未定义引用、直接/间接左递归、可达性、to_string 格式 |
| `serializer_test.mbt` | DSL round-trip、start 有无、precedence、JSON 各字段、JSON 转义 |

## 以后可以扩展的领域
- **左递归变换**：检测到左递归后自动转换为 `Repeat` 形式（Tree-Sitter 风格）
- **1.5 externals 声明**：显式声明外部 token（供词法器注入）
- **JSON 反序列化**：`from_json()` 实现，与 `grammar_to_json()` 配对
- **解析器代码生成**：`generate_parser()` 输出目标语言解析器骨架
- **语义动作执行**：`Tagged`/`Field` 节点与 AST 构建钩子对接
- **错误恢复**：解析遇错后跳过 Token 继续，积累多个错误
- **增量解析**：`update(tree, changes)` 接口（runtime/ 包待实现）

## 已知局限
- `grammar_to_string` 输出规则顺序与原始输入可能不同（Map 迭代顺序不保证）
- 左递归只检测，不自动修复
- `first_rule_refs` 在左递归检测中简化处理了 `Optional`/`Repeat` 首位传播（不追踪"可空"传播链）
- `from_json` 暂未实现（只能 DSL 文本 → Grammar，不能 JSON → Grammar）

## 示例：MoonBit 代码直接构建 Grammar

文本 DSL 是主要用户输入，也可直接在 MoonBit 代码中构建 Grammar 对象（用于工具链内部或代码生成）：

```moonbit
let grammar : Grammar = {
  start: Some("program"),
  rules: {
    "program": { name: "program", pattern: Repeat(RuleRef("statement")), is_named: true },
    "statement": { name: "statement", is_named: true, pattern: Choice([
      RuleRef("if_stmt"),
      RuleRef("assign_stmt"),
    ]) },
  },
  precedences: [],
}
```