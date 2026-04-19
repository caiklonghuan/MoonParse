///|
// 公开入口（runtime 对外 API）

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
pub fn parse(
  table : @tablegen.ParseTable,
  input : String,
) -> Result[CstNode, ParseError] {
  glr_parse(table, input)
}

///|
/// 增量解析：提供旧树和编辑描述，复用未受编辑影响的子树。
pub fn parse_with_old_tree(
  table : @tablegen.ParseTable,
  input : String,
  old_tree : OldTree?,
  edit : InputEdit?,
) -> Result[CstNode, ParseError] {
  parse_incremental(table, input, old_tree, edit)
}

///|
/// 带自定义错误恢复配置的解析入口。
pub fn parse_with_config(
  table : @tablegen.ParseTable,
  input : String,
  config : ParseConfig,
) -> Result[CstNode, ParseError] {
  glr_parse_with_config(table, input, config)
}

///|
/// 带自定义配置的增量解析入口。
pub fn parse_with_old_tree_and_config(
  table : @tablegen.ParseTable,
  input : String,
  old_tree : OldTree?,
  edit : InputEdit?,
  config : ParseConfig,
) -> Result[CstNode, ParseError] {
  parse_incremental_with_config(table, input, old_tree, edit, config)
}

///|
/// DSL → ParseTable → CST 的入口
pub fn parse_from_dsl(
  dsl : String,
  input : String,
) -> Result[CstNode, ParseError] {
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) =>
      return Err({
        position: 0,
        point: { row: 0, column: 0 },
        message: e.message,
      })
  }
  let val_errors = blocking_validation_errors(g)
  if !val_errors.is_empty() {
    return Err({
      position: 0,
      point: { row: 0, column: 0 },
      message: "validation failed:\n" + validation_error_message(val_errors),
    })
  }
  match @tablegen.generate_parse_table(g) {
    Err(e) =>
      return Err({ position: 0, point: { row: 0, column: 0 }, message: e })
    Ok((table, _)) => parse(table, input)
  }
}

///|
/// 解析 input，使用外部词法器回调。
/// 语法错误以带 ERROR/MISSING 节点的 CST 形式返回 Ok。
pub fn parse_with_external_scanner(
  table : @tablegen.ParseTable,
  input : String,
  scanner : ExternalScanner,
) -> Result[CstNode, ParseError] {
  glr_parse_with_external_scanner(table, input, scanner)
}

///|
/// 增量解析 + 外部词法器回调
pub fn parse_with_old_tree_and_external_scanner(
  table : @tablegen.ParseTable,
  input : String,
  old_tree : OldTree?,
  edit : InputEdit?,
  scanner : ExternalScanner,
) -> Result[CstNode, ParseError] {
  parse_incremental_with_external_scanner(table, input, old_tree, edit, scanner)
}

///|
/// 解析 input，使用有状态外部词法器。
/// GLR 分支时会对 scanner 状态进行 clone，确保每条解析路径持有独立状态。
pub fn parse_with_stateful_scanner(
  table : @tablegen.ParseTable,
  input : String,
  scanner : &StatefulScanner,
) -> Result[CstNode, ParseError] {
  glr_parse_with_stateful_scanner(table, input, scanner)
}

///|
/// 解析 input，使用有状态外部词法器和自定义错误恢复配置。
pub fn parse_with_stateful_scanner_and_config(
  table : @tablegen.ParseTable,
  input : String,
  scanner : &StatefulScanner,
  config : ParseConfig,
) -> Result[CstNode, ParseError] {
  glr_parse_with_stateful_scanner_and_config(table, input, scanner, config)
}

///|
/// 增量解析 + 有状态外部词法器
pub fn parse_with_old_tree_and_stateful_scanner(
  table : @tablegen.ParseTable,
  input : String,
  old_tree : OldTree?,
  edit : InputEdit?,
  scanner : &StatefulScanner,
) -> Result[CstNode, ParseError] {
  parse_incremental_with_stateful_scanner(table, input, old_tree, edit, scanner)
}

///|
/// 增量解析 + 有状态外部词法器 + 自定义错误恢复配置
pub fn parse_with_old_tree_and_stateful_scanner_and_config(
  table : @tablegen.ParseTable,
  input : String,
  old_tree : OldTree?,
  edit : InputEdit?,
  scanner : &StatefulScanner,
  config : ParseConfig,
) -> Result[CstNode, ParseError] {
  parse_incremental_with_stateful_scanner_and_config(
    table, input, old_tree, edit, scanner, config,
  )
}
