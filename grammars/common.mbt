///|
// 通用语法辅助片段

///|
/// 通用空白：空格、制表符、换行符、回车符。
/// 适合大多数非换行敏感语言作 extras 条目。
pub let whitespace_pattern : String =
  #|/[ \t\n\r]+/

///|
/// 仅水平空白（换行敏感语言 extras，换行用独立 rule 处理）。
pub let horizontal_ws_pattern : String =
  #|/[ \t\f]+/

///|
/// C / C++ / Java / Rust 风格行注释 `// …`，消耗至行尾（含换行符）。
pub let c_line_comment_pattern : String =
  #|/\/\/[^\n\r]*(\r\n|\n|\r)?/

///|
/// C 风格块注释 `/* … */`，支持内嵌 `*` 序列（非贪婪）。
pub let c_block_comment_pattern : String =
  #|/\/\*([^*]|\*+[^*/])*\*+\//

///|
/// Python / Shell / Ruby / TOML 风格行注释 `# …`，消耗至行尾。
pub let hash_line_comment_pattern : String =
  #|/#[^\n\r]*(\r\n|\n|\r)?/

///|
/// SQL / Haskell / Lua 风格行注释 `-- …`，消耗至行尾。
pub let dash_line_comment_pattern : String =
  #|/--[^\n\r]*(\r\n|\n|\r)?/

///|
/// Haskell 风格块注释 `{- … -}`（非嵌套）。
pub let haskell_block_comment_pattern : String =
  #|/\{-([^-]|-+[^-}])*-+\}/

///|
/// 换行符（`\r\n | \n | \r`），用于换行敏感语言的 rule 或 extras。
pub let newline_pattern : String =
  #|/(\r\n|\n|\r)/

///|
/// 标准 ASCII 标识符：字母或下划线开头，后接字母 / 数字 / 下划线。
/// 适合 C、Python、Lua、MoonBit 等语言。
pub let ascii_identifier_pattern : String =
  #|/[A-Za-z_][A-Za-z0-9_]*/

///|
/// JS / JSON5 风格标识符：允许 `$` 开头。
pub let js_identifier_pattern : String =
  #|/[$A-Za-z_][$0-9A-Za-z_]*/

///|
/// 十进制非负整数（不含前置 +/-）。
pub let decimal_int_pattern : String =
  #|/[0-9]+/

///|
/// 十六进制整数（`0x` / `0X` 前缀）。
pub let hex_int_pattern : String =
  #|/0[xX][0-9a-fA-F]+/

///|
/// 八进制整数（`0o` / `0O` 前缀）。
pub let octal_int_pattern : String =
  #|/0[oO][0-7]+/

///|
/// 二进制整数（`0b` / `0B` 前缀）。
pub let binary_int_pattern : String =
  #|/0[bB][01]+/

///|
// ── 浮点字面量 ───────────────────────────────────────────────────

///|
/// 浮点数（含科学记数法，不含前置符号）：
///   `1.23`  `1.`  `.5`  `1e10`  `.5e-3`
pub let float_pattern : String =
  #|/[0-9]+\.[0-9]*([eE][+-]?[0-9]+)?|\.[0-9]+([eE][+-]?[0-9]+)?|[0-9]+[eE][+-]?[0-9]+/

///|
/// C 风格数字常量（含 hex 整数、十进制浮点/ 整数）：
///   `0xFF`  `3.14`  `.5e10`  `42`
pub let c_number_pattern : String =
  #|/0[xX][0-9a-fA-F]+|[0-9]+\.[0-9]*([eE][+-]?[0-9]+)?|\.[0-9]+([eE][+-]?[0-9]+)?|[0-9]+([eE][+-]?[0-9]+)?/

