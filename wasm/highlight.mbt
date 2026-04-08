///|
// Highlight Query WASM 导出

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
/// 在已解析的语法树上执行高亮查询，返回 JSON 数组字符串
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
/// 在已解析的语法树上执行 高亮查询 + 局部变量解析，返回 JSON 数组字符串
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
/// 返回标准高亮名称列表（JSON 字符串数组），方便 JS 端枚举可用的高亮类型
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
