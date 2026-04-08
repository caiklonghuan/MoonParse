///|
// highlight_test.mbt
// Highlight Query 引擎的黑盒测试

///|
fn compile_ok(pattern : String) -> CompiledQuery {
  match compile(pattern) {
    Ok(q) => q
    Err(e) => {
      println("compile failed: \{e}")
      panic()
    }
  }
}

///|
test "highlight/basic_returns_array" {
  let json_dsl =
    #|start json
    #|extras [/[ \t\n\r]+/]
    #|rule json: value
    #|rule value: jstring | number | "true" | "false" | "null"
    #|rule jstring: /"[^"]*"/
    #|rule number: /-?[0-9]+/
  let (root, table) = parse_ok(json_dsl, "42")
  let hq_s =
    #|(number) @number
  let hq = compile_ok(hq_s)
  let ranges = apply_highlights(root, "42", table, hq)
  assert_true(ranges.length() > 0)
  assert_eq(ranges[0].highlight_name, "number")
}

///|
test "highlight/sorted_by_start_byte" {
  let json_dsl =
    #|start json
    #|extras [/[ \t\n\r]+/]
    #|rule json: value
    #|rule value: jstring | number | "true" | "false" | "null"
    #|rule jstring: /"[^"]*"/
    #|rule number: /-?[0-9]+/
  let (root, table) = parse_ok(json_dsl, "42")
  // 使用两个捕获模式，测试输出是否按 start_byte 排序
  let hq_s =
    #|(json) @module
    #|(number) @number
  let hq = compile_ok(hq_s)
  let ranges = apply_highlights(root, "42", table, hq)
  let mut prev_start = -1
  for r in ranges {
    assert_true(r.start_byte >= prev_start)
    prev_start = r.start_byte
  }
}

///|
test "highlight/string_capture" {
  let json_dsl =
    #|start json
    #|extras [/[ \t\n\r]+/]
    #|rule json: value
    #|rule value: jstring | number | "true" | "false" | "null"
    #|rule jstring: /"[ -!#-~]*"/
    #|rule number: /-?[0-9]+/
  let input = "\"hello\""
  let (root, table) = parse_ok(json_dsl, input)
  let hq_s =
    #|(jstring) @string
  let hq = compile_ok(hq_s)
  let ranges = apply_highlights(root, input, table, hq)
  assert_true(ranges.length() > 0)
  assert_eq(ranges[0].highlight_name, "string")
  assert_eq(ranges[0].start_byte, 0)
  assert_eq(ranges[0].end_byte, input.length())
}

///|
test "highlight/multiple_captures_same_tree" {
  let json_dsl =
    #|start json
    #|extras [/[ \t\n\r]+/]
    #|rule json: value
    #|rule value: jstring | number | "true" | "false" | "null"
    #|rule jstring: /"[ -!#-~]*"/
    #|rule number: /-?[0-9]+/
  let input = "\"key\""
  let (root, table) = parse_ok(json_dsl, input)
  let hq_s =
    #|(jstring) @string
    #|(value) @variable
  let hq = compile_ok(hq_s)
  let ranges = apply_highlights(root, input, table, hq)
  // 两个模式都命中同一区间，应都被收录
  assert_true(ranges.length() >= 2)
}

///|
test "highlight/local_captures_filtered" {
  // @local.* 捕获名不应出现在 apply_highlights 结果中
  let json_dsl =
    #|start json
    #|extras [/[ \t\n\r]+/]
    #|rule json: value
    #|rule value: jstring | number | "true" | "false" | "null"
    #|rule jstring: /"[^"]*"/
    #|rule number: /-?[0-9]+/
  let input = "42"
  let (root, table) = parse_ok(json_dsl, input)
  let hq_s =
    #|(number) @local.definition
    #|(value) @number
  let hq = compile_ok(hq_s)
  let ranges = apply_highlights(root, input, table, hq)
  for r in ranges {
    assert_true(r.highlight_name != "local.definition")
  }
}