///|
/// JSON5 / TOML 风格带符号数字（支持前置 +/-，含 hex、浮点、整数）：
///   `+0xFF`  `-3.14`  `+1e10`  `42`
pub let signed_number_pattern : String =
  #|/[-+]?(0[xX][0-9a-fA-F]+|[0-9]+\.[0-9]*([eE][+-]?[0-9]+)?|\.[0-9]+([eE][+-]?[0-9]+)?|[0-9]+([eE][+-]?[0-9]+)?)/

///|
// ── 字符串字面量 ─────────────────────────────────────────────────

///|
/// 双引号字符串（支持 `\"` `\\` 等反斜杠转义，不支持换行）。
pub let dq_string_pattern : String =
  #|/"([^"\\]|\\.)*"/

///|
/// 单引号字符串（同上，引号改为 `'`）。
pub let sq_string_pattern : String =
  #|/'([^'\\]|\\.)*'/

///|
/// JS 反引号模板字符串（不支持嵌套 `${...}` 表达式，仅匹配 \` … \` 文本）。
pub let backtick_string_pattern : String =
  #|/`([^`\\]|\\.)*`/

///|
/// 生成 C 风格 extras 行（空白 + 行注释 + 块注释）：
pub fn c_style_extras() -> String {
  "extras [" +
  whitespace_pattern +
  ", " +
  c_line_comment_pattern +
  ", " +
  c_block_comment_pattern +
  "]"
}

///|
/// 生成 Python / Shell 风格 extras 行（空白 + hash 行注释）：
pub fn hash_comment_extras() -> String {
  "extras [" + whitespace_pattern + ", " + hash_line_comment_pattern + "]"
}

///|
/// 生成换行敏感语言的水平空白 extras 行（仅空格 / 制表符）：
pub fn horizontal_whitespace_extras() -> String {
  "extras [" + horizontal_ws_pattern + "]"
}

///|
/// 生成 SQL / Haskell 风格 extras 行（空白 + dash 行注释）：
pub fn dash_comment_extras() -> String {
  "extras [" + whitespace_pattern + ", " + dash_line_comment_pattern + "]"
}

///|
/// 支持四则运算、函数调用、圆括号分组的通用表达式语法 DSL 字符串。
///
/// 词法元素：ASCII 标识符、十进制整数、浮点数、十六进制整数、双引号字符串。
/// 运算符优先级（从低到高）：加减 < 乘除取余 < 一元减/正/逻辑非。
pub let expression_grammar : String =
  #|start expression
  #|extras [/[ \t\n\r]+/, /\/\/[^\n\r]*(\r\n|\n|\r)?/, /\/\*([^*]|\*+[^*/])*\*+\//]
  #|rule expression: additive_expression
  #|rule additive_expression: multiplicative_expression | prec.left(1, additive_expression ("+" | "-") multiplicative_expression)
  #|rule multiplicative_expression: unary_expression | prec.left(2, multiplicative_expression ("*" | "/" | "%") unary_expression)
  #|rule unary_expression: postfix_expression | prec.right(3, ("-" | "+" | "!") unary_expression)
  #|rule postfix_expression: primary_expression | prec.left(4, postfix_expression "(" argument_list? ")")
  #|rule primary_expression: identifier | number | string | "(" expression ")"
  #|rule argument_list: expression ("," expression)*
  #|rule identifier: /[A-Za-z_][A-Za-z0-9_]*/
  #|rule number: /0[xX][0-9a-fA-F]+|[0-9]+\.[0-9]*([eE][+-]?[0-9]+)?|\.[0-9]+([eE][+-]?[0-9]+)?|[0-9]+([eE][+-]?[0-9]+)?/
  #|rule string: /"([^"\\]|\\.)*"/

///|
let expression_table : @tablegen.ParseTable = compile_builtin_grammar(
  expression_grammar,
)

///|
/// 解析算术表达式字符串，返回 CST。
/// 示例：`parse_expression("1 + 2 * foo(3, 4)")`
pub fn parse_expression(
  source : String,
) -> Result[@runtime.CstNode, @runtime.ParseError] {
  @runtime.parse(expression_table, source)
}
