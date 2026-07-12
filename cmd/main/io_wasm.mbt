///|
// 文件 I/O 的 wasm / wasm-gc 目标实现（由 run.js 提供宿主 API）
// 请使用 `node run.js <cmd> [args]` 运行，而非 `moon run --target wasm-gc`。

// --- 不透明外部类型（FFI handle） ---

///|
#external
priv type XStringCreateHandle

///|
#external
priv type XStringReadHandle

///|
#external
priv type XExternString

///|
#external
priv type XStringArrayReadHandle

///|
#external
priv type XExternStringArray

///|
#external
priv type XByteArrayReadHandle

///|
#external
priv type XByteArrayCreateHandle

///|
#external
priv type XExternByteArray

// --- 字符串构建 FFI（__moonbit_fs_unstable） ---

///|
fn wasm_begin_create_string() -> XStringCreateHandle = "__moonbit_fs_unstable" "begin_create_string"

///|
fn wasm_string_append_char(handle : XStringCreateHandle, ch : Char) = "__moonbit_fs_unstable" "string_append_char"

///|
fn wasm_finish_create_string(handle : XStringCreateHandle) -> XExternString = "__moonbit_fs_unstable" "finish_create_string"

///|
fn wasm_begin_read_string(s : XExternString) -> XStringReadHandle = "__moonbit_fs_unstable" "begin_read_string"

///|
fn wasm_string_read_char(handle : XStringReadHandle) -> Int = "__moonbit_fs_unstable" "string_read_char"

///|
fn wasm_finish_read_string(handle : XStringReadHandle) = "__moonbit_fs_unstable" "finish_read_string"

// --- 瀛楃涓叉暟缁勮鍙?FFI ---

///|
fn wasm_begin_read_string_array(
  arr : XExternStringArray,
) -> XStringArrayReadHandle = "__moonbit_fs_unstable" "begin_read_string_array"

///|
fn wasm_string_array_read_string(
  handle : XStringArrayReadHandle,
) -> XExternString = "__moonbit_fs_unstable" "string_array_read_string"

///|
fn wasm_finish_read_string_array(handle : XStringArrayReadHandle) = "__moonbit_fs_unstable" "finish_read_string_array"

// --- 字节数组读取 FFI ---

///|
fn wasm_begin_read_byte_array(arr : XExternByteArray) -> XByteArrayReadHandle = "__moonbit_fs_unstable" "begin_read_byte_array"

///|
fn wasm_byte_array_read_byte(handle : XByteArrayReadHandle) -> Int = "__moonbit_fs_unstable" "byte_array_read_byte"

///|
fn wasm_finish_read_byte_array(handle : XByteArrayReadHandle) = "__moonbit_fs_unstable" "finish_read_byte_array"

// --- 字节数组构建 FFI（用于写入） ---

///|
fn wasm_begin_create_byte_array() -> XByteArrayCreateHandle = "__moonbit_fs_unstable" "begin_create_byte_array"

///|
fn wasm_byte_array_append_byte(handle : XByteArrayCreateHandle, b : Int) = "__moonbit_fs_unstable" "byte_array_append_byte"

///|
fn wasm_finish_create_byte_array(
  handle : XByteArrayCreateHandle,
) -> XExternByteArray = "__moonbit_fs_unstable" "finish_create_byte_array"

// --- 文件读写 FFI（由 run.js 提供） ---

///|
fn wasm_read_file_to_bytes(path : XExternString) -> XExternByteArray = "__moonbit_fs_unstable" "read_file_to_bytes"

///|
// 返回 0 = 成功，1 = 失败
fn wasm_write_string_to_file(
  path : XExternString,
  content : XExternString,
) -> Int = "__moonbit_fs_unstable" "write_string_to_file"

///|
// 返回 0 = 成功，1 = 失败
fn wasm_write_bytes_to_file(
  path : XExternString,
  data : XExternByteArray,
) -> Int = "__moonbit_fs_unstable" "write_bytes_to_file"

///|
// 返回 0 = 成功，1 = 失败
fn wasm_create_dir_all(path : XExternString) -> Int = "__moonbit_fs_unstable" "create_dir_all"

///|
// 返回 0 = 成功，1 = 失败
fn wasm_remove_dir_all(path : XExternString) -> Int = "__moonbit_fs_unstable" "remove_dir_all"

///|
fn wasm_atomic_write_string_to_file(
  path : XExternString,
  content : XExternString,
) -> Int = "__moonbit_fs_unstable" "atomic_write_string_to_file"

///|
fn wasm_list_files(path : XExternString) -> XExternStringArray = "__moonbit_fs_unstable" "list_files"

///|
fn wasm_run_command(
  cwd : XExternString,
  command : XExternString,
) -> XExternString = "__moonbit_fs_unstable" "run_command"

// --- stdin 读取 FFI ---

///|
fn wasm_read_char() -> Int = "__moonbit_io_unstable" "read_char"

// --- 进程退出 FFI（WASI） ---

///|
fn wasm_proc_exit(code : Int) = "wasi_snapshot_preview1" "proc_exit"

// --- 辅助：MoonBit String → XExternString ---

///|
fn string_to_extern_ffi(s : String) -> XExternString {
  let handle = wasm_begin_create_string()
  for i = 0; i < s.length(); i = i + 1 {
    wasm_string_append_char(handle, s.code_unit_at(i).unsafe_to_char())
  }
  wasm_finish_create_string(handle)
}

