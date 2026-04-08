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

///|
// ── moonparse_version ────────────────────────────────────────────

///|
test "moonparse_version/returns_semver_string" {
  let v = moonparse_version()
  // 应为非空语义版本字符串，如 "0.1.0"
  assert_true(v.length() > 0)
  assert_true(v.contains("."))
}

///|
// ── parser_get_dsl ───────────────────────────────────────────────

///|
test "parser_get_dsl/returns_original_dsl" {
  let dsl = "start s\nrule s: \"a\""
  let pid = parser_create_from_dsl(dsl)
  assert_true(pid >= 1)
  assert_eq(parser_get_dsl(pid), dsl)
  parser_free(pid)
}

///|
test "parser_get_dsl/invalid_id_returns_empty" {
  assert_eq(parser_get_dsl(99999), "")
}

///|
// ── parse_full + tree lifecycle ──────────────────────────────────

///|
test "parse_full/valid_grammar_and_input" {
  let dsl = "start s\nrule s: \"a\""
  let pid = parser_create_from_dsl(dsl)
  assert_true(pid >= 1)
  let tid = parse_full(pid, "a")
  assert_true(tid >= 1)
  tree_free(tid)
  parser_free(pid)
}

///|
test "parse_full/invalid_parser_id_returns_minus_one" {
  let tid = parse_full(99999, "a")
  assert_eq(tid, -1)
}

///|
test "parse_full/parse_failure_returns_minus_one" {
  // 文法期望 "a"，输入 "" → 解析失败
  let dsl = "start s\nrule s: \"a\""
  let pid = parser_create_from_dsl(dsl)
  assert_true(pid >= 1)
  let tid = parse_full(pid, "")
  assert_eq(tid, -1)
  parser_free(pid)
}

///|
// ── tree_to_json ─────────────────────────────────────────────────

///|
test "tree_to_json/contains_required_fields" {
  let dsl = "start s\nrule s: \"a\""
  let pid = parser_create_from_dsl(dsl)
  let tid = parse_full(pid, "a")
  assert_true(tid >= 1)
  let json = tree_to_json(tid)
  assert_true(json.length() > 0)
  assert_true(json.contains("\"type\""))
  assert_true(json.contains("\"start_byte\""))
  assert_true(json.contains("\"end_byte\""))
  tree_free(tid)
  parser_free(pid)
}

///|
test "tree_to_json/invalid_tree_id_returns_empty" {
  assert_eq(tree_to_json(99999), "")
}

///|
// ── tree_root_sexp ───────────────────────────────────────────────

///|
test "tree_root_sexp/named_root_wrapped_in_parens" {
  let dsl = "start s\nrule s: \"a\""
  let pid = parser_create_from_dsl(dsl)
  let tid = parse_full(pid, "a")
  assert_true(tid >= 1)
  let sexp = tree_root_sexp(tid)
  // 根节点 s 是命名节点，sexp 应以 "(s" 开头并以 ")" 结尾
  assert_true(sexp.has_prefix("(s"))
  assert_true(sexp.has_suffix(")"))
  tree_free(tid)
  parser_free(pid)
}

///|
test "tree_root_sexp/invalid_tree_id_returns_empty" {
  assert_eq(tree_root_sexp(99999), "")
}

///|
// ── tree_error_summary ───────────────────────────────────────────

///|
test "tree_error_summary/clean_parse_returns_ok" {
  let dsl = "start s\nrule s: \"a\""
  let pid = parser_create_from_dsl(dsl)
  let tid = parse_full(pid, "a")
  assert_true(tid >= 1)
  assert_eq(tree_error_summary(tid), "ok")
  tree_free(tid)
  parser_free(pid)
}

///|
test "tree_error_summary/error_tree_starts_with_error_prefix" {
  // 使用缺失 token 的场景：文法 s → "a" "b"，输入 "a"
  // 缺少 "b" → 错误恢复插入 MISSING 节点 → tree_error_summary 返回 "error:..."
  let dsl = "start s\nrule s: \"a\" \"b\""
  let pid = parser_create_from_dsl(dsl)
  assert_true(pid >= 1)
  // 输入 "a"：缺少 "b"，但不含 EOF，所以解析失败
  // 改为使用更可靠的触发：用不兼容的输入强制产生 MISSING 节点
  // 文法 s → "a" ";" "b"，输入 "ab"（缺 ";"）→ insert_missing 插入 ";" → MISSING 节点
  parser_free(pid)
  let dsl2 = "start s\nrule s: \"a\" \";\" \"b\""
  let pid2 = parser_create_from_dsl(dsl2)
  assert_true(pid2 >= 1)
  let tid = parse_full(pid2, "ab")
  assert_true(tid >= 1)
  let summary = tree_error_summary(tid)
  // 存在 MISSING ";" 节点 → summary = "error:行:列"
  assert_true(summary.has_prefix("error:"))
  tree_free(tid)
  parser_free(pid2)
}