///|
// ── 基础测试：resolve_locals ─────────────────────────────────────

///|
test "locals/empty_result_when_no_scopes" {
  // 无 @local.scope，所有 ref 均视为全局
  let dsl =
    #|start prog
    #|extras [/[ \t\n\r]+/]
    #|rule prog: ident*
    #|rule ident: /[a-z]+/
  let input = "foo bar"
  let (root, table) = parse_ok(dsl, input)
  let lq_s =
    #|(ident) @local.reference
  let lq = compile_ok(lq_s)
  let res = resolve_locals(root, input, table, lq)
  // 无 scope → 无 local_ref
  assert_true(res.local_refs.length() == 0)
}

///|
test "locals/ref_in_scope_with_def" {
  // ident 作为 scope，第一个 ident 是 def，第二个是 ref
  let dsl =
    #|start prog
    #|extras [/[ \t\n\r]+/]
    #|rule prog: ident*
    #|rule ident: /[a-z]+/
  // 用 prog 整体作 scope，第一个 ident 作 def，所有 ident 作 ref
  let input = "foo foo"
  let (root, table) = parse_ok(dsl, input)
  let lq_s =
    #|(prog) @local.scope
    #|(ident) @local.definition
    #|(ident) @local.reference
  let lq = compile_ok(lq_s)
  let res = resolve_locals(root, input, table, lq)
  // "foo" 在 scope 内有定义，所以 ref 处（字节偏移 0 和 4）应被标记为 local
  // （两次都解析为 local，因为 defs 和 refs 都匹配 ident）
  assert_true(res.local_refs.length() > 0)
}

///|
// ── 测试：apply_highlights_with_locals ──────────────────────────

///|
test "highlight_with_locals/local_ref_gets_local_suffix" {
  let dsl =
    #|start prog
    #|extras [/[ \t\n\r]+/]
    #|rule prog: ident*
    #|rule ident: /[a-z]+/
  let input = "foo foo"
  let (root, table) = parse_ok(dsl, input)
  let hq_s =
    #|(ident) @variable
  let hq = compile_ok(hq_s)
  let lq_s =
    #|(prog) @local.scope
    #|(ident) @local.definition
    #|(ident) @local.reference
  let lq = compile_ok(lq_s)
  let ranges = apply_highlights_with_locals(root, input, table, hq, lq)
  // 至少有一个 variable.local
  let has_local = ranges
    .iter()
    .any(fn(r) { r.highlight_name == "variable.local" })
  assert_true(has_local)
}

///|
// ── 测试：HighlightRange 字段正确性 ─────────────────────────────

///|
test "highlight/range_fields_correct" {
  let dsl =
    #|start prog
    #|extras [/[ \t\n\r]+/]
    #|rule prog: num
    #|rule num: /[0-9]+/
  let input = "123"
  let (root, table) = parse_ok(dsl, input)
  let hq_s =
    #|(num) @number
  let hq = compile_ok(hq_s)
  let ranges = apply_highlights(root, input, table, hq)
  assert_true(ranges.length() > 0)
  let r = ranges[0]
  assert_eq(r.start_byte, 0)
  assert_eq(r.end_byte, 3)
  assert_eq(r.start_point.row, 0)
  assert_eq(r.start_point.column, 0)
  assert_eq(r.highlight_name, "number")
}

///|
test "highlight/multiline_points" {
  // 验证 start_point.row 在多行输入中正确反映行号
  let dsl =
    #|start prog
    #|extras [/[ \t\n\r]+/]
    #|rule prog: num
    #|rule num: /[0-9]+/
  // 在第二行放一个数字
  let input = "\n42"
  let (root, table) = parse_ok(dsl, input)
  let hq_s =
    #|(num) @number
  let hq = compile_ok(hq_s)
  let ranges = apply_highlights(root, input, table, hq)
  assert_true(ranges.length() >= 1)
  let first = ranges[0]
  assert_eq(first.start_point.row, 1)
  assert_eq(first.start_byte, 1)
}
