// serialize_test.mbt — table_to_json() / serialize_table / deserialize_table 黑盒测试

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

// 表 2：productions 内容
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

// 表 3：action 条目内容
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

// 表 4：symbol_metadata 内容
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

// 词法 DFA 序列化

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
        assert_eq(gs.transitions.length(), os.transitions.length())
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
      assert_eq(got.valid_tokens.length(), orig.valid_tokens.length())
      // 每个 LR 状态的合法 token 数量一致
      for state_id, tids in orig.valid_tokens {
        match got.valid_tokens.get(state_id) {
          None => assert_eq(false, true) // 键缺失
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
        assert_eq(gs.transitions.length(), os.transitions.length())
      }
    }
  }
}

// 公开 API

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

///|
/// 同一 ParseTable 序列化两次结果完全相同（确定性）
test "serialize_table deterministic: same bytes on repeated calls" {
  let (table, _) = gen_ok("start e\nrule e: e \"+\" t | t\nrule t: \"n\"")
  let b1 = serialize_table(table)
  let b2 = serialize_table(table)
  assert_eq(b1.length(), b2.length())
  for i in 0..<b1.length() {
    assert_eq(b1[i], b2[i])
  }
}

///|
/// terminal_names 往返：TerminalId → 名称映射完整还原
test "serialize/deserialize preserves terminal_names" {
  let (table, _) = gen_ok("start e\nrule e: e \"+\" t | t\nrule t: \"n\"")
  // terminal_names 非空（有终结符）
  assert_eq(table.terminal_names.length() > 0, true)
  let b = serialize_table(table)
  match deserialize_table(b) {
    Err(msg) => assert_eq(msg, "")
    Ok(t2) => {
      assert_eq(t2.terminal_names.length(), table.terminal_names.length())
      // 同一 TerminalId 名称一致
      for tid, name in table.terminal_names {
        assert_eq(t2.terminal_names.get(tid), Some(name))
      }
    }
  }
}

///|
/// table_to_json 包含 terminal_names 字段
test "table_to_json includes terminal_names" {
  let (table, _) = gen_ok("start s\nrule s: \"hello\"")
  let json = table_to_json(table)
  assert_eq(json.contains("terminal_names"), true)
}

///|
/// extras 往返：DSL extras 声明的 TerminalId 列表完整还原
test "serialize/deserialize preserves extras" {
  let (table, _) = gen_ok("start s\nrule s: \"a\"\nextras [/\\s+/]")
  // extras 非空（有空白 extra）
  assert_eq(table.extras.length() > 0, true)
  let b = serialize_table(table)
  match deserialize_table(b) {
    Err(msg) => assert_eq(msg, "")
    Ok(t2) => assert_eq(t2.extras.length(), table.extras.length())
  }
}

///|
/// extras 为空时往返正常
test "serialize/deserialize extras empty" {
  let (table, _) = gen_ok("start s\nrule s: \"a\"")
  assert_eq(table.extras.length(), 0)
  let b = serialize_table(table)
  match deserialize_table(b) {
    Err(msg) => assert_eq(msg, "")
    Ok(t2) => assert_eq(t2.extras.length(), 0)
  }
}

///|
/// table_to_json 包含 extras 字段
test "table_to_json includes extras" {
  let (table, _) = gen_ok("start s\nrule s: \"a\"")
  let json = table_to_json(table)
  assert_eq(json.contains("extras"), true)
}

///|
test "table_to_json includes lexer_dfa" {
  let (table, _) = gen_ok("start s\nrule s: \"a\"")
  let json = table_to_json(table)
  assert_eq(json.contains("lexer_dfa"), true)
}

///|
test "table_from_json round-trip: states preserved" {
  let (table, _) = gen_ok("start s\nrule s: \"a\"")
  let json = table_to_json(table)
  match table_from_json(json) {
    Err(msg) => {
      println("table_from_json failed: \{msg}")
      assert_true(false)
    }
    Ok(t2) => assert_eq(t2.states, table.states)
  }
}

///|
test "table_from_json round-trip: productions count preserved" {
  let dsl = "start expr\nrule expr: /[0-9]+/"
  let (table, _) = gen_ok(dsl)
  let json = table_to_json(table)
  match table_from_json(json) {
    Err(msg) => {
      println("table_from_json failed: \{msg}")
      assert_true(false)
    }
    Ok(t2) => assert_eq(t2.productions.length(), table.productions.length())
  }
}

///|
test "table_from_json round-trip: action entries preserved" {
  let dsl = "start s\nrule s: \"a\""
  let (table, _) = gen_ok(dsl)
  let json = table_to_json(table)
  match table_from_json(json) {
    Err(msg) => {
      println("table_from_json failed: \{msg}")
      assert_true(false)
    }
    Ok(t2) => assert_eq(t2.action.length(), table.action.length())
  }
}

