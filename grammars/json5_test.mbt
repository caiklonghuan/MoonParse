///|
fn parse_json5_ok(source : String) -> @runtime.CstNode {
  match @grammars.parse_json5(source) {
    Ok(node) => node
    Err(e) => {
      println("parse_json5 failed: \{e.message}")
      panic()
    }
  }
}

///|
fn nested_json5_array(depth : Int) -> String {
  let buf = StringBuilder::new()
  for _ in 0..<depth {
    buf.write_char('[')
  }
  buf.write_string("0")
  for _ in 0..<depth {
    buf.write_string(",]")
  }
  buf.to_string()
}

///|
fn nested_json5_object(depth : Int) -> String {
  let buf = StringBuilder::new()
  for i in 0..<depth {
    buf.write_string("{k")
    buf.write_string(i.to_string())
    buf.write_string(":")
  }
  buf.write_string("0")
  for _ in 0..<depth {
    buf.write_string(",}")
  }
  buf.to_string()
}

///|
fn wide_json5_array(width : Int) -> String {
  let items : Array[String] = []
  for i in 0..<width {
    items.push(i.to_string())
  }
  "[" + items.join(", ") + ",]"
}

///|
fn wide_json5_object(width : Int) -> String {
  let fields : Array[String] = []
  for i in 0..<width {
    fields.push("k" + i.to_string() + ": " + i.to_string())
  }
  "{" + fields.join(", ") + ",}"
}

///|
test "json5_trailing_commas_and_single_quotes" {
  let source =
    #|{ unquoted: 'value', list: [1, 2, 3,], }
  let node = parse_json5_ok(source)
  assert_true(!node.is_error)
}

///|
test "json5_hex_and_special_numbers" {
  let node = parse_json5_ok("{hex: 0x2a, pos: +Infinity, bad: NaN}")
  assert_true(!node.is_error)
}

///|
test "json5_nested_objects" {
  let node = parse_json5_ok(
    "{cfg: {name: 'moon', enabled: true,}, nums: [1, .5, -3.0]}",
  )
  assert_true(!node.is_error)
}

///|
test "json5_line_comment" {
  let source =
    #|// top-level comment
    #|{
    #|  // this is a key
    #|  key: 'value',
    #|}
  let node = parse_json5_ok(source)
  assert_true(!node.is_error)
}

///|
test "json5_identifier_key_variants" {
  // $-prefix and _-prefix identifiers as keys, number with exponent
  let node = parse_json5_ok("{$ref: 1, _private: 'ok', e: 2.5e3}")
  assert_true(!node.is_error)
}

///|
test "json5_string_escape_sequences" {
  // single-quoted with escape, double-quoted with escape
  let node = parse_json5_ok("{a: 'it\\'s ok', b: \"say \\\"hi\\\"\"}")
  assert_true(!node.is_error)
}

///|
test "json5_negative_infinity" {
  let node = parse_json5_ok("{x: -Infinity}")
  assert_true(!node.is_error)
}

///|
test "json5_empty_object_and_array" {
  let node = parse_json5_ok("{arr: [], obj: {},}")
  assert_true(!node.is_error)
}

// ============================================================
// 1.4  最小结构 snapshot 集
// ============================================================

///|
test "json5 snapshot / unquoted key" {
  inspect(
    @grammars.json5_sexp("{a: 1}"),
    content=(
      #|(json5 (value (object (members (member (property_name (identifier)) (value (number)))))))
    ),
  )
}

///|
test "json5 snapshot / 单引号字符串" {
  inspect(
    @grammars.json5_sexp("'hello'"),
    content=(
      #|(json5 (value (string (sstring))))
    ),
  )
}

///|
test "json5 snapshot / 尾随逗号数组" {
  inspect(
    @grammars.json5_sexp("[1, 2, 3,]"),
    content=(
      #|(json5 (value (array (elements (value (number)) (value (number)) (value (number))))))
    ),
  )
}

// ============================================================
// 3.3  Grammar Stress Test
// ============================================================

///|
test "json5 stress / 100 层数组与对象嵌套" {
  let inputs = [nested_json5_array(100), nested_json5_object(100)]
  for input in inputs {
    let root = parse_json5_ok(input)
    assert_true(!@grammars.json5_sexp(input).contains("ERROR"))
    @grammars.assert_span_eq(root, 0, input.length())
  }
}

///|
test "json5 stress / 超长数组与对象字段列表" {
  let inputs = [wide_json5_array(256), wide_json5_object(256)]
  for input in inputs {
    let root = parse_json5_ok(input)
    assert_true(!@grammars.json5_sexp(input).contains("ERROR"))
    @grammars.assert_span_eq(root, 0, input.length())
  }
}

// ============================================================
// JSON 黑盒测试（parse_json = parse_json5 超集）
// ============================================================

///|
/// 辅助：解析 JSON 并返回根节点，断言无顶层错误
fn parse_ok(source : String) -> @runtime.CstNode {
  match @grammars.parse_json(source) {
    Ok(node) => node
    Err(e) => {
      println("parse_json failed: \{e.message}")
      panic()
    }
  }
}

///|
fn has_error_or_missing(node : @runtime.CstNode) -> Bool {
  if node.is_error || node.is_missing {
    return true
  }
  for child in node.children {
    if has_error_or_missing(child) {
      return true
    }
  }
  false
}

///|
fn count_error_nodes(node : @runtime.CstNode) -> Int {
  let mut total = if node.is_error { 1 } else { 0 }
  for child in node.children {
    total = total + count_error_nodes(child)
  }
  total
}

///|
fn count_missing_nodes(node : @runtime.CstNode) -> Int {
  let mut total = if node.is_missing { 1 } else { 0 }
  for child in node.children {
    total = total + count_missing_nodes(child)
  }
  total
}

///|
fn assert_json_recovery_usable(
  label : String,
  input : String,
  expected_start_byte : Int,
  expect_error : Bool,
  expect_missing : Bool,
  expected_fragment : String,
) -> Unit {
  let root = parse_ok(input)
  @grammars.assert_cst_invariants(root, input, "root")
  if !has_error_or_missing(root) {
    println("\{label}: expected ERROR or MISSING node in recovered tree")
    panic()
  }
  if root.start_byte != expected_start_byte {
    println(
      "\{label}: expected root.start_byte = \{expected_start_byte}, got \{root.start_byte}",
    )
    panic()
  }
  if root.end_byte != input.length() {
    println(
      "\{label}: expected root.end_byte = \{input.length()}, got \{root.end_byte}",
    )
    panic()
  }
  if expect_error && count_error_nodes(root) == 0 {
    println("\{label}: expected recovered tree to contain ERROR node")
    panic()
  }
  if expect_missing && count_missing_nodes(root) == 0 {
    println("\{label}: expected recovered tree to contain MISSING node")
    panic()
  }
  let sexp = @grammars.json_sexp(input)
  if sexp.is_empty() {
    println("\{label}: json_sexp should stay available on recovered tree")
    panic()
  }
  if !sexp.has_prefix("(json") {
    println("\{label}: expected json sexp to keep root node, got \{sexp}")
    panic()
  }
  if !expected_fragment.is_empty() && !sexp.contains(expected_fragment) {
    println(
      "\{label}: expected recovered sexp to contain \{expected_fragment}, got \{sexp}",
    )
    panic()
  }
}

