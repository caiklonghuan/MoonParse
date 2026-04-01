// tablegen_test.mbt — generate_parse_table() 端到端集成测试（表格驱动）
//
// 辅助函数 count_table_actions / count_conflict_cells / has_severity
// 复用自同一测试包中的 lalr_test.mbt / conflicts_test.mbt。
//
// 5 个表格驱动测试块：
//   1. 基本数量属性     — states / report_count / accept_count
//   2. 冲突类型与消解   — has_ambiguous / has_warn / conflict_cells
//   3. Shift/Reduce 存在性
//   4. symbol_metadata 与 productions 结构
//   5. table_to_json 顶层字段覆盖

// ─── 辅助 ─────────────────────────────────────────────────────────────────────

///|
/// generate_parse_table() 必须返回 Ok，否则 panic
fn gen_ok(dsl : String) -> (ParseTable, Array[ConflictReport]) {
  match @grammar.parse_grammar(dsl) {
    Success(g) =>
      match generate_parse_table(g) {
        Ok(r) => r
        Err(_) => panic()
      }
    Error(_) => panic()
  }
}

// ─── 表 1：文法基本数量属性 ───────────────────────────────────────────────────
// (_label, dsl, exp_states, exp_report_count, exp_accepts)
// exp_states / exp_report_count = -1 → 跳过该断言

///|
test "基本数量属性" {
  let cases : Array[(String, String, Int, Int, Int)] = [
    ("最简 s", "start s\nrule s: \"a\"", 4, 0, 1),
    ("顺序 s", "start s\nrule s: \"a\" \"b\"", -1, 0, 1),
    ("选择 s", "start s\nrule s: \"a\" | \"b\"", -1, 0, 1),
    ("算术无prec", "start e\nrule e: e \"+\" e | \"n\"", 6, -1, 1),
    (
      "算术prec.left", "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"", -1,
      -1, 1,
    ),
    ("e/t 分层", "start e\nrule e: e \"+\" t | t\nrule t: \"n\"", -1, 0, 1),
    ("Optional 展开", "start s\nrule s: \"a\" \"b\"?", -1, 0, 1),
  ]
  for case in cases {
    let (_l, dsl, exp_states, exp_reports, exp_accepts) = case
    let (table, reports) = gen_ok(dsl)
    if exp_states >= 0 {
      assert_eq(table.states, exp_states)
    }
    if exp_reports >= 0 {
      assert_eq(reports.length(), exp_reports)
    }
    assert_eq(count_table_actions(table, fn(a) { a == Accept }), exp_accepts)
  }
}

// ─── 表 2：冲突类型与消解 ─────────────────────────────────────────────────────
// (_label, dsl, has_ambiguous, has_warn, exp_conflict_cells)
// exp_conflict_cells = -1 → 跳过

///|
test "冲突类型与消解" {
  let cases : Array[(String, String, Bool, Bool, Int)] = [
    ("无歧义文法", "start s\nrule s: \"a\"", false, false, 0),
    ("算术无prec", "start e\nrule e: e \"+\" e | \"n\"", true, false, -1),
    (
      "算术prec.left", "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"", false,
      true, 0,
    ),
    (
      "e/t 分层", "start e\nrule e: e \"+\" t | t\nrule t: \"n\"", false, false,
      0,
    ),
  ]
  for case in cases {
    let (_l, dsl, want_ambiguous, want_warn, exp_cells) = case
    let (table, reports) = gen_ok(dsl)
    assert_eq(
      has_severity(reports, fn(s) {
        match s {
          Ambiguous(_) => true
          _ => false
        }
      }),
      want_ambiguous,
    )
    assert_eq(
      has_severity(reports, fn(s) {
        match s {
          Warn(_) => true
          _ => false
        }
      }),
      want_warn,
    )
    if exp_cells >= 0 {
      assert_eq(count_conflict_cells(table), exp_cells)
    }
  }
}

// ─── 表 3：Shift / Reduce 动作存在性 ─────────────────────────────────────────
// (_label, dsl, expect_shift, expect_reduce)

