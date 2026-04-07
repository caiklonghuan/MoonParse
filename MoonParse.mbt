// 公共 API：grammar DSL → ParseTable → CST
// generate : DSL 字符串 → 解析表 JSON（用于持久化 / 调试）
// parse    : DSL 字符串 + 源码 → CST 文本（快速端到端解析）

///|
/// 将 Grammar DSL 编译为 LALR(1) 解析表，以 JSON 字符串返回。
///
/// 解析或表生成失败时返回以 "Error: " 开头的错误描述字符串。
pub fn generate(grammar_dsl : String) -> String {
  let g = match @grammar.parse_grammar(grammar_dsl) {
    Success(g) => g
    Error(err) =>
      return "Error: parse failed at " +
        err.location.line.to_string() +
        ":" +
        err.location.column.to_string() +
        ": " +
        err.message
  }
  let (table, _reports) = match @tablegen.generate_parse_table(g) {
    Ok(r) => r
    Err(msg) => return "Error: table generation failed: " + msg
  }
  @tablegen.table_to_json(table)
}

///|
/// 用 Grammar DSL 解析 source，返回 CST 的文本表示。
///
/// 解析失败时返回以 "Error: " 开头的错误描述字符串。
pub fn parse(grammar_dsl : String, source : String) -> String {
  match @runtime.parse_from_dsl(grammar_dsl, source) {
    Ok(node) => node.to_string()
    Err(err) => "Error: " + err.to_string()
  }
}

///|
/// 用内置 JSON 语法解析 source，返回 CST 的文本表示。
///
/// 解析失败时返回以 "Error: " 开头的错误描述字符串。
pub fn parse_json(source : String) -> String {
  match @grammars.parse_json(source) {
    Ok(node) => node.to_string()
    Err(err) => "Error: " + err.to_string()
  }
}

///|
/// 用内置 JSON5 语法解析 source，返回 CST 的文本表示。
pub fn parse_json5(source : String) -> String {
  match @grammars.parse_json5(source) {
    Ok(node) => node.to_string()
    Err(err) => "Error: " + err.to_string()
  }
}

///|
/// 用内置 MoonBit 语法解析 source，返回 CST 的文本表示。
pub fn parse_moonbit(source : String) -> String {
  match @grammars.parse_moonbit(source) {
    Ok(node) => node.to_string()
    Err(err) => "Error: " + err.to_string()
  }
}

///|
/// 用内置 Python 语法解析 source，返回 CST 的文本表示。
pub fn parse_python(source : String) -> String {
  match @grammars.parse_python(source) {
    Ok(node) => node.to_string()
    Err(err) => "Error: " + err.to_string()
  }
}

///|
/// 用内置 C 语法解析 source，返回 CST 的文本表示。
pub fn parse_c(source : String) -> String {
  match @grammars.parse_c(source) {
    Ok(node) => node.to_string()
    Err(err) => "Error: " + err.to_string()
  }
}