///|
test "tree_error_summary/invalid_tree_id_returns_invalid" {
  assert_eq(tree_error_summary(99999), "invalid")
}

///|
// ── parse_incremental (低层 12 参数 API) ────────────────────────

///|
test "parse_incremental/same_length_substitution" {
  // 文法 s → /[a-z]/ /[a-z]/
  // 旧输入 "ab"，将 'b'→'d'（同长度编辑）→ 新输入 "ad"
  let dsl = "start s\nrule s: /[a-z]/ /[a-z]/"
  let pid = parser_create_from_dsl(dsl)
  assert_true(pid >= 1)
  let old_tid = parse_full(pid, "ab")
  assert_true(old_tid >= 1)
  let new_tid = parse_incremental(
    pid, old_tid, "ad", 1, 2, 2, // start_byte=1, old_end=2, new_end=2
     0, 1, 0, 2, 0, 2, // start_row/col, old_end_row/col, new_end_row/col
  )
  assert_true(new_tid >= 1)
  // 新树覆盖完整输入 [0, 2)
  let sexp = tree_root_sexp(new_tid)
  assert_true(sexp.length() > 0)
  tree_free(old_tid)
  tree_free(new_tid)
  parser_free(pid)
}

///|
test "parse_incremental/invalid_old_tree_falls_back_to_full_parse" {
  // old_tree_id 无效（99999）→ 降级为全量解析
  let dsl = "start s\nrule s: \"a\""
  let pid = parser_create_from_dsl(dsl)
  assert_true(pid >= 1)
  let new_tid = parse_incremental(pid, 99999, "a", 0, 0, 0, 0, 0, 0, 0, 0, 0)
  // 降级全量解析应成功
  assert_true(new_tid >= 1)
  tree_free(new_tid)
  parser_free(pid)
}

///|
// ── wasm_parse ───────────────────────────────────────────────────

///|
test "wasm_parse/returns_json_with_type_field" {
  let dsl = "start s\nrule s: \"a\""
  let pid = wasm_create_parser(dsl)
  assert_true(pid >= 1)
  let json = wasm_parse(pid, "a")
  assert_true(json.length() > 0)
  assert_true(json.contains("\"type\""))
  wasm_free_parser(pid)
}

///|
test "wasm_parse/parse_failure_returns_empty" {
  let dsl = "start s\nrule s: \"a\""
  let pid = wasm_create_parser(dsl)
  assert_true(pid >= 1)
  // 空输入 → 解析失败 → ""
  let json = wasm_parse(pid, "")
  assert_eq(json, "")
  wasm_free_parser(pid)
}

///|
// ── wasm_parse_incremental ───────────────────────────────────────

///|
test "wasm_parse_incremental/valid_changes_json_returns_json" {
  let dsl = "start s\nrule s: /[a-z]/ /[a-z]/"
  let pid = wasm_create_parser(dsl)
  assert_true(pid >= 1)
  // 先全量解析 "ab"，得到 old_tree_id
  let old_tid = parse_full(pid, "ab")
  assert_true(old_tid >= 1)
  // 编辑：'b'→'d'（同长度）
  let changes =
    #|{"start_byte":1,"old_end_byte":2,"new_end_byte":2,"start_row":0,"start_col":1,"old_end_row":0,"old_end_col":2,"new_end_row":0,"new_end_col":2}
  let json = wasm_parse_incremental(pid, "ad", old_tid, changes)
  assert_true(json.length() > 0)
  assert_true(json.contains("\"type\""))
  // wasm_parse_incremental 内部会 tree_free 新树，old_tid 需手动释放
  tree_free(old_tid)
  wasm_free_parser(pid)
}

///|
// ── parser_table_to_json + parser_create_from_json round-trip ───

///|
test "parser_table_to_json+parser_create_from_json/round_trip_same_parse" {
  let dsl = "start s\nrule s: \"a\""
  let pid1 = parser_create_from_dsl(dsl)
  assert_true(pid1 >= 1)
  // 序列化
  let table_json = parser_table_to_json(pid1)
  assert_true(table_json.length() > 0)
  // 反序列化
  let pid2 = parser_create_from_json(table_json)
  assert_true(pid2 >= 1)
  // 用两个解析器解析相同输入，验证 sexp 一致
  let tid1 = parse_full(pid1, "a")
  let tid2 = parse_full(pid2, "a")
  assert_true(tid1 >= 1)
  assert_true(tid2 >= 1)
  assert_eq(tree_root_sexp(tid1), tree_root_sexp(tid2))
  tree_free(tid1)
  tree_free(tid2)
  parser_free(pid1)
  parser_free(pid2)
}

///|
test "parser_table_to_json/invalid_id_returns_empty" {
  assert_eq(parser_table_to_json(99999), "")
}

///|
test "parser_create_from_json/invalid_json_returns_minus_one" {
  let pid = parser_create_from_json("not-valid-json{{{")
  assert_eq(pid, -1)
}

