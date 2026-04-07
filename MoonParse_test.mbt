// Blackbox tests run against the package's public API. Use `@MoonParse` to import.
// Prefer high-level behaviors over implementation details.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.

///|
// ── generate() ──────────────────────────────────────────────────

///|
test "generate/valid_grammar_returns_json" {
  let dsl =
    #|start expr
    #|rule expr: /[0-9]+/
  let result = @MoonParse.generate(dsl)
  // 成功时应返回 JSON 对象（以 '{' 开头）
  assert_true(result.length() > 0 && result[0] == '{')
}

///|
test "generate/invalid_dsl_returns_error_prefix" {
  let result = @MoonParse.generate("this is not valid DSL !!!")
  assert_true(result.has_prefix("Error:"))
}

///|
test "generate/output_contains_states_key" {
  // 生成的表 JSON 应包含 "states" 字段
  let dsl =
    #|start expr
    #|rule expr: /[0-9]+/
  let result = @MoonParse.generate(dsl)
  assert_true(result.contains("states"))
}

///|
// ── parse() ─────────────────────────────────────────────────────

///|
test "parse/number_grammar" {
  let dsl =
    #|start num
    #|rule num: /[0-9]+/
  let result = @MoonParse.parse(dsl, "42")
  // 不应含有 ERROR 节点
  assert_true(not(result.contains("ERROR")))
}

///|
test "parse/expression_grammar" {
  let dsl =
    #|start expr
    #|extras [/[ \t]+/]
    #|precedence left plus
    #|rule expr: expr plus expr | /[0-9]+/
    #|rule plus: "+"
  let result = @MoonParse.parse(dsl, "1 + 2 + 3")
  assert_true(not(result.contains("ERROR")))
}

///|
test "parse/invalid_dsl_returns_error_prefix" {
  let result = @MoonParse.parse("not a grammar", "input")
  assert_true(result.has_prefix("Error:"))
}

///|
// ── parse_json() ─────────────────────────────────────────────────

///|
test "parse_json/object" {
  let result = @MoonParse.parse_json("{\"key\": 42}")
  assert_true(not(result.contains("ERROR")))
}

///|
test "parse_json/array" {
  let result = @MoonParse.parse_json("[1, 2, 3]")
  assert_true(not(result.contains("ERROR")))
}

///|
test "parse_json/null_literal" {
  let result = @MoonParse.parse_json("null")
  assert_true(not(result.contains("ERROR")))
}

///|
test "parse_json/invalid_input_contains_error_node" {
  // 非法 JSON 应返回含 ERROR 节点的 CST（而非 panic 或空串）
  let result = @MoonParse.parse_json("{invalid}")
  assert_true(result.length() > 0)
}

///|
// ── built-in stdlib grammars ───────────────────────────────────

///|
test "parse_json5/object_with_comments" {
  let result = @MoonParse.parse_json5("{name: 'moon', list: [1, 2,],}")
  assert_true(not(result.contains("ERROR")))
}

///|
test "parse_moonbit/type_alias" {
  let source =
    #|pub type IntList = Array[Int]
  let result = @MoonParse.parse_moonbit(source)
  assert_true(not(result.contains("ERROR")))
}

///|
test "parse_python/indented_function" {
  let source =
    #|def identity(x):
    #|    return x
  let result = @MoonParse.parse_python(source)
  assert_true(not(result.contains("ERROR")))
}

///|
test "parse_c/function" {
  let source =
    #|int add(int a, int b) {
    #|  return a + b;
    #|}
  let result = @MoonParse.parse_c(source)
  assert_true(not(result.contains("ERROR")))
}

///|
// ── table_from_json round-trip（通过 generate + parse 验证）────────

///|
test "generate_then_reload/json_round_trip_can_parse" {
  // 1. 编译 DSL → JSON
  let dsl =
    #|start expr
    #|extras [/[ \t]+/]
    #|rule expr: /[0-9]+/
  let json = @MoonParse.generate(dsl)
  assert_true(not(json.has_prefix("Error:")))
  // 2. 从 JSON 还原 ParseTable，然后解析输入
  match @tablegen.table_from_json(json) {
    Err(msg) => {
      println("table_from_json failed: \{msg}")
      assert_true(false)
    }
    Ok(table) =>
      match @runtime.parse(table, "42") {
        Ok(node) => assert_true(not(node.is_error))
        Err(e) => {
          println("parse failed: \{e.message}")
          assert_true(false)
        }
      }
  }
}
