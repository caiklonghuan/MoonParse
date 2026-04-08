///|
/// 将用户 Grammar 一步生成 LALR(1) 解析表（含词法器 DFA）
pub fn generate_parse_table(
  grammar : @grammar.Grammar,
) -> Result[(ParseTable, Array[ConflictReport]), String] {
  // 输入校验
  if grammar.rules.length() == 0 {
    return Err("generate_parse_table: empty grammar (no rules)")
  }
  match grammar.start {
    None => return Err("generate_parse_table: no start rule declared")
    Some(s) =>
      if not(grammar.rules.contains(s)) {
        return Err("generate_parse_table: start rule '\{s}' not found")
      }
  }
  let aug = augment_grammar(grammar)
  let item_sets = build_item_sets(aug)
  let goto_map = build_goto_map(aug, item_sets)
  let table = build_lalr_table(aug, item_sets, goto_map)
  let (resolved_table, reports) = resolve_conflicts(table, aug)
  let real_dfa = build_lexer_dfa(aug, resolved_table)
  // 从 aug.terminals（名称→ID）反转得到 terminal_names（ID→名称）
  let terminal_names : Map[TerminalId, String] = Map::new()
  for name, tid in aug.terminals {
    terminal_names.set(tid, name)
  }
  let final_table = {
    states: resolved_table.states,
    action: resolved_table.action,
    goto_table: resolved_table.goto_table,
    productions: resolved_table.productions,
    lexer_dfa: real_dfa,
    symbol_metadata: resolved_table.symbol_metadata,
    terminal_patterns: resolved_table.terminal_patterns,
    terminal_names,
    extras: aug.extras,
    external_token_ids: aug.external_ids,
  }
  Ok((final_table, reports))
}