///|
// ── cursor API ───────────────────────────────────────────────────

///|
test "cursor/create_and_free" {
  let dsl = "start s\nrule s: \"a\""
  let pid = parser_create_from_dsl(dsl)
  let tid = parse_full(pid, "a")
  assert_true(tid >= 1)
  let cid = cursor_new(tid)
  assert_true(cid >= 1)
  cursor_free(cid)
  tree_free(tid)
  parser_free(pid)
}

///|
test "cursor/invalid_tree_returns_minus_one" {
  let cid = cursor_new(99999)
  assert_eq(cid, -1)
}

///|
test "cursor/root_node_type_matches_start_rule" {
  let dsl = "start s\nrule s: \"a\""
  let pid = parser_create_from_dsl(dsl)
  let tid = parse_full(pid, "a")
  let cid = cursor_new(tid)
  assert_true(cid >= 1)
  // 根节点是 s，cursor_node_type 应返回 "s"
  assert_eq(cursor_node_type(cid), "s")
  assert_eq(cursor_node_is_named(cid), 1)
  assert_eq(cursor_node_is_error(cid), 0)
  assert_eq(cursor_node_start_byte(cid), 0)
  assert_eq(cursor_node_end_byte(cid), 1)
  cursor_free(cid)
  tree_free(tid)
  parser_free(pid)
}

///|
test "cursor/goto_first_child_and_back" {
  // 文法 s → "a" "b"，输入 "ab"
  // 根节点 s 有两个匿名子节点
  let dsl = "start s\nrule s: \"a\" \"b\""
  let pid = parser_create_from_dsl(dsl)
  let tid = parse_full(pid, "ab")
  assert_true(tid >= 1)
  let cid = cursor_new(tid)
  assert_true(cid >= 1)
  // 根节点有子节点
  assert_true(cursor_node_child_count(cid) > 0)
  // 进入第一个子节点
  assert_eq(cursor_goto_first_child(cid), 1)
  // 第一个子节点覆盖 [0,1)
  assert_eq(cursor_node_start_byte(cid), 0)
  assert_eq(cursor_node_end_byte(cid), 1)
  assert_eq(cursor_node_text(cid), "a")
  // 移动到下一个兄弟节点
  assert_eq(cursor_goto_next_sibling(cid), 1)
  assert_eq(cursor_node_start_byte(cid), 1)
  assert_eq(cursor_node_end_byte(cid), 2)
  assert_eq(cursor_node_text(cid), "b")
  // 没有更多兄弟节点
  assert_eq(cursor_goto_next_sibling(cid), 0)
  cursor_free(cid)
  tree_free(tid)
  parser_free(pid)
}

///|
test "cursor/leaf_node_has_no_children" {
  let dsl = "start s\nrule s: \"a\""
  let pid = parser_create_from_dsl(dsl)
  let tid = parse_full(pid, "a")
  let cid = cursor_new(tid)
  // 进入叶子节点
  if cursor_goto_first_child(cid) == 1 {
    // 叶子节点没有子节点
    assert_eq(cursor_goto_first_child(cid), 0)
  }
  cursor_free(cid)
  tree_free(tid)
  parser_free(pid)
}

///|
test "cursor/node_position_fields" {
  let dsl = "start s\nrule s: \"a\""
  let pid = parser_create_from_dsl(dsl)
  let tid = parse_full(pid, "a")
  let cid = cursor_new(tid)
  // 根节点在第 0 行 0 列
  assert_eq(cursor_node_start_row(cid), 0)
  assert_eq(cursor_node_start_col(cid), 0)
  assert_eq(cursor_node_end_row(cid), 0)
  assert_eq(cursor_node_end_col(cid), 1)
  cursor_free(cid)
  tree_free(tid)
  parser_free(pid)
}

///|
// ── wasm_query ───────────────────────────────────────────────────

///|
test "wasm_query/capture_returns_json_array" {
  // 文法 s → "a"，查询 (s) @root → 应捕获根节点
  let dsl = "start s\nrule s: \"a\""
  let pid = parser_create_from_dsl(dsl)
  let tid = parse_full(pid, "a")
  assert_true(tid >= 1)
  let result = wasm_query(tid, "(s) @root")
  // 非空 JSON 数组
  assert_true(result.length() > 0)
  assert_true(result.has_prefix("["))
  assert_true(result.contains("\"capture\""))
  tree_free(tid)
  parser_free(pid)
}

///|
test "wasm_query/invalid_pattern_returns_empty_array" {
  let dsl = "start s\nrule s: \"a\""
  let pid = parser_create_from_dsl(dsl)
  let tid = parse_full(pid, "a")
  assert_true(tid >= 1)
  // 格式错误的查询 → "[]"
  let result = wasm_query(tid, "((( invalid")
  assert_eq(result, "[]")
  tree_free(tid)
  parser_free(pid)
}
