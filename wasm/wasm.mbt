/// WASM 接口
/// 将解析器编译为 WASM，提供浏览器集成
///
/// 验证实验：use-js-builtin-string 下的 String 互操作

///|
/// 验证：JS String 直传 —— 接受一个字符串并原样返回
/// 若 use-js-builtin-string 生效，JS 调用者无需做任何编码转换
pub fn echo_string(s : String) -> String {
  s
}

///|
/// 验证：返回字符串长度（字符数）
pub fn string_len(s : String) -> Int {
  s.length()
}
