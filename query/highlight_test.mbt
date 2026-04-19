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

///|
test "api/highlight_names_non_empty" {
  // highlight_names 是对外承诺的常量，不能为空
  assert_true(highlight_names.length() > 0)
}

///|
test "api/highlight_names_contains_common" {
  // 检查关键高亮名存在于列表中
  let has_keyword = highlight_names.iter().any(fn(n) { n == "keyword" })
  let has_string = highlight_names.iter().any(fn(n) { n == "string" })
  let has_number = highlight_names.iter().any(fn(n) { n == "number" })
  assert_true(has_keyword)
  assert_true(has_string)
  assert_true(has_number)
}

///|
test "api/is_local_ref_returns_false_for_unknown_key" {
  // 对不在 local_refs 中的字节偏移，is_local_ref 应返回 false
  let dsl =
    #|start s
    #|extras [/[ \t\n\r]+/]
    #|rule s: ident*
    #|rule ident: /[a-z]+/
  let input = "foo"
  let (root, table) = parse_ok(dsl, input)
  let lq = compile_ok("(ident) @local.reference")
  let res = resolve_locals(root, input, table, lq)
  // 无 scope → local_refs 为空，任何偏移返回 false
  assert_true(!res.is_local_ref(0))
  assert_true(!res.is_local_ref(999))
}

///|
test "locals/ref_without_def_not_marked_local" {
  let dsl =
    #|start prog
    #|extras [/[ \t\n\r]+/]
    #|rule prog: ident*
    #|rule ident: /[a-z]+/
  // 有 scope，但没有 definition → ref 不应被标记为 local
  let input = "foo"
  let (root, table) = parse_ok(dsl, input)
  let lq_s =
    #|(prog) @local.scope
    #|(ident) @local.reference
  let lq = compile_ok(lq_s)
  let res = resolve_locals(root, input, table, lq)
  assert_true(!res.is_local_ref(0))
}

///|
test "locals/ref_matching_def_is_local" {
  let dsl =
    #|start prog
    #|extras [/[ \t\n\r]+/]
    #|rule prog: ident*
    #|rule ident: /[a-z]+/
  // scope 内有 "foo" 的定义，"foo" 的引用应被标记为 local
  let input = "foo foo"
  let (root, table) = parse_ok(dsl, input)
  let lq_s =
    #|(prog) @local.scope
    #|(ident) @local.definition
    #|(ident) @local.reference
  let lq = compile_ok(lq_s)
  let res = resolve_locals(root, input, table, lq)
  // 两个 "foo" 节点都应被标记（start_byte = 0 和 4）
  assert_true(res.is_local_ref(0) || res.is_local_ref(4))
}

///|
test "locals/ref_not_matching_def_not_local" {
  // 用不同节点类型区分 def 和 ref，避免 def 和 ref 文本重叠
  // def_id 只作定义，ref_id 只作引用
  let dsl =
    #|start prog
    #|rule prog: def_id ref_id
    #|rule def_id: /[a-z]+/
    #|rule ref_id: /[a-z]+/
  // 输入：def="foo"，ref="bar"；"bar" 无对应定义 → 不是 local
  let input = "foo bar"
  let (root, table) = parse_ok(dsl, input)
  let lq_s =
    #|(prog) @local.scope
    #|(def_id) @local.definition
    #|(ref_id) @local.reference
  let lq = compile_ok(lq_s)
  let res = resolve_locals(root, input, table, lq)
  // ref_id "bar" 的 start_byte=4，scope 内 def 是 "foo"，不匹配 → 不是 local
  assert_true(!res.is_local_ref(4))
}

///|
// ─────────────────────────────────────────────────
// apply_highlights_with_locals 补充测试
// ─────────────────────────────────────────────────

///|
test "highlight_with_locals/non_local_ref_unchanged" {
  let dsl =
    #|start prog
    #|extras [/[ \t\n\r]+/]
    #|rule prog: ident*
    #|rule ident: /[a-z]+/
  // "foo" 无对应 definition → 不应加 .local 后缀
  let input = "foo"
  let (root, table) = parse_ok(dsl, input)
  let hq = compile_ok("(ident) @variable")
  let lq_s =
    #|(prog) @local.scope
    #|(ident) @local.reference
  let lq = compile_ok(lq_s)
  let ranges = apply_highlights_with_locals(root, input, table, hq, lq)
  assert_true(ranges.length() > 0)
  // 无 definition，所有高亮名应保持 "variable" 而非 "variable.local"
  for r in ranges {
    assert_true(r.highlight_name != "variable.local")
  }
}
