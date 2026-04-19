// 公共 API：grammar DSL → ParseTable → CST
// generate : DSL 字符串 → 解析表 JSON
// parse    : DSL 字符串 + 源码 → CST 文本

///|
fn should_block_on_validation_error(err : @grammar.ValidationError) -> Bool {
  match err.kind {
    @grammar.ValidationErrorKind::DirectLeftRecursion(_)
    | @grammar.ValidationErrorKind::IndirectLeftRecursion(_) => false
    _ => true
  }
}

///|
fn blocking_validation_errors(
  grammar : @grammar.Grammar,
) -> Array[@grammar.ValidationError] {
  let blocking : Array[@grammar.ValidationError] = []
  for err in @grammar.validate_grammar(grammar) {
    if should_block_on_validation_error(err) {
      blocking.push(err)
    }
  }
  blocking
}

///|
fn validation_error_message(errors : Array[@grammar.ValidationError]) -> String {
  let lines : Array[String] = []
  for err in errors {
    lines.push(err.to_string())
  }
  lines.join("\n")
}

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
  let val_errors = blocking_validation_errors(g)
  if !val_errors.is_empty() {
    return "Error: validation failed:\n" + validation_error_message(val_errors)
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

///|
pub fn compile_grammar(grammar : @grammar.Grammar) -> String {
  let val_errors = blocking_validation_errors(grammar)
  if !val_errors.is_empty() {
    return "Error: validation failed:\n" + validation_error_message(val_errors)
  }
  let (table, _reports) = match @tablegen.generate_parse_table(grammar) {
    Ok(r) => r
    Err(msg) => return "Error: table generation failed: " + msg
  }
  @tablegen.table_to_json(table)
}

///|
pub fn parse_with_grammar(
  grammar : @grammar.Grammar,
  source : String,
) -> String {
  let val_errors = blocking_validation_errors(grammar)
  if !val_errors.is_empty() {
    return "Error: validation failed:\n" + validation_error_message(val_errors)
  }
  let (table, _reports) = match @tablegen.generate_parse_table(grammar) {
    Ok(r) => r
    Err(msg) => return "Error: " + msg
  }
  match @runtime.parse(table, source) {
    Ok(node) => node.to_string()
    Err(err) => "Error: " + err.to_string()
  }
}
