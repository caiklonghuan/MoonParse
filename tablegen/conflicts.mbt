///|
// 冲突处理

///|
/// 预构建 Map[TerminalId, (Int, PrecKind?)]：扫描全部产生式（O(P×B)）各做一次，
/// 返回每个终结符作为 Shift 目标时的最高优先级与结合性。
/// prec_table（顶层声明）权威提供结合性；产生式内联 prec 仅补充优先级数值。
fn build_shift_prec_map(
  grammar : AugmentedGrammar,
) -> Map[TerminalId, (Int, @grammar.PrecKind?)] {
  let m : Map[TerminalId, (Int, @grammar.PrecKind?)] = Map::new()
  // 产生式内联 prec：记录优先级，结合性留 None（来自产生式自身，不代表终结符 assoc）
  for prod in grammar.productions {
    match prod.prec {
      None => ()
      Some(p) =>
        for bs in prod.body {
          match bs.symbol {
            Terminal(t) =>
              match m.get(t) {
                None => m.set(t, (p, None))
                Some((cur, cur_k)) => if p > cur { m.set(t, (p, cur_k)) }
              }
            _ => ()
          }
        }
    }
  }
  // prec_table（顶层声明）：优先级 + 结合性均权威，覆盖产生式来源的条目
  for t, entry in grammar.prec_table {
    let (lv, lk) = entry
    match m.get(t) {
      None => m.set(t, (lv, Some(lk)))
      Some((cur, _)) =>
        // prec_table 总是胜出 assoc；优先级取较大值
        if lv >= cur {
          m.set(t, (lv, Some(lk)))
        } else {
          // 旧优先级更高，但 assoc 仍使用顶层声明
          m.set(t, (cur, Some(lk)))
        }
    }
  }
  m
}

///|
/// O(1) 查询预构建表；t 不在表中则返回 None。
fn shift_prec_lookup(
  shift_map : Map[TerminalId, (Int, @grammar.PrecKind?)],
  t : TerminalId,
) -> (Int, @grammar.PrecKind?)? {
  shift_map.get(t)
}

// 辅助：单格冲突消解

///|
/// 判断一组规则名是否被同一条 DSL conflicts 声明显式涵盖（子集关系）
fn is_declared_conflict(
  rule_names : Array[String],
  declared_groups : Array[Array[String]],
) -> Bool {
  if rule_names.length() == 0 {
    return false
  }
  for group in declared_groups {
    let mut all_in = true
    for n in rule_names {
      if !group.contains(n) {
        all_in = false
        break
      }
    }
    if all_in {
      return true
    }
  }
  false
}

///|
/// 对单个含多个动作的 action 格进行优先级/结合性消解
fn resolve_cell(
  state : StateId,
  terminal : TerminalId,
  actions : Array[Action],
  grammar : AugmentedGrammar,
  shift_map : Map[TerminalId, (Int, @grammar.PrecKind?)],
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

  // Reduce-Reduce：检查是否为声明的 GLR 冲突
  if shifts.length() == 0 {
    let reduce_names : Array[String] = []
    for a in reduces {
      match a {
        Reduce(pid) => reduce_names.push(grammar.productions[pid].rule_name)
        _ => ()
      }
    }
    let severity = if is_declared_conflict(
        reduce_names,
        grammar.declared_conflicts,
      ) {
      Declared(
        "Reduce-Reduce conflict (declared GLR) in state \{state} on terminal \{terminal}",
      )
    } else {
      Ambiguous(
        "Reduce-Reduce conflict in state \{state} on terminal \{terminal}",
      )
    }
    return (actions, Some({ state, terminal, actions, severity }))
  }

  // Shift-Reduce
  // 解构终结符优先级与结合性（terminal assoc 来自顶层 prec_table，优先于产生式 assoc）
  let sp_entry = shift_prec_lookup(shift_map, terminal)
  let sp = match sp_entry {
    Some((lv, _)) => Some(lv)
    None => None
  }
  let terminal_assoc : @grammar.PrecKind? = match sp_entry {
    Some((_, k)) => k
    None => None
  }

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
        if prod.body.length() == 0 && grammar.nt_metas[prod.head].is_synthetic {
          warn_msg = "Shift-Reduce: greedy shift wins over synthetic ε (rule: \{prod.rule_name}) in state \{state} on terminal \{terminal}"
          // 丢弃本 Reduce，保留 Shift，继续下一个 reduce
          continue
        }
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
              // prec 相等，按结合性决定；终结符 assoc（来自顶层声明）优先于产生式 assoc
              let effective_assoc = match terminal_assoc {
                Some(_) => terminal_assoc
                None => prod.assoc
              }
              match effective_assoc {
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
  let report : ConflictReport? = if !all_resolved {
    let reduce_names : Array[String] = []
    for r in kept_reduces {
      match r {
        Reduce(pid) => reduce_names.push(grammar.productions[pid].rule_name)
        _ => ()
      }
    }
    let severity = if is_declared_conflict(
        reduce_names,
        grammar.declared_conflicts,
      ) {
      Declared(
        "Shift-Reduce conflict (declared GLR) in state \{state} on terminal \{terminal}",
      )
    } else {
      Ambiguous(
        "Shift-Reduce conflict (no prec info) in state \{state} on terminal \{terminal}",
      )
    }
    Some({ state, terminal, actions, severity })
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
    word_token: table.word_token,
    keyword_map: table.keyword_map,
  }
  (new_table, reports)
}
