///|
// 文件 I/O 适配层

///|
pub fn read_file(path : String) -> Result[String, String] {
  read_file_impl(path)
}

///|
pub fn write_file(path : String, content : String) -> Result[Unit, String] {
  write_file_impl(path, content)
}

///|
pub fn read_stdin() -> String {
  read_stdin_impl()
}

///|
/// 向 stderr 输出一行（末尾追加换行符）。
pub fn print_err(s : String) -> Unit {
  print_err_impl(s)
}

///|
pub fn isatty(fd : Int) -> Bool {
  isatty_impl(fd)
}

///|
pub fn write_bytes(path : String, bytes : Bytes) -> Result[Unit, String] {
  write_bytes_impl(path, bytes)
}

///|
pub fn read_bytes(path : String) -> Result[Bytes, String] {
  read_bytes_impl(path)
}

///|
pub fn process_exit(code : Int) -> Unit {
  process_exit_impl(code)
}

///|
pub fn make_dir(path : String) -> Result[Unit, String] {
  make_dir_impl(path)
}

///|
pub fn remove_dir_all(path : String) -> Result[Unit, String] {
  remove_dir_all_impl(path)
}
