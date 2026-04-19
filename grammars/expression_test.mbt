///|
// expression_test.mbt — expression grammar 完整测试套件
//
// 覆盖：
//   §1.1  结构正确性（根节点类型、无 ERROR、命名节点存在）
//   §1.2  Golden/Snapshot（运算符优先级、括号、左结合）
//   §1.3  位置一致性（span 有序、根节点覆盖全部输入）
//   §3.3  Grammar Stress Test（超长链、超多参数）
//   §6.1  非语法随机 fuzz（不崩溃稳定性）
//   §6.2  语法引导 fuzz（合法表达式必须解析成功）
//   §6.3  变异式 fuzz（不崩溃 + 增量结果等于全量重解析）
//
// 文件布局：
//   A. 基础辅助函数
//   B. 随机/Fuzz 基础设施（LCG 随机数、随机文本生成器）
//   C. 语法引导表达式生成器
//   D. 变异基础设施（token 扫描器、变异构造器）
//   E. 断言辅助函数
//   F. 测试（按 §1.1 → §1.2 → §1.3 → §3.3 → §6.1 → §6.2 → §6.3 排列）

// ============================================================
// A. 基础辅助函数
// ============================================================

///|
/// 辅助：解析表达式并断言无顶层错误
fn parse_expr_ok(source : String) -> @runtime.CstNode {
  match @grammars.parse_expression(source) {
    Ok(node) => node
    Err(e) => {
      println("parse_expression failed: \{e.message}")
      panic()
    }
  }
}

///|
fn additive_chain(count : Int) -> String {
  let parts : Array[String] = []
  for _ in 0..<count {
    parts.push("n")
  }
  parts.join("+")
}

///|
fn unary_chain(depth : Int) -> String {
  let buf = StringBuilder::new()
  for i in 0..<depth {
    match i % 3 {
      0 => buf.write_char('!')
      1 => buf.write_char('-')
      _ => buf.write_char('+')
    }
  }
  buf.write_char('n')
  buf.to_string()
}

///|
fn call_with_many_args(width : Int) -> String {
  let args : Array[String] = []
  for i in 0..<width {
    args.push("n" + i.to_string())
  }
  "f(" + args.join(", ") + ")"
}

// ============================================================
// B. 随机 / Fuzz 基础设施
// ============================================================

///|
fn expr_fuzz_next_seed(seed : Int) -> Int {
  let next = (seed * 48271 + 1) % 2147483647
  if next <= 0 {
    next + 2147483646
  } else {
    next
  }
}

///|
fn expr_fuzz_pick(seed : Int, modulo : Int) -> (Int, Int) {
  let next = expr_fuzz_next_seed(seed)
  (next, next % modulo)
}

///|
fn expr_repeat_fragment(fragment : String, count : Int) -> String {
  let buf = StringBuilder::new()
  for _ in 0..<count {
    buf.write_string(fragment)
  }
  buf.to_string()
}

///|
fn expr_random_ascii(seed : Int, length : Int) -> (Int, String) {
  let buf = StringBuilder::new()
  let mut cur = seed
  for _ in 0..<length {
    let (next, code) = expr_fuzz_pick(cur, 95)
    cur = next
    buf.write_char((32 + code).to_char().unwrap())
  }
  (cur, buf.to_string())
}

///|
fn expr_random_utf8_text(seed : Int, length : Int) -> (Int, String) {
  let palette = [
    "\u4f60", "\u597d", "\u6708", "\u5149", "foo", "bar", " ", "(", ")", "+", "*",
  ]
  let buf = StringBuilder::new()
  let mut cur = seed
  for _ in 0..<length {
    let (next, index) = expr_fuzz_pick(cur, palette.length())
    cur = next
    buf.write_string(palette[index])
  }
  (cur, buf.to_string())
}

///|
fn expr_random_control_text(seed : Int, length : Int) -> (Int, String) {
  let buf = StringBuilder::new()
  let mut cur = seed
  for _ in 0..<length {
    let (next, kind) = expr_fuzz_pick(cur, 8)
    cur = next
    match kind {
      0 => buf.write_char('\n')
      1 => buf.write_char('\t')
      2 => buf.write_char('\r')
      3 => {
        let (next, code) = expr_fuzz_pick(cur, 32)
        cur = next
        buf.write_char(code.to_char().unwrap())
      }
      _ => {
        let (next, code) = expr_fuzz_pick(cur, 95)
        cur = next
        buf.write_char((32 + code).to_char().unwrap())
      }
    }
  }
  (cur, buf.to_string())
}

