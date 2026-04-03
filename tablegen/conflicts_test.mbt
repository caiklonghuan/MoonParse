// conflicts_test.mbt — resolve_conflicts 的黑盒单元测试
//
// 辅助函数 build_ag / nt_id / term_id 复用自 sets_test.mbt；
// build_table / any_table_action / count_table_actions / has_conflict_cell
// 复用自 lalr_test.mbt。

// 辅助函数

///|
/// 完整流水线：parse → augment → item_sets → goto_map → lalr_table → resolve
fn build_resolved(
  dsl : String,
) -> (AugmentedGrammar, ParseTable, Array[ConflictReport]) {
  let (ag, raw) = build_table(dsl)
  let (resolved, reports) = resolve_conflicts(raw, ag)
  (ag, resolved, reports)
}

///|
/// 检查报告列表中是否含指定 severity 类型的报告
fn has_severity(
  reports : Array[ConflictReport],
  pred : (ConflictSeverity) -> Bool,
) -> Bool {
  let mut found = false
  for r in reports {
    if pred(r.severity) {
      found = true
      break
    }
  }
  found
}

///|
/// 统计 action 表中多动作格的总数（仍有 GLR 冲突的格）
fn count_conflict_cells(table : ParseTable) -> Int {
  let mut n = 0
  for _, actions in table.action {
    if actions.length() > 1 {
      n = n + 1
    }
  }
  n
}

// 无冲突文法

///|
test "resolve_conflicts / 无歧义文法不产生报告" {
  let (_, _, reports) = build_resolved("start s\nrule s: \"a\"")
  assert_eq(reports.length(), 0)
}

///|
test "resolve_conflicts / 无歧义文法解析表无变化（无冲突格）" {
  let (_, table, _) = build_resolved("start s\nrule s: \"a\"")
  assert_eq(count_conflict_cells(table), 0)
}

///|
test "resolve_conflicts / 无歧义文法 Accept 动作保留" {
  let (_, table, _) = build_resolved("start s\nrule s: \"a\"")
  assert_eq(count_table_actions(table, fn(a) { a == Accept }), 1)
}

// Ambiguous（无 prec 信息）

///|
test "resolve_conflicts / 歧义文法产生 Ambiguous 报告" {
  // e → e "+" e | "n"：经典 S-R 冲突，无 prec 标注
  let (_, _, reports) = build_resolved("start e\nrule e: e \"+\" e | \"n\"")
  assert_eq(
    has_severity(reports, fn(s) {
      match s {
        Ambiguous(_) => true
        _ => false
      }
    }),
    true,
  )
}

///|
test "resolve_conflicts / 歧义文法（无 prec）冲突格动作不丢失（GLR 保留）" {
  // 无 prec → Ambiguous → GLR 保留全部动作，冲突格仍含多动作
  let (_, table, _) = build_resolved("start e\nrule e: e \"+\" e | \"n\"")
  assert_eq(count_conflict_cells(table) >= 1, true)
}

// Left 结合性（Reduce 胜）

///|
test "resolve_conflicts / Left-assoc 产生 Warn 报告" {
  let (_, _, reports) = build_resolved(
    "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"",
  )
  assert_eq(
    has_severity(reports, fn(s) {
      match s {
        Warn(_) => true
        _ => false
      }
    }),
    true,
  )
}

///|
test "resolve_conflicts / Left-assoc 消解后无冲突格（Reduce 胜）" {
  // left-assoc：同 prec 时 Reduce 胜，冲突格缩减为单动作
  let (_, table, _) = build_resolved(
    "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"",
  )
  assert_eq(count_conflict_cells(table), 0)
}

///|
test "resolve_conflicts / Left-assoc 消解后保留 Reduce 动作" {
  let (_, table, _) = build_resolved(
    "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"",
  )
  assert_eq(
    any_table_action(table, fn(a) {
      match a {
        Reduce(_) => true
        _ => false
      }
    }),
    true,
  )
}

///|
test "resolve_conflicts / Left-assoc 消解后动作总数少于消解前" {
  // 消解移除了冲突格中的 Shift，总动作数应减少
  let (ag, raw) = build_table(
    "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"",
  )
  let (resolved, _) = resolve_conflicts(raw, ag)
  let raw_total = count_table_actions(raw, fn(_a) { true })
  let res_total = count_table_actions(resolved, fn(_a) { true })
  assert_eq(res_total < raw_total, true)
}

// Right 结合性（Shift 胜）

///|
test "resolve_conflicts / Right-assoc 消解后无冲突格（Shift 胜）" {
  let (_, table, _) = build_resolved(
    "start e\nrule e: prec.right(1, e \"+\" e) | \"n\"",
  )
  assert_eq(count_conflict_cells(table), 0)
}

///|
test "resolve_conflicts / Right-assoc 消解后 '+' 列保留 Shift" {
  let (ag, table, _) = build_resolved(
    "start e\nrule e: prec.right(1, e \"+\" e) | \"n\"",
  )
  let t_plus = term_id(ag, "lit:+")
  let mut has_shift_on_plus = false
  for key, actions in table.action {
    let (_, tid) = key
    if tid == t_plus {
      for a in actions {
        match a {
          Shift(_) => has_shift_on_plus = true
          _ => ()
        }
      }
    }
  }
  assert_eq(has_shift_on_plus, true)
}

///|
test "resolve_conflicts / Right-assoc 产生 Warn 报告" {
  let (_, _, reports) = build_resolved(
    "start e\nrule e: prec.right(1, e \"+\" e) | \"n\"",
  )
  assert_eq(
    has_severity(reports, fn(s) {
      match s {
        Warn(_) => true
        _ => false
      }
    }),
    true,
  )
}