///|
fn extern_string_to_string(s : XExternString) -> String {
  let buf = StringBuilder::new()
  let handle = wasm_begin_read_string(s)
  while true {
    let ch = wasm_string_read_char(handle)
    if ch == -1 {
      break
    }
    buf.write_char(ch.unsafe_to_char())
  }
  wasm_finish_read_string(handle)
  buf.to_string()
}

///|
fn extern_string_array_to_array(arr : XExternStringArray) -> Array[String] {
  let values : Array[String] = []
  let handle = wasm_begin_read_string_array(arr)
  while true {
    let value = extern_string_to_string(wasm_string_array_read_string(handle))
    if value == "ffi_end_of_/string_array" {
      break
    }
    values.push(value)
  }
  wasm_finish_read_string_array(handle)
  values
}

// --- 辅助：XExternByteArray → Bytes ---

///|
fn extern_byte_array_to_bytes(arr : XExternByteArray) -> Bytes {
  let buf = @buffer.new()
  let handle = wasm_begin_read_byte_array(arr)
  while true {
    let b = wasm_byte_array_read_byte(handle)
    if b == -1 {
      break
    }
    buf.write_byte(b.to_byte())
  }
  wasm_finish_read_byte_array(handle)
  buf.to_bytes()
}

// --- 辅助：Bytes → XExternByteArray ---

///|
fn bytes_to_extern_byte_array(bytes : Bytes) -> XExternByteArray {
  let handle = wasm_begin_create_byte_array()
  for i = 0; i < bytes.length(); i = i + 1 {
    wasm_byte_array_append_byte(handle, bytes[i].to_int())
  }
  wasm_finish_create_byte_array(handle)
}

///|
fn read_file_impl(path : String) -> Result[String, String] {
  let arr = wasm_read_file_to_bytes(string_to_extern_ffi(path))
  let bytes = extern_byte_array_to_bytes(arr)
  if bytes.length() == 0 {
    Err("cannot read file: \{path}")
  } else {
    Ok(@utf8.decode_lossy(bytes[:]))
  }
}

///|
fn write_file_impl(path : String, content : String) -> Result[Unit, String] {
  let r = wasm_write_string_to_file(
    string_to_extern_ffi(path),
    string_to_extern_ffi(content),
  )
  if r == 0 {
    Ok(())
  } else {
    Err("cannot write file: \{path}")
  }
}

///|
fn read_stdin_impl() -> String {
  let buf = StringBuilder::new()
  while true {
    let ch = wasm_read_char()
    if ch == -1 {
      break
    }
    buf.write_char(ch.unsafe_to_char())
  }
  buf.to_string()
}

///|
fn read_line_impl() -> String? {
  None
}

///|
fn list_files_impl(path : String) -> Result[Array[String], String] {
  let files = extern_string_array_to_array(
    wasm_list_files(string_to_extern_ffi(path)),
  )
  if !files.is_empty() && files[0].has_prefix("ffi_error:") {
    Err("cannot list directory: " + path + ": " + files[0][10:].to_owned())
  } else {
    Ok(files)
  }
}

///|
fn atomic_write_file_impl(
  path : String,
  content : String,
) -> Result[Unit, String] {
  let r = wasm_atomic_write_string_to_file(
    string_to_extern_ffi(path),
    string_to_extern_ffi(content),
  )
  if r == 0 {
    Ok(())
  } else {
    Err("cannot atomically write file: \{path}")
  }
}

///|
fn print_err_impl(s : String) -> Unit {
  // wasm-gc 无独立 stderr，退化为 stdout
  println("[stderr] \{s}")
}

///|
fn isatty_impl(fd : Int) -> Bool {
  let _ = fd
  false
}

///|
fn write_bytes_impl(path : String, bytes : Bytes) -> Result[Unit, String] {
  let r = wasm_write_bytes_to_file(
    string_to_extern_ffi(path),
    bytes_to_extern_byte_array(bytes),
  )
  if r == 0 {
    Ok(())
  } else {
    Err("cannot write bytes: \{path}")
  }
}

///|
fn read_bytes_impl(path : String) -> Result[Bytes, String] {
  let arr = wasm_read_file_to_bytes(string_to_extern_ffi(path))
  let bytes = extern_byte_array_to_bytes(arr)
  if bytes.length() == 0 {
    Err("cannot read file: \{path}")
  } else {
    Ok(bytes)
  }
}

///|
fn process_exit_impl(code : Int) -> Unit {
  wasm_proc_exit(code)
}

///|
fn make_dir_impl(path : String) -> Result[Unit, String] {
  let r = wasm_create_dir_all(string_to_extern_ffi(path))
  if r == 0 {
    Ok(())
  } else {
    Err("cannot create directory: \{path}")
  }
}

///|
fn remove_dir_all_impl(path : String) -> Result[Unit, String] {
  let r = wasm_remove_dir_all(string_to_extern_ffi(path))
  if r == 0 {
    Ok(())
  } else {
    Err("cannot remove directory: \{path}")
  }
}

///|
fn run_command_impl(cwd : String, command : String) -> Result[Unit, String] {
  let error = extern_string_to_string(
    wasm_run_command(string_to_extern_ffi(cwd), string_to_extern_ffi(command)),
  )
  if error.is_empty() {
    Ok(())
  } else {
    Err(error)
  }
}
