// serialize_test.mbt — table_to_json() / serialize_table / deserialize_table 黑盒测试
//
// gen_ok() 复用自 tablegen_test.mbt（同一测试包，共享辅助函数）。
//
// 四个表格驱动测试块：
//   1. 顶层结构     — 必要键存在、states 值正确、格式合法
//   2. productions  — 增广产生式与用户规则名出现在 JSON 中
//   3. action 条目  — shift / reduce / accept 字符串存在
//   4. symbol_metadata — $accept 条目及 is_named 值

// ─── 表 1：顶层结构 ────────────────────────────────────────────────────────────
// (_label, dsl, exp_states)

///|
test "table_to_json 顶层结构" {
  let cases : Array[(String, String, Int)] = [
    ("最简 s",        "start s\nrule s: \"a\"",                             4),
    ("e/t 分层",      "start e\nrule e: e \"+\" t | t\nrule t: \"n\"",     -1),
    ("选择",          "start s\nrule s: \"a\" | \"b\"",                    -1),
    ("算术prec.left", "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"", -1),
  ]
  let required_keys = [
    "\"states\"",
    "\"productions\"",
    "\"action\"",
    "\"goto\"",
    "\"symbol_metadata\"",
  ]
  for case in cases {
    let (_l, dsl, exp_states) = case
    let (table, _) = gen_ok(dsl)
    let json = table_to_json(table)
    // 格式：以 { 开头、以 } 结尾
    assert_eq(json.has_prefix("{"), true)
    assert_eq(json.has_suffix("}"), true)
    // 必要键全部存在
    for key in required_keys {
      assert_eq(json.contains(key), true)
    }
    // states 值正确（exp_states >= 0 时断言）
    if exp_states >= 0 {
      assert_eq(json.contains("\"states\":\{exp_states}"), true)
    }
  }
}

// ─── 表 2：productions 内容 ───────────────────────────────────────────────────
// (_label, dsl, rule_names_present)  rule_names_present：JSON 中必须出现的 rule_name 列表

///|
test "table_to_json productions 内容" {
  let cases : Array[(String, String, Array[String])] = [
    (
      "最简文法",
      "start s\nrule s: \"a\"",
      ["$accept", "s"],
    ),
    (
      "e/t 分层",
      "start e\nrule e: e \"+\" t | t\nrule t: \"n\"",
      ["$accept", "e", "t"],
    ),
    (
      "算术prec.left",
      "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"",
      ["$accept", "e"],
    ),
  ]
  for case in cases {
    let (_l, dsl, names) = case
    let (table, _) = gen_ok(dsl)
    let json = table_to_json(table)
    for name in names {
      // rule_name 以 JSON 字符串形式出现
      assert_eq(json.contains("\"rule_name\":\"\{name}\""), true)
    }
  }
}

// ─── 表 3：action 条目内容 ────────────────────────────────────────────────────
// (_label, dsl, has_shift, has_reduce, has_accept)

///|
test "table_to_json action 条目内容" {
  let cases : Array[(String, String, Bool, Bool, Bool)] = [
    (
      "最简 s",
      "start s\nrule s: \"a\"",
      true, true, true,
    ),
    (
      "e/t 分层",
      "start e\nrule e: e \"+\" t | t\nrule t: \"n\"",
      true, true, true,
    ),
    (
      "算术prec.left",
      "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"",
      true, true, true,
    ),
  ]
  for case in cases {
    let (_l, dsl, want_shift, want_reduce, want_accept) = case
    let (table, _) = gen_ok(dsl)
    let json = table_to_json(table)
    if want_shift {
      assert_eq(json.contains("\"type\":\"shift\""), true)
    }
    if want_reduce {
      assert_eq(json.contains("\"type\":\"reduce\""), true)
    }
    if want_accept {
      assert_eq(json.contains("\"type\":\"accept\""), true)
    }
  }
}

// ─── 表 4：symbol_metadata 内容 ───────────────────────────────────────────────
// 验证每个文法的 JSON 中 $accept 以 is_named:false 出现，用户规则名以 is_named:true 出现

///|
test "table_to_json symbol_metadata 内容" {
  let cases : Array[(String, String, Array[String])] = [
    (
      "最简文法",
      "start s\nrule s: \"a\"",
      ["s"],
    ),
    (
      "e/t 分层",
      "start e\nrule e: e \"+\" t | t\nrule t: \"n\"",
      ["e", "t"],
    ),
  ]
  for case in cases {
    let (_l, dsl, user_rules) = case
    let (table, _) = gen_ok(dsl)
    let json = table_to_json(table)
    // $accept 必须为 is_named:false
    assert_eq(
      json.contains("\"name\":\"$accept\",\"is_named\":false"),
      true,
    )
    // 用户规则名必须在 symbol_metadata 中以 is_named:true 出现
    for name in user_rules {
      assert_eq(
        json.contains("\"name\":\"\{name}\",\"is_named\":true"),
        true,
      )
    }
  }
}

// ─── Phase 2 桩实现 ───────────────────────────────────────────────────────────

///|
test "serialize_table Phase2 桩返回空字节" {
  let (table, _) = gen_ok("start s\nrule s: \"a\"")
  let b = serialize_table(table)
  assert_eq(b.length(), 0)
}

///|
test "deserialize_table Phase2 桩返回 Err" {
  match deserialize_table(Bytes::new(0)) {
    Err(_) => ()
    Ok(_) => assert_eq(false, true)
  }
}
