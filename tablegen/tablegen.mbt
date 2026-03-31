///|
// ─── §8 一键入口 ──────────────────────────────────────────────────────────────
//
// 将 §1~§5 的流水线封装为单一公开函数：
//   generate_parse_table(grammar) -> Result[(ParseTable, Array[ConflictReport]), String]
//
// 流水线：
//   Grammar
//     │ augment_grammar()          §1
//     ▼
//   AugmentedGrammar
//     │ build_item_sets()          §3
//     ▼
//   Array[Set[LRItem]]
//     │ build_goto_map()           §3
//     ▼
//   Map[(StateId, Symbol), StateId]
//     │ build_lalr_table()         §4
//     ▼
//   ParseTable (含冲突)
//     │ resolve_conflicts()        §5
//     ▼
//   (ParseTable, Array[ConflictReport])

///|
/// 将用户 Grammar 一步生成 LALR(1) 解析表。
///
/// 返回 `Ok((table, reports))`：
/// - `table`   — 完成冲突解决后的解析表
/// - `reports` — 所有冲突报告（Warn / Ambiguous / DynamicConflict）
///
/// 当前 Phase 1 不做输入校验，空文法会返回退化表而非 Err。
pub fn generate_parse_table(
  grammar : @grammar.Grammar,
) -> Result[(ParseTable, Array[ConflictReport]), String] {
  let aug = augment_grammar(grammar)
  let item_sets = build_item_sets(aug)
  let goto_map = build_goto_map(aug, item_sets)
  let table = build_lalr_table(aug, item_sets, goto_map)
  let (resolved_table, reports) = resolve_conflicts(table, aug)
  Ok((resolved_table, reports))
}
