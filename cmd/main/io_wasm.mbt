///|
// 文件 I/O 的 wasm / wasm-gc 目标存根
//
// WASM 在浏览器或 Node.js 环境中运行时，文件系统访问依赖宿主提供。
// 当前 CLI 不支持 wasm 目标的文件 I/O；所有操作返回 Err 或退化为 stdout。

///|
fn read_file_impl(path : String) -> Result[String, String] {
  let _ = path
  Err("read_file is not available in WASM target (no host file I/O)")
}

///|
fn write_file_impl(path : String, content : String) -> Result[Unit, String] {
  let _ = path
  let _ = content
  Err("write_file is not available in WASM target (no host file I/O)")
}

///|
fn read_stdin_impl() -> String {
  // wasm-gc 无法直接读取 stdin，返回空字符串
  ""
}

///|
fn print_err_impl(s : String) -> Unit {
  // wasm-gc 无独立 stderr，退化为 stdout
  println("[stderr] \{s}")
}

///|
fn isatty_impl(fd : Int) -> Bool {
  let _ = fd
  // WASM 目标通常不连接到终端
  false
}
