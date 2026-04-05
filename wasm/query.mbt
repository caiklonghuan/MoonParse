///|
// Query WASM 导出

///|
/// 序列化单条 CaptureResult 为 JSON object 字符串
fn capture_to_json(c : @query.CaptureResult, tree : TreeEntry) -> String {
  let node = c.node
  let buf = StringBuilder::new()
  buf.write_string("{")
  buf.write_string("\"match_id\":")
  buf.write_string(c.match_id.to_string())
  buf.write_string(",\"capture\":\"")
  // capture_name 已由 parser 保证只含安全字符，无需转义
  buf.write_string(c.capture_name)
  buf.write_string("\"")
  buf.write_string(",\"start\":")
  buf.write_string(node.start_byte.to_string())
  buf.write_string(",\"end\":")
  buf.write_string(node.end_byte.to_string())
  buf.write_string(",\"start_row\":")
  buf.write_string(node.start_point.row.to_string())
  buf.write_string(",\"start_col\":")
  buf.write_string(node.start_point.column.to_string())
  buf.write_string(",\"end_row\":")
  buf.write_string(node.end_point.row.to_string())
  buf.write_string(",\"end_col\":")
  buf.write_string(node.end_point.column.to_string())
  buf.write_string(",\"text\":")
  let text = tree.input[node.start_byte:node.end_byte].to_string()
  write_json_string(buf, text)
  buf.write_string("}")
  buf.to_string()
}

///|
/// 将字符串以 JSON 字符串形式（带双引号）写入 buf，进行必要的转义
fn write_json_string(buf : StringBuilder, s : String) -> Unit {
  buf.write_char('"')
  for i in 0..<s.length() {
    let c = s[i].to_int().unsafe_to_char()
    match c {
      '"' => {
        buf.write_char('\\')
        buf.write_char('"')
      }
      '\\' => {
        buf.write_char('\\')
        buf.write_char('\\')
      }
      '\n' => {
        buf.write_char('\\')
        buf.write_char('n')
      }
      '\r' => {
        buf.write_char('\\')
        buf.write_char('r')
      }
      '\t' => {
        buf.write_char('\\')
        buf.write_char('t')
      }
      _ => buf.write_char(c)
    }
  }
  buf.write_char('"')
}

///|
// ── WASM 导出 ────────────────────────────────────────────────────

///|
/// 将 S-表达式模式字符串编译为查询对象，返回句柄 ID（失败返回 -1）。
///
/// JS 调用：
///   const qid = query_compile("(identifier) @name");
///   if (qid < 0) { /* 编译失败 */ }
pub fn query_compile(pattern_str : String) -> Int {
  match @query.compile(pattern_str) {
    Ok(q) => query_registry.register({ query: q })
    Err(_) => -1
  }
}

///|
/// 在指定语法树上执行查询，返回 JSON 字符串（失败或无结果时返回 "[]"）。
///
/// JS 调用：
///   const json = query_exec(qid, tree_id);
///   const captures = JSON.parse(json);
pub fn query_exec(query_id : Int, tree_id : Int) -> String {
  let qentry = match query_registry.get(query_id) {
    Some(e) => e
    None => return "[]"
  }
  let tree = match tree_registry.get(tree_id) {
    Some(t) => t
    None => return "[]"
  }
  let parser_entry = match parser_registry.get(tree.parser_id) {
    Some(p) => p
    None => return "[]"
  }
  let captures = @query.exec(
    qentry.query,
    tree.root,
    tree.input,
    parser_entry.table,
  )
  // 序列化为 JSON 数组
  let buf = StringBuilder::new()
  buf.write_char('[')
  for i in 0..<captures.length() {
    if i > 0 {
      buf.write_char(',')
    }
    buf.write_string(capture_to_json(captures[i], tree))
  }
  buf.write_char(']')
  buf.to_string()
}

///|
/// 释放查询对象，释放后其 ID 不再有效。
///
/// JS 调用：
///   query_free(qid);
pub fn query_free(query_id : Int) -> Unit {
  let _ = query_registry.remove(query_id)
}