///|
fn expr_random_layout_noise(seed : Int, count : Int) -> (Int, String) {
  let fragments = [
    "(", ")", "+", "-", "*", "/", "%", "!", ",", "foo", "0", "\n", "\r\n", "\t",
    " \n ",
  ]
  let buf = StringBuilder::new()
  let mut cur = seed
  for _ in 0..<count {
    let (next, index) = expr_fuzz_pick(cur, fragments.length())
    cur = next
    buf.write_string(fragments[index])
  }
  (cur, buf.to_string())
}

///|
fn check_expr_any_input_stable(label : String, input : String) -> Unit {
  let sexp = @grammars.expression_sexp(input)
  if sexp.is_empty() {
    println("\{label}: expression_sexp returned empty output")
    panic()
  }
  if !sexp.has_prefix("(expression") && !sexp.has_prefix("ERROR: ") {
    println("\{label}: unexpected expression_sexp prefix: \{sexp}")
    panic()
  }
  match @grammars.parse_expression(input) {
    Ok(root) => {
      @grammars.assert_cst_invariants(root, input, "root")
      if root.end_byte > input.length() {
        println(
          "\{label}: root.end_byte out of range: \{root.end_byte} > \{input.length()}",
        )
        panic()
      }
    }
    Err(e) =>
      if e.message.is_empty() {
        println("\{label}: parse returned empty error message")
        panic()
      }
  }
}

// ============================================================
// C. 语法引导表达式生成器
// ============================================================

///|
fn expr_guided_ws(seed : Int) -> (Int, String) {
  let gaps = ["", " ", "\t", "\n", " \n "]
  let (next, index) = expr_fuzz_pick(seed, gaps.length())
  (next, gaps[index])
}

///|
fn expr_guided_identifier(seed : Int) -> (Int, String) {
  let starts = ["n", "foo", "bar", "_tmp", "value", "arg", "X"]
  let suffixes = ["", "0", "1", "_x", "_2", "Beta", "42"]
  let (next, start_index) = expr_fuzz_pick(seed, starts.length())
  let (next, suffix_index) = expr_fuzz_pick(next, suffixes.length())
  (next, starts[start_index] + suffixes[suffix_index])
}

///|
fn expr_guided_decimal_digits(seed : Int, count : Int) -> (Int, String) {
  let buf = StringBuilder::new()
  let mut cur = seed
  for _ in 0..<count {
    let (next, digit) = expr_fuzz_pick(cur, 10)
    cur = next
    buf.write_char(('0'.to_int() + digit).to_char().unwrap())
  }
  (cur, buf.to_string())
}

///|
fn expr_guided_hex_digits(seed : Int, count : Int) -> (Int, String) {
  let digits = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let buf = StringBuilder::new()
  let mut cur = seed
  for _ in 0..<count {
    let (next, index) = expr_fuzz_pick(cur, digits.length())
    cur = next
    buf.write_char(digits[index])
  }
  (cur, buf.to_string())
}

///|
fn expr_guided_number(seed : Int) -> (Int, String) {
  let (next, kind) = expr_fuzz_pick(seed, 5)
  match kind {
    0 => {
      let (next, digits) = expr_guided_decimal_digits(next, 1 + kind % 3 + 1)
      (next, digits)
    }
    1 => {
      let (next, int_part) = expr_guided_decimal_digits(next, 1 + kind % 3 + 1)
      let (next, frac_part) = expr_guided_decimal_digits(next, 2)
      (next, int_part + "." + frac_part)
    }
    2 => {
      let (next, frac_part) = expr_guided_decimal_digits(next, 2)
      (next, "." + frac_part)
    }
    3 => {
      let (next, int_part) = expr_guided_decimal_digits(next, 2)
      let (next, sign_pick) = expr_fuzz_pick(next, 3)
      let (next, exp_part) = expr_guided_decimal_digits(next, 2)
      let sign = match sign_pick {
        0 => "+"
        1 => "-"
        _ => ""
      }
      (next, int_part + "e" + sign + exp_part)
    }
    _ => {
      let (next, hex_part) = expr_guided_hex_digits(next, 3)
      (next, "0x" + hex_part)
    }
  }
}

///|
fn expr_guided_string(seed : Int, max_units : Int) -> (Int, String) {
  let raw_units = ["a", "b", "Z", "0", "_", " "]
  let escaped_units = ["\\n", "\\t", "\\\"", "\\\\"]
  let (next, count_pick) = expr_fuzz_pick(seed, max_units + 1)
  let buf = StringBuilder::new()
  let mut cur = next
  buf.write_char('"')
  for _ in 0..<count_pick {
    let (next, kind) = expr_fuzz_pick(cur, 4)
    cur = next
    if kind == 0 {
      let (next, index) = expr_fuzz_pick(cur, escaped_units.length())
      cur = next
      buf.write_string(escaped_units[index])
    } else {
      let (next, index) = expr_fuzz_pick(cur, raw_units.length())
      cur = next
      buf.write_string(raw_units[index])
    }
  }
  buf.write_char('"')
  (cur, buf.to_string())
}