///|
/// 测试非法 JSON 输入的"不崩溃"保证（4.4 任务清单）。
///
/// - 若恢复成功：断言树不变量 + ERROR/MISSING 存在 + sexp 可用。
/// - 若无法恢复：断言错误消息非空（干净失败，非 panic）。
fn check_json_error_input(label : String, input : String) -> Unit {
  match @grammars.parse_json(input) {
    Ok(root) => {
      @grammars.assert_cst_invariants(root, input, "root")
      if !has_error_or_missing(root) {
        println("\{label}: unexpected clean parse on invalid input")
        panic()
      }
      let sexp = @grammars.json_sexp(input)
      if sexp.is_empty() || !sexp.has_prefix("(json") {
        println("\{label}: json_sexp unusable on recovered tree: \{sexp}")
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

///|
fn nested_json_array(depth : Int) -> String {
  let buf = StringBuilder::new()
  for _ in 0..<depth {
    buf.write_char('[')
  }
  buf.write_string("0")
  for _ in 0..<depth {
    buf.write_char(']')
  }
  buf.to_string()
}

///|
fn nested_json_object(depth : Int) -> String {
  let buf = StringBuilder::new()
  for i in 0..<depth {
    buf.write_string("{\"k")
    buf.write_string(i.to_string())
    buf.write_string("\":")
  }
  buf.write_string("0")
  for _ in 0..<depth {
    buf.write_char('}')
  }
  buf.to_string()
}

///|
fn wide_json_array(width : Int) -> String {
  let items : Array[String] = []
  for i in 0..<width {
    items.push(i.to_string())
  }
  "[" + items.join(",") + "]"
}

///|
fn wide_json_object(width : Int) -> String {
  let fields : Array[String] = []
  for i in 0..<width {
    fields.push("\"k" + i.to_string() + "\":" + i.to_string())
  }
  "{" + fields.join(",") + "}"
}

///|
fn json_fuzz_next_seed(seed : Int) -> Int {
  let next = (seed * 48271 + 1) % 2147483647
  if next <= 0 {
    next + 2147483646
  } else {
    next
  }
}

///|
fn json_fuzz_pick(seed : Int, modulo : Int) -> (Int, Int) {
  let next = json_fuzz_next_seed(seed)
  (next, next % modulo)
}

///|
fn json_repeat_fragment(fragment : String, count : Int) -> String {
  let buf = StringBuilder::new()
  for _ in 0..<count {
    buf.write_string(fragment)
  }
  buf.to_string()
}

///|
fn json_random_ascii(seed : Int, length : Int) -> (Int, String) {
  let buf = StringBuilder::new()
  let mut cur = seed
  for _ in 0..<length {
    let (next, code) = json_fuzz_pick(cur, 95)
    cur = next
    buf.write_char((32 + code).to_char().unwrap())
  }
  (cur, buf.to_string())
}

///|
fn json_random_utf8_text(seed : Int, length : Int) -> (Int, String) {
  let palette = [
    "\u4f60", "\u597d", "\u6708", "\u5149", "\u6587", "\u5b57", "\u4e2d", "\u754c",
    "A", "7", " ",
  ]
  let buf = StringBuilder::new()
  let mut cur = seed
  for _ in 0..<length {
    let (next, index) = json_fuzz_pick(cur, palette.length())
    cur = next
    buf.write_string(palette[index])
  }
  (cur, buf.to_string())
}

///|
fn json_random_control_text(seed : Int, length : Int) -> (Int, String) {
  let buf = StringBuilder::new()
  let mut cur = seed
  for _ in 0..<length {
    let (next, kind) = json_fuzz_pick(cur, 8)
    cur = next
    match kind {
      0 => buf.write_char('\n')
      1 => buf.write_char('\t')
      2 => buf.write_char('\r')
      3 => {
        let (next, code) = json_fuzz_pick(cur, 32)
        cur = next
        buf.write_char(code.to_char().unwrap())
      }
      _ => {
        let (next, code) = json_fuzz_pick(cur, 95)
        cur = next
        buf.write_char((32 + code).to_char().unwrap())
      }
    }
  }
  (cur, buf.to_string())
}

///|
fn json_random_layout_noise(seed : Int, count : Int) -> (Int, String) {
  let fragments = [
    "[", "]", "{", "}", ",", ":", "\"", "a", "0", "\n", "\r\n", "\t", " \n ", "\t\t",
  ]
  let buf = StringBuilder::new()
  let mut cur = seed
  for _ in 0..<count {
    let (next, index) = json_fuzz_pick(cur, fragments.length())
    cur = next
    buf.write_string(fragments[index])
  }
  (cur, buf.to_string())
}

///|
fn check_json_any_input_stable(label : String, input : String) -> Unit {
  let sexp = @grammars.json_sexp(input)
  if sexp.is_empty() {
    println("\{label}: json_sexp returned empty output")
    panic()
  }
  if !sexp.has_prefix("(json") && !sexp.has_prefix("ERROR: ") {
    println("\{label}: unexpected json_sexp prefix: \{sexp}")
    panic()
  }
  match @grammars.parse_json(input) {
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

///|
fn json_guided_gap(seed : Int) -> (Int, String) {
  let gaps = ["", " ", "\n", "\t", " \n "]
  let (next, index) = json_fuzz_pick(seed, gaps.length())
  (next, gaps[index])
}

///|
fn json_guided_digits(seed : Int, count : Int) -> (Int, String) {
  let buf = StringBuilder::new()
  let mut cur = seed
  for _ in 0..<count {
    let (next, digit) = json_fuzz_pick(cur, 10)
    cur = next
    buf.write_char(('0'.to_int() + digit).to_char().unwrap())
  }
  (cur, buf.to_string())
}

///|
fn json_guided_string(seed : Int, max_units : Int) -> (Int, String) {
  let raw_units = ["a", "b", "Z", "0", "_", "-", " "]
  let escaped_units = ["\\\"", "\\\\", "\\n", "\\t", "\\u4e2d"]
  let (next, count_pick) = json_fuzz_pick(seed, max_units + 1)
  let buf = StringBuilder::new()
  let mut cur = next
  buf.write_char('"')
  for _ in 0..<count_pick {
    let (next, kind) = json_fuzz_pick(cur, 4)
    cur = next
    if kind == 0 {
      let (next, index) = json_fuzz_pick(cur, escaped_units.length())
      cur = next
      buf.write_string(escaped_units[index])
    } else {
      let (next, index) = json_fuzz_pick(cur, raw_units.length())
      cur = next
      buf.write_string(raw_units[index])
    }
  }
  buf.write_char('"')
  (cur, buf.to_string())
}

///|
fn json_guided_number(seed : Int) -> (Int, String) {
  let (next, neg_pick) = json_fuzz_pick(seed, 2)
  let (next, int_count_pick) = json_fuzz_pick(next, 4)
  let (next, int_part) = json_guided_digits(next, int_count_pick + 1)
  let (next, frac_pick) = json_fuzz_pick(next, 3)
  let mut cur = next
  let prefix = if neg_pick == 0 { "-" } else { "" }
  let mut result = prefix + int_part
  if frac_pick == 0 {
    let (next, frac_count_pick) = json_fuzz_pick(cur, 3)
    let (next, frac_part) = json_guided_digits(next, frac_count_pick + 1)
    cur = next
    result = result + "." + frac_part
  }
  let (next, exp_pick) = json_fuzz_pick(cur, 3)
  cur = next
  if exp_pick == 0 {
    let (next, sign_pick) = json_fuzz_pick(cur, 3)
    let (next, exp_count_pick) = json_fuzz_pick(next, 3)
    let (next, exp_part) = json_guided_digits(next, exp_count_pick + 1)
    cur = next
    let sign = match sign_pick {
      0 => "+"
      1 => "-"
      _ => ""
    }
    result = result + "e" + sign + exp_part
  }
  (cur, result)
}

///|
fn json_guided_value_kind(
  seed : Int,
  kind : Int,
  depth : Int,
  width : Int,
) -> (Int, String) {
  if depth <= 0 && kind < 2 {
    return json_guided_value_kind(seed, kind + 2, depth, width)
  }
  match kind {
    0 => {
      let (next, count_pick) = json_fuzz_pick(seed, width + 1)
      let buf = StringBuilder::new()
      let mut cur = next
      buf.write_char('{')
      for i in 0..<count_pick {
        if i > 0 {
          buf.write_char(',')
        }
        let (next, before_key) = json_guided_gap(cur)
        let (next, key) = json_guided_string(next, 4)
        let (next, before_colon) = json_guided_gap(next)
        let (next, after_colon) = json_guided_gap(next)
        let (next, value_kind) = json_fuzz_pick(next, 7)
        let (next, value) = json_guided_value_kind(
          next,
          value_kind,
          depth - 1,
          width,
        )
        cur = next
        buf.write_string(before_key)
        buf.write_string(key)
        buf.write_string(before_colon)
        buf.write_char(':')
        buf.write_string(after_colon)
        buf.write_string(value)
      }
      let (cur, trailing_gap) = json_guided_gap(cur)
      buf.write_string(trailing_gap)
      buf.write_char('}')
      (cur, buf.to_string())
    }
    1 => {
      let (next, count_pick) = json_fuzz_pick(seed, width + 1)
      let buf = StringBuilder::new()
      let mut cur = next
      buf.write_char('[')
      for i in 0..<count_pick {
        if i > 0 {
          buf.write_char(',')
        }
        let (next, gap) = json_guided_gap(cur)
        let (next, value_kind) = json_fuzz_pick(next, 7)
        let (next, value) = json_guided_value_kind(
          next,
          value_kind,
          depth - 1,
          width,
        )
        cur = next
        buf.write_string(gap)
        buf.write_string(value)
      }
      let (cur, trailing_gap) = json_guided_gap(cur)
      buf.write_string(trailing_gap)
      buf.write_char(']')
      (cur, buf.to_string())
    }
    2 => json_guided_string(seed, width + 2)
    3 => json_guided_number(seed)
    4 => (seed, "true")
    5 => (seed, "false")
    _ => (seed, "null")
  }
}

///|
fn json_guided_value(seed : Int, depth : Int, width : Int) -> (Int, String) {
  let (next, kind) = json_fuzz_pick(seed, 7)
  json_guided_value_kind(next, kind, depth, width)
}

///|
fn assert_json_guided_parse(label : String, input : String) -> Unit {
  match @grammars.parse_json(input) {
    Ok(root) => {
      @grammars.assert_cst_invariants(root, input, "root")
      if root.start_byte != 0 || root.end_byte != input.length() {
        println(
          "\{label}: expected root span [0, \{input.length()}) got [\{root.start_byte}, \{root.end_byte}) for \{input.escape()}",
        )
        panic()
      }
      let sexp = @grammars.json_sexp(input)
      if sexp.contains("ERROR") || !sexp.has_prefix("(json") {
        println(
          "\{label}: guided JSON should parse cleanly for \{input.escape()}, got \{sexp}",
        )
        panic()
      }
    }
    Err(e) => {
      println(
        "\{label}: generated invalid JSON \{input.escape()} -> \{e.message}",
      )
      panic()
    }
  }
}

///|
priv struct JsonToken {
  start_byte : Int
  end_byte : Int
  kind : Int
}

///|
priv struct JsonMutation {
  name : String
  start_byte : Int
  old_end_byte : Int
  replacement : String
}

///|
fn json_make_table() -> @tablegen.ParseTable {
  let grammar = match @grammar.parse_grammar(@grammars.json_grammar) {
    @grammar.Success(grammar) => grammar
    @grammar.Error(e) => {
      println("json_make_table: parse_grammar failed: \{e.message}")
      panic()
    }
  }
  match @tablegen.generate_parse_table(grammar) {
    Ok((table, _)) => table
    Err(e) => {
      println("json_make_table: generate_parse_table failed: \{e}")
      panic()
    }
  }
}

///|
fn json_point_at(input : String, pos : Int) -> @runtime.Point {
  @runtime.bytes_to_point(input, 0, { row: 0, column: 0 }, pos)
}

///|
fn json_replace_range(
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
fn json_make_edit_from_replacement(
  old_input : String,
  start_byte : Int,
  old_end_byte : Int,
  replacement : String,
) -> (String, @runtime.InputEdit) {
  let new_input = json_replace_range(
    old_input, start_byte, old_end_byte, replacement,
  )
  let new_end_byte = start_byte + replacement.length()
  let edit : @runtime.InputEdit = {
    start_byte,
    old_end_byte,
    new_end_byte,
    start_point: json_point_at(old_input, start_byte),
    old_end_point: json_point_at(old_input, old_end_byte),
    new_end_point: json_point_at(new_input, new_end_byte),
  }
  (new_input, edit)
}

///|
fn json_byte_at(input : String, pos : Int) -> Char {
  input[pos].to_int().to_char().unwrap()
}

///|
fn json_is_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r'
}

///|
fn json_is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn json_starts_with_at(input : String, start : Int, fragment : String) -> Bool {
  let end_byte = start + fragment.length()
  end_byte <= input.length() && input[start:end_byte].to_string() == fragment
}

///|
fn json_scan_string_end(input : String, start_byte : Int) -> Int {
  let mut i = start_byte + 1
  while i < input.length() {
    let ch = json_byte_at(input, i)
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
fn json_scan_number_end(input : String, start_byte : Int) -> Int {
  let mut i = start_byte
  if i < input.length() && json_byte_at(input, i) == '-' {
    i = i + 1
  }
  while i < input.length() && json_is_digit(json_byte_at(input, i)) {
    i = i + 1
  }
  if i < input.length() && json_byte_at(input, i) == '.' {
    i = i + 1
    while i < input.length() && json_is_digit(json_byte_at(input, i)) {
      i = i + 1
    }
  }
  if i < input.length() {
    let ch = json_byte_at(input, i)
    if ch == 'e' || ch == 'E' {
      i = i + 1
      if i < input.length() {
        let sign = json_byte_at(input, i)
        if sign == '+' || sign == '-' {
          i = i + 1
        }
      }
      while i < input.length() && json_is_digit(json_byte_at(input, i)) {
        i = i + 1
      }
    }
  }
  i
}

///|
fn json_collect_tokens(input : String) -> Array[JsonToken] {
  let tokens : Array[JsonToken] = []
  let mut i = 0
  while i < input.length() {
    let ch = json_byte_at(input, i)
    if json_is_space(ch) {
      i = i + 1
    } else if ch == '{' ||
      ch == '}' ||
      ch == '[' ||
      ch == ']' ||
      ch == ',' ||
      ch == ':' {
      tokens.push({ start_byte: i, end_byte: i + 1, kind: 0 })
      i = i + 1
    } else if ch == '"' {
      let end_byte = json_scan_string_end(input, i)
      tokens.push({ start_byte: i, end_byte, kind: 1 })
      i = end_byte
    } else if ch == '-' || json_is_digit(ch) {
      let end_byte = json_scan_number_end(input, i)
      tokens.push({ start_byte: i, end_byte, kind: 2 })
      i = end_byte
    } else if json_starts_with_at(input, i, "true") {
      tokens.push({ start_byte: i, end_byte: i + 4, kind: 3 })
      i = i + 4
    } else if json_starts_with_at(input, i, "false") {
      tokens.push({ start_byte: i, end_byte: i + 5, kind: 3 })
      i = i + 5
    } else if json_starts_with_at(input, i, "null") {
      tokens.push({ start_byte: i, end_byte: i + 4, kind: 3 })
      i = i + 4
    } else {
      i = i + 1
    }
  }
  tokens
}

///|
fn json_mutation_garbage(seed : Int) -> (Int, String) {
  let fragments = ["!", "@@", "???", "\n!\t", "#]", "\r\n?", "\t@"]
  let (next, index) = json_fuzz_pick(seed, fragments.length())
  (next, fragments[index])
}

///|
fn json_token_replacement(
  seed : Int,
  input : String,
  token : JsonToken,
) -> (Int, String) {
  let current = input[token.start_byte:token.end_byte].to_string()
  match token.kind {
    0 => {
      let replacement = match current {
        "{" => "["
        "}" => ")"
        "[" => "{"
        "]" => "}"
        ":" => ","
        _ => ":"
      }
      (seed, replacement)
    }
    1 => {
      let (next, replacement) = json_guided_string(seed, 3)
      if replacement == current {
        (next, "\"mut\"")
      } else {
        (next, replacement)
      }
    }
    2 => {
      let (next, replacement) = json_guided_number(seed)
      if replacement == current {
        (next, "0")
      } else {
        (next, replacement)
      }
    }
    _ => {
      let keywords = ["true", "false", "null"]
      let (next, index) = json_fuzz_pick(seed, keywords.length())
      let replacement = if keywords[index] == current {
        keywords[(index + 1) % keywords.length()]
      } else {
        keywords[index]
      }
      (next, replacement)
    }
  }
}

///|
fn json_delete_char_mutation(seed : Int, input : String) -> (Int, JsonMutation) {
  let (next, start_byte) = json_fuzz_pick(seed, input.length())
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
fn json_delete_token_mutation(
  seed : Int,
  input : String,
) -> (Int, JsonMutation) {
  let tokens = json_collect_tokens(input)
  if tokens.is_empty() {
    return json_delete_char_mutation(seed, input)
  }
  let (next, index) = json_fuzz_pick(seed, tokens.length())
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
fn json_replace_token_mutation(
  seed : Int,
  input : String,
) -> (Int, JsonMutation) {
  let tokens = json_collect_tokens(input)
  if tokens.is_empty() {
    return json_delete_char_mutation(seed, input)
  }
  let (next, index) = json_fuzz_pick(seed, tokens.length())
  let token = tokens[index]
  let (next, replacement) = json_token_replacement(next, input, token)
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
fn json_scramble_bracket_mutation(
  seed : Int,
  input : String,
) -> (Int, JsonMutation) {
  let positions : Array[Int] = []
  for i in 0..<input.length() {
    let ch = json_byte_at(input, i)
    if ch == '{' || ch == '}' || ch == '[' || ch == ']' {
      positions.push(i)
    }
  }
  if positions.is_empty() {
    return json_replace_token_mutation(seed, input)
  }
  let (next, index) = json_fuzz_pick(seed, positions.length())
  let start_byte = positions[index]
  let replacement = match json_byte_at(input, start_byte) {
    '{' => "]"
    '}' => "["
    '[' => "}"
    _ => "{"
  }
  (
    next,
    {
      name: "scramble-bracket",
      start_byte,
      old_end_byte: start_byte + 1,
      replacement,
    },
  )
}

///|
fn json_insert_garbage_mutation(
  seed : Int,
  input : String,
) -> (Int, JsonMutation) {
  let (next, start_byte) = json_fuzz_pick(seed, input.length() + 1)
  let (next, replacement) = json_mutation_garbage(next)
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
fn json_truncate_prefix_mutation(
  seed : Int,
  input : String,
) -> (Int, JsonMutation) {
  let (next, start_byte) = json_fuzz_pick(seed, input.length())
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
fn json_mutation_kind(
  seed : Int,
  input : String,
  kind : Int,
) -> (Int, JsonMutation) {
  match kind {
    0 => json_delete_char_mutation(seed, input)
    1 => json_delete_token_mutation(seed, input)
    2 => json_replace_token_mutation(seed, input)
    3 => json_scramble_bracket_mutation(seed, input)
    4 => json_insert_garbage_mutation(seed, input)
    _ => json_truncate_prefix_mutation(seed, input)
  }
}

///|
fn json_is_visible_for_compare(node : @runtime.CstNode) -> Bool {
  node.is_named || node.is_error || node.is_missing
}

///|
fn json_collect_visible_children(
  node : @runtime.CstNode,
) -> Array[@runtime.CstNode] {
  let out : Array[@runtime.CstNode] = []
  for child in node.children {
    if json_is_visible_for_compare(child) {
      out.push(child)
    } else if !child.children.is_empty() {
      for nested in json_collect_visible_children(child) {
        out.push(nested)
      }
    }
  }
  out
}

///|
fn json_assert_same_tree_shape(
  label : String,
  actual : @runtime.CstNode,
  expected : @runtime.CstNode,
  path : String,
) -> Unit {
  if json_is_visible_for_compare(actual) !=
    json_is_visible_for_compare(expected) {
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
  let actual_children = json_collect_visible_children(actual)
  let expected_children = json_collect_visible_children(expected)
  if actual_children.length() != expected_children.length() {
    println(
      "\{label}: children length mismatch at \{path}: \{actual_children.length()} != \{expected_children.length()}",
    )
    panic()
  }
  for i in 0..<actual_children.length() {
    json_assert_same_tree_shape(
      label,
      actual_children[i],
      expected_children[i],
      path + "/" + i.to_string(),
    )
  }
}

///|
fn assert_json_incremental_mutation_matches_full(
  label : String,
  table : @tablegen.ParseTable,
  old_input : String,
  mutation : JsonMutation,
) -> Unit {
  let old_root = match @runtime.parse(table, old_input) {
    Ok(root) => root
    Err(e) => {
      println("\{label}: old parse failed: \{e.message}")
      panic()
    }
  }
  let (new_input, edit) = json_make_edit_from_replacement(
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
      let inc_recovered = has_error_or_missing(inc_root)
      let full_recovered = has_error_or_missing(full_root)
      if !inc_recovered && !full_recovered {
        json_assert_same_tree_shape(label, inc_root, full_root, "root")
      } else {
        if inc_recovered != full_recovered {
          println(
            "\{label}: incremental/full recovery presence mismatch on mutated JSON",
          )
          panic()
        }
        if inc_root.start_byte != full_root.start_byte ||
          inc_root.end_byte != full_root.end_byte {
          println(
            "\{label}: recovered root span mismatch: [\{inc_root.start_byte}, \{inc_root.end_byte}) != [\{full_root.start_byte}, \{full_root.end_byte})",
          )
          panic()
        }
        if inc_root.start_point != full_root.start_point ||
          inc_root.end_point != full_root.end_point {
          println(
            "\{label}: recovered root point mismatch: inc=(\{inc_root.start_point.row}, \{inc_root.start_point.column})..(\{inc_root.end_point.row}, \{inc_root.end_point.column}) full=(\{full_root.start_point.row}, \{full_root.start_point.column})..(\{full_root.end_point.row}, \{full_root.end_point.column})",
          )
          panic()
        }
      }
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

///|
test "json mutation fuzz / 单次变异输入保持稳定" {
  let mut seed = 61093
  for sample in 0..<16 {
    let depth = 2 + sample % 3
    let width = 2 + sample % 2
    let (next, base) = json_guided_value(seed, depth, width)
    seed = next
    assert_json_guided_parse("json mutation base #\{sample}", base)
    for kind in 0..<6 {
      let (next, mutation) = json_mutation_kind(seed, base, kind)
      seed = next
      let mutated = json_replace_range(
        base,
        mutation.start_byte,
        mutation.old_end_byte,
        mutation.replacement,
      )
      if mutated == base {
        println(
          "json mutation #\{sample}/\{mutation.name}: expected edited input to change",
        )
        panic()
      }
      check_json_any_input_stable(
        "json mutation #\{sample}/\{mutation.name}",
        mutated,
      )
    }
  }
}

///|
test "json mutation fuzz / 单次变异的增量结果等于全量重解析" {
  let table = json_make_table()
  let mut seed = 78121
  for sample in 0..<14 {
    let depth = 2 + sample % 3
    let width = 2 + sample % 2
    let (next, base) = json_guided_value(seed, depth, width)
    seed = next
    assert_json_guided_parse("json incremental base #\{sample}", base)
    for kind in 0..<6 {
      let (next, mutation) = json_mutation_kind(seed, base, kind)
      seed = next
      assert_json_incremental_mutation_matches_full(
        "json incremental mutation #\{sample}/\{mutation.name}",
        table,
        base,
        mutation,
      )
    }
  }
}

///|
test "json_null" {
  let node = parse_ok("null")
  assert_true(!node.is_error)
}

///|
test "json_true" {
  let node = parse_ok("true")
  assert_true(!node.is_error)
}

///|
test "json_false" {
  let node = parse_ok("false")
  assert_true(!node.is_error)
}

///|
test "json_number_integer" {
  let node = parse_ok("42")
  assert_true(!node.is_error)
}

///|
test "json_number_negative" {
  let node = parse_ok("-3.14")
  assert_true(!node.is_error)
}

///|
test "json_string" {
  let node = parse_ok("\"hello world\"")
  assert_true(!node.is_error)
}

///|
test "json_empty_object" {
  let node = parse_ok("{}")
  assert_true(!node.is_error)
}

///|
test "json_empty_array" {
  let node = parse_ok("[]")
  assert_true(!node.is_error)
}

///|
test "json_simple_object" {
  let node = parse_ok("{\"key\": 123}")
  assert_true(!node.is_error)
}

///|
test "json_nested_object" {
  let node = parse_ok("{\"a\": {\"b\": true}}")
  assert_true(!node.is_error)
}

///|
test "json_array_of_numbers" {
  let node = parse_ok("[1, 2, 3]")
  assert_true(!node.is_error)
}

///|
test "json_array_mixed" {
  let node = parse_ok("[1, \"two\", true, null]")
  assert_true(!node.is_error)
}

///|
test "json_complex" {
  let node = parse_ok(
    "{\"name\": \"Alice\", \"age\": 30, \"scores\": [10, 20, 30], \"active\": true}",
  )
  assert_true(!node.is_error)
}

///|
test "json_whitespace_ignored" {
  // 空白应被 extras 规则忽略
  let node = parse_ok("  {  \"k\"  :  1  }  ")
  assert_true(!node.is_error)
}

///|
test "json_cst_has_children" {
  // 对象节点应该有子节点
  let node = parse_ok("{\"x\": 1}")
  // 根节点 json → value → object，至少有一层 children
  assert_true(!node.children.is_empty())
}

///|
test "json_string_escape_backslash" {
  let node = parse_ok("\"back\\\\slash\"")
  assert_true(!node.is_error)
}

///|
test "json_string_escape_quote" {
  let node = parse_ok("\"say \\\"hello\\\"\"")
  assert_true(!node.is_error)
}

///|
test "json_string_escape_control" {
  // \b \f \n \r \t
  let node = parse_ok("\"\\b\\f\\n\\r\\t\"")
  assert_true(!node.is_error)
}

///|
test "json_string_unicode_escape" {
  let node = parse_ok("\"\\u6708\\u5149\"")
  assert_true(!node.is_error)
}

///|
test "json_string_empty" {
  let node = parse_ok("\"\"")
  assert_true(!node.is_error)
}

///|
test "json_number_exponent" {
  let node = parse_ok("1.5e10")
  assert_true(!node.is_error)
}

///|
test "json_number_negative_exponent" {
  let node = parse_ok("-2.5E-3")
  assert_true(!node.is_error)
}

///|
test "json_complex_with_escapes" {
  let source =
    #|{
    #|  "name": "MoonParse",
    #|  "desc": "A \"parser-generator\"",
    #|  "path": "C:\\projects\\moon",
    #|  "unicode": "\u6708\u5149",
    #|  "count": 42,
    #|  "pi": 3.14159e0
    #|}
  let node = parse_ok(source)
  assert_true(!node.is_error)
}

// ============================================================
// 1.1  结构正确性：从"是否成功解析"升级到"树结构是否正确"
// ============================================================

///|
/// 辅助：递归检查所有节点满足 start_byte <= end_byte，返回 Bool
fn spans_valid(node : @runtime.CstNode) -> Bool {
  if node.start_byte > node.end_byte {
    return false
  }
  for child in node.children {
    if !spans_valid(child) {
      return false
    }
  }
  true
}

///|
test "json 结构 / null 根节点类型为 json5，有唯一命名子节点 value" {
  let s = @grammars.json_sexp("null")
  assert_true(s.has_prefix("(json5 "))
  assert_true(s.contains("(value)"))
  assert_true(!s.contains("ERROR"))
}

///|
test "json 结构 / 对象包含 object → members → member → string + number" {
  let s = @grammars.json_sexp("{\"a\": 1}")
  assert_true(s.contains("(object "))
  assert_true(s.contains("(member "))
  assert_true(s.contains("(string "))
  assert_true(s.contains("(number)"))
  assert_true(!s.contains("ERROR"))
}

///|
test "json 结构 / 数组包含 array 和 elements 节点" {
  let s = @grammars.json_sexp("[1, 2, 3]")
  assert_true(s.contains("(array "))
  assert_true(s.contains("(elements "))
  assert_true(!s.contains("ERROR"))
}

///|
test "json 结构 / 合法输入均无 ERROR 节点" {
  let inputs = [
    "null", "true", "false", "42", "\"hello\"", "{}", "[]", "{\"a\":1}",
  ]
  for input in inputs {
    assert_true(!@grammars.json_sexp(input).contains("ERROR"))
  }
}

// ============================================================
// 1.2  Golden / Snapshot 测试
// ============================================================

///|
test "json snapshot / null" {
  inspect(
    @grammars.json_sexp("null"),
    content=(
      #|(json5 (value))
    ),
  )
}

///|
test "json snapshot / simple object" {
  inspect(
    @grammars.json_sexp("{\"a\": 1}"),
    content=(
      #|(json5 (value (object (members (member (property_name (string (dstring))) (value (number)))))))
    ),
  )
}

///|
test "json snapshot / nested" {
  inspect(
    @grammars.json_sexp("{\"a\": [1, 2, {\"b\": true}]}"),
    content=(
      #|(json5 (value (object (members (member (property_name (string (dstring))) (value (array (elements (value (number)) (value (number)) (value (object (members (member (property_name (string (dstring))) (value)))))))))))))
    ),
  )
}

///|
test "json snapshot / array" {
  inspect(
    @grammars.json_sexp("[1,2,3]"),
    content=(
      #|(json5 (value (array (elements (value (number)) (value (number)) (value (number))))))
    ),
  )
}

///|
test "json snapshot / extras（whitespace 被忽略）" {
  inspect(
    @grammars.json_sexp(" { \"a\" : 1 } "),
    content=(
      #|(json5 (value (object (members (member (property_name (string (dstring))) (value (number)))))))
    ),
  )
}

///|
test "json snapshot / true false null 关键字" {
  inspect(
    @grammars.json_sexp("[true, false, null]"),
    content=(
      #|(json5 (value (array (elements (value) (value) (value)))))
    ),
  )
}

// ============================================================
// 1.3  位置与文本一致性测试
// ============================================================

///|
test "json 位置 / 所有节点满足 start_byte <= end_byte" {
  // 注：深层递归所有待展开到阶段八（不变量检查器）；此处只检查根节点和直接子节点
  let root = parse_ok("{\"a\": [1, 2, {\"b\": true}]}")
  assert_true(root.start_byte <= root.end_byte)
  for child in root.children {
    assert_true(child.start_byte <= child.end_byte)
  }
  assert_true(spans_valid(parse_ok("null")))
  assert_true(spans_valid(parse_ok("[1, \"two\", false]")))
}

///|
test "json 位置 / 根节点字节区间覆盖全部输入" {
  let input = "{\"key\": 42}"
  let root = parse_ok(input)
  assert_eq(root.start_byte, 0)
  assert_eq(root.end_byte, input.length())
  assert_eq(input[root.start_byte:root.end_byte].to_string(), input)
}

///|
test "json 位置 / CJK 字符串列号按 codepoint 推进（不是 UTF-8 字节数）" {
  // 使用接受 CJK 的自定义文法，而非 JSON jstring（其 [^"\\] 局限于 ASCII 字母表）
  // "你好" = 2 个 Unicode codepoint；如按 UTF-8 字节数计则为 6
  let dsl = "start s\nrule s: /[\u4e00-\u9fa5]+/"
  let input = "\u4f60\u597d"
  match @runtime.parse_from_dsl(dsl, input) {
    Ok(root) => {
      assert_eq(root.end_byte - root.start_byte, 2)
      assert_eq(root.end_point.column, 2)
      assert_eq(root.end_point.row, 0)
    }
    Err(e) => fail(e.message)
  }
}

///|
test "json 位置 / 多行输入 end_point.row 正确跨两个换行符" {
  // "{\n\"中\": 1\n}" — codepoints: { \n " 中 " : sp 1 \n }
  // 第 0 行: {, 第 1 行: "中": 1, 第 2 行: }
  let input = "{\n\"中\": 1\n}"
  let root = parse_ok(input)
  assert_eq(root.end_point.row, 2)
  assert_eq(root.end_point.column, 1)
}

// ============================================================
// 1.4  补充结构 snapshot 与统一断言工具的使用示例
// ============================================================

///|
test "json snapshot / empty object" {
  inspect(
    @grammars.json_sexp("{}"),
    content=(
      #|(json5 (value (object)))
    ),
  )
}

///|
test "json snapshot / empty array" {
  inspect(
    @grammars.json_sexp("[]"),
    content=(
      #|(json5 (value (array)))
    ),
  )
}

///|
test "json snapshot / number types" {
  inspect(
    @grammars.json_sexp("-3.14"),
    content=(
      #|(json5 (value (number)))
    ),
  )
}

///|
// assert_tree_shape_eq — 强断言（不通过 --update 更新）
test "json 断言 / assert_tree_shape_eq 演示（null）" {
  @grammars.assert_tree_shape_eq(@grammars.json_sexp("null"), "(json5 (value))")
}

///|
// assert_node_text_eq — 检查节点原文
test "json 断言 / assert_node_text_eq 检查 number 叶节点文本" {
  let source = "42"
  let root = parse_ok(source)
  // root → value → number (root.children[0].children[0])
  let value = root.children[0]
  let number = value.children[0]
  @grammars.assert_node_text_eq(number, source, "42")
}

///|
// assert_span_eq — 检查字节区间
test "json 断言 / assert_span_eq 检查根节点区间" {
  let source = "true"
  let root = parse_ok(source)
  @grammars.assert_span_eq(root, 0, 4)
}

///|
// assert_point_eq — 检查行列
test "json 断言 / assert_point_eq 检查单行末尾列号" {
  let source = "false"
  let root = parse_ok(source)
  @grammars.assert_point_eq(root.end_point, 0, 5)
}

// ============================================================
// 3.3  Grammar Stress Test
// ============================================================

///|
test "json stress / 100 层数组与对象嵌套" {
  let inputs = [nested_json_array(100), nested_json_object(100)]
  for input in inputs {
    let root = parse_ok(input)
    assert_true(!@grammars.json_sexp(input).contains("ERROR"))
    @grammars.assert_span_eq(root, 0, input.length())
  }
}

///|
test "json stress / 超长数组与对象字段列表" {
  let inputs = [wide_json_array(256), wide_json_object(256)]
  for input in inputs {
    let root = parse_ok(input)
    assert_true(!@grammars.json_sexp(input).contains("ERROR"))
    @grammars.assert_span_eq(root, 0, input.length())
  }
}

// ============================================================
// 4.1 / 4.2  错误恢复：非法输入也应返回可继续使用的树
// ============================================================

///|
test "json recovery / 非法 token 前缀仍返回 object 树" {
  let input = "!!!{\"a\":1}"
  assert_json_recovery_usable(
    "json recovery / 非法 token 前缀", input, 3, true, false, "(object",
  )
}

///|
test "json recovery / 中间非法 token 仍保留 object 结构" {
  let input = "{\"a\": ! 1}"
  assert_json_recovery_usable(
    "json recovery / 中间非法 token", input, 0, true, false, "(object",
  )
}

// json recovery / 多余逗号仍返回 array 树 — 已删除：JSON5 语法支持尾随逗号，[1,2,] 是合法输入

///|
test "json recovery / 截断数组 EOF 仍保留外层 object" {
  let input = "{\"a\": [1, 2, 3}"
  assert_json_recovery_usable(
    "json recovery / 截断数组 EOF", input, 0, true, false, "(object",
  )
}

///|
test "json recovery / 嵌套内部损坏仍保留外层 object" {
  let input = "{\"a\": [1, , 3], \"c\": 2}"
  assert_json_recovery_usable(
    "json recovery / 嵌套内部损坏", input, 0, false, true, "(object",
  )
}

// ============================================================
// 4.3 重点恢复场景：按输入类别逐条覆盖
// ============================================================

// ── 4.3.1 前缀垃圾（illegal token prefix） ─────────────────

///|
test "json recovery / 前缀垃圾 — 单字符 !" {
  // !{"b":2} — 1 字节前缀，应恢复或干净失败
  check_json_error_input("json recovery / 前缀垃圾 !", "!{\"b\":2}")
}

///|
test "json recovery / 前缀垃圾 — @@@[1,2,3]" {
  check_json_error_input("json recovery / 前缀垃圾 @@@", "@@@[1,2,3]")
}

///|
test "json recovery / 前缀垃圾 — ##42" {
  check_json_error_input("json recovery / 前缀垃圾 ##", "##42")
}

///|
test "json recovery / 前缀垃圾 — !null" {
  check_json_error_input("json recovery / 前缀垃圾 !null", "!null")
}

// ── 4.3.2 中间垃圾（middle illegal token） ──────────────────

///|
test "json recovery / 中间垃圾 — array 内单字符 !" {
  let input = "[1, !, 3]"
  assert_json_recovery_usable(
    "json recovery / 中间垃圾 [1,!,3]", input, 0, true, false, "(array",
  )
}

///|
test "json recovery / 中间垃圾 — array 内多字符 @@@" {
  check_json_error_input("json recovery / 中间垃圾 @@@", "[1, @@@, 3]")
}

///|
test "json recovery / 中间垃圾 — object value 位置 !" {
  check_json_error_input(
    "json recovery / 中间垃圾 obj val", "{\"a\": !, \"b\": 2}",
  )
}

///|
test "json recovery / 中间垃圾 — object value 位置 !!" {
  check_json_error_input(
    "json recovery / 中间垃圾 obj val !!", "{\"a\": !!, \"b\": 2}",
  )
}

///|
test "json recovery / 中间垃圾 — 局部合法局部非法 array" {
  // [1, 2, !, 4, 5]
  check_json_error_input(
    "json recovery / 中间垃圾 混合 array", "[1, 2, !, 4, 5]",
  )
}

// ── 4.3.3 缺右括号（missing closing bracket/brace at EOF） ──

///|
test "json recovery / 缺右括号 — [1,2,3" {
  check_json_error_input("json recovery / 缺右括号 array", "[1,2,3")
}

///|
test "json recovery / 缺右括号 — {\"a\":1" {
  check_json_error_input("json recovery / 缺右括号 object", "{\"a\":1")
}

///|
test "json recovery / 缺右括号 — [[1,2]" {
  check_json_error_input("json recovery / 缺右括号 nested array", "[[1,2]")
}

// ── 4.3.4 缺分隔符（missing separator/colon） ───────────────

///|
test "json recovery / 缺分隔符 — {\"a\" 1}" {
  // 已知：当前 JSON 文法不恢复此输入，但不应 panic
  check_json_error_input(
    "json recovery / 缺分隔符 key no colon", "{\"a\" 1}",
  )
}

///|
test "json recovery / 缺分隔符 — {\"a\":1 \"b\":2}" {
  check_json_error_input(
    "json recovery / 缺分隔符 no comma", "{\"a\":1 \"b\":2}",
  )
}

// ── 4.3.5 多余逗号（extra comma） ──────────────────────────

// json recovery / 多余逗号 — object 尾部逗号 — 已删除：JSON5 支持尾随逗号，{"a":1,} 是合法输入

///|
test "json recovery / 多余逗号 — 嵌套 array 双逗号" {
  // {"a":[1, , 3]} — 与已有 4.1 case 结构相同但无外层 "c"
  let input = "{\"a\":[1, , 3]}"
  assert_json_recovery_usable(
    "json recovery / 多余逗号 nested double", input, 0, false, true, "(object",
  )
}

///|
test "json recovery / 多余逗号 — [1,,2]" {
  check_json_error_input(
    "json recovery / 多余逗号 double in array", "[1,,2]",
  )
}

// ── 4.3.6 截断字符串（truncated string literal） ────────────

///|
test "json recovery / 截断字符串 — \"hello" {
  check_json_error_input("json recovery / 截断字符串 bare", "\"hello")
}

///|
test "json recovery / 截断字符串 — {\"a\": \"hello" {
  check_json_error_input(
    "json recovery / 截断字符串 in object", "{\"a\": \"hello",
  )
}

// ── 4.3.7 局部合法、局部非法（mixed valid/invalid） ─────────

///|
test "json recovery / 局部非法 — [1, ???, 3]" {
  // {"a": 1, "b": [1, ???, 3], "c": 2}
  check_json_error_input(
    "json recovery / 局部非法 ???", "{\"a\": 1, \"b\": [1, ???, 3], \"c\": 2}",
  )
}

///|
test "json recovery / 局部非法 — nested array 有单个 !" {
  check_json_error_input(
    "json recovery / 局部非法 nested !", "{\"a\": 1, \"b\": [1, !, 3], \"c\": 2}",
  )
}

// ============================================================
// 4.4 错误恢复成本模型回归（cost model regression）
//
// 对已知稳定输入断言 ERROR / MISSING 节点精确数量，防止恢复
// 算法退化时悄悄增加错误节点数。
// ============================================================

// json recovery cost model / [1,2,] 精确 1 MISSING — 已删除：JSON5 支持尾随逗号，[1,2,] 无 MISSING 节点

///|
test "json recovery cost model / {\"a\":[1, , 3]} 精确 1 MISSING" {
  // 嵌套 array 双逗号 → 插入一个 MISSING 值节点，无 ERROR
  let root = parse_ok("{\"a\":[1, , 3]}")
  inspect(count_missing_nodes(root), content="1")
  inspect(count_error_nodes(root), content="0")
}

///|
test "json recovery cost model / !!!{\"a\":1} 至少 1 ERROR 不超过 5" {
  let root = parse_ok("!!!{\"a\":1}")
  let total = count_error_nodes(root) + count_missing_nodes(root)
  assert_true(total >= 1)
  assert_true(total <= 5)
}

///|
test "json recovery cost model / {\"a\": ! 1} 至少 1 ERROR 不超过 5" {
  let root = parse_ok("{\"a\": ! 1}")
  let total = count_error_nodes(root) + count_missing_nodes(root)
  assert_true(total >= 1)
  assert_true(total <= 5)
}

///|
test "json recovery cost model / {\"a\": [1, 2, 3} 至少 1 ERROR 不超过 5" {
  let root = parse_ok("{\"a\": [1, 2, 3}")
  let total = count_error_nodes(root) + count_missing_nodes(root)
  assert_true(total >= 1)
  assert_true(total <= 5)
}

// ============================================================
// 6.1 非语法引导随机输入
// ============================================================

///|
test "json fuzz / 非语法随机输入不会崩溃" {
  let mut seed = 17

  for i in 0..<32 {
    let (next, input) = json_random_ascii(seed, 8 + i % 64)
    seed = next
    check_json_any_input_stable("json ascii #" + i.to_string(), input)
  }

  for i in 0..<24 {
    let (next, input) = json_random_utf8_text(seed, 6 + i % 24)
    seed = next
    check_json_any_input_stable("json utf8 #" + i.to_string(), input)
  }

  for
    input in [
      json_repeat_fragment("a", 4096),
      json_repeat_fragment("[", 4096),
      json_repeat_fragment("\"", 4096),
      json_repeat_fragment("\u4f60", 1024),
      json_repeat_fragment("\n", 2048),
    ] {
    check_json_any_input_stable("json repeated run", input)
  }

  for i in 0..<24 {
    let (next, input) = json_random_control_text(seed, 128)
    seed = next
    check_json_any_input_stable("json control #" + i.to_string(), input)
  }

  for i in 0..<24 {
    let (next, input) = json_random_layout_noise(seed, 128)
    seed = next
    check_json_any_input_stable("json layout #" + i.to_string(), input)
  }
}

// ============================================================
// 6.2 语法引导 fuzz
// ============================================================

///|
test "json guided fuzz / 合法 JSON 样本都可解析" {
  let mut seed = 97

  for i in 0..<70 {
    let depth = 1 + i % 4
    let width = 1 + i % 4
    let (next, input) = json_guided_value_kind(seed, i % 7, depth, width)
    seed = next
    assert_json_guided_parse("json guided kind #" + i.to_string(), input)
  }

  for i in 0..<30 {
    let depth = 1 + i % 4
    let width = 1 + (i + 2) % 4
    let (next, input) = json_guided_value(seed, depth, width)
    seed = next
    assert_json_guided_parse("json guided mixed #" + i.to_string(), input)
  }
}
