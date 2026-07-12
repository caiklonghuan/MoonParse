///|
// Python 语法定义（行级核心子集）。
//
// 覆盖：
//   - def / class / if / while / for
//   - import / from-import（含 as 别名）/ return / pass / break / continue
//   - raise / del / global / nonlocal / assert / augmented assign
//   - try/except/finally / with / async def
//   - 常见表达式、调用、索引、属性访问、列表 / 字典 / 集合字面量
//   - 幂运算 **、位运算 & | ^ ~ << >>、三元表达式 a if c else b
//   - 切片 a[1:3]、单元素元组 (x,)、省略号 ...
//   - 数字字面量（十六进制/二进制/八进制/浮点/复数）、多前缀字符串（r/b/f/三重引号）
//   - 仅位置参数分隔符 /
//   - 缩进块以"整行缩进文本"方式收集，优先保证标准库示例可稳定解析

///|

///|
pub let python_grammar : String = builtin_python_pack.grammar_source

///|
let python_table : @tablegen.ParseTable = builtin_python_bundle.table

///|
pub fn parse_python(
  source : String,
) -> Result[@runtime.CstNode, @runtime.ParseError] {
  @runtime.parse_with_stateful_scanner(
    python_table,
    source,
    python_indent_scanner(python_table),
  )
}

///|
pub fn python_indent_scanner(
  table : @tablegen.ParseTable,
) -> &@runtime.StatefulScanner {
  PythonIndentScanner::new(table) as &@runtime.StatefulScanner
}

///|
pub fn python_sexp(source : String) -> String {
  match parse_python(source) {
    Ok(node) => cst_to_sexp(node, source, python_table)
    Err(_) => "(ERROR)"
  }
}

///|
/// 将 Python 源码解析后，以缩进树形格式输出 CST。
pub fn python_tree(source : String) -> String {
  match parse_python(source) {
    Ok(node) => cst_to_tree(node, source, python_table)
    Err(e) => "(ERROR: " + e.message + ")"
  }
}

///|
/// Python 缩进扫描器 — 实现 StatefulScanner，追踪缩进栈以发射 INDENT/DEDENT。
pub struct PythonIndentScanner {
  indent_id : Int
  dedent_id : Int
  newline_id : Int
  indent_stack : Array[Int]
  mut pending_dedents : Int
  mut emitted_eof_newline : Bool
}

///|
pub fn PythonIndentScanner::new(
  table : @tablegen.ParseTable,
) -> PythonIndentScanner {
  // externals [indent dedent newline] → indices 0, 1, 2
  {
    indent_id: table.external_token_ids[0],
    dedent_id: table.external_token_ids[1],
    newline_id: table.external_token_ids[2],
    indent_stack: [0],
    pending_dedents: 0,
    emitted_eof_newline: false,
  }
}

///|
/// 测量 input 中 pos 所在行的缩进列数。
/// extras 已经跳过了行首空白，pos 指向第一个非空白字符，
/// 因此从行首到 pos 之间的字符全部是空白。
fn measure_indent(input : String, pos : Int) -> Int {
  if pos >= input.length() {
    return 0 // EOF → 回到基础缩进
  }
  // 向后扫描找到行首
  let mut line_start = pos
  while line_start > 0 {
    let prev = input[line_start - 1]
    if prev == '\n' || prev == '\r' {
      break
    }
    line_start = line_start - 1
  }
  // 计算行首到 pos 的空白字符数
  let mut indent = 0
  let mut i = line_start
  while i < input.length() {
    let ch = input[i]
    if ch == ' ' || ch == '\t' || ch == '\u000C' {
      indent = indent + 1
    } else {
      break
    }
    i = i + 1
  }
  indent
}

///|
fn has_tid(tids : Array[Int], target : Int) -> Bool {
  for tid in tids {
    if tid == target {
      return true
    }
  }
  false
}

///|
impl @runtime.StatefulScanner for PythonIndentScanner with fn scan(
  self,
  input,
  pos,
  ext_tids,
) {
  // 1. 优先发射挂起的 DEDENT
  if self.pending_dedents > 0 {
    if has_tid(ext_tids, self.dedent_id) {
      self.pending_dedents = self.pending_dedents - 1
      return Some((self.dedent_id, pos)) // 零宽
    }
    return None
  }
  // 2. 尝试匹配换行符
  if has_tid(ext_tids, self.newline_id) && pos < input.length() {
    let ch = input[pos]
    if ch == '\r' {
      let end = if pos + 1 < input.length() && input[pos + 1] == '\n' {
        pos + 2
      } else {
        pos + 1
      }
      return Some((self.newline_id, end))
    }
    if ch == '\n' {
      return Some((self.newline_id, pos + 1))
    }
  }
  // 3. 检测 INDENT / DEDENT
  if has_tid(ext_tids, self.newline_id) &&
    pos >= input.length() &&
    !self.emitted_eof_newline {
    self.emitted_eof_newline = true
    return Some((self.newline_id, pos))
  }
  let check_indent = has_tid(ext_tids, self.indent_id)
  let check_dedent = has_tid(ext_tids, self.dedent_id)
  if check_indent || check_dedent {
    let indent = measure_indent(input, pos)
    let current = self.indent_stack[self.indent_stack.length() - 1]
    if check_indent && indent > current {
      self.indent_stack.push(indent)
      return Some((self.indent_id, pos)) // 零宽
    }
    if check_dedent && indent < current {
      // 弹出所有超过 indent 的层级
      while self.indent_stack.length() > 1 &&
            self.indent_stack[self.indent_stack.length() - 1] > indent {
        let _ = self.indent_stack.pop()
        self.pending_dedents = self.pending_dedents + 1
      }
      if self.pending_dedents > 0 {
        self.pending_dedents = self.pending_dedents - 1
        return Some((self.dedent_id, pos))
      }
    }
  }
  None
}

///|
impl @runtime.StatefulScanner for PythonIndentScanner with fn clone_scanner(
  self,
) {
  let new_stack : Array[Int] = Array::new(capacity=self.indent_stack.length())
  for v in self.indent_stack {
    new_stack.push(v)
  }
  (
    {
      indent_id: self.indent_id,
      dedent_id: self.dedent_id,
      newline_id: self.newline_id,
      indent_stack: new_stack,
      pending_dedents: self.pending_dedents,
      emitted_eof_newline: self.emitted_eof_newline,
    } : PythonIndentScanner)
  as &@runtime.StatefulScanner
}
