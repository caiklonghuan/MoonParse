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

///|
fn gen_reports_ok(dsl : String) -> (ParseTable, Array[ConflictReport]) {
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(e) => {
      println(e.message)
      panic()
    }
    @grammar.Success(g) =>
      match @tablegen.generate_parse_table(g) {
        Err(e) => {
          println(e)
          panic()
        }
        Ok((table, reports)) => (table, reports)
      }
  }
}

///|
fn severity_tag(severity : ConflictSeverity) -> String {
  match severity {
    Warn(_) => "warn"
    Ambiguous(_) => "ambiguous"
    DynamicConflict(_) => "dynamic"
    Declared(_) => "declared"
  }
}

///|
fn severity_detail(severity : ConflictSeverity) -> String {
  match severity {
    Warn(msg) => msg
    Ambiguous(msg) => msg
    DynamicConflict(id) => "dynamic_id=" + id.to_string()
    Declared(msg) => msg
  }
}

///|
fn format_conflict_action(action : Action, table : ParseTable) -> String {
  match action {
    Shift(state) => "Shift(" + state.to_string() + ")"
    Reduce(pid) =>
      "Reduce(" + pid.to_string() + ":" + table.productions[pid].rule_name + ")"
    Accept => "Accept"
  }
}

///|
fn count_empty_action_cells(table : ParseTable) -> Int {
  let mut n = 0
  for _, acts in table.action {
    if acts.is_empty() {
      n = n + 1
    }
  }
  n
}

///|
fn append_conflict_line(buf : StringBuilder, line : String) -> Unit {
  buf.write_string(line)
  buf.write_char('\n')
}

