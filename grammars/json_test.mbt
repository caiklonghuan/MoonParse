///|
// JSON 语法黑盒测试
//
// 验证 json_table 能正确解析各种合法 JSON 输入，
// 以及对非法输入生成带 ERROR 节点的 CST（而非 panic）。

///|
/// 辅助：解析 JSON 并返回根节点，断言无顶层错误
fn parse_ok(source : String) -> @runtime.CstNode {
  match @grammars.parse_json(source) {
    Ok(node) => node
    Err(e) => {
      println("parse_json failed: \{e.message}")
      panic()
    }
  }
}

///|
/// 辅助：解析 JSON，返回 CST 字符串，供 assert_eq 比较
fn parse_str(source : String) -> String {
  match @grammars.parse_json(source) {
    Ok(node) => node.to_string()
    Err(e) => "Err: \{e.message}"
  }
}

///|
test "json_null" {
  let node = parse_ok("null")
  assert_true(not(node.is_error))
}

///|
test "json_true" {
  let node = parse_ok("true")
  assert_true(not(node.is_error))
}

///|
test "json_false" {
  let node = parse_ok("false")
  assert_true(not(node.is_error))
}

///|
test "json_number_integer" {
  let node = parse_ok("42")
  assert_true(not(node.is_error))
}

///|
test "json_number_negative" {
  let node = parse_ok("-3.14")
  assert_true(not(node.is_error))
}

///|
test "json_string" {
  let node = parse_ok("\"hello world\"")
  assert_true(not(node.is_error))
}

///|
test "json_empty_object" {
  let node = parse_ok("{}")
  assert_true(not(node.is_error))
}

///|
test "json_empty_array" {
  let node = parse_ok("[]")
  assert_true(not(node.is_error))
}

///|
test "json_simple_object" {
  let node = parse_ok("{\"key\": 123}")
  assert_true(not(node.is_error))
}

///|
test "json_nested_object" {
  let node = parse_ok("{\"a\": {\"b\": true}}")
  assert_true(not(node.is_error))
}

///|
test "json_array_of_numbers" {
  let node = parse_ok("[1, 2, 3]")
  assert_true(not(node.is_error))
}

///|
test "json_array_mixed" {
  let node = parse_ok("[1, \"two\", true, null]")
  assert_true(not(node.is_error))
}

///|
test "json_complex" {
  let node = parse_ok(
    "{\"name\": \"Alice\", \"age\": 30, \"scores\": [10, 20, 30], \"active\": true}",
  )
  assert_true(not(node.is_error))
}

///|
test "json_whitespace_ignored" {
  // 空白应被 extras 规则忽略
  let node = parse_ok("  {  \"k\"  :  1  }  ")
  assert_true(not(node.is_error))
}

///|
test "json_cst_has_children" {
  // 对象节点应该有子节点
  let node = parse_ok("{\"x\": 1}")
  // 根节点 json → value → object，至少有一层 children
  assert_true(not(node.children.is_empty()))
}
