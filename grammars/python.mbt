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
pub let python_grammar : String =
  #|start module
  #|extras [/[ \t]+/, /#[^\n\r]*/]
  #|externals [indent dedent newline]
  #|rule module: (newline | statement)*
  #|rule statement: compound_statement newline* | simple_statement newline*
  #|rule simple_statement: import_statement | return_statement | pass_statement | break_statement | continue_statement | raise_statement | del_statement | global_statement | nonlocal_statement | assert_statement | augmented_assign_statement | assign_statement | expression_statement
  #|rule compound_statement: if_statement | while_statement | for_statement | decorated_statement | try_statement | with_statement
  #|rule import_statement: "import" import_alias ("," import_alias)* | "from" dotted_name "import" import_targets
  #|rule import_alias: dotted_name ("as" identifier)?
  #|rule import_targets: "*" | import_as_item ("," import_as_item)*
  #|rule import_as_item: identifier ("as" identifier)?
  #|rule return_statement: "return" expression_list?
  #|rule pass_statement: "pass"
  #|rule break_statement: "break"
  #|rule continue_statement: "continue"
  #|rule raise_statement: "raise" expression? ("from" expression)?
  #|rule del_statement: "del" expression ("," expression)*
  #|rule global_statement: "global" identifier ("," identifier)*
  #|rule nonlocal_statement: "nonlocal" identifier ("," identifier)*
  #|rule assert_statement: "assert" expression ("," expression)?
  #|rule assign_statement: target ("," target)* ","? (":" type_hint)? "=" expression
  #|rule augmented_assign_statement: target augmented_operator expression
  #|rule augmented_operator: "+=" | "-=" | "*=" | "/=" | "%=" | "**=" | "//=" | "&=" | "|=" | "^=" | "<<=" | ">>="
  #|rule expression_statement: expression
  #|rule target: identifier | postfix_expression | "*" identifier
  #|rule if_statement: "if" expression ":" suite ("elif" expression ":" suite)* ("else" ":" suite)?
  #|rule while_statement: "while" expression ":" suite
  #|rule for_statement: "for" for_target "in" expression ":" suite
  #|rule for_target: identifier ("," identifier)*
  #|rule def_statement: "def" identifier "(" parameter_list? ")" return_hint? ":" suite
  #|rule class_statement: "class" identifier ("(" argument_list? ")")? ":" suite
  #|rule try_statement: "try" ":" suite except_clause* ("else" ":" suite)? ("finally" ":" suite)?
  #|rule except_clause: "except" exception_spec? ":" suite
  #|rule exception_spec: expression ("as" identifier)?
  #|rule with_statement: "with" with_item ("," with_item)* ":" suite
  #|rule with_item: expression ("as" target)?
  #|rule async_def_statement: "async" "def" identifier "(" parameter_list? ")" return_hint? ":" suite
  #|rule suite: simple_statement | newline indent statement+ dedent
  #|rule return_hint: "->" type_hint
  #|rule type_hint: dotted_name ("[" type_hint ("," type_hint)* "]")?
  #|rule parameter_list: parameter_item ("," parameter_item)* ("," "/" ("," parameter_item)*)?
  #|rule parameter_item: "**" identifier | "*" identifier? | identifier (":" type_hint)? ("=" expression)?
  #|rule dotted_name: identifier ("." identifier)*
  #|rule expression: lambda_expression | yield_expression | named_expression | conditional_expression
  #|rule lambda_expression: "lambda" parameter_names? ":" expression
  #|rule parameter_names: identifier ("," identifier)*
  #|rule conditional_expression: or_expression ("if" or_expression "else" expression)?
  #|rule or_expression: and_expression ("or" and_expression)*
  #|rule and_expression: not_expression ("and" not_expression)*
  #|rule not_expression: "not" not_expression | comparison_expression
  #|rule comparison_expression: bitwise_or_expression (comparison_operator bitwise_or_expression)*
  #|rule comparison_operator: "==" | "!=" | "<" | ">" | "<=" | ">=" | "in" | "not" "in" | "is" "not" | "is"
  #|rule bitwise_or_expression: bitwise_xor_expression ("|" bitwise_xor_expression)*
  #|rule bitwise_xor_expression: bitwise_and_expression ("^" bitwise_and_expression)*
  #|rule bitwise_and_expression: shift_expression ("&" shift_expression)*
  #|rule shift_expression: additive_expression (("<<" | ">>") additive_expression)*
  #|rule additive_expression: multiplicative_expression (("+" | "-") multiplicative_expression)*
  #|rule multiplicative_expression: power_expression (("*" | "/" | "%" | "//") power_expression)*
  #|rule power_expression: unary_expression ("**" unary_expression)?
  #|rule unary_expression: postfix_expression | await_expression | ("+" | "-" | "~") unary_expression
  #|rule postfix_expression: primary_expression postfix_suffix*
  #|rule postfix_suffix: "(" argument_list? ")" | "[" subscript "]" | "." identifier
  #|rule subscript: slice | expression
  #|rule slice: expression? ":" expression? (":" expression?)?
  #|rule argument_list: argument_item ("," argument_item)*
  #|rule argument_item: "**" expression | "*" expression | identifier "=" expression | expression
  #|rule primary_expression: literal | identifier | tuple_literal | list_literal | set_literal | dict_literal | "(" expression ")"
  #|rule tuple_literal: "(" expression ("," expression)* "," ")"
  #|rule list_literal: "[" expression_list? "]" | "[" expression comp_clause+ "]"
  #|rule set_literal: "{" expression ("," expression)* ","? "}" | "{" expression comp_clause+ "}"
  #|rule dict_literal: "{" dict_item ("," dict_item)* ","? "}" | "{" "}" | "{" dict_item comp_clause+ "}"
  #|rule dict_item: expression ":" expression
  #|rule expression_list: expression ("," expression)*
  #|rule literal: number_literal | string_literal | "True" | "False" | "None" | "..."
  #|rule identifier: /[A-Za-z_][A-Za-z0-9_]*/
  #|rule number_literal: /0[xX][0-9a-fA-F][0-9a-fA-F_]*|0[bB][01][01_]*|0[oO][0-7][0-7_]*|[0-9][0-9_]*(\.[0-9][0-9_]*)?([eE][+-]?[0-9]+)?[jJ]?/
  #|rule string_literal: /(r|b|rb|br|f|fr|rf|R|B|RB|BR|F|FR|RF)?("""([^"\\]|\\.)*"""|'''([^'\\]|\\.)*'''|"([^"\\]|\\.)*"|'([^'\\]|\\.)*')/
  #|rule comp_clause: "for" for_target "in" or_expression ("if" or_expression)*
  #|rule decorated_statement: decorator* (def_statement | class_statement | async_def_statement)
  #|rule decorator: "@" dotted_name ("(" argument_list? ")")? newline
  #|rule yield_expression: "yield" "from" expression | "yield" expression?
  #|rule await_expression: "await" unary_expression
  #|rule named_expression: identifier ":=" expression

///|
let python_table : @tablegen.ParseTable = compile_builtin_grammar(
  python_grammar,
)

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
  while i < pos {
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
impl @runtime.StatefulScanner for PythonIndentScanner with scan(
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
impl @runtime.StatefulScanner for PythonIndentScanner with clone_scanner(self) {
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
    } : PythonIndentScanner)
  as &@runtime.StatefulScanner
}
