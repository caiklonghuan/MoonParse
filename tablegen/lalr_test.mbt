// lalr_test.mbt — build_lalr_table 的黑盒单元测试
//
// 辅助函数 build_ag / nt_id / term_id 复用自同一测试包中的 sets_test.mbt。

// 辅助函数

///|
/// 流水线：parse → augment → item_sets → goto_map → lalr_table
fn build_table(dsl : String) -> (AugmentedGrammar, ParseTable) {
  let ag = build_ag(dsl)
  let item_sets = build_item_sets(ag)
  let goto_map = build_goto_map(ag, item_sets)
  let table = build_lalr_table(ag, item_sets, goto_map)
  (ag, table)
}

///|
/// 遍历 action 表，检查是否存在满足 pred 的动作
fn any_table_action(table : ParseTable, pred : (Action) -> Bool) -> Bool {
  let mut found = false
  for _, actions in table.action {
    if found {
      break
    }
    for a in actions {
      if pred(a) {
        found = true
        break
      }
    }
  }
  found
}

///|
/// 统计跨全部格中满足 pred 的动作总数
fn count_table_actions(table : ParseTable, pred : (Action) -> Bool) -> Int {
  let mut n = 0
  for _, actions in table.action {
    for a in actions {
      if pred(a) {
        n = n + 1
      }
    }
  }
  n
}

///|
/// 检查 action 表中是否存在含多个动作的格（GLR 冲突）
fn has_conflict_cell(table : ParseTable) -> Bool {
  let mut found = false
  for _, actions in table.action {
    if actions.length() > 1 {
      found = true
      break
    }
  }
  found
}

///|
/// 在 grammar.productions 中按 head name 查找产生式 ID（取第一条）
fn prod_id_by_head(ag : AugmentedGrammar, head_name : String) -> ProductionId {
  let head = nt_id(ag, head_name)
  let mut result : ProductionId? = None
  for prod in ag.productions {
    if result is None && prod.head == head {
      result = Some(prod.id)
    }
  }
  match result {
    Some(id) => id
    None => panic()
  }
}

// states 数量

///|
test "build_lalr_table / s→'a' 文法有 4 个状态" {
  // I0 初始, I1 GOTO(s), I2 GOTO('a'), I3 GOTO(EndOfInput)
  let (_, table) = build_table("start s\nrule s: \"a\"")
  assert_eq(table.states, 4)
}

///|
test "build_lalr_table / s→'a''b' 文法有 5 个状态" {
  // I0, I1(s), I2('a'), I3($), I4('b')
  let (_, table) = build_table("start s\nrule s: \"a\" \"b\"")
  assert_eq(table.states, 5)
}

// Shift 动作

///|
test "build_lalr_table / 存在 Shift 动作" {
  let (_, table) = build_table("start s\nrule s: \"a\"")
  assert_eq(
    any_table_action(table, fn(a) {
      match a {
        Shift(_) => true
        _ => false
      }
    }),
    true,
  )
}

///|
test "build_lalr_table / Shift 目标状态均在合法范围内" {
  let (_, table) = build_table("start s\nrule s: \"a\"")
  let mut valid = true
  for _, actions in table.action {
    for a in actions {
      match a {
        Shift(s) => if s < 0 || s >= table.states { valid = false }
        _ => ()
      }
    }
  }
  assert_eq(valid, true)
}

// Accept 动作

///|
test "build_lalr_table / 恰好存在一个 Accept 动作" {
  let (_, table) = build_table("start s\nrule s: \"a\"")
  assert_eq(count_table_actions(table, fn(a) { a == Accept }), 1)
}

///|
test "build_lalr_table / Accept 动作在 eoi_id（-1）列" {
  let (_, table) = build_table("start s\nrule s: \"a\"")
  let mut found = false
  for key, actions in table.action {
    if found {
      break
    }
    let (_, tid) = key
    if tid == eoi_id {
      for a in actions {
        if a == Accept {
          found = true
          break
        }
      }
    }
  }
  assert_eq(found, true)
}

///|
test "build_lalr_table / $accept 产生式不生成 Reduce（只用 Accept）" {
  let (ag, table) = build_table("start s\nrule s: \"a\"")
  let accept_prod = prod_id_by_head(ag, "$accept")
  assert_eq(any_table_action(table, fn(a) { a == Reduce(accept_prod) }), false)
}

// Reduce 动作

