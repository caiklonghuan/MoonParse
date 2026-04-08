///|
// Highlight Query WASM 导出
//
// 提供以下两个 WASM 导出函数供 JS 侧调用：
//   highlight_exec(query_id, tree_id) -> String
//   highlight_exec_with_locals(hl_qid, loc_qid, tree_id) -> String
//
// 返回值格式：JSON 数组，每个元素为一个 HighlightRange：
//   [{"highlight":"keyword","start_byte":0,"end_byte":2,
//     "start_row":0,"start_col":0,"end_row":0,"end_col":2}, ...]
// 失败（无效 ID）时返回空数组 "[]"。

///|
// 序列化辅助

///|
/// 将单个 HighlightRange 序列化为 JSON 对象字符串
fn highlight_range_to_json(
  r : @query.HighlightRange,
  buf : StringBuilder,
) -> Unit {
  buf.write_char('{')
  write_kvs(buf, "highlight", r.highlight_name)
  buf.write_char(',')
  write_kvi(buf, "start_byte", r.start_byte)
  buf.write_char(',')
  write_kvi(buf, "end_byte", r.end_byte)
  buf.write_char(',')
  write_kvi(buf, "start_row", r.start_point.row)
  buf.write_char(',')
  write_kvi(buf, "start_col", r.start_point.column)
  buf.write_char(',')
  write_kvi(buf, "end_row", r.end_point.row)
  buf.write_char(',')
  write_kvi(buf, "end_col", r.end_point.column)
  buf.write_char('}')
}

///|
/// 将 Array[HighlightRange] 序列化为 JSON 数组字符串
fn highlight_ranges_to_json(ranges : Array[@query.HighlightRange]) -> String {
  let buf = StringBuilder::new()
  buf.write_char('[')
  let mut first = true
  for r in ranges {
    if not(first) {
      buf.write_char(',')
    }
    highlight_range_to_json(r, buf)
    first = false
  }
  buf.write_char(']')
  buf.to_string()
}

///|
// 公开 WASM 导出

///|
/// 在已解析的语法树上执行高亮查询，返回 JSON 数组字符串。
///
/// # 参数
/// - query_id : 由 `query_compile` 返回的查询句柄
/// - tree_id  : 由 `parse_full` / `parse_incremental` 返回的树句柄
///
/// # 返回值
/// JSON 数组字符串，每个元素含 highlight/start_byte/end_byte/行列信息。
/// 任一 ID 无效时返回 "[]"。
///
/// # JS 调用示例
/// ```js
/// const qid = query_compile("(string) @string\n(number) @number");
/// const json = highlight_exec(qid, tid);
/// const highlights = JSON.parse(json);
/// // [{highlight: "number", start_byte: 0, end_byte: 2, ...}, ...]
/// ```
pub fn highlight_exec(query_id : Int, tree_id : Int) -> String {
  let tree_entry = match tree_registry.get(tree_id) {
    Some(e) => e
    None => return "[]"
  }
  let table = match parser_registry.get(tree_entry.parser_id) {
    Some(pe) => pe.table
    None => return "[]"
  }
  let q_entry = match query_registry.get(query_id) {
    Some(e) => e
    None => return "[]"
  }
  let ranges = @query.apply_highlights(
    tree_entry.root,
    tree_entry.input,
    table,
    q_entry.query,
  )
  highlight_ranges_to_json(ranges)
}

///|
/// 在已解析的语法树上执行 高亮查询 + 局部变量解析，返回 JSON 数组字符串。
///
/// # 参数
/// - hl_query_id  : 高亮查询句柄（包含 @keyword/@string 等捕获）
/// - loc_query_id : 局部变量查询句柄（包含 @local.scope/@local.definition/@local.reference）
/// - tree_id      : 语法树句柄
///
/// # 返回值
/// 同 highlight_exec，但局部变量引用的 highlight_name 会追加 ".local" 后缀。
/// 任一 ID 无效时返回 "[]"。
///
/// # JS 调用示例
/// ```js
/// const hlq = query_compile("(identifier) @variable");
/// const lq  = query_compile(
///   "(block) @local.scope\n" +
///   "(let_decl name: (identifier) @local.definition)\n" +
///   "(identifier) @local.reference"
/// );
/// const json = highlight_exec_with_locals(hlq, lq, tid);
/// // [{highlight: "variable.local", ...}, {highlight: "variable", ...}, ...]
/// ```
pub fn highlight_exec_with_locals(
  hl_query_id : Int,
  loc_query_id : Int,
  tree_id : Int,
) -> String {
  let tree_entry = match tree_registry.get(tree_id) {
    Some(e) => e
    None => return "[]"
  }
  let table = match parser_registry.get(tree_entry.parser_id) {
    Some(pe) => pe.table
    None => return "[]"
  }
  let hl_entry = match query_registry.get(hl_query_id) {
    Some(e) => e
    None => return "[]"
  }
  let loc_entry = match query_registry.get(loc_query_id) {
    Some(e) => e
    None => return "[]"
  }
  let ranges = @query.apply_highlights_with_locals(
    tree_entry.root,
    tree_entry.input,
    table,
    hl_entry.query,
    loc_entry.query,
  )
  highlight_ranges_to_json(ranges)
}

///|
/// 返回标准高亮名称列表（JSON 字符串数组），方便 JS 端枚举可用的高亮类型。
///
/// 返回格式：`["keyword","string","number",...]`
pub fn highlight_names_json() -> String {
  let buf = StringBuilder::new()
  buf.write_char('[')
  let mut first = true
  for name in @query.highlight_names {
    if not(first) {
      buf.write_char(',')
    }
    write_jstr(buf, name)
    first = false
  }
  buf.write_char(']')
  buf.to_string()
}
