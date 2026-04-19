///|
// 文件 I/O 的 native/llvm 实现
//
// 使用 C stdio（fopen/fread/fwrite/fclose）进行文件操作。
// 使用 POSIX read(0,...) 读取 stdin，write(2,...) 写入 stderr。
//
// FILE* 在 64 位系统上是 64 位指针，以 Int64 表示。

///|
fn str_to_cstr(s : String) -> Bytes {
  let buf = @buffer.new(size_hint=s.length() + 1)
  buf.write_string_utf8(s)
  buf.write_byte(b'\x00')
  buf.to_bytes()
}

///|
fn str_to_utf8(s : String) -> Bytes {
  let buf = @buffer.new(size_hint=s.length())
  buf.write_string_utf8(s)
  buf.to_bytes()
}

///|
fn shell_quote(path : String) -> String {
  "\"" + path + "\""
}

///|
// C stdio FFI

///|
#borrow(path, mode)
extern "c" fn c_fopen(path : Bytes, mode : Bytes) -> Int64 = "fopen"

///|
extern "c" fn c_fclose(file : Int64) -> Int = "fclose"

///|
extern "c" fn c_fseek(file : Int64, offset : Int64, whence : Int) -> Int = "fseek"

///|
extern "c" fn c_ftell(file : Int64) -> Int64 = "ftell"

///|
#borrow(buf)
extern "c" fn c_fread(
  buf : Bytes,
  size : Int,
  count : Int,
  file : Int64,
) -> Int = "fread"

///|
#borrow(buf)
extern "c" fn c_fwrite(
  buf : Bytes,
  size : Int,
  count : Int,
  file : Int64,
) -> Int = "fwrite"

///|
// POSIX read(fd, buf, count): 从文件描述符读取最多 count 字节
// 返回实际读取字节数；0 = EOF；负数 = 错误
#borrow(buf)
extern "c" fn c_read(fd : Int, buf : Bytes, count : Int) -> Int = "read"

///|
// POSIX write(fd, buf, count): 向文件描述符写入 count 字节
// fd=2 为 stderr
#borrow(buf)
extern "c" fn c_write(fd : Int, buf : Bytes, count : Int) -> Int = "write"

///|
// POSIX isatty(fd): 检查文件描述符是否连接到终端
extern "c" fn c_isatty(fd : Int) -> Int = "isatty"

///|
// fseek whence 常量（C stdio）
let seek_set : Int = 0 // 从文件头偏移

///|
let seek_end : Int = 2 // 从文件尾偏移

///|
// 接口实现

///|
fn read_file_impl(path : String) -> Result[String, String] {
  let cpath = str_to_cstr(path)
  let mode = str_to_cstr("rb")
  let file = c_fopen(cpath, mode)
  if file == 0L {
    return Err("cannot open file: \{path}")
  }
  // 定位到文件尾，获取大小
  if c_fseek(file, 0L, seek_end) != 0 {
    let _ = c_fclose(file)
    return Err("fseek(SEEK_END) failed: \{path}")
  }
  let size64 = c_ftell(file)
  if size64 < 0L {
    let _ = c_fclose(file)
    return Err("ftell failed: \{path}")
  }
  // 回到文件头
  if c_fseek(file, 0L, seek_set) != 0 {
    let _ = c_fclose(file)
    return Err("fseek(SEEK_SET) failed: \{path}")
  }
  // 一次性读取全部内容
  let size = size64.to_int()
  let buf = Bytes::new(size)
  let read = c_fread(buf, 1, size, file)
  let _ = c_fclose(file)
  if read < 0 {
    return Err("fread failed: \{path}")
  }
  Ok(@utf8.decode_lossy(buf[0:read]))
}