///|
test "Shift Reduce 动作存在性" {
  let cases : Array[(String, String, Bool, Bool)] = [
    ("最简 s", "start s\nrule s: \"a\"", true, true),
    ("e/t 分层", "start e\nrule e: e \"+\" t | t\nrule t: \"n\"", true, true),
    (
      "算术prec.left", "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"", true,
      true,
    ),
  ]
  for case in cases {
    let (_l, dsl, want_shift, want_reduce) = case
    let (table, _) = gen_ok(dsl)
    assert_eq(
      count_table_actions(table, fn(a) {
        match a {
          Shift(_) => true
          _ => false
        }
      }) >
      0,
      want_shift,
    )
    assert_eq(
      count_table_actions(table, fn(a) {
        match a {
          Reduce(_) => true
          _ => false
        }
      }) >
      0,
      want_reduce,
    )
  }
}

// ─── 表 4：symbol_metadata 与 productions 结构 ───────────────────────────────
// (_label, dsl, min_prod_count)

///|
test "symbol_metadata 与 productions 结构" {
  let cases : Array[(String, String, Int)] = [
    ("最简文法", "start s\nrule s: \"a\"", 2),
    ("e/t 分层文法", "start e\nrule e: e \"+\" t | t\nrule t: \"n\"", 4),
    ("prec.left 文法", "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"", 2),
  ]
  for case in cases {
    let (_l, dsl, min_prods) = case
    let (table, _) = gen_ok(dsl)
    // symbol_metadata 非空
    assert_eq(table.symbol_metadata.length() > 0, true)
    // $accept 条目存在且 is_named=false
    let mut found_accept = false
    for meta in table.symbol_metadata {
      if meta.name == "$accept" {
        assert_eq(meta.is_named, false)
        found_accept = true
        break
      }
    }
    assert_eq(found_accept, true)
    // productions 中存在 rule_name="$accept" 的增广产生式
    let mut found_aug = false
    for prod in table.productions {
      if prod.rule_name == "$accept" {
        found_aug = true
        break
      }
    }
    assert_eq(found_aug, true)
    // productions 数量满足下界
    assert_eq(table.productions.length() >= min_prods, true)
  }
}

// ─── 表 5：table_to_json 顶层字段覆盖 ────────────────────────────────────────
// 对多个文法 × 全部必要 JSON 键做笛卡尔检查

///|
test "table_to_json 字段覆盖" {
  let grammars : Array[(String, String)] = [
    ("最简文法", "start s\nrule s: \"a\""),
    ("e/t 分层文法", "start e\nrule e: e \"+\" t | t\nrule t: \"n\""),
    ("算术prec.left", "start e\nrule e: prec.left(1, e \"+\" e) | \"n\""),
  ]
  let required_keys = [
    "\"states\"", "\"productions\"", "\"action\"", "\"goto\"", "\"symbol_metadata\"",
  ]
  for g in grammars {
    let (_l, dsl) = g
    let (table, _) = gen_ok(dsl)
    let json = table_to_json(table)
    assert_eq(json.has_prefix("{"), true)
    assert_eq(json.has_suffix("}"), true)
    for key in required_keys {
      assert_eq(json.contains(key), true)
    }
  }
}

///|
test "generate_parse_table: empty grammar returns Err" {
  let empty : @grammar.Grammar = {
    rules: {},
    start: None,
    precedences: [],
    extras: [],
  }
  match generate_parse_table(empty) {
    Err(msg) => assert_true(msg.length() > 0)
    Ok(_) => fail("expected Err for empty grammar")
  }
}

///|
test "generate_parse_table: missing start rule returns Err" {
  // parse_grammar 不能构造出 start 指向不存在规则的情况，直接手动构造 Grammar
  let g : @grammar.Grammar = {
    rules: {
      "s": {
        name: "s",
        pattern: @grammar.Pattern::Literal("a"),
        is_named: true,
      },
    },
    start: Some("missing"),
    precedences: [],
    extras: [],
  }
  match generate_parse_table(g) {
    Err(msg) => assert_true(msg.length() > 0)
    Ok(_) => fail("expected Err for missing start rule")
  }
}

///|
test "generate_parse_table: no start declared returns Err" {
  let g : @grammar.Grammar = {
    rules: {
      "s": {
        name: "s",
        pattern: @grammar.Pattern::Literal("a"),
        is_named: true,
      },
    },
    start: None,
    precedences: [],
    extras: [],
  }
  match generate_parse_table(g) {
    Err(msg) => assert_true(msg.length() > 0)
    Ok(_) => fail("expected Err for no start")
  }
}
