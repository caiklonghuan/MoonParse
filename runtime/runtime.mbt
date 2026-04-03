///|
// ─── §0 公开入口（runtime 对外 API）──────────────────────────────────────────
//
// 对外暴露三个解析函数，内部分阶段路由：
//
//   parse(table, input)
//     · Phase 2a：→ parse_linear（单栈 LR，无错误恢复）
//     · Phase 2b：→ parse_linear + 错误恢复
//     · Phase 2c：→ glr_parse（GSS，歧义语法）
//
//   parse_with_old_tree(table, input, old_tree, edit)
//     · Phase 3a：→ parse_incremental（复用旧子树）
//
// 本文件不含业务逻辑，仅做薄包装与文档收口。

///|
/// 解析 input，返回完整 CST。
///
/// · 语法错误（Phase 2a）：返回 Err(ParseError)
/// · Phase 2b 起：语法错误以带 ERROR 节点的 CST 形式返回 Ok
///
/// # 参数
/// - table : 由 tablegen 生成的 LALR 解析表（含词法 DFA）
/// - input : 待解析的 UTF-8 字符串
pub fn parse(
  table : @tablegen.ParseTable,
  input : String,
) -> Result[CstNode, ParseError] {
  parse_linear(table, input)
}

///|
/// 增量解析：提供旧树和编辑描述以复用未变更子树。
///
/// · Phase 3a 前：忽略 old_tree / edit，退化为全量解析
/// · Phase 3a 起：see incremental.mbt
///
/// # 参数
/// - table    : LALR 解析表
/// - input    : 新的完整输入字符串（编辑后）
/// - old_tree : 上一次解析结果（None = 首次解析）
/// - edit     : 描述本次编辑的 InputEdit（None = 全量重解析）
pub fn parse_with_old_tree(
  table : @tablegen.ParseTable,
  input : String,
  old_tree : OldTree?,
  edit : InputEdit?,
) -> Result[CstNode, ParseError] {
  parse_incremental(table, input, old_tree, edit)
}