///|
fn write_file_impl(path : String, content : String) -> Result[Unit, String] {
  let cpath = str_to_cstr(path)
  let mode = str_to_cstr("wb")
  let file = c_fopen(cpath, mode)
  if file == 0L {
    return Err("cannot open file for writing: \{path}")
  }
  let bytes = str_to_utf8(content)
  let len = bytes.length()
  let written = c_fwrite(bytes, 1, len, file)
  let _ = c_fclose(file)
  if written != len {
    return Err("fwrite incomplete: wrote \{written} of \{len} bytes to \{path}")
  }
  Ok(())
}

///|
fn read_stdin_impl() -> String {
  // 分块读取 stdin（fd=0）直到 EOF
  let out = @buffer.new(size_hint=4096)
  let chunk = Bytes::new(4096)
  let mut n = c_read(0, chunk, 4096)
  while n > 0 {
    let decoded = @utf8.decode_lossy(chunk[0:n])
    out.write_string_utf8(decoded)
    n = c_read(0, chunk, 4096)
  }
  out.to_string()
}

///|
fn print_err_impl(s : String) -> Unit {
  // 向 stderr（fd=2）写入 UTF-8 编码的字符串 + 换行
  let bytes = str_to_utf8(s + "\n")
  let _ = c_write(2, bytes, bytes.length())
}

///|
fn isatty_impl(fd : Int) -> Bool {
  c_isatty(fd) != 0
}

///|
fn write_bytes_impl(path : String, bytes : Bytes) -> Result[Unit, String] {
  let cpath = str_to_cstr(path)
  let mode = str_to_cstr("wb")
  let file = c_fopen(cpath, mode)
  if file == 0L {
    return Err("cannot open file for writing: \{path}")
  }
  let len = bytes.length()
  let written = c_fwrite(bytes, 1, len, file)
  let _ = c_fclose(file)
  if written != len {
    return Err("write incomplete: wrote \{written} of \{len} bytes to \{path}")
  }
  Ok(())
}

///|
fn read_bytes_impl(path : String) -> Result[Bytes, String] {
  let cpath = str_to_cstr(path)
  let mode = str_to_cstr("rb")
  let file = c_fopen(cpath, mode)
  if file == 0L {
    return Err("cannot open file: \{path}")
  }
  if c_fseek(file, 0L, seek_end) != 0 {
    let _ = c_fclose(file)
    return Err("fseek(SEEK_END) failed: \{path}")
  }
  let size64 = c_ftell(file)
  if size64 < 0L {
    let _ = c_fclose(file)
    return Err("ftell failed: \{path}")
  }
  if c_fseek(file, 0L, seek_set) != 0 {
    let _ = c_fclose(file)
    return Err("fseek(SEEK_SET) failed: \{path}")
  }
  let size = size64.to_int()
  let buf = Bytes::new(size)
  let read = c_fread(buf, 1, size, file)
  let _ = c_fclose(file)
  if read < 0 {
    return Err("fread failed: \{path}")
  }
  Ok(Bytes::makei(read, fn(i) { buf[i] }))
}

///|
extern "c" fn c_exit(code : Int) -> Unit = "exit"

///|
fn process_exit_impl(code : Int) -> Unit {
  c_exit(code)
}

///|
#borrow(cmd)
extern "c" fn c_system(cmd : Bytes) -> Int = "system"

///|
fn make_dir_impl(path : String) -> Result[Unit, String] {
  // best-effort: `mkdir` 在 Windows 上可递归创建，在 Unix 上至少可处理单层输出目录；
  // 真正的失败会在后续 write_file / write_bytes 阶段暴露。
  let _ = c_system(str_to_cstr("mkdir " + shell_quote(path)))
  Ok(())
}

///|
fn remove_dir_all_impl(path : String) -> Result[Unit, String] {
  let quoted = shell_quote(path)
  let unix_code = c_system(str_to_cstr("rm -rf " + quoted))
  if unix_code == 0 {
    return Ok(())
  }
  let win_code = c_system(str_to_cstr("rmdir /s /q " + quoted))
  if win_code == 0 {
    Ok(())
  } else {
    // 缺失目录在不同 shell 上返回码不一致；clean 语义上应保持幂等。
    Ok(())
  }
}
