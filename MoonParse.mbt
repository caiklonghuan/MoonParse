// 公共 API：grammar DSL → ParseTable → CST
// generate : DSL 字符串 → 解析表 JSON
// parse    : DSL 字符串 + 源码 → CST 文本

// ── Typed API 类型 ────────────────────────────────────────

///|
/// 编译/解析错误种类
pub(all) enum MoonParseErrorKind {
  GrammarParse
  GrammarValidation
  TableGeneration
  AmbiguousConflict
  RuntimeParse
} derive(Debug, Eq)

///|
/// 结构化错误
pub(all) struct MoonParseError {
  kind : MoonParseErrorKind
  message : String
} derive(Debug)

///|
/// 编译输出：解析表 + conflicts + 警告
pub(all) struct CompileOutput {
  table : @tablegen.ParseTable
  table_json : String
  conflicts : Array[@tablegen.ConflictReport]
  validation_warnings : Array[@grammar.ValidationError]
}

///|
/// 解析输出
pub(all) struct ParseOutput {
  root : @runtime.CstNode
  source : String
}

// ── 内部辅助 ──────────────────────────────────────────────

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

// ── Typed API（v0.1 稳定入口） ─────────────────────────────

///|
/// 编译 Grammar DSL → CompileOutput（含 conflicts 和 validation 信息）。
/// ambiguous conflict 默认阻塞返回 Err。
pub fn compile_dsl(
  grammar_dsl : String,
) -> Result[CompileOutput, MoonParseError] {
  let g = match @grammar.parse_grammar(grammar_dsl) {
    Success(g) => g
    Error(err) =>
      return Err({
        kind: GrammarParse,
        message: "parse failed at " +
        err.location.line.to_string() +
        ":" +
        err.location.column.to_string() +
        ": " +
        err.message,
      })
  }
  let val_errors = @grammar.validate_grammar(g)
  let blocking_errors = blocking_validation_errors(g)
  if !blocking_errors.is_empty() {
    return Err({
      kind: GrammarValidation,
      message: "validation failed:\n" +
      validation_error_message(blocking_errors),
    })
  }
  let (table, conflicts) = match @tablegen.generate_parse_table(g) {
    Ok(r) => r
    Err(msg) => return Err({ kind: TableGeneration, message: msg })
  }
  for c in conflicts {
    match c.severity {
      @tablegen.ConflictSeverity::Ambiguous(_) =>
        return Err({
          kind: AmbiguousConflict,
          message: "ambiguous conflict: state " +
          c.state.to_string() +
          " on terminal " +
          c.terminal.to_string(),
        })
      _ => ()
    }
  }
  let json = @tablegen.table_to_json(table)
  Ok({ table, table_json: json, conflicts, validation_warnings: val_errors })
}

///|
/// 使用 Grammar DSL 解析源码 → ParseOutput。
/// 内部先调用 compile_dsl 确保 conflict 语义一致（ambiguous 阻塞），
/// 再用 CompileOutput.table 解析 source。
pub fn parse_dsl(
  grammar_dsl : String,
  source : String,
) -> Result[ParseOutput, MoonParseError] {
  let compiled = match compile_dsl(grammar_dsl) {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  match @runtime.parse(compiled.table, source) {
    Ok(node) => Ok({ root: node, source })
    Err(err) => Err({ kind: RuntimeParse, message: err.to_string() })
  }
}
