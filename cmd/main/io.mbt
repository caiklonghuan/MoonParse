///|
// 文件 I/O 适配层

///|
// 共用辅助

///|
/// MoonBit String → null 结尾 UTF-8 字节（C 字符串，用于 fopen 路径等参数）
fn str_to_cstr(s : String) -> Bytes {
  let buf = @buffer.new(size_hint=s.length() + 1)
  buf.write_string_utf8(s)
  buf.write_byte(b'\x00')
  buf.to_bytes()
}

///|
/// MoonBit String → UTF-8 字节（无 null 结尾，用于写入文件内容）
fn str_to_utf8(s : String) -> Bytes {
  let buf = @buffer.new(size_hint=s.length())
  buf.write_string_utf8(s)
  buf.to_bytes()
}

///|
// 公开 API

///|
/// 读取文件全部内容，解码为 UTF-8 字符串。
///
/// 失败（文件不存在、无读权限等）返回 `Err(message)`。
pub fn read_file(path : String) -> Result[String, String] {
  read_file_impl(path)
}

///|
/// 将字符串内容以 UTF-8 编码覆盖写入文件。
///
/// 失败返回 `Err(message)`。
pub fn write_file(path : String, content : String) -> Result[Unit, String] {
  write_file_impl(path, content)
}

///|
/// 从 stdin 读取全部内容（直到 EOF），解码为 UTF-8 字符串。
pub fn read_stdin() -> String {
  read_stdin_impl()
}

///|
/// 向 stderr 输出一行（末尾追加换行符）。
pub fn print_err(s : String) -> Unit {
  print_err_impl(s)
}

///|
/// 检查文件描述符是否连接到终端。
/// fd=1 为 stdout，fd=2 为 stderr。
pub fn isatty(fd : Int) -> Bool {
  isatty_impl(fd)
}

///|
/// 将字节数组内容以二进制模式写入文件（覆盖写）。
///
/// 失败返回 `Err(message)`。
pub fn write_bytes(path : String, bytes : Bytes) -> Result[Unit, String] {
  write_bytes_impl(path, bytes)
}

///|
/// 读取文件全部内容，返回原始字节（不做 UTF-8 解码，适用于二进制文件）。
///
/// 失败返回 `Err(message)`。
pub fn read_bytes(path : String) -> Result[Bytes, String] {
  read_bytes_impl(path)
}

///|
/// 退出进程，使用指定的退出码。
/// 在 native 目标上调用 C 的 exit()；在 wasm 目标上，非零码触发 panic。
pub fn process_exit(code : Int) -> Unit {
  process_exit_impl(code)
}