///|
fn expr_guided_atom_kind(seed : Int, kind : Int) -> (Int, String) {
  match kind {
    0 => expr_guided_identifier(seed)
    1 => expr_guided_number(seed)
    _ => expr_guided_string(seed, 4)
  }
}

///|
fn expr_guided_parenthesized(
  seed : Int,
  depth : Int,
  width : Int,
) -> (Int, String) {
  let (next, before) = expr_guided_ws(seed)
  let (next, inner) = expr_guided_expr(next, depth - 1, width)
  let (next, after) = expr_guided_ws(next)
  (next, "(" + before + inner + after + ")")
}

///|
fn expr_guided_call(seed : Int, depth : Int, width : Int) -> (Int, String) {
  let (next, callee_kind) = expr_fuzz_pick(seed, 2)
  let (next, callee) = match callee_kind {
    0 => expr_guided_identifier(next)
    _ => expr_guided_parenthesized(next, depth - 1, width)
  }
  let (next, argc_pick) = expr_fuzz_pick(next, width + 1)
  let args : Array[String] = []
  let mut cur = next
  for _ in 0..<argc_pick {
    let (next, arg) = expr_guided_expr(cur, depth - 1, width)
    cur = next
    args.push(arg)
  }
  let (cur, gap) = expr_guided_ws(cur)
  (cur, callee + "(" + gap + args.join(", ") + gap + ")")
}

///|
fn expr_guided_unary(seed : Int, depth : Int, width : Int) -> (Int, String) {
  let ops = ["-", "+", "!"]
  let (next, op_index) = expr_fuzz_pick(seed, ops.length())
  let (next, gap) = expr_guided_ws(next)
  let (next, inner_kind) = expr_fuzz_pick(next, 6)
  let (next, inner) = if depth <= 1 {
    expr_guided_atom_kind(next, inner_kind % 3)
  } else {
    expr_guided_expr_kind(next, inner_kind, depth - 1, width)
  }
  (next, ops[op_index] + gap + inner)
}

///|
fn expr_guided_operand(seed : Int, depth : Int, width : Int) -> (Int, String) {
  let (next, kind) = expr_fuzz_pick(seed, if depth <= 0 { 3 } else { 6 })
  if depth <= 0 {
    expr_guided_atom_kind(next, kind)
  } else {
    match kind {
      0 => expr_guided_identifier(next)
      1 => expr_guided_number(next)
      2 => expr_guided_string(next, width + 2)
      3 => expr_guided_unary(next, depth, width)
      4 => expr_guided_call(next, depth, width)
      _ => expr_guided_parenthesized(next, depth, width)
    }
  }
}

///|
fn expr_guided_binary(seed : Int, depth : Int, width : Int) -> (Int, String) {
  let ops = ["+", "-", "*", "/", "%"]
  let (next, count_pick) = expr_fuzz_pick(seed, width + 1)
  let count = count_pick + 2
  let (next, first) = expr_guided_operand(next, depth - 1, width)
  let buf = StringBuilder::new()
  let mut cur = next
  buf.write_string(first)
  for _ in 1..<count {
    let (next, before_op) = expr_guided_ws(cur)
    let (next, op_index) = expr_fuzz_pick(next, ops.length())
    let (next, after_op) = expr_guided_ws(next)
    let (next, rhs) = expr_guided_operand(next, depth - 1, width)
    cur = next
    buf.write_string(before_op)
    buf.write_string(ops[op_index])
    buf.write_string(after_op)
    buf.write_string(rhs)
  }
  let (cur, wrap_pick) = expr_fuzz_pick(cur, 3)
  if wrap_pick == 0 {
    (cur, "(" + buf.to_string() + ")")
  } else {
    (cur, buf.to_string())
  }
}

///|
fn expr_guided_expr_kind(
  seed : Int,
  kind : Int,
  depth : Int,
  width : Int,
) -> (Int, String) {
  if depth <= 0 && kind >= 3 {
    return expr_guided_atom_kind(seed, kind % 3)
  }
  match kind {
    0 => expr_guided_identifier(seed)
    1 => expr_guided_number(seed)
    2 => expr_guided_string(seed, width + 2)
    3 => expr_guided_unary(seed, depth, width)
    4 => expr_guided_binary(seed, depth, width)
    5 => expr_guided_call(seed, depth, width)
    _ => expr_guided_parenthesized(seed, depth, width)
  }
}

///|
fn expr_guided_expr(seed : Int, depth : Int, width : Int) -> (Int, String) {
  let (next, kind) = expr_fuzz_pick(seed, 7)
  expr_guided_expr_kind(next, kind, depth, width)
}

