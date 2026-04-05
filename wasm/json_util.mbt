///|
// JSON 序列化工具（wasm/ 包内共用）
//
// 被 cst_json.mbt 和 query.mbt 共同使用，集中维护转义逻辑，
// 避免两处实现在边界字符（Unicode 控制字符等）处理上产生不一致。

///|
/// 将字符串内容以 JSON 转义格式写入 buf（不含外层引号）
fn write_escaped(buf : StringBuilder, s : String) -> Unit {
  for ch in s {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(ch)
    }
  }
}

///|
/// 向 buf 写入带双引号的 JSON 字符串
fn write_jstr(buf : StringBuilder, s : String) -> Unit {
  buf.write_char('"')
  write_escaped(buf, s)
  buf.write_char('"')
}

///|
/// 向 buf 写入 JSON 键值对 `"key": "string_value"`
fn write_kvs(buf : StringBuilder, key : String, value : String) -> Unit {
  write_jstr(buf, key)
  buf.write_char(':')
  write_jstr(buf, value)
}

///|
/// 向 buf 写入 JSON 键值对 `"key": int_value`
fn write_kvi(buf : StringBuilder, key : String, value : Int) -> Unit {
  write_jstr(buf, key)
  buf.write_char(':')
  buf.write_string(value.to_string())
}

///|
/// 向 buf 写入 JSON 键值对 `"key": bool_value`
fn write_kvb(buf : StringBuilder, key : String, value : Bool) -> Unit {
  write_jstr(buf, key)
  buf.write_char(':')
  buf.write_string(if value { "true" } else { "false" })
}
