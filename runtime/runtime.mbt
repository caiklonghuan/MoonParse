///|
// 公开入口（runtime 对外 API）
//
// 对外暴露三个解析函数：
//
//   parse(table, input)                        → glr_parse（GSS，支持歧义文法 + 错误恢复）
//   parse_with_old_tree(table, input, ot, ed)  → parse_incremental（复用旧子树）
//   parse_from_dsl(dsl, input)                 → 便捷入口，Grammar DSL 一键解析

///|
/// 解析 input，返回完整 CST。
/// 语法错误以带 ERROR/MISSING 节点的 CST 形式返回 Ok。
///
/// # 参数
/// - table : 由 tablegen 生成的 LALR 解析表（含词法 DFA）
/// - input : 待解析的 UTF-8 字符串
pub fn parse(
  table : @tablegen.ParseTable,
  input : String,
) -> Result[CstNode, ParseError] {
  glr_parse(table, input)
}

///|
/// 增量解析：提供旧树和编辑描述，复用未受编辑影响的子树。
///
/// 当 old_tree / edit 均为 Some 时，对旧树标记 has_changes、校正字节偏移与
/// 行列坐标后，在 GLR Shift 前尝试直接复用旧节点；否则退化为全量解析。
///
/// # 参数
/// - table    : LALR 解析表
/// - input    : 新的完整输入字符串（编辑后）
/// - old_tree : 上一次解析结果（None = 首次解析，走全量路径）
/// - edit     : 描述本次编辑的 InputEdit（None = 全量重解析）
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
/// # 参数
/// - table  : LALR 解析表
/// - input  : 待解析的 UTF-8 字符串
/// - config : 错误恢复与 GLR 版本数配置（见 `ParseConfig::default()`）
pub fn parse_with_config(
  table : @tablegen.ParseTable,
  input : String,
  config : ParseConfig,
) -> Result[CstNode, ParseError] {
  glr_parse_with_config(table, input, config)
}

///|
/// 带自定义配置的增量解析入口。

///|
/// # 参数
/// - table    : LALR 解析表
/// - input    : 新的完整输入字符串（编辑后）
/// - old_tree : 上一次解析结果（None = 全量重解析）
/// - edit     : 编辑描述（None = 全量重解析）
/// - config   : 错误恢复与 GLR 版本数配置
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
/// DSL → ParseTable → CST 的一键便捷入口（主要用于测试和简单用例）
///
/// # 参数
/// - dsl   : Grammar DSL 字符串（与 @grammar.parse_grammar 格式一致）
/// - input : 待解析的 UTF-8 字符串
///
/// # 返回
/// - Ok(CstNode) — 解析成功
/// - Err(ParseError) — 语法错误或 DSL/表生成失败
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
  match @tablegen.generate_parse_table(g) {
    Err(e) =>
      return Err({ position: 0, point: { row: 0, column: 0 }, message: e })
    Ok((table, _)) => parse(table, input)
  }
}