///|
test "table_from_json round-trip: lexer_dfa states count preserved" {
  let dsl = "start expr\nrule expr: /[0-9]+/"
  let (table, _) = gen_ok(dsl)
  let json = table_to_json(table)
  match table_from_json(json) {
    Err(msg) => {
      println("table_from_json failed: \{msg}")
      assert_true(false)
    }
    Ok(t2) =>
      assert_eq(t2.lexer_dfa.states.length(), table.lexer_dfa.states.length())
  }
}

///|
test "table_from_json: invalid JSON returns Err" {
  match table_from_json("not json at all") {
    Err(_) => () // 期望失败
    Ok(_) => assert_true(false)
  }
}

// ── 版本 3 压缩格式测试 ────────────────────────────────────────────────────────

///|
/// 版本 3 二进制头：magic 第 4 字节应为 0x03
test "serialize_table v3: magic byte is 0x03" {
  let (table, _) = gen_ok("start s\nrule s: \"a\"")
  let b = serialize_table(table)
  // bytes 0..3 = 0x4D 0x50 0x54 0x03
  assert_eq(b[3].to_int(), 0x03)
}

///|
/// 往返：states 数量不变（基础正确性）
test "serialize_table v3 roundtrip: states" {
  let cases = [
    "start s\nrule s: \"a\"", "start e\nrule e: e \"+\" t | t\nrule t: \"n\"", "start s\nrule s: \"a\" | \"b\" | \"c\"",
    "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"",
  ]
  for dsl in cases {
    let (table, _) = gen_ok(dsl)
    let b = serialize_table(table)
    match deserialize_table(b) {
      Err(msg) => assert_eq(msg, "")
      Ok(t2) => assert_eq(t2.states, table.states)
    }
  }
}

///|
/// 往返：action 表条目数量与每个 (state, terminal) 的动作数完全一致
test "serialize_table v3 roundtrip: action table entries" {
  let cases = [
    "start s\nrule s: \"a\"", "start e\nrule e: e \"+\" t | t\nrule t: \"n\"", "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"",
  ]
  for dsl in cases {
    let (table, _) = gen_ok(dsl)
    let b = serialize_table(table)
    match deserialize_table(b) {
      Err(msg) => assert_eq(msg, "")
      Ok(t2) => {
        assert_eq(t2.action.length(), table.action.length())
        // 每个条目的动作列表长度一致
        for key, acts in table.action {
          match t2.action.get(key) {
            None => assert_eq(false, true) // 条目缺失
            Some(acts2) => assert_eq(acts2.length(), acts.length())
          }
        }
      }
    }
  }
}

///|
/// 往返：goto 表条目数量与每个 (state, nt) 的目标状态完全一致
test "serialize_table v3 roundtrip: goto table entries" {
  let cases = [
    "start s\nrule s: \"a\"", "start e\nrule e: e \"+\" t | t\nrule t: \"n\"",
  ]
  for dsl in cases {
    let (table, _) = gen_ok(dsl)
    let b = serialize_table(table)
    match deserialize_table(b) {
      Err(msg) => assert_eq(msg, "")
      Ok(t2) => {
        assert_eq(t2.goto_table.length(), table.goto_table.length())
        for key, target in table.goto_table {
          assert_eq(t2.goto_table.get(key), Some(target))
        }
      }
    }
  }
}

///|
/// 往返：productions 完整还原（id / head / body 长度一致）
test "serialize_table v3 roundtrip: productions" {
  let (table, _) = gen_ok("start e\nrule e: e \"+\" t | t\nrule t: \"n\"")
  let b = serialize_table(table)
  match deserialize_table(b) {
    Err(msg) => assert_eq(msg, "")
    Ok(t2) => {
      assert_eq(t2.productions.length(), table.productions.length())
      for i in 0..<table.productions.length() {
        assert_eq(t2.productions[i].id, table.productions[i].id)
        assert_eq(t2.productions[i].head, table.productions[i].head)
        assert_eq(
          t2.productions[i].body.length(),
          table.productions[i].body.length(),
        )
      }
    }
  }
}

///|
/// 往返：GLR 冲突（悬挂 else）多动作条目经压缩后正确还原
test "serialize_table v3 roundtrip: GLR conflict multi-action entries" {
  // 悬挂 else 文法存在 S/R 冲突，action 表中有多动作条目
  let dsl = "start s\nrule s: \"i\" s \"e\" s | \"i\" s | \"x\""
  let (table, _) = gen_ok(dsl)
  let b = serialize_table(table)
  match deserialize_table(b) {
    Err(msg) => assert_eq(msg, "")
    Ok(t2) => {
      assert_eq(t2.action.length(), table.action.length())
      // 验证有多动作条目存在且数量一致
      let mut multi_orig = 0
      let mut multi_restored = 0
      for _, acts in table.action {
        if acts.length() > 1 {
          multi_orig = multi_orig + 1
        }
      }
      for _, acts in t2.action {
        if acts.length() > 1 {
          multi_restored = multi_restored + 1
        }
      }
      assert_eq(multi_restored, multi_orig)
    }
  }
}