// ============================================================
// E. 断言辅助函数
// ============================================================

///|
fn assert_expr_guided_parse(label : String, input : String) -> Unit {
  match @grammars.parse_expression(input) {
    Ok(root) => {
      @grammars.assert_cst_invariants(root, input, "root")
      if root.start_byte != 0 || root.end_byte != input.length() {
        println(
          "\{label}: expected root span [0, \{input.length()}) got [\{root.start_byte}, \{root.end_byte}) for \{input.escape()}",
        )
        panic()
      }
      let sexp = @grammars.expression_sexp(input)
      if sexp.contains("ERROR") || !sexp.has_prefix("(expression") {
        println(
          "\{label}: guided expression should parse cleanly for \{input.escape()}, got \{sexp}",
        )
        panic()
      }
    }
    Err(e) => {
      println(
        "\{label}: generated invalid expression \{input.escape()} -> \{e.message}",
      )
      panic()
    }
  }
}

// ============================================================
// D. 变异基础设施（token 扫描器、变异构造器）
// ============================================================

///|
priv struct ExprToken {
  start_byte : Int
  end_byte : Int
  kind : Int
}

///|
priv struct ExprMutation {
  name : String
  start_byte : Int
  old_end_byte : Int
  replacement : String
}

///|
fn expr_make_table() -> @tablegen.ParseTable {
  let grammar = match @grammar.parse_grammar(@grammars.expression_grammar) {
    @grammar.Success(grammar) => grammar
    @grammar.Error(e) => {
      println("expr_make_table: parse_grammar failed: \{e.message}")
      panic()
    }
  }
  match @tablegen.generate_parse_table(grammar) {
    Ok((table, _)) => table
    Err(e) => {
      println("expr_make_table: generate_parse_table failed: \{e}")
      panic()
    }
  }
}

///|
fn expr_point_at(input : String, pos : Int) -> @runtime.Point {
  @runtime.bytes_to_point(input, 0, { row: 0, column: 0 }, pos)
}

///|
fn expr_replace_range(
  old_input : String,
  start_byte : Int,
  old_end_byte : Int,
  replacement : String,
) -> String {
  old_input[0:start_byte].to_string() +
  replacement +
  old_input[old_end_byte:old_input.length()].to_string()
}

///|
fn expr_make_edit_from_replacement(
  old_input : String,
  start_byte : Int,
  old_end_byte : Int,
  replacement : String,
) -> (String, @runtime.InputEdit) {
  let new_input = expr_replace_range(
    old_input, start_byte, old_end_byte, replacement,
  )
  let new_end_byte = start_byte + replacement.length()
  let edit : @runtime.InputEdit = {
    start_byte,
    old_end_byte,
    new_end_byte,
    start_point: expr_point_at(old_input, start_byte),
    old_end_point: expr_point_at(old_input, old_end_byte),
    new_end_point: expr_point_at(new_input, new_end_byte),
  }
  (new_input, edit)
}

///|
fn expr_byte_at(input : String, pos : Int) -> Char {
  input[pos].to_int().to_char().unwrap()
}

///|
fn expr_is_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r'
}

///|
fn expr_is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn expr_is_hex_digit(ch : Char) -> Bool {
  expr_is_digit(ch) || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')
}

