///|
fn wasm_stub_error(path : String) -> String {
  "host filesystem imports unavailable in debug wasm target: " + path
}

///|
fn read_file_impl(path : String) -> Result[String, String] {
  Err(wasm_stub_error(path))
}

///|
fn write_file_impl(path : String, _content : String) -> Result[Unit, String] {
  Err(wasm_stub_error(path))
}

///|
fn read_stdin_impl() -> String {
  ""
}

///|
fn read_line_impl() -> String? {
  None
}

///|
fn list_files_impl(path : String) -> Result[Array[String], String] {
  Err(wasm_stub_error(path))
}

///|
fn atomic_write_file_impl(
  path : String,
  _content : String,
) -> Result[Unit, String] {
  Err(wasm_stub_error(path))
}

///|
fn print_err_impl(s : String) -> Unit {
  println("[stderr] \{s}")
}

///|
fn isatty_impl(_fd : Int) -> Bool {
  false
}

///|
fn write_bytes_impl(path : String, _bytes : Bytes) -> Result[Unit, String] {
  Err(wasm_stub_error(path))
}

///|
fn read_bytes_impl(path : String) -> Result[Bytes, String] {
  Err(wasm_stub_error(path))
}

///|
fn process_exit_impl(code : Int) -> Unit {
  abort("process_exit(\{code}) in debug wasm target")
}

///|
fn make_dir_impl(path : String) -> Result[Unit, String] {
  Err(wasm_stub_error(path))
}

///|
fn remove_dir_all_impl(path : String) -> Result[Unit, String] {
  Err(wasm_stub_error(path))
}

///|
fn run_command_impl(cwd : String, command : String) -> Result[Unit, String] {
  Err(wasm_stub_error(cwd) + ": " + command)
}
