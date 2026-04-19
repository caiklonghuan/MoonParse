// 序列化功能测试

///|
fn parse_ok_s(dsl : String) -> Grammar {
  match parse_grammar(dsl) {
    Success(g) => g
    Error(err) => abort("parse failed: \{err.message}")
  }
}

///|
test "serialize_roundtrip_simple" {
  let dsl = "start expr\nrule expr: /\\d+/"
  let g = parse_ok_s(dsl)
  let out = grammar_to_string(g)
  // 重新解析应成功且结构相同
  let g2 = parse_ok_s(out)
  assert_eq(g2.start, g.start)
  assert_eq(g2.rules.length(), g.rules.length())
}

///|
/// fmt(fmt(src)) == fmt(src)：grammar_to_string 的幂等性。
/// fmt --check 依赖此性质：若两次序列化结果不等，CI 会报假阳性。
test "serialize_idempotent" {
  let cases = [
    "start expr\nrule expr: /\\d+/", "start s\nrule s: \"if\" | \"else\"", "start e\nprecedence left plus\nrule e: /\\d+/\nrule plus: \"+\"",
    "rule a: b c*\nrule b: /[a-z]+/\nrule c: \",\" b", "start p\nextras [/\\s+/]\nrule p: item+\nrule item: /\\w+/",
    "start p\nexternals [indent, dedent]\nrule p: /\\w+/",
  ]
  for src in cases {
    let s1 = grammar_to_string(parse_ok_s(src))
    let s2 = grammar_to_string(parse_ok_s(s1))
    assert_eq(s2, s1)
  }
}

///|
test "serialize_contains_start" {
  let g = parse_ok_s("start foo\nrule foo: /\\d+/")
  let out = grammar_to_string(g)
  assert_true(out.contains("start foo"))
}

///|
test "serialize_contains_rule" {
  let g = parse_ok_s("rule expr: /\\d+/ | /[a-z]/")
  let out = grammar_to_string(g)
  assert_true(out.contains("rule expr:"))
}

///|
test "serialize_no_start_omitted" {
  let g = parse_ok_s("rule expr: /\\d+/")
  let out = grammar_to_string(g)
  assert_true(!out.contains("start "))
}

///|
test "serialize_precedence_decl" {
  let g = parse_ok_s(
    "start e\nprecedence left plus\nprecedence right power\nrule e: /\\d+/\nrule plus: \"+\"\nrule power: \"**\"",
  )
  let out = grammar_to_string(g)
  assert_true(out.contains("precedence left"))
  assert_true(out.contains("precedence right"))
}

// grammar_to_json 测试

///|
test "json_has_start_key" {
  let g = parse_ok_s("start expr\nrule expr: /\\d+/")
  let j = grammar_to_json(g)
  assert_true(j.contains("\"start\""))
  assert_true(j.contains("\"expr\""))
}

///|
test "json_null_start_when_absent" {
  let g = parse_ok_s("rule expr: /\\d+/")
  let j = grammar_to_json(g)
  assert_true(j.contains("\"start\": null"))
}

///|
test "json_has_rules_key" {
  let g = parse_ok_s("rule a: /\\d+/\nrule b: a")
  let j = grammar_to_json(g)
  assert_true(j.contains("\"rules\""))
  assert_true(j.contains("\"a\""))
  assert_true(j.contains("\"b\""))
}

///|
test "json_has_precedences_key" {
  let g = parse_ok_s("precedence left plus\nrule plus: \"+\"\nrule e: /\\d+/")
  let j = grammar_to_json(g)
  assert_true(j.contains("\"precedences\""))
  assert_true(j.contains("\"Left\""))
}

///|
test "json_pattern_types" {
  let g = parse_ok_s("rule e: /\\d+/ | \"x\" | .")
  let j = grammar_to_json(g)
  assert_true(j.contains("\"Regex\""))
  assert_true(j.contains("\"Literal\""))
  assert_true(j.contains("\"AnyChar\""))
}

///|
test "json_string_escape" {
  // 规则名含引号时需正确转义
  let g = parse_ok_s("rule expr: \"hello \\\"world\\\"\"")
  let j = grammar_to_json(g)
  // JSON 中应出现转义后的引号
  assert_true(j.contains("\\\\\"") || j.contains("\\\""))
}

///|
test "json_is_named_field" {
  let g = parse_ok_s("rule expr: /\\d+/")
  let j = grammar_to_json(g)
  assert_true(j.contains("\"is_named\""))
}

///|
test "json_has_extras_field" {
  let g = parse_ok_s("start p\nextras [/[ \\t\\n]+/]\nrule p: /\\w+/")
  let j = grammar_to_json(g)
  assert_true(j.contains("\"extras\""))
  assert_true(j.contains("\"Regex\""))
}

///|
test "json_extras_empty_when_absent" {
  let g = parse_ok_s("rule expr: /\\d+/")
  let j = grammar_to_json(g)
  // 无 extras 声明时应输出空数组
  assert_true(j.contains("\"extras\": []"))
}

///|
test "grammar_from_json_roundtrip_simple" {
  let dsl = "start expr\nrule expr: /\\d+/"
  let g = parse_ok_s(dsl)
  let j = grammar_to_json(g)
  let g2 = match grammar_from_json(j) {
    Success(g) => g
    Error(e) => abort("grammar_from_json failed: \{e.message}")
  }
  assert_eq(g2.start, g.start)
  assert_eq(g2.rules.length(), g.rules.length())
}

///|
test "grammar_from_json_roundtrip_extras" {
  let dsl = "start p\nextras [/[ \\t\\n]+/, /\\/\\/.*/]\nrule p: /\\w+/"
  let g = parse_ok_s(dsl)
  let j = grammar_to_json(g)
  let g2 = match grammar_from_json(j) {
    Success(g) => g
    Error(e) => abort("grammar_from_json failed: \{e.message}")
  }
  // extras 数量应保持一致
  assert_eq(g2.extras.length(), g.extras.length())
}

///|
test "grammar_from_json_roundtrip_precedences" {
  let dsl = "start e\nprecedence left plus\nprecedence right power\nrule e: /\\d+/\nrule plus: \"+\"\nrule power: \"**\""
  let g = parse_ok_s(dsl)
  let j = grammar_to_json(g)
  let g2 = match grammar_from_json(j) {
    Success(g) => g
    Error(e) => abort("grammar_from_json failed: \{e.message}")
  }
  assert_eq(g2.precedences.length(), g.precedences.length())
  assert_eq(g2.start, g.start)
}
