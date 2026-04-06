///|
// wasm_wbtest.mbt — whitebox tests for wasm WASM API

///|
test "parser_diagnostics_json/no_conflicts" {
  // 无冲突文法 → diagnostics 为空列表
  let dsl = "start s\nrule s: \"a\""
  let pid = parser_create_from_dsl(dsl)
  assert_true(pid >= 1)
  let diag = parser_diagnostics_json(pid)
  assert_eq(diag, "[]")
  parser_free(pid)
}

///|
test "parser_diagnostics_json/ambiguous_grammar" {
  // 有 reduce/reduce 冲突的文法 → diagnostics 非空
  let dsl =
    #|start e
    #|rule e: e "+" e | "n"
  let pid = parser_create_from_dsl(dsl)
  assert_true(pid >= 1)
  let diag = parser_diagnostics_json(pid)
  // 应包含 JSON 数组（非空）
  assert_true(diag != "[]")
  assert_true(diag.has_prefix("[{"))
  // 每条记录应有 severity、state、terminal 字段
  assert_true(diag.contains("\"severity\""))
  assert_true(diag.contains("\"state\""))
  assert_true(diag.contains("\"terminal\""))
  parser_free(pid)
}

///|
test "parser_diagnostics_json/invalid_id" {
  // 无效 parser_id → 返回 "[]"
  let diag = parser_diagnostics_json(99999)
  assert_eq(diag, "[]")
}

///|
test "parser_diagnostics_json/warn_severity" {
  // prec.left 产生 warn 而非 ambiguous
  let dsl =
    #|start e
    #|rule e: prec.left(1, e "+" e) | "n"
  let pid = parser_create_from_dsl(dsl)
  assert_true(pid >= 1)
  let diag = parser_diagnostics_json(pid)
  // prec.left 解消了冲突 → 可能为空或为 warn
  // 断言：如果非空，severity 应包含 "warn"
  if diag != "[]" {
    assert_true(diag.contains("warn"))
  }
  parser_free(pid)
}
