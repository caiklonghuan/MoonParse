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
  write_kvs(buf, "text", tree.input[node.start_byte:node.end_byte].to_string())
  buf.write_char('}')
  buf.to_string()
}

///|
// WASM 导出

///|
/// 最近一次 query_compile 失败时的错误信息（JSON 对象字符串）。
/// 格式：{"offset": 5, "message": "expected ')'"}
/// 编译成功时清空为 ""。
///
/// **线程安全：** WASM MVP 为单线程模型，此全局变量无竞争风险。
/// 若将来在 Node.js worker_threads 或 Wasm Component Model 共享内存场景下
/// 并发调用 query_compile，需改为线程本地存储或加锁保护。
let last_compile_error : Array[String] = [""]

///|
/// 将 S-表达式模式字符串编译为查询对象，返回句柄 ID（失败返回 -1）。
///
/// JS 调用：
///   const qid = query_compile("(identifier) @name");
///   if (qid < 0) {
///     const err = JSON.parse(query_compile_error_last());
///     console.error(`offset ${err.offset}: ${err.message}`);
///   }
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
/// 返回最近一次 query_compile 失败的错误详情（JSON 对象字符串）。
/// 若上次编译成功，返回空字符串 ""。
///
/// JS 调用：
///   const errJson = query_compile_error_last(); // "" 或 JSON string
pub fn query_compile_error_last() -> String {
  last_compile_error[0]
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