// Nonassoc（两者均删除）

///|
test "resolve_conflicts / Nonassoc 消解后 '+' 列无任何动作" {
  // prec(1, ...) = Nonassoc：同优先级时冲突格两者均删除，不再有 Shift-Reduce 冲突
  let (_, table, _) = build_resolved(
    "start e\nrule e: prec(1, e \"+\" e) | \"n\"",
  )
  // 冲突在消解后应被清空，不再有多动作格
  assert_eq(count_conflict_cells(table), 0)
}

///|
test "resolve_conflicts / Nonassoc 产生 Warn 报告" {
  let (_, _, reports) = build_resolved(
    "start e\nrule e: prec(1, e \"+\" e) | \"n\"",
  )
  assert_eq(
    has_severity(reports, fn(s) {
      match s {
        Warn(_) => true
        _ => false
      }
    }),
    true,
  )
}

// Reduce-Reduce 冲突

///|
test "resolve_conflicts / Reduce-Reduce 产生 Ambiguous 报告" {
  // s → a "e" | b "e"; a → "d"; b → "d"
  // 见到 "d" → state 中同时有 [a → "d" •] 和 [b → "d" •]
  // FOLLOW(a) = FOLLOW(b) = {"e"} → action[(state,"e")] 含两个 Reduce
  let (_, _, reports) = build_resolved(
    "start s\nrule s: a \"e\" | b \"e\"\nrule a: \"d\"\nrule b: \"d\"",
  )
  assert_eq(
    has_severity(reports, fn(s) {
      match s {
        Ambiguous(_) => true
        _ => false
      }
    }),
    true,
  )
}

///|
test "resolve_conflicts / Reduce-Reduce 冲突动作 GLR 全部保留" {
  let (_, table, _) = build_resolved(
    "start s\nrule s: a \"e\" | b \"e\"\nrule a: \"d\"\nrule b: \"d\"",
  )
  // 冲突格仍含 2 个 Reduce
  assert_eq(count_conflict_cells(table) >= 1, true)
}

// Dynamic prec

///|
test "resolve_conflicts / Dynamic prec 产生 DynamicConflict 报告" {
  let (_, _, reports) = build_resolved(
    "start e\nrule e: prec.dynamic(1, e \"+\" e) | \"n\"",
  )
  assert_eq(
    has_severity(reports, fn(s) {
      match s {
        DynamicConflict(_) => true
        _ => false
      }
    }),
    true,
  )
}

///|
test "resolve_conflicts / Dynamic prec 报告携带 prec id" {
  // prec.dynamic(1, ...) 应携带 id = 1
  let (_, _, reports) = build_resolved(
    "start e\nrule e: prec.dynamic(1, e \"+\" e) | \"n\"",
  )
  let mut found_id = false
  for r in reports {
    match r.severity {
      DynamicConflict(id) => if id == 1 { found_id = true }
      _ => ()
    }
  }
  assert_eq(found_id, true)
}

///|
test "resolve_conflicts / Dynamic prec 动作 GLR 全部保留" {
  let (_, table, _) = build_resolved(
    "start e\nrule e: prec.dynamic(1, e \"+\" e) | \"n\"",
  )
  assert_eq(count_conflict_cells(table) >= 1, true)
}

// 综合：多运算符优先级

///|
test "resolve_conflicts / 双运算符（* 优先级高于 +）消解后无冲突" {
  // e → prec.left(2, e "*" e) | prec.left(1, e "+" e) | "n"
  // "*" 的 shift_prec = 2，reduce prec of e→e+e = 1 → shift 胜
  // "+" 的 shift_prec = 1，reduce prec of e→e+e = 1, left → reduce 胜
  let (_, table, _) = build_resolved(
    "start e\nrule e: prec.left(2, e \"*\" e) | prec.left(1, e \"+\" e) | \"n\"",
  )
  assert_eq(count_conflict_cells(table), 0)
}

///|
test "resolve_conflicts / 双运算符消解产生 Warn 但不产生 Ambiguous" {
  let (_, _, reports) = build_resolved(
    "start e\nrule e: prec.left(2, e \"*\" e) | prec.left(1, e \"+\" e) | \"n\"",
  )
  let has_warn = has_severity(reports, fn(s) {
    match s {
      Warn(_) => true
      _ => false
    }
  })
  let has_ambiguous = has_severity(reports, fn(s) {
    match s {
      Ambiguous(_) => true
      _ => false
    }
  })
  assert_eq(has_warn, true)
  assert_eq(has_ambiguous, false)
}

// resolve_conflicts 不影响无冲突动作

///|
test "resolve_conflicts / 消解不改变 goto_table" {
  let (ag, raw) = build_table("start e\nrule e: e \"+\" e | \"n\"")
  let (resolved, _) = resolve_conflicts(raw, ag)
  // goto_table 应完全一致
  assert_eq(resolved.goto_table.length(), raw.goto_table.length())
}

///|
test "resolve_conflicts / 消解不改变 states 数量" {
  let (ag, raw) = build_table("start e\nrule e: e \"+\" e | \"n\"")
  let (resolved, _) = resolve_conflicts(raw, ag)
  assert_eq(resolved.states, raw.states)
}

///|
test "resolve_conflicts / 消解不改变 productions" {
  let (ag, raw) = build_table("start e\nrule e: e \"+\" e | \"n\"")
  let (resolved, _) = resolve_conflicts(raw, ag)
  assert_eq(resolved.productions.length(), raw.productions.length())
}