///|
fn expr_is_ident_start(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

///|
fn expr_is_ident_continue(ch : Char) -> Bool {
  expr_is_ident_start(ch) || expr_is_digit(ch)
}

///|
fn expr_starts_number(input : String, start_byte : Int) -> Bool {
  let ch = expr_byte_at(input, start_byte)
  expr_is_digit(ch) ||
  (
    ch == '.' &&
    start_byte + 1 < input.length() &&
    expr_is_digit(expr_byte_at(input, start_byte + 1))
  )
}

///|
fn expr_scan_string_end(input : String, start_byte : Int) -> Int {
  let mut i = start_byte + 1
  while i < input.length() {
    let ch = expr_byte_at(input, i)
    if ch == '\\' {
      if i + 1 >= input.length() {
        return input.length()
      }
      i = i + 2
    } else if ch == '"' {
      return i + 1
    } else {
      i = i + 1
    }
  }
  input.length()
}

///|
fn expr_scan_number_end(input : String, start_byte : Int) -> Int {
  let mut i = start_byte
  let first = expr_byte_at(input, start_byte)
  if first == '0' && i + 1 < input.length() {
    let second = expr_byte_at(input, i + 1)
    if second == 'x' || second == 'X' {
      i = i + 2
      while i < input.length() && expr_is_hex_digit(expr_byte_at(input, i)) {
        i = i + 1
      }
      return i
    }
  }
  if first == '.' {
    i = i + 1
    while i < input.length() && expr_is_digit(expr_byte_at(input, i)) {
      i = i + 1
    }
  } else {
    while i < input.length() && expr_is_digit(expr_byte_at(input, i)) {
      i = i + 1
    }
    if i < input.length() && expr_byte_at(input, i) == '.' {
      i = i + 1
      while i < input.length() && expr_is_digit(expr_byte_at(input, i)) {
        i = i + 1
      }
    }
  }
  if i < input.length() {
    let ch = expr_byte_at(input, i)
    if ch == 'e' || ch == 'E' {
      i = i + 1
      if i < input.length() {
        let sign = expr_byte_at(input, i)
        if sign == '+' || sign == '-' {
          i = i + 1
        }
      }
      while i < input.length() && expr_is_digit(expr_byte_at(input, i)) {
        i = i + 1
      }
    }
  }
  i
}

///|
fn expr_collect_tokens(input : String) -> Array[ExprToken] {
  let tokens : Array[ExprToken] = []
  let mut i = 0
  while i < input.length() {
    let ch = expr_byte_at(input, i)
    if expr_is_space(ch) {
      i = i + 1
    } else if expr_is_ident_start(ch) {
      let start_byte = i
      i = i + 1
      while i < input.length() && expr_is_ident_continue(expr_byte_at(input, i)) {
        i = i + 1
      }
      tokens.push({ start_byte, end_byte: i, kind: 1 })
    } else if expr_starts_number(input, i) {
      let end_byte = expr_scan_number_end(input, i)
      tokens.push({ start_byte: i, end_byte, kind: 2 })
      i = end_byte
    } else if ch == '"' {
      let end_byte = expr_scan_string_end(input, i)
      tokens.push({ start_byte: i, end_byte, kind: 3 })
      i = end_byte
    } else if ch == '(' ||
      ch == ')' ||
      ch == ',' ||
      ch == '+' ||
      ch == '-' ||
      ch == '*' ||
      ch == '/' ||
      ch == '%' ||
      ch == '!' {
      tokens.push({ start_byte: i, end_byte: i + 1, kind: 0 })
      i = i + 1
    } else {
      i = i + 1
    }
  }
  tokens
}

///|
fn expr_mutation_garbage(seed : Int) -> (Int, String) {
  let fragments = ["@", "$$", "??", "\n#\t", "/*", ")]", "\r\n!"]
  let (next, index) = expr_fuzz_pick(seed, fragments.length())
  (next, fragments[index])
}

///|
fn expr_token_replacement(
  seed : Int,
  input : String,
  token : ExprToken,
) -> (Int, String) {
  let current = input[token.start_byte:token.end_byte].to_string()
  match token.kind {
    0 => {
      let replacement = match current {
        "(" => "]"
        ")" => "{"
        "," => "+"
        "+" => "-"
        "-" => "%"
        "*" => "/"
        "/" => "*"
        "%" => "+"
        _ => ","
      }
      (seed, replacement)
    }
    1 => {
      let (next, replacement) = expr_guided_identifier(seed)
      if replacement == current {
        (next, "mutVar")
      } else {
        (next, replacement)
      }
    }
    2 => {
      let (next, replacement) = expr_guided_number(seed)
      if replacement == current {
        (next, "1")
      } else {
        (next, replacement)
      }
    }
    _ => {
      let (next, replacement) = expr_guided_string(seed, 3)
      if replacement == current {
        (next, "\"mut\"")
      } else {
        (next, replacement)
      }
    }
  }
}

///|
fn expr_delete_char_mutation(seed : Int, input : String) -> (Int, ExprMutation) {
  let (next, start_byte) = expr_fuzz_pick(seed, input.length())
  (
    next,
    {
      name: "delete-char",
      start_byte,
      old_end_byte: start_byte + 1,
      replacement: "",
    },
  )
}

///|
fn expr_delete_token_mutation(
  seed : Int,
  input : String,
) -> (Int, ExprMutation) {
  let tokens = expr_collect_tokens(input)
  if tokens.is_empty() {
    return expr_delete_char_mutation(seed, input)
  }
  let (next, index) = expr_fuzz_pick(seed, tokens.length())
  let token = tokens[index]
  (
    next,
    {
      name: "delete-token",
      start_byte: token.start_byte,
      old_end_byte: token.end_byte,
      replacement: "",
    },
  )
}

///|
fn expr_replace_token_mutation(
  seed : Int,
  input : String,
) -> (Int, ExprMutation) {
  let tokens = expr_collect_tokens(input)
  if tokens.is_empty() {
    return expr_delete_char_mutation(seed, input)
  }
  let (next, index) = expr_fuzz_pick(seed, tokens.length())
  let token = tokens[index]
  let (next, replacement) = expr_token_replacement(next, input, token)
  (
    next,
    {
      name: "replace-token",
      start_byte: token.start_byte,
      old_end_byte: token.end_byte,
      replacement,
    },
  )
}

///|
fn expr_scramble_paren_mutation(
  seed : Int,
  input : String,
) -> (Int, ExprMutation) {
  let positions : Array[Int] = []
  for i in 0..<input.length() {
    let ch = expr_byte_at(input, i)
    if ch == '(' || ch == ')' {
      positions.push(i)
    }
  }
  if positions.is_empty() {
    return expr_replace_token_mutation(seed, input)
  }
  let (next, index) = expr_fuzz_pick(seed, positions.length())
  let start_byte = positions[index]
  let replacement = match expr_byte_at(input, start_byte) {
    '(' => "]"
    _ => "{"
  }
  (
    next,
    {
      name: "scramble-paren",
      start_byte,
      old_end_byte: start_byte + 1,
      replacement,
    },
  )
}

///|
fn expr_insert_garbage_mutation(
  seed : Int,
  input : String,
) -> (Int, ExprMutation) {
  let (next, start_byte) = expr_fuzz_pick(seed, input.length() + 1)
  let (next, replacement) = expr_mutation_garbage(next)
  (
    next,
    {
      name: "insert-garbage",
      start_byte,
      old_end_byte: start_byte,
      replacement,
    },
  )
}

///|
fn expr_truncate_prefix_mutation(
  seed : Int,
  input : String,
) -> (Int, ExprMutation) {
  let (next, start_byte) = expr_fuzz_pick(seed, input.length())
  (
    next,
    {
      name: "truncate-prefix",
      start_byte,
      old_end_byte: input.length(),
      replacement: "",
    },
  )
}

///|
fn expr_mutation_kind(
  seed : Int,
  input : String,
  kind : Int,
) -> (Int, ExprMutation) {
  match kind {
    0 => expr_delete_char_mutation(seed, input)
    1 => expr_delete_token_mutation(seed, input)
    2 => expr_replace_token_mutation(seed, input)
    3 => expr_scramble_paren_mutation(seed, input)
    4 => expr_insert_garbage_mutation(seed, input)
    _ => expr_truncate_prefix_mutation(seed, input)
  }
}

///|
fn expr_is_visible_for_compare(node : @runtime.CstNode) -> Bool {
  node.is_named || node.is_error || node.is_missing
}

///|
fn expr_collect_visible_children(
  node : @runtime.CstNode,
) -> Array[@runtime.CstNode] {
  let out : Array[@runtime.CstNode] = []
  for child in node.children {
    if expr_is_visible_for_compare(child) {
      out.push(child)
    } else if !child.children.is_empty() {
      for nested in expr_collect_visible_children(child) {
        out.push(nested)
      }
    }
  }
  out
}

///|
fn expr_assert_same_tree_shape(
  label : String,
  actual : @runtime.CstNode,
  expected : @runtime.CstNode,
  path : String,
) -> Unit {
  if expr_is_visible_for_compare(actual) !=
    expr_is_visible_for_compare(expected) {
    println("\{label}: visible-node mismatch at \{path}")
    panic()
  }
  if actual.symbol != expected.symbol {
    println(
      "\{label}: symbol mismatch at \{path}: \{actual.symbol} != \{expected.symbol}",
    )
    panic()
  }
  if actual.is_named != expected.is_named {
    println("\{label}: is_named mismatch at \{path}")
    panic()
  }
  if actual.extra != expected.extra {
    println("\{label}: extra mismatch at \{path}")
    panic()
  }
  if actual.is_missing != expected.is_missing {
    println("\{label}: is_missing mismatch at \{path}")
    panic()
  }
  if actual.is_error != expected.is_error {
    println("\{label}: is_error mismatch at \{path}")
    panic()
  }
  if actual.start_byte != expected.start_byte ||
    actual.end_byte != expected.end_byte {
    println(
      "\{label}: byte span mismatch at \{path}: [\{actual.start_byte}, \{actual.end_byte}) != [\{expected.start_byte}, \{expected.end_byte})",
    )
    panic()
  }
  if actual.start_point != expected.start_point ||
    actual.end_point != expected.end_point {
    println("\{label}: point mismatch at \{path}")
    panic()
  }
  let actual_children = expr_collect_visible_children(actual)
  let expected_children = expr_collect_visible_children(expected)
  if actual_children.length() != expected_children.length() {
    println(
      "\{label}: children length mismatch at \{path}: \{actual_children.length()} != \{expected_children.length()}",
    )
    panic()
  }
  for i in 0..<actual_children.length() {
    expr_assert_same_tree_shape(
      label,
      actual_children[i],
      expected_children[i],
      path + "/" + i.to_string(),
    )
  }
}

///|
fn assert_expr_incremental_mutation_matches_full(
  label : String,
  table : @tablegen.ParseTable,
  old_input : String,
  mutation : ExprMutation,
) -> Unit {
  let old_root = match @runtime.parse(table, old_input) {
    Ok(root) => root
    Err(e) => {
      println("\{label}: old parse failed: \{e.message}")
      panic()
    }
  }
  let (new_input, edit) = expr_make_edit_from_replacement(
    old_input,
    mutation.start_byte,
    mutation.old_end_byte,
    mutation.replacement,
  )
  let inc_result = @runtime.parse_with_old_tree(
    table,
    new_input,
    Some({ root: old_root, old_input }),
    Some(edit),
  )
  let full_result = @runtime.parse(table, new_input)
  match (inc_result, full_result) {
    (Ok(inc_root), Ok(full_root)) => {
      @grammars.assert_cst_invariants(inc_root, new_input, "root")
      @grammars.assert_cst_invariants(full_root, new_input, "root")
      expr_assert_same_tree_shape(label, inc_root, full_root, "root")
    }
    (Err(inc_err), Err(full_err)) =>
      if inc_err.position != full_err.position ||
        inc_err.point != full_err.point ||
        inc_err.message != full_err.message {
        println(
          "\{label}: incremental/full Err mismatch: inc=\{inc_err} full=\{full_err}",
        )
        panic()
      }
    (Ok(_), Err(full_err)) => {
      println(
        "\{label}: incremental parse succeeded but full parse failed: \{full_err}",
      )
      panic()
    }
    (Err(inc_err), Ok(_)) => {
      println(
        "\{label}: incremental parse failed but full parse succeeded: \{inc_err}",
      )
      panic()
    }
  }
}

// ============================================================
// F. 测试
// ============================================================

// ============================================================
// §1.1  结构正确性
// ============================================================

///|
test "expr 结构 / 根节点类型为 expression，无 ERROR" {
  for input in ["n", "n+n", "n*n", "n+n*n", "(n+n)*n", "n+n+n"] {
    let s = @grammars.expression_sexp(input)
    assert_true(s.has_prefix("(expression "))
    assert_true(!s.contains("ERROR"))
  }
}

///|
test "expr 结构 / 含标识符节点" {
  let s = @grammars.expression_sexp("n+n*n")
  assert_true(s.contains("(identifier)"))
}

// ============================================================
// §1.2  Golden / Snapshot 测试
// ============================================================

///|
test "expr snapshot / n+n*n（运算符优先级）" {
  inspect(
    @grammars.expression_sexp("n+n*n"),
    content=(
      #|(expression (additive_expression (additive_expression (multiplicative_expression (unary_expression (postfix_expression (primary_expression (identifier)))))) (multiplicative_expression (multiplicative_expression (unary_expression (postfix_expression (primary_expression (identifier))))) (unary_expression (postfix_expression (primary_expression (identifier)))))))
    ),
  )
}

///|
test "expr snapshot / (n+n)*n（括号改变优先级）" {
  inspect(
    @grammars.expression_sexp("(n+n)*n"),
    content=(
      #|(expression (additive_expression (multiplicative_expression (multiplicative_expression (unary_expression (postfix_expression (primary_expression (expression (additive_expression (additive_expression (multiplicative_expression (unary_expression (postfix_expression (primary_expression (identifier)))))) (multiplicative_expression (unary_expression (postfix_expression (primary_expression (identifier))))))))))) (unary_expression (postfix_expression (primary_expression (identifier)))))))
    ),
  )
}

///|
test "expr snapshot / n+n+n（左结合）" {
  inspect(
    @grammars.expression_sexp("n+n+n"),
    content=(
      #|(expression (additive_expression (additive_expression (additive_expression (multiplicative_expression (unary_expression (postfix_expression (primary_expression (identifier)))))) (multiplicative_expression (unary_expression (postfix_expression (primary_expression (identifier)))))) (multiplicative_expression (unary_expression (postfix_expression (primary_expression (identifier)))))))
    ),
  )
}

// ============================================================
// §1.3  位置一致性
// ============================================================

///|
test "expr 位置 / 所有节点满足 start_byte <= end_byte" {
  fn spans_ok(node : @runtime.CstNode) -> Bool {
    if node.start_byte > node.end_byte {
      return false
    }
    for child in node.children {
      if !spans_ok(child) {
        return false
      }
    }
    true
  }

  assert_true(spans_ok(parse_expr_ok("n+n*n")))
  assert_true(spans_ok(parse_expr_ok("(n+n)*n")))
}

///|
test "expr 位置 / 根节点字节区间覆盖全部输入" {
  let input = "n+n*n"
  let root = parse_expr_ok(input)
  assert_eq(root.start_byte, 0)
  assert_eq(root.end_byte, input.length())
}

// ============================================================
// §3.3  Grammar Stress Test
// ============================================================

///|
test "expr stress / 长链左递归与右递归" {
  let inputs = [additive_chain(256), unary_chain(256)]
  for input in inputs {
    let root = parse_expr_ok(input)
    assert_true(!@grammars.expression_sexp(input).contains("ERROR"))
    assert_eq(root.start_byte, 0)
    assert_eq(root.end_byte, input.length())
  }
}

///|
test "expr stress / 超长参数列表" {
  let input = call_with_many_args(256)
  let root = parse_expr_ok(input)
  assert_true(!@grammars.expression_sexp(input).contains("ERROR"))
  assert_eq(root.start_byte, 0)
  assert_eq(root.end_byte, input.length())
}

// ============================================================
// §6.1  非语法随机 fuzz
// ============================================================

///|
test "expr fuzz / 非语法随机输入不会崩溃" {
  let mut seed = 31

  for i in 0..<32 {
    let (next, input) = expr_random_ascii(seed, 8 + i % 64)
    seed = next
    check_expr_any_input_stable("expr ascii #" + i.to_string(), input)
  }

  for i in 0..<24 {
    let (next, input) = expr_random_utf8_text(seed, 6 + i % 24)
    seed = next
    check_expr_any_input_stable("expr utf8 #" + i.to_string(), input)
  }

  for
    input in [
      expr_repeat_fragment("(", 4096),
      expr_repeat_fragment("!", 4096),
      expr_repeat_fragment("n", 4096),
      expr_repeat_fragment("\u4f60", 1024),
      expr_repeat_fragment("\n", 2048),
    ] {
    check_expr_any_input_stable("expr repeated run", input)
  }

  for i in 0..<24 {
    let (next, input) = expr_random_control_text(seed, 128)
    seed = next
    check_expr_any_input_stable("expr control #" + i.to_string(), input)
  }

  for i in 0..<24 {
    let (next, input) = expr_random_layout_noise(seed, 128)
    seed = next
    check_expr_any_input_stable("expr layout #" + i.to_string(), input)
  }
}

// ============================================================
// §6.2  语法引导 fuzz
// ============================================================

///|
test "expr guided fuzz / 合法表达式样本都可解析" {
  let mut seed = 211

  for i in 0..<84 {
    let depth = 1 + i % 4
    let width = 1 + i % 4
    let (next, input) = expr_guided_expr_kind(seed, i % 7, depth, width)
    seed = next
    assert_expr_guided_parse("expr guided kind #" + i.to_string(), input)
  }

  for i in 0..<36 {
    let depth = 1 + i % 4
    let width = 1 + (i + 1) % 4
    let (next, input) = expr_guided_expr(seed, depth, width)
    seed = next
    assert_expr_guided_parse("expr guided mixed #" + i.to_string(), input)
  }
}

// ============================================================
// §6.3  变异式 fuzz
// ============================================================

///|
test "expr mutation fuzz / 单次变异输入保持稳定" {
  let mut seed = 90217
  for sample in 0..<16 {
    let depth = 2 + sample % 3
    let width = 2 + sample % 2
    let (next, base) = expr_guided_expr(seed, depth, width)
    seed = next
    assert_expr_guided_parse("expr mutation base #\{sample}", base)
    for kind in 0..<6 {
      let (next, mutation) = expr_mutation_kind(seed, base, kind)
      seed = next
      let mutated = expr_replace_range(
        base,
        mutation.start_byte,
        mutation.old_end_byte,
        mutation.replacement,
      )
      if mutated == base {
        println(
          "expr mutation #\{sample}/\{mutation.name}: expected edited input to change",
        )
        panic()
      }
      check_expr_any_input_stable(
        "expr mutation #\{sample}/\{mutation.name}",
        mutated,
      )
    }
  }
}

///|
test "expr mutation fuzz / 单次变异的增量结果等于全量重解析" {
  let table = expr_make_table()
  let mut seed = 99173
  for sample in 0..<14 {
    let depth = 2 + sample % 3
    let width = 2 + sample % 2
    let (next, base) = expr_guided_expr(seed, depth, width)
    seed = next
    assert_expr_guided_parse("expr incremental base #\{sample}", base)
    for kind in 0..<6 {
      let (next, mutation) = expr_mutation_kind(seed, base, kind)
      seed = next
      assert_expr_incremental_mutation_matches_full(
        "expr incremental mutation #\{sample}/\{mutation.name}",
        table,
        base,
        mutation,
      )
    }
  }
}
