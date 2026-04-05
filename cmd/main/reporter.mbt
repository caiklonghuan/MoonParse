///|
// 错误 / 诊断格式化输出
//
// 将各层错误（Grammar 解析错误、校验错误、冲突报告、ParseError、QueryError）
// 格式化为可读的终端输出，支持 ANSI 颜色高亮（可选）。

///|
/// 是否启用 ANSI 颜色码。默认关闭，由 main 根据终端检测结果调用 set_color_output 启用。
/// 用 Array[Bool] 模拟可变全局（MoonBit 顶层不允许 let mut 原始类型）。
let use_color_cell : Array[Bool] = [false]

///|
/// 设置是否使用 ANSI 颜色输出。
/// 通常在 main 中检测 NO_COLOR 环境变量或 --no-color flag 后调用。
/// 如果未显式设置，则自动检测 stderr 是否连接到终端。
pub fn set_color_output(enabled : Bool?) -> Unit {
  let should_use_color = match enabled {
    Some(e) => e
    None =>
      // 自动检测：检查 stderr (fd=2) 是否为终端
      isatty_impl(2)
  }
  use_color_cell[0] = should_use_color
}

///|
// ANSI 颜色辅助

///|
fn ansi_red(s : String) -> String {
  if use_color_cell[0] {
    "\u001B[1;31m\{s}\u001B[0m"
  } else {
    s
  }
}

///|
fn ansi_yellow(s : String) -> String {
  if use_color_cell[0] {
    "\u001B[1;33m\{s}\u001B[0m"
  } else {
    s
  }
}

///|
fn ansi_bold(s : String) -> String {
  if use_color_cell[0] {
    "\u001B[1m\{s}\u001B[0m"
  } else {
    s
  }
}

///|
fn ansi_blue(s : String) -> String {
  if use_color_cell[0] {
    "\u001B[1;34m\{s}\u001B[0m"
  } else {
    s
  }
}

///|
fn ansi_cyan(s : String) -> String {
  if use_color_cell[0] {
    "\u001B[36m\{s}\u001B[0m"
  } else {
    s
  }
}

///|
// 字符串工具

///|
/// 生成 n 个空格组成的字符串。
fn spaces(n : Int) -> String {
  if n <= 0 {
    return ""
  }
  let buf = @buffer.new(size_hint=n)
  for _ in 0..<n {
    buf.write_char(' ')
  }
  buf.to_string()
}

///|
/// 取出 source 中第 line_no 行（1-indexed）的文本内容。
fn get_source_line(source : String, line_no : Int) -> String? {
  let mut cur = 1
  let mut line_begin = 0
  let len = source.length()
  for i in 0..<len {
    if source[i] == '\n' {
      if cur == line_no {
        return Some(source[line_begin:i].to_string())
      }
      cur = cur + 1
      line_begin = i + 1
    }
  }
  if cur == line_no {
    return Some(source[line_begin:len].to_string())
  }
  None
}

///|
/// 生成带行号槽和 `^` 插入符的源码上下文块（三行：空槽 / 代码行 / 指针行）。
/// line_no: 1-indexed，col: 1-indexed。
/// label: （可选）显示在 `^` 旁边的错误消息。
fn render_source_snippet(
  source : String,
  line_no : Int,
  col : Int,
  label : String?,
) -> String {
  let n = line_no.to_string()
  let w = n.length()
  let g = spaces(w)
  let blank_gutter = ansi_blue(" \{g} |")
  match get_source_line(source, line_no) {
    None => "\{blank_gutter}\n"
    Some(content) => {
      let indent = spaces(if col > 1 { col - 1 } else { 0 })
      let caret = ansi_red("^")
      let label_str = match label {
        Some(msg) => " " + ansi_red(msg)
        None => ""
      }
      "\{blank_gutter}\n \{ansi_blue(n)} | \{content}\n\{blank_gutter} \{indent}\{caret}\{label_str}\n"
    }
  }
}

///|
/// 格式化文件位置头部：`  --> path/to/file:line:col`
fn loc_line(file : String, line : Int, col : Int) -> String {
  let arrow = ansi_cyan("-->")
  "  \{arrow} \{file}:\{line}:\{col}"
}

///|
// 公开报告函数

///|
/// 初始化 reporter 模块。应在程序启动时调用。
/// 自动检测终端并设置颜色输出。
pub fn init_reporter() -> Unit {
  set_color_output(None)
}

///|
/// 打印一般信息消息到 stdout。
pub fn print_info(msg : String) -> Unit {
  println(msg)
}

///|
/// 打印警告消息到 stderr。
pub fn print_warning(msg : String) -> Unit {
  let tag = ansi_yellow("warning")
  print_err("\{tag}: \{msg}")
}

