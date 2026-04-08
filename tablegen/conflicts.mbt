///|
// 冲突处理
///|
/// 预构建 Map[TerminalId, Int]：扫描全部产生式（O(P×B)）各做一次，
/// 返回每个终结符作为 Shift 目标时的最高优先级。
/// 已有 prec_table 的条目作为回落（顶层优先级声明）
fn build_shift_prec_map(grammar : AugmentedGrammar) -> Map[TerminalId, Int] {
  let m : Map[TerminalId, Int] = Map::new()
  // 产生式内联 prec
  for prod in grammar.productions {
    match prod.prec {
      None => ()
      Some(p) =>
        for bs in prod.body {
          match bs.symbol {
            Terminal(t) =>
              match m.get(t) {
                None => m.set(t, p)
                Some(cur) => if p > cur { m.set(t, p) }
              }
            _ => ()
          }
        }
    }
  }
  // prec_table 回落（顶层声明，已有值时只升不降）
  for t, entry in grammar.prec_table {
    let (lv, _) = entry
    match m.get(t) {
      None => m.set(t, lv)
      Some(cur) => if lv > cur { m.set(t, lv) }
    }
  }
  m
}

///|
/// O(1) 查询预构建表；t 不在表中则返回 None。
fn shift_prec_lookup(shift_map : Map[TerminalId, Int], t : TerminalId) -> Int? {
  shift_map.get(t)
}

// 辅助：单格冲突消解

///|
/// 对单个含多个动作的 action 格进行优先级/结合性消解
fn resolve_cell(
  state : StateId,
  terminal : TerminalId,
  actions : Array[Action],
  grammar : AugmentedGrammar,
  shift_map : Map[TerminalId, Int],
) -> (Array[Action], ConflictReport?) {
  // 拆分 Shift（含 Accept）与 Reduce
  let shifts : Array[Action] = []
  let reduces : Array[Action] = []
  for a in actions {
    match a {
      Shift(_) | Accept => shifts.push(a)
      Reduce(_) => reduces.push(a)
    }
  }

  // Reduce-Reduce：无法消解，报 Ambiguous
  if shifts.length() == 0 {
    let msg = "Reduce-Reduce conflict in state \{state} on terminal \{terminal}"
    return (
      actions,
      Some({ state, terminal, actions, severity: Ambiguous(msg) }),
    )
  }

  // Shift-Reduce
  let sp = shift_prec_lookup(shift_map, terminal)

  // 先扫描 Dynamic assoc（编译期无法消解，直接返回 DynamicConflict）
  for a in reduces {
    match a {
      Reduce(pid) => {
        let prod = grammar.productions[pid]
        match prod.assoc {
          Some(@grammar.PrecKind::Dynamic) => {
            let dyn_id = match prod.prec {
              Some(n) => n
              None => 0
            }
            return (
              actions,
              Some({
                state,
                terminal,
                actions,
                severity: DynamicConflict(dyn_id),
              }),
            )
          }
          _ => ()
        }
      }
      _ => ()
    }
  }

  // 逐 Reduce 与 Shift 比较，决定各自去留
  let mut keep_shifts = true
  let kept_reduces : Array[Action] = []
  let mut all_resolved = true
  let mut warn_msg = ""

  for a in reduces {
    match a {
      Reduce(pid) => {
        let prod = grammar.productions[pid]
        match (sp, prod.prec) {
          (Some(sv), Some(rv)) =>
            if sv > rv {
              // Shift 胜出，丢弃本 Reduce
              warn_msg = "Shift-Reduce: shift wins (prec \{sv} > \{rv}) in state \{state} on terminal \{terminal}"
            } else if sv < rv {
              // Reduce 胜出，保留 Reduce，丢弃 Shift
              kept_reduces.push(a)
              keep_shifts = false
              warn_msg = "Shift-Reduce: reduce wins (prec \{rv} > \{sv}) in state \{state} on terminal \{terminal}"
            } else {
              // prec 相等，按结合性决定
              match prod.assoc {
                Some(@grammar.PrecKind::Left) => {
                  kept_reduces.push(a)
                  keep_shifts = false
                  warn_msg = "Shift-Reduce: left-assoc, reduce wins in state \{state} on terminal \{terminal}"
                }
                Some(@grammar.PrecKind::Right) =>
                  // 右结合：保留 Shift，丢弃 Reduce
                  warn_msg = "Shift-Reduce: right-assoc, shift wins in state \{state} on terminal \{terminal}"
                Some(@grammar.PrecKind::Nonassoc) => {
                  // 无结合性：两者均删除，输入在该点非法
                  keep_shifts = false
                  warn_msg = "Shift-Reduce: nonassoc, both removed in state \{state} on terminal \{terminal}"
                }
                _ => {
                  // None 或 Dynamic（Dynamic 已在上方处理过）：保守保留两者
                  kept_reduces.push(a)
                  all_resolved = false
                }
              }
            }
          _ => {
            // 无 prec 信息，无法消解，保留 Reduce
            kept_reduces.push(a)
            all_resolved = false
          }
        }
      }
      _ => ()
    }
  }

  // 组装过滤后的动作列表
  let kept : Array[Action] = []
  if keep_shifts {
    for s in shifts {
      kept.push(s)
    }
  }
  for r in kept_reduces {
    kept.push(r)
  }

  // 生成报告
  let report : ConflictReport? = if not(all_resolved) {
    let msg = "Shift-Reduce conflict (no prec info) in state \{state} on terminal \{terminal}"
    Some({ state, terminal, actions, severity: Ambiguous(msg) })
  } else if kept.length() < actions.length() {
    Some({ state, terminal, actions, severity: Warn(warn_msg) })
  } else {
    None
  }
  (kept, report)
}

// 公开 API

///|
/// 用优先级/结合性过滤 ParseTable 中的冲突；无法消解的冲突保留并生成报告
pub fn resolve_conflicts(
  table : ParseTable,
  grammar : AugmentedGrammar,
) -> (ParseTable, Array[ConflictReport]) {
  let reports : Array[ConflictReport] = []
  let new_action : Map[(StateId, TerminalId), Array[Action]] = Map::new()
  // 预构建 shift 优先级查找表（O(P×B) 一次，后续每格 O(1)）
  let shift_map = build_shift_prec_map(grammar)

  for key, actions in table.action {
    let (state, terminal) = key
    if actions.length() > 1 {
      let (kept, report) = resolve_cell(
        state, terminal, actions, grammar, shift_map,
      )
      new_action.set(key, kept)
      match report {
        Some(r) => reports.push(r)
        None => ()
      }
    } else {
      new_action.set(key, actions)
    }
  }

  let new_table : ParseTable = {
    states: table.states,
    action: new_action,
    goto_table: table.goto_table,
    productions: table.productions,
    lexer_dfa: table.lexer_dfa,
    symbol_metadata: table.symbol_metadata,
    terminal_patterns: table.terminal_patterns,
    terminal_names: table.terminal_names,
    extras: table.extras,
    external_token_ids: table.external_token_ids,
  }
  (new_table, reports)
}
