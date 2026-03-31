///|
// ─── §5 冲突处理 ─────────────────────────────────────────────────────────────
//
// 实现 design.md §5 的公开函数：
//   resolve_conflicts(table, grammar) -> (ParseTable, Array[ConflictReport])
//
// 算法概览：
//   对每个 action[(state, t)] 含多个动作的格：
//   1. 若为 Reduce-Reduce → 无法消解，报 Ambiguous（GLR 保留全部）
//   2. 若为 Shift-Reduce  → 对比 shift_prec 与 reduce_prec：
//        shift_prec  = grammar 中 body 含 Terminal(t) 的产生式 .prec 最大值
//        reduce_prec = 被规约产生式的 .prec
//      - shift_prec > reduce_prec : 删除 Reduce（Shift 胜）
//      - shift_prec < reduce_prec : 删除 Shift（Reduce 胜）
//      - shift_prec == reduce_prec :
//          Left  → 删除 Shift（Reduce 胜）
//          Right → 删除 Reduce（Shift 胜）
//          Nonassoc → 两者均删除（该输入为语法错误）
//          Dynamic  → 编译期无法消解，报 DynamicConflict
//      - 无 prec 信息 → 报 Ambiguous（GLR 保留全部）

// ─── 辅助：终结符 t 对应的 Shift 优先级 ────────────────────────────────────

///|
/// 在 grammar.productions 中查找所有 body 含 Terminal(t) 的产生式，
/// 返回其 .prec 的最大值；所有产生式均无 prec 标注时返回 None。
fn shift_prec_for(grammar : AugmentedGrammar, t : TerminalId) -> Int? {
  let mut best : Int? = None
  for prod in grammar.productions {
    let mut has_t = false
    for bs in prod.body {
      if bs.symbol == Terminal(t) {
        has_t = true
        break
      }
    }
    if has_t {
      match prod.prec {
        Some(p) =>
          match best {
            None => best = Some(p)
            Some(b) => if p > b { best = Some(p) }
          }
        None => ()
      }
    }
  }
  best
}

// ─── 辅助：单格冲突消解 ──────────────────────────────────────────────────────

///|
/// 对单个含多个动作的 action 格进行优先级/结合性消解。
///
/// 返回 (过滤后动作列表, 冲突报告?)。
/// - 过滤后列表为空 → Nonassoc 同优先级冲突，该位置输入为语法错误
/// - 报告为 None    → 动作只有一个，理论上不会进入此函数
fn resolve_cell(
  state : StateId,
  terminal : TerminalId,
  actions : Array[Action],
  grammar : AugmentedGrammar,
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

  // ── Reduce-Reduce：无法消解，报 Ambiguous ─────────────────────────────────
  if shifts.length() == 0 {
    let msg = "Reduce-Reduce conflict in state \{state} on terminal \{terminal}"
    return (
      actions,
      Some({ state, terminal, actions, severity: Ambiguous(msg) }),
    )
  }

  // ── Shift-Reduce ──────────────────────────────────────────────────────────
  let sp = shift_prec_for(grammar, terminal)

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

// ─── 公开 API ─────────────────────────────────────────────────────────────────

///|
/// 用优先级/结合性过滤 ParseTable 中的冲突；无法消解的冲突保留并生成报告。
///
/// - 消解成功（prec/assoc 充分）    → ConflictReport.severity = Warn
/// - 无 prec 信息                    → severity = Ambiguous（GLR 保留全部动作）
/// - dynamic assoc                   → severity = DynamicConflict（运行时处理）
pub fn resolve_conflicts(
  table : ParseTable,
  grammar : AugmentedGrammar,
) -> (ParseTable, Array[ConflictReport]) {
  let reports : Array[ConflictReport] = []
  let new_action : Map[(StateId, TerminalId), Array[Action]] = Map::new()

  for key, actions in table.action {
    let (state, terminal) = key
    if actions.length() > 1 {
      let (kept, report) = resolve_cell(state, terminal, actions, grammar)
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
  }
  (new_table, reports)
}