///|
test "build_lalr_table / 存在 Reduce 动作" {
  let (_, table) = build_table("start s\nrule s: \"a\"")
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
test "build_lalr_table / s→'a' 的 Reduce 动作在 eoi_id 列" {
  // FOLLOW(s) 含 eoi_id（$accept → s $），所以 Reduce 落在 eoi_id 列
  let (ag, table) = build_table("start s\nrule s: \"a\"")
  let s_prod = prod_id_by_head(ag, "s")
  let mut found = false
  for key, actions in table.action {
    if found {
      break
    }
    let (_, tid) = key
    if tid == eoi_id {
      for a in actions {
        if a == Reduce(s_prod) {
          found = true
          break
        }
      }
    }
  }
  assert_eq(found, true)
}

///|
test "build_lalr_table / s→'a'|'b' 两条产生式均有 Reduce" {
  let (ag, table) = build_table("start s\nrule s: \"a\" | \"b\"")
  let s_nt = nt_id(ag, "s")
  // 收集 s 的两条产生式 ID
  let s_prods : Array[ProductionId] = []
  for prod in ag.productions {
    if prod.head == s_nt {
      s_prods.push(prod.id)
    }
  }
  assert_eq(s_prods.length() >= 2, true)
  let p0 = s_prods[0]
  let p1 = s_prods[1]
  assert_eq(any_table_action(table, fn(a) { a == Reduce(p0) }), true)
  assert_eq(any_table_action(table, fn(a) { a == Reduce(p1) }), true)
}

///|
test "build_lalr_table / expr 多规则文法含正确 Reduce 产生式" {
  let (ag, table) = build_table(
    "start expr\nrule expr: num \"+\" num\nrule num: /d+/",
  )
  let num_prod = prod_id_by_head(ag, "num")
  assert_eq(any_table_action(table, fn(a) { a == Reduce(num_prod) }), true)
}

// goto_table

///|
test "build_lalr_table / goto_table 含 s 的非终结符跳转条目" {
  let (ag, table) = build_table("start s\nrule s: \"a\"")
  let s_nt = nt_id(ag, "s")
  let mut has_s = false
  for key, _ in table.goto_table {
    let (_, nt) = key
    if nt == s_nt {
      has_s = true
      break
    }
  }
  assert_eq(has_s, true)
}

///|
test "build_lalr_table / goto_table 中目标状态均在合法范围" {
  let (_, table) = build_table("start s\nrule s: \"a\" \"b\"")
  let mut valid = true
  for _, target in table.goto_table {
    if target < 0 || target >= table.states {
      valid = false
    }
  }
  assert_eq(valid, true)
}

///|
test "build_lalr_table / goto_table 不含终结符键（终结符走 action）" {
  // goto_table 的键类型是 (StateId, NonTerminalId)，终结符不应出现在此
  // 间接验证：action 中 Shift 数量 > 0，而 goto_table 条目是非终结符跳转
  let (_, table) = build_table("start s\nrule s: \"a\"")
  let shift_count = count_table_actions(table, fn(a) {
    match a {
      Shift(_) => true
      _ => false
    }
  })
  assert_eq(shift_count > 0, true)
  // goto_table 仅含 1 条（s → 某状态）
  let mut gt_count = 0
  for _, _ in table.goto_table {
    gt_count = gt_count + 1
  }
  assert_eq(gt_count, 1)
}

// productions

///|
test "build_lalr_table / productions 与 AugmentedGrammar 长度一致" {
  let (ag, table) = build_table("start s\nrule s: \"a\"")
  assert_eq(table.productions.length(), ag.productions.length())
}

// symbol_metadata

///|
test "build_lalr_table / symbol_metadata 覆盖全部非终结符 ID" {
  let (ag, table) = build_table("start s\nrule s: \"a\"")
  let mut ok = true
  for _, id in ag.nonterminals {
    if id >= table.symbol_metadata.length() {
      ok = false
    }
  }
  assert_eq(ok, true)
}

///|
test "build_lalr_table / $accept 的 is_named 为 false" {
  let (ag, table) = build_table("start s\nrule s: \"a\"")
  let accept_nt = nt_id(ag, "$accept")
  assert_eq(table.symbol_metadata[accept_nt].is_named, false)
}

///|
test "build_lalr_table / s 的 is_named 为 true" {
  let (ag, table) = build_table("start s\nrule s: \"a\"")
  let s_nt = nt_id(ag, "s")
  assert_eq(table.symbol_metadata[s_nt].is_named, true)
}

///|
test "build_lalr_table / symbol_metadata 中 name 字段正确" {
  let (ag, table) = build_table("start s\nrule s: \"a\"")
  let s_nt = nt_id(ag, "s")
  assert_eq(table.symbol_metadata[s_nt].name, "s")
}

// lexer_dfa 桩

///|
test "build_lalr_table / Phase 1 lexer_dfa 为桩（无 DFA 状态）" {
  let (_, table) = build_table("start s\nrule s: \"a\"")
  assert_eq(table.lexer_dfa.states.length(), 0)
}

// GLR 冲突

///|
test "build_lalr_table / 无歧义文法无冲突格" {
  let (_, table) = build_table("start s\nrule s: \"a\"")
  assert_eq(has_conflict_cell(table), false)
}

///|
test "build_lalr_table / 歧义文法产生 Shift-Reduce 冲突格" {
  // e → e "+" e | "n"：在含 [e → e • "+" e] 和 [e → e "+" e •] 的状态
  // action[(state, "+")] 同时含 Shift 和 Reduce
  let (_, table) = build_table("start e\nrule e: e \"+\" e | \"n\"")
  assert_eq(has_conflict_cell(table), true)
}
