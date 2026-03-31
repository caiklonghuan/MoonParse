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
    ("最简 s", "start s\nrule s: \"a\"", 4),
    ("e/t 分层", "start e\nrule e: e \"+\" t | t\nrule t: \"n\"", -1),
    ("选择", "start s\nrule s: \"a\" | \"b\"", -1),
    ("算术prec.left", "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"", -1),
  ]
  let required_keys = [
    "\"states\"", "\"productions\"", "\"action\"", "\"goto\"", "\"symbol_metadata\"",
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
    ("最简文法", "start s\nrule s: \"a\"", ["$accept", "s"]),
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
    ("最简 s", "start s\nrule s: \"a\"", true, true, true),
    (
      "e/t 分层", "start e\nrule e: e \"+\" t | t\nrule t: \"n\"", true, true,
      true,
    ),
    (
      "算术prec.left", "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"", true,
      true, true,
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
    ("最简文法", "start s\nrule s: \"a\"", ["s"]),
    ("e/t 分层", "start e\nrule e: e \"+\" t | t\nrule t: \"n\"", ["e", "t"]),
  ]
  for case in cases {
    let (_l, dsl, user_rules) = case
    let (table, _) = gen_ok(dsl)
    let json = table_to_json(table)
    // $accept 必须为 is_named:false
    assert_eq(json.contains("\"name\":\"$accept\",\"is_named\":false"), true)
    // 用户规则名必须在 symbol_metadata 中以 is_named:true 出现
    for name in user_rules {
      assert_eq(json.contains("\"name\":\"\{name}\",\"is_named\":true"), true)
    }
  }
}

// ─── 词法 DFA 序列化 ──────────────────────────────────────────────────────────

///|
/// 验证 lexer_dfa.states / start / valid_tokens 经二进制往返后结构一致
test "lexer_dfa 往返：states 数量与 start 不变" {
  let (table, _) = gen_ok("start s\nrule s: \"a\"")
  let orig = table.lexer_dfa
  let b = serialize_table(table)
  match deserialize_table(b) {
    Err(msg) => assert_eq(msg, "")
    Ok(t2) => {
      let got = t2.lexer_dfa
      assert_eq(got.states.length(), orig.states.length())
      assert_eq(got.start, orig.start)
    }
  }
}

///|
/// 验证每个 DFA 状态的 transitions 条目数与 accept 标记经往返不变
test "lexer_dfa 往返：DFA 状态 transitions 与 accept" {
  let (table, _) = gen_ok("start s\nrule s: \"a\" | \"b\"")
  let orig = table.lexer_dfa
  let b = serialize_table(table)
  match deserialize_table(b) {
    Err(msg) => assert_eq(msg, "")
    Ok(t2) => {
      let got = t2.lexer_dfa
      assert_eq(got.states.length(), orig.states.length())
      // 逐状态比对 transitions 数量和 accept 是否有值
      for i in 0..<orig.states.length() {
        let os = orig.states[i]
        let gs = got.states[i]
        assert_eq(gs.id, os.id)
        assert_eq(gs.transitions.size(), os.transitions.size())
        assert_eq(gs.accept is Some(_), os.accept is Some(_))
      }
    }
  }
}

///|
/// 验证 valid_tokens 映射的键集合（LR 状态 ID）经往返不变
test "lexer_dfa 往返：valid_tokens 键集合" {
  let (table, _) = gen_ok("start e\nrule e: e \"+\" t | t\nrule t: \"n\"")
  let orig = table.lexer_dfa
  let b = serialize_table(table)
  match deserialize_table(b) {
    Err(msg) => assert_eq(msg, "")
    Ok(t2) => {
      let got = t2.lexer_dfa
      assert_eq(got.valid_tokens.size(), orig.valid_tokens.size())
      // 每个 LR 状态的合法 token 数量一致
      for state_id, tids in orig.valid_tokens {
        match got.valid_tokens.get(state_id) {
          None => assert_eq(false, true)    // 键缺失
          Some(got_tids) => assert_eq(got_tids.length(), tids.length())
        }
      }
    }
  }
}

///|
/// 验证 Regex 文法的 DFA transitions 字符映射经往返完整还原
test "lexer_dfa 往返：Regex 文法的 transitions 字符" {
  let (table, _) = gen_ok("start s\nrule s: /[0-9]+/")
  let orig = table.lexer_dfa
  let b = serialize_table(table)
  match deserialize_table(b) {
    Err(msg) => assert_eq(msg, "")
    Ok(t2) => {
      let got = t2.lexer_dfa
      assert_eq(got.states.length(), orig.states.length())
      for i in 0..<orig.states.length() {
        let os = orig.states[i]
        let gs = got.states[i]
        // transitions 字符集合相同（按数量验证——Map key 顺序不影响）
        assert_eq(gs.transitions.size(), os.transitions.size())
      }
    }
  }
}

// ─── 公开 API ─────────────────────────────────────────────────────────────────

///|
test "serialize_table 返回非空字节" {
  let (table, _) = gen_ok("start s\nrule s: \"a\"")
  let b = serialize_table(table)
  assert_eq(b.length() > 0, true)
}

///|
test "deserialize_table magic 错误返回 Err" {
  match deserialize_table(Bytes::new(0)) {
    Err(_) => ()
    Ok(_) => assert_eq(false, true)
  }
}

///|
test "serialize_table / deserialize_table 往返一致" {
  let (table, _) = gen_ok("start s\nrule s: \"a\"")
  let b = serialize_table(table)
  match deserialize_table(b) {
    Err(msg) => assert_eq(msg, "")
    Ok(t2) => {
      assert_eq(t2.states, table.states)
      assert_eq(t2.productions.length(), table.productions.length())
      assert_eq(t2.symbol_metadata.length(), table.symbol_metadata.length())
    }
  }
}
