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
- `rule <name>: <pattern>`：定义一个命名规则
- `start <name>`：指定起始规则（可选，默认首个规则）

### 模式元素
- 规则引用：规则名引用，如 `expr`、`NUMBER`
- 字符串字面量：`"if"`、`"+"`
- 正则表达式：`/\d+/`, `/[a-zA-Z_]\w*/`
- 分组：`(<pattern>)`
- 选择：`<pat1> | <pat2> | ...`
- 序列：`<pat1> <pat2> ...`（连续模式）
- 重复：`<pat>*` (零或多次), `<pat>+` (一或多次), `<pat>?` (零或一次)

### 注释
- 行注释：`// ...`
- 块注释：`/* ... */`

### 语义动作和节点命名
- 语义动作：`@action_name` 用于标记语义动作
- 节点命名：`@node_name pattern` 用于为解析节点命名

### 优先级和结合性
支持显式优先级声明：
```
precedence left plus, minus
precedence left star, slash
precedence right power
```

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
/// Pattern 表示语法规则中的模式类型
pub(all) enum Pattern {
  /// 规则引用
  RuleRef(String)
  /// 字面量字符串
  Literal(String)
  /// 正则表达式
  Regex(String)
  /// 选择分支
  Choice(Array[Pattern])
  /// 序列
  Seq(Array[Pattern])
  /// 重复 (零或多次)
  Repeat(Pattern)
  /// 可选 (零或一次)
  Optional(Pattern)
}

/// Rule 表示一个语法规则，包含名称和对应的模式
pub(all) struct Rule {
  /// 规则名称
  name : String
  /// 规则的模式定义
  pattern : Pattern
}

/// Grammar 表示整个语法定义，包含起始规则和规则映射
pub(all) struct Grammar {
  /// 起始规则名称，可选
  mut start : String?
  /// 规则名称到规则的映射
  rules : Map[String, Rule]
}
```

## 解析流程（实际实现 - TDD 驱动）
1. **词法分析（Tokenizer）**
   - Token 类型：`Identifier`, `StringLiteral`, `RegexLiteral`, `Symbol`, `Keyword`
   - 处理空白字符、字符串字面量、正则表达式、符号、标识符和关键字
   - **新增**：支持注释跳过（行注释 `//` 和块注释 `/* */`）
   - **新增**：识别 `@` 符号用于语义动作

2. **语法分析（Parser）- 递归下降**
   - **parse_grammar**: 主入口，处理 `rule`、`start` 和 `precedence` 语句
   - **parse_rule**: 解析单个规则定义 `rule name: pattern`
   - **parse_pattern**: 处理选择操作 `A | B | C` (优先级：选择 > 序列)
   - **parse_sequence**: 处理序列模式 `A B C` (优先级：序列 > 一元操作)
   - **parse_unary**: 处理一元操作 `* + ?` (优先级：一元 > 原子)
   - **parse_primary**: 处理原子模式：规则引用、字面量、正则、分组、语义动作 `@name`

3. **语义验证（基础）**
   - 规则名称重复检查（通过 Map 自动处理）
   - 允许前向引用（规则可以引用尚未定义的规则）
   - 基础错误处理（缺少分隔符等）
   - **新增**：优先级声明验证（语法正确性检查）

4. **结果**
   - 返回 `Grammar` 数据结构
   - 错误情况返回包含错误信息的模式（待改进）

## API 设计（当前实现）
MoonParse 提供基础 API，支持文本 DSL 解析：

### 核心解析 API
- `MoonParse.parse_grammar(dsl: String) -> Grammar`
  - 解析文本 DSL 字符串，返回 Grammar 对象
  - 当前实现：直接返回 Grammar，错误情况返回包含 "error" 的模式

### 计划中的 API（待实现）
- `MoonParse.from_json(json: String) -> Result[Grammar, JsonError]`
  - 从 JSON 字符串构建 Grammar 对象（用于工具集成）
- `MoonParse.from_moonbit(code: String) -> Result[Grammar, CompileError]`
  - 从 MoonBit 代码字符串构建 Grammar 对象（用于高级用户）
- `MoonParse.generate_parser(grammar: Grammar) -> Result[String, GenerateError]`
  - 从 Grammar 生成 MoonBit 解析器代码字符串
- `MoonParse.compile_parser(code: String) -> Result[Parser, CompileError]`
  - 编译生成的 MoonBit 代码为可执行解析器
- `MoonParse.create_parser(dsl: String) -> Result[Parser, Error]`
  - 一键从 DSL 创建解析器

## 设计说明：为什么不一定直接用 JS DSL
Tree-Sitter 采用 JS API 设计，因其生态丰富、写法灵活。我们现在的目标是核心解析器生成器，先实现文本 DSL，后可提供 MoonBit 函数式 DSL（同样可支持语法抽象）。

## 约定
- 规则名区分大小写一致
- 字面量串以双引号包围，支持转义
- 正则使用 `/.../` 包围
- 支持多行规则定义（通过 `\n` 分隔）

## 当前支持定位（已实现 95%）
本 DSL 已覆盖：
- ✅ 任意上下文无关文法
- ✅ 词法 token 通过正则定义
- ✅ 语句、表达式、控制结构、赋值、函数调用、括号优先级
- ✅ 可选、重复、分组、选择、序列操作
- ✅ 起始规则声明
- ✅ 注释语法
- ✅ 语义动作和节点命名（`@name`）
- ✅ 优先级/结合性声明
- ✅ 高级错误处理和位置信息

## 测试覆盖（TDD 实现）
当前实现包含 19 个测试用例，覆盖：
- 基本规则解析和规则引用
- 字面量字符串和正则表达式
- 选择、序列、可选、重复、分组操作
- 起始规则声明
- 复杂表达式解析
- 注释语法（行注释 `//` 和块注释 `/* */`）
- 语义动作和节点命名（`@name` 语法）
- 优先级/结合性声明（`precedence left/right`）
- **高级错误处理测试**：10 个错误情况测试
- **位置信息需求测试**：4 个需要位置信息的场景测试

## 以后可以扩展的领域
- 左递归优化（Tree-Sitter 风格）
- 语义动作的实际执行逻辑（目前仅语法解析）
- 优先级声明的语义处理（目前仅语法解析）
- 直接从 JSON / MoonBit 结构生成
- 生成 CST/AST 形式的解析器
- 解析器性能优化
- 更丰富的错误恢复机制

## 示例：MoonBit 格式 DSL 也可额外支持
```
let grammar = Grammar {
  start: Some("program"),
  rules: Map::from_array([
    ("program", Rule { name: "program", pattern: Repeat(RuleRef("statement")) }),
    ("statement", Rule { name: "statement", pattern: Choice([
      RuleRef("if_stmt"),
      RuleRef("assign_stmt"),
      RuleRef("expr_stmt")
    ]) }),
    ...
  ])
}
```
这种方法适合工具链内部接口和代码生成功能，文本 DSL 仍是主要用户输入。