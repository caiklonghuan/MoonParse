///|
// Query WASM 导出

///|
/// 序列化单条 CaptureResult 为 JSON object 字符串
fn capture_to_json(c : @query.CaptureResult, tree : TreeEntry) -> String {
  let node = c.node
  let buf = StringBuilder::new()
  buf.write_char('{')
  write_kvi(buf, "match_id", c.match_id)
  buf.write_char(',')
  // capture_name 经过完整 JSON 转义（write_kvs），而非依赖"字段名已安全"的隐式假设。
  write_kvs(buf, "capture", c.capture_name)
  buf.write_char(',')
  write_kvi(buf, "start", node.start_byte)
  buf.write_char(',')
  write_kvi(buf, "end", node.end_byte)
  buf.write_char(',')
  write_kvi(buf, "start_row", node.start_point.row)
  buf.write_char(',')
  write_kvi(buf, "start_col", node.start_point.column)
  buf.write_char(',')
  write_kvi(buf, "end_row", node.end_point.row)
  buf.write_char(',')
  write_kvi(buf, "end_col", node.end_point.column)
  buf.write_char(',')

  let text = if node.start_byte <= node.end_byte &&
    node.end_byte <= tree.input.length() {
    tree.input[node.start_byte:node.end_byte].to_string()
  } else {
    ""
  }
  write_kvs(buf, "text", text)
  buf.write_char('}')
  buf.to_string()
}

///|
// WASM 导出

///|
/// 最近一次 query_compile 失败时的错误信息（JSON 对象字符串）
let last_compile_error : Array[String] = [""]

///|
/// 将 S-表达式模式字符串编译为查询对象，返回句柄 ID（失败返回 -1）
pub fn query_compile(pattern_str : String) -> Int {
  match @query.compile(pattern_str) {
    Ok(q) => {
      last_compile_error[0] = ""
      query_registry.register({ query: q })
    }
    Err(@query.ParseError(offset, msg)) => {
      let buf = StringBuilder::new()
      buf.write_string("{\"offset\":")
      buf.write_string(offset.to_string())
      buf.write_string(",\"message\":")
      write_jstr(buf, msg)
      buf.write_char('}')
      last_compile_error[0] = buf.to_string()
      -1
    }
  }
}

///|
/// 返回最近一次 query_compile 失败的错误详情（JSON 对象字符串）
pub fn query_compile_error_last() -> String {
  last_compile_error[0]
}

///|
/// 在指定语法树上执行查询，返回 JSON 字符串（失败或无结果时返回 "[]"）
pub fn query_exec(query_id : Int, tree_id : Int) -> String {
  let qentry = match query_registry.get(query_id) {
    Some(e) => e
    None => return "[]"
  }
  let tree = match tree_registry.get(tree_id) {
    Some(t) => t
    None => return "[]"
  }

  let captures = @query.exec(qentry.query, tree.root, tree.input, tree.table)
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
/// 在指定语法树上运行 locals 查询，返回局部变量解析结果 JSON 对象字符串。
/// 格式：`{"<start_byte>": true, ...}`，每个 key 是被识别为本地引用的节点起始字节。
/// 查询或树无效时返回 "{}"。
pub fn query_resolve_locals(query_id : Int, tree_id : Int) -> String {
  let qentry = match query_registry.get(query_id) {
    Some(e) => e
    None => return "{}"
  }
  let tree = match tree_registry.get(tree_id) {
    Some(t) => t
    None => return "{}"
  }
  let res = @query.resolve_locals(
    tree.root,
    tree.input,
    tree.table,
    qentry.query,
  )
  let buf = StringBuilder::new()
  buf.write_char('{')
  let mut first = true
  res.local_refs.each(fn(k, v) {
    if v {
      if !first {
        buf.write_char(',')
      }
      buf.write_char('"')
      buf.write_string(k.to_string())
      buf.write_string("\":true")
      first = false
    }
  })
  buf.write_char('}')
  buf.to_string()
}

///|
/// 释放查询对象，释放后其 ID 不再有效
pub fn query_free(query_id : Int) -> Unit {
  let _ = query_registry.remove(query_id)
}