///|
fn conflict_report_snapshot(
  table : ParseTable,
  reports : Array[ConflictReport],
) -> String {
  let sorted = reports.copy()
  sorted.sort_by(fn(a, b) {
    let c1 = a.state.compare(b.state)
    if c1 != 0 {
      c1
    } else {
      let c2 = a.terminal.compare(b.terminal)
      if c2 != 0 {
        c2
      } else {
        severity_tag(a.severity).compare(severity_tag(b.severity))
      }
    }
  })

  let mut warn = 0
  let mut ambiguous = 0
  let mut dynamic = 0
  let mut declared = 0
  for r in sorted {
    match r.severity {
      Warn(_) => warn = warn + 1
      Ambiguous(_) => ambiguous = ambiguous + 1
      DynamicConflict(_) => dynamic = dynamic + 1
      Declared(_) => declared = declared + 1
    }
  }

  let buf = StringBuilder::new()
  append_conflict_line(
    buf,
    "counts total=" +
    sorted.length().to_string() +
    " warn=" +
    warn.to_string() +
    " ambiguous=" +
    ambiguous.to_string() +
    " dynamic=" +
    dynamic.to_string() +
    " declared=" +
    declared.to_string(),
  )
  append_conflict_line(
    buf,
    "cells conflict=" +
    count_conflict_cells(table).to_string() +
    " empty=" +
    count_empty_action_cells(table).to_string(),
  )
  for r in sorted {
    let terminal_name = match table.terminal_names.get(r.terminal) {
      Some(name) => name
      None => "<t:" + r.terminal.to_string() + ">"
    }
    let acts : Array[String] = []
    for action in r.actions {
      acts.push(format_conflict_action(action, table))
    }
    append_conflict_line(
      buf,
      "[" +
      severity_tag(r.severity) +
      "] state=" +
      r.state.to_string() +
      " terminal=" +
      terminal_name +
      " actions=" +
      acts.join(", "),
    )
    append_conflict_line(buf, "  " + severity_detail(r.severity))
  }
  buf.to_string()
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

///|
/// Optional(?) seq 内嵌の greedy fix 検証
test "resolve_conflicts / Optional seq 内嵌の greedy shift 消解" {
  // rule s: "n"? "n" → _s_opt_N → ε | "n", s → _s_opt_N "n"
  // LALR state 0 上の lookahead "n": shift ("n" を opt でマッチ) vs reduce _s_opt_N → ε
  // _s_opt_N は synthetic かつ ε 産生式 → greedy shift 勝ち → Warn, 0 conflict cells
  let (_, table, reports) = build_resolved("start s\nrule s: \"n\"? \"n\"")
  assert_eq(count_conflict_cells(table), 0)
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

///|
/// Warn メッセージに "greedy" が含まれることを検証
test "resolve_conflicts / greedy ε Warn メッセージ確認" {
  let (_, _, reports) = build_resolved("start s\nrule s: \"n\"? \"n\"")
  let mut found = false
  for r in reports {
    match r.severity {
      Warn(msg) => if msg.contains("greedy") { found = true }
      _ => ()
    }
  }
  assert_eq(found, true)
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

// conflicts 声明 → Declared 级别

///|
test "resolve_conflicts / Reduce-Reduce 声明冲突产生 Declared（非 Ambiguous）报告" {
  // conflicts 声明放在 rules 之前，避免 parse_sequence 将 "conflicts [[" 误读为模板实例化
  let dsl = "start s\nconflicts [[a, b]]\nrule s: a \"e\" | b \"e\"\nrule a: \"d\"\nrule b: \"d\""
  let (_, _, reports) = build_resolved(dsl)
  let has_declared = has_severity(reports, fn(s) {
    match s {
      Declared(_) => true
      _ => false
    }
  })
  let has_ambiguous = has_severity(reports, fn(s) {
    match s {
      Ambiguous(_) => true
      _ => false
    }
  })
  assert_eq(has_declared, true)
  assert_eq(has_ambiguous, false)
}

///|
test "resolve_conflicts / 已声明冲突仍 GLR 保留（动作不丢失）" {
  let dsl = "start s\nconflicts [[a, b]]\nrule s: a \"e\" | b \"e\"\nrule a: \"d\"\nrule b: \"d\""
  let (_, table, _) = build_resolved(dsl)
  // 动作未被过滤掉，冲突格仍含多动作
  assert_eq(count_conflict_cells(table) >= 1, true)
}

///|
test "resolve_conflicts / 未声明冲突仍产生 Ambiguous（声明不扩大范围）" {
  // a b 冲突已声明，但 c d 冲突未声明，应仍为 Ambiguous
  let dsl = "start s\nconflicts [[a, b]]\nrule s: a \"e\" | b \"e\" | c \"f\" | d \"f\"\nrule a: \"d\"\nrule b: \"d\"\nrule c: \"g\"\nrule d: \"g\""
  let (_, _, reports) = build_resolved(dsl)
  let has_ambiguous = has_severity(reports, fn(s) {
    match s {
      Ambiguous(_) => true
      _ => false
    }
  })
  assert_eq(has_ambiguous, true)
}

// generate_parse_table 冲突报告 snapshot（Phase 3.2）

///|
test "generate_parse_table / conflict snapshot dangling else" {
  let dsl =
    #|start stmt
    #|rule stmt: "if" expr "then" stmt
    #|  | "if" expr "then" stmt "else" stmt
    #|  | "other"
    #|rule expr: "cond"
  let (table, reports) = gen_reports_ok(dsl)
  inspect(
    conflict_report_snapshot(table, reports),
    content=(
      #|counts total=1 warn=0 ambiguous=1 dynamic=0 declared=0
      #|cells conflict=1 empty=0
      #|[ambiguous] state=8 terminal=lit:else actions=Shift(9), Reduce(1:stmt)
      #|  Shift-Reduce conflict (no prec info) in state 8 on terminal 2
      #|
    ),
  )
}

///|
test "generate_parse_table / conflict snapshot precedence associativity" {
  let (table, reports) = gen_reports_ok(
    "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"",
  )
  inspect(
    conflict_report_snapshot(table, reports),
    content=(
      #|counts total=1 warn=1 ambiguous=0 dynamic=0 declared=0
      #|cells conflict=0 empty=0
      #|[warn] state=5 terminal=lit:+ actions=Shift(4), Reduce(1:e)
      #|  Shift-Reduce: left-assoc, reduce wins in state 5 on terminal 0
      #|
    ),
  )
}

///|
test "generate_parse_table / conflict snapshot nonassoc empty action" {
  let (table, reports) = gen_reports_ok(
    "start e\nrule e: prec(1, e \"+\" e) | \"n\"",
  )
  inspect(
    conflict_report_snapshot(table, reports),
    content=(
      #|counts total=1 warn=1 ambiguous=0 dynamic=0 declared=0
      #|cells conflict=0 empty=1
      #|[warn] state=5 terminal=lit:+ actions=Shift(4), Reduce(1:e)
      #|  Shift-Reduce: nonassoc, both removed in state 5 on terminal 0
      #|
    ),
  )
}

///|
test "generate_parse_table / conflict snapshot dynamic precedence" {
  let (table, reports) = gen_reports_ok(
    "start e\nrule e: prec.dynamic(1, e \"+\" e) | \"n\"",
  )
  inspect(
    conflict_report_snapshot(table, reports),
    content=(
      #|counts total=1 warn=0 ambiguous=0 dynamic=1 declared=0
      #|cells conflict=1 empty=0
      #|[dynamic] state=5 terminal=lit:+ actions=Shift(4), Reduce(1:e)
      #|  dynamic_id=1
      #|
    ),
  )
}

///|
test "generate_parse_table / conflict snapshot declared conflict" {
  let dsl = "start s\nconflicts [[a, b]]\nrule s: a \"e\" | b \"e\"\nrule a: \"d\"\nrule b: \"d\""
  let (table, reports) = gen_reports_ok(dsl)
  inspect(
    conflict_report_snapshot(table, reports),
    content=(
      #|counts total=1 warn=0 ambiguous=0 dynamic=0 declared=1
      #|cells conflict=1 empty=0
      #|[declared] state=4 terminal=lit:e actions=Reduce(3:a), Reduce(4:b)
      #|  Reduce-Reduce conflict (declared GLR) in state 4 on terminal 0
      #|
    ),
  )
}