///|
/// 往返：nonassoc 空动作列表条目（acts = []）正确还原
test "serialize_table v3 roundtrip: nonassoc empty action entries" {
  let dsl = "start e\nprecedence nonassoc ==\nrule e: e \"==\" e | /[a-z]+/"
  let (table, _) = gen_ok(dsl)
  // 统计原始空动作条目数
  let mut empty_orig = 0
  for _, acts in table.action {
    if acts.length() == 0 {
      empty_orig = empty_orig + 1
    }
  }
  let b = serialize_table(table)
  match deserialize_table(b) {
    Err(msg) => assert_eq(msg, "")
    Ok(t2) => {
      let mut empty_restored = 0
      for _, acts in t2.action {
        if acts.length() == 0 {
          empty_restored = empty_restored + 1
        }
      }
      assert_eq(empty_restored, empty_orig)
    }
  }
}

// keyword_map / word_token / external_token_ids 往返

///|
test "serialize/deserialize preserves keyword_map" {
  // 含关键字的文法：keyword_map 应含 "if"、"else" → TerminalId 映射
  let (table, _) = gen_ok("start s\nrule s: \"if\" | \"else\" | /[a-z]+/")
  assert_true(table.keyword_map.get("if") is Some(_))
  assert_true(table.keyword_map.get("else") is Some(_))
  let b = serialize_table(table)
  match deserialize_table(b) {
    Err(msg) => assert_eq(msg, "")
    Ok(t2) => {
      assert_eq(t2.keyword_map.length(), table.keyword_map.length())
      for text, tid in table.keyword_map {
        assert_eq(t2.keyword_map.get(text), Some(tid))
      }
    }
  }
}

///|
test "serialize/deserialize: word_token None preserved" {
  // 无 word 声明的文法：word_token 应为 None，往返后仍为 None
  let (table, _) = gen_ok("start s\nrule s: \"a\"")
  assert_eq(table.word_token, None)
  let b = serialize_table(table)
  match deserialize_table(b) {
    Err(msg) => assert_eq(msg, "")
    Ok(t2) => assert_eq(t2.word_token, None)
  }
}

///|
test "serialize/deserialize preserves external_token_ids" {
  // externals 声明：external_token_ids 应非空，往返后长度一致
  let (table, _) = gen_ok("start s\nexternals [_ws]\nrule s: _ws \"a\"")
  assert_true(table.external_token_ids.length() > 0)
  let b = serialize_table(table)
  match deserialize_table(b) {
    Err(msg) => assert_eq(msg, "")
    Ok(t2) =>
      assert_eq(
        t2.external_token_ids.length(),
        table.external_token_ids.length(),
      )
  }
}

// production.prec / assoc 往返精确值

///|
test "serialize/deserialize preserves production prec and assoc" {
  // prec.left(2, e "+" e)：对应产生式应有 prec=Some(2) 且 assoc=Left
  let (table, _) = gen_ok("start e\nrule e: prec.left(2, e \"+\" e) | \"n\"")
  let mut orig_prec : Int? = None
  let mut orig_has_left = false
  for prod in table.productions {
    if prod.rule_name == "e" && prod.body.length() == 3 {
      orig_prec = prod.prec
      orig_has_left = match prod.assoc {
        Some(@grammar.PrecKind::Left) => true
        _ => false
      }
    }
  }
  assert_eq(orig_prec, Some(2))
  assert_eq(orig_has_left, true)
  let b = serialize_table(table)
  match deserialize_table(b) {
    Err(msg) => assert_eq(msg, "")
    Ok(t2) => {
      let mut found = false
      for prod in t2.productions {
        if prod.rule_name == "e" && prod.body.length() == 3 {
          found = true
          assert_eq(prod.prec, orig_prec)
          assert_eq(
            match prod.assoc {
              Some(@grammar.PrecKind::Left) => true
              _ => false
            },
            true,
          )
        }
      }
      assert_eq(found, true)
    }
  }
}

///|
/// 序列化确定性：同一表多次压缩得到完全相同的字节
test "serialize_table v3 deterministic" {
  let (table, _) = gen_ok("start e\nrule e: e \"+\" t | t\nrule t: \"n\"")
  let b1 = serialize_table(table)
  let b2 = serialize_table(table)
  assert_eq(b1.length(), b2.length())
  for i in 0..<b1.length() {
    assert_eq(b1[i], b2[i])
  }
}

///|
/// 压缩后二进制不超过预期上限（测试压缩效果）
/// 对最简文法，压缩后字节数应远小于 4096 字节
test "serialize_table v3: compressed size reasonable" {
  let (table, _) = gen_ok("start s\nrule s: \"a\"")
  let b = serialize_table(table)
  assert_true(b.length() < 4096)
}