///|
/// 打印 Grammar DSL 解析错误到 stderr。
///
/// - `file`：（可选）语法文件路径，用于显示位置箭头行
/// - `source`：（可选）文件全文，用于显示源码行高亮；需同时提供 `file` 才显示
pub fn report_grammar_parse_error(
  err : @grammar.ParseError,
  file : String?,
  source : String?,
) -> Unit {
  let loc = err.location
  let tag = ansi_red("error")
  let msg = ansi_bold(err.message)
  print_err("\{tag}: \{msg}")
  match file {
    None => ()
    Some(path) => print_err(loc_line(path, loc.line, loc.column))
  }
  match (file, source) {
    (Some(_), Some(src)) =>
      print_err(
        render_source_snippet(src, loc.line, loc.column, Some(err.message)),
      )
    _ => ()
  }
}

///|
/// 打印 Grammar 语义校验错误列表到 stderr。
///
/// `file`：（可选）语法文件路径，用于显示位置行。
pub fn report_validation_errors(
  errors : Array[@grammar.ValidationError],
  file : String?,
) -> Unit {
  let tag = ansi_red("error")
  for e in errors {
    let msg = ansi_bold(e.to_string())
    print_err("\{tag}: \{msg}")
    match file {
      None => ()
      Some(path) => {
        let arrow = ansi_cyan("-->")
        print_err("  \{arrow} \{path} (rule '\{e.rule}')")
      }
    }
  }
}

///|
/// 打印解析表冲突报告到 stderr。
/// `Warn` 以黄色显示，`Ambiguous` 以红色显示。
pub fn report_conflicts(reports : Array[@tablegen.ConflictReport]) -> Unit {
  if reports.is_empty() {
    return
  }
  print_err(ansi_bold("冲突报告（\{reports.length()} 条）"))
  for r in reports {
    match r.severity {
      Warn(msg) => {
        let lbl = ansi_yellow("[warn]")
        print_err("  \{lbl} \{msg}")
        print_err(
          "    state=\{r.state}  terminal=\{r.terminal}  actions=\{r.actions.length()}",
        )
      }
      Ambiguous(msg) => {
        let lbl = ansi_red("[error]")
        print_err("  \{lbl} \{msg}")
        print_err(
          "    state=\{r.state}  terminal=\{r.terminal}  actions=\{r.actions.length()}",
        )
      }
      DynamicConflict(id) => {
        let lbl = ansi_yellow("[dynamic]")
        print_err(
          "  \{lbl} dynamic prec id=\{id} in state \{r.state} on terminal \{r.terminal}",
        )
        print_err(
          "    state=\{r.state}  terminal=\{r.terminal}  actions=\{r.actions.length()}",
        )
      }
    }
  }
}

///|
/// 打印运行时解析错误到 stderr。
///
/// `runtime.Point` 是 0-indexed，显示时自动 +1 转为 1-indexed。
/// - `file`：（可选）输入文件路径
/// - `source`：（可选）文件全文，用于显示源码行高亮
pub fn report_parse_error(
  err : @runtime.ParseError,
  file : String?,
  source : String?,
) -> Unit {
  let p = err.point
  // runtime.Point 是 0-indexed，转为 1-indexed 显示
  let line = p.row + 1
  let col = p.column + 1
  let tag = ansi_red("error")
  let msg = ansi_bold(err.message)
  print_err("\{tag}: \{msg}")
  match file {
    None => ()
    Some(path) => print_err(loc_line(path, line, col))
  }
  match (file, source) {
    (Some(_), Some(src)) =>
      print_err(render_source_snippet(src, line, col, Some(err.message)))
    _ => ()
  }
}

///|
/// 打印 Query 编译错误到 stderr。
///
/// `pattern`：（可选）原始查询模式字符串，用于显示错误位置插入符。
pub fn report_query_error(err : @query.QueryError, pattern : String?) -> Unit {
  match err {
    ParseError(offset, msg) => {
      let tag = ansi_red("error")
      let bold_msg = ansi_bold(msg)
      print_err("\{tag}: \{bold_msg}")
      match pattern {
        None => ()
        Some(pat) => {
          let arrow = ansi_cyan("-->")
          print_err("  \{arrow} query pattern at offset \{offset}")
          // 显示模式字符串与偏移量插入符
          if offset >= 0 && offset <= pat.length() {
            let caret = ansi_red("^")
            let label_str = " " + ansi_red(msg)
            let indent = spaces(offset)
            print_err("  \{pat}")
            print_err("  \{indent}\{caret}\{label_str}")
          }
        }
      }
    }
  }
}

///|
/// 打印诊断汇总行到 stderr，例如 `"2 errors, 1 warning"`。
/// 若 errors 和 warnings 均为 0 则不输出任何内容。
pub fn report_summary(errors : Int, warnings : Int) -> Unit {
  if errors == 0 && warnings == 0 {
    return
  }
  let parts : Array[String] = []
  if errors > 0 {
    let noun = if errors == 1 { "error" } else { "errors" }
    parts.push(ansi_red("\{errors} \{noun}"))
  }
  if warnings > 0 {
    let noun = if warnings == 1 { "warning" } else { "warnings" }
    parts.push(ansi_yellow("\{warnings} \{noun}"))
  }
  print_err(parts.join(", "))
}
