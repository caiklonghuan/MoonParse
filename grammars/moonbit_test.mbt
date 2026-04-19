///|
fn parse_moonbit_ok(source : String) -> @runtime.CstNode {
  match @grammars.parse_moonbit(source) {
    Ok(node) => node
    Err(e) => {
      println("parse_moonbit failed: \{e}")
      println("source around error:")
      let start = if e.position > 20 { e.position - 20 } else { 0 }
      let end = if e.position + 20 < source.length() {
        e.position + 20
      } else {
        source.length()
      }
      println("  ...\{source.substring(start~, end~)}...")
      panic()
    }
  }
}

///|
fn nested_moonbit_function(depth : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string("fn stress(x : Int) -> Int {\n")
  for _ in 0..<depth {
    buf.write_string("  if true {\n")
  }
  buf.write_string("    x\n")
  for _ in 0..<depth {
    buf.write_string("  }\n")
  }
  buf.write_string("}\n")
  buf.to_string()
}

///|
fn wide_moonbit_function(param_count : Int, statement_count : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string("fn wide(")
  for i in 0..<param_count {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string("p")
    buf.write_string(i.to_string())
    buf.write_string(" : Int")
  }
  buf.write_string(") -> Int {\n")
  for i in 0..<statement_count {
    buf.write_string("  let x")
    buf.write_string(i.to_string())
    buf.write_string(" = ")
    buf.write_string(i.to_string())
    buf.write_string("\n")
  }
  buf.write_string("  0\n")
  buf.write_string("}\n")
  buf.to_string()
}

///|
test "moonbit_type_alias" {
  let source =
    #|pub type IntList = Array[Int]
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_struct_and_enum" {
  let source =
    #|pub(all) struct Point {
    #|  row : Int
    #|  column : Int
    #|} derive(Eq, Debug)
    #|
    #|enum Token {
    #|  Number(Int)
    #|  Name(String)
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_match_expression" {
  let source =
    #|fn unwrap(value : Option[Int]) -> Int {
    #|  match value {
    #|    Some(inner) => inner
    #|    None => 0
    #|  }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_record_literal" {
  let source =
    #|fn make_point(x : Int, y : Int) -> Point {
    #|  { x: x, y: y }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_test_block" {
  let source =
    #|test "example" {
    #|  let x = 1 + 2
    #|  assert_eq(x, 3)
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_while_loop" {
  let source =
    #|fn count(n : Int) -> Unit {
    #|  let i = 0
    #|  while i < n {
    #|    let k = i + 1
    #|  }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_enum_match_with_guard" {
  let source =
    #|fn area(s : Shape) -> Double {
    #|  match s {
    #|    Circle(r) if r > 0.0 => 3.14159 * r * r
    #|    Rect(w, h) => w * h
    #|    _ => 0.0
    #|  }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_visibility_and_derive" {
  let source =
    #|pub(all) enum Color {
    #|  Red
    #|  Green
    #|  Blue
    #|} derive(Debug, Eq, Hash)
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_pub_readonly" {
  let source =
    #|pub(readonly) struct Config {
    #|  name : String
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_trait_decl" {
  let source =
    #|pub trait Equal {
    #|  equal(self, other : Self) -> Bool
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_loop_statement" {
  let source =
    #|fn spin() -> Unit {
    #|  loop {
    #|    break
    #|  }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_raise_statement" {
  let source =
    #|fn fail() -> Unit {
    #|  raise Error
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_try_catch" {
  let source =
    #|fn recover() -> Int {
    #|  try {
    #|    risky()?
    #|  } catch(err) {
    #|    0
    #|  }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_try_result_expression" {
  let source =
    #|fn wrap() -> Result[Int, Error] {
    #|  try? risky()
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_impl_debug_inspect" {
  // 无换行 — 预期失败（EOI 不在 state 481 lookahead）
  println(@grammars.moonbit_sexp("impl A for B with f() {}"))
  // 有尾部换行 — 假设能成功
  println(@grammars.moonbit_sexp("impl A for B with f() {}\n"))
  // 多行形式（with 后换行）
  println(@grammars.moonbit_sexp("impl A for B with\nf() {}"))
  println(
    @grammars.moonbit_sexp(
      "impl Equal for Int with is_equal(a, b) { a == b }\n",
    ),
  )
}

///|
test "moonbit_conflicts_report" {
  let grammar = match @grammar.parse_grammar(@grammars.moonbit_grammar) {
    Success(g) => g
    Error(_) => {
      println("grammar parse error")
      panic()
    }
  }
  match @tablegen.generate_parse_table(grammar) {
    Ok((table, conflicts)) => {
      println("conflicts: \{conflicts.length()}")
      for r in conflicts {
        let tname = match table.terminal_names.get(r.terminal) {
          Some(n) => n
          None => "(unknown)"
        }
        match r.severity {
          Ambiguous(msg) =>
            println("[ambig] state=\{r.state} t=\{r.terminal}(\{tname}) \{msg}")
          _ => ()
        }
      }
      // 检查 state 481 的 EOI (-1) 动作
      println("--- state 481 EOI action ---")
      match table.action.get((481, -1)) {
        None => println("  NO EOI action in state 481")
        Some(acts) =>
          for a in acts {
            match a {
              Shift(s) => println("  EOI Shift(\{s})")
              Reduce(p) => {
                let pname = match table.productions.get(p) {
                  Some(prod) => prod.rule_name
                  None => "?"
                }
                println("  EOI Reduce(prod=\{p} rule=\{pname})")
              }
              Accept => println("  EOI Accept")
            }
          }
      }
      // 搜索所有包含 impl_decl 的 reduce action 的状态
      println("--- states with impl_decl reduce ---")
      for prod in table.productions {
        if prod.rule_name == "impl_decl" {
          println(
            "  prod_id=\{prod.id} rule=impl_decl body_len=\{prod.body.length()}",
          )
        }
      }
    }
    Err(_) => println("table gen error")
  }
}

// ============================================================
// 1.4  最小结构 snapshot 集
// ============================================================

///|
test "moonbit snapshot / let 声明" {
  inspect(
    @grammars.moonbit_sexp("let x = 1"),
    content=(
      #|(module (lit:pub) (item (let_decl (pattern (or_pattern (as_pattern (single_pattern (qualified_identifier (identifier)))))) (expression (assignment_expression (pipe_expression (logical_or_expression (logical_and_expression (is_expression (equality_expression (comparison_expression (bitwise_or_expression (bitwise_xor_expression (bitwise_and_expression (shift_expression (range_expression (additive_expression (multiplicative_expression (unary_expression (postfix_expression (primary_expression (literal (number_literal)))))))))))))))))))))))
    ),
  )
}

///|
test "moonbit snapshot / 单行函数" {
  inspect(
    @grammars.moonbit_sexp("fn id(x : Int) -> Int { x }"),
    content=(
      #|(module (lit:pub) (item (function_decl (fn_name (identifier)) (parameter_clause (parameter_list (parameter (identifier) (type_annotation (type_expr (simple_type (qualified_identifier (identifier)))))))) (return_type (type_expr (simple_type (qualified_identifier (identifier))))) (block (statement (expression (assignment_expression (pipe_expression (logical_or_expression (logical_and_expression (is_expression (equality_expression (comparison_expression (bitwise_or_expression (bitwise_xor_expression (bitwise_and_expression (shift_expression (range_expression (additive_expression (multiplicative_expression (unary_expression (postfix_expression (primary_expression (qualified_identifier (identifier)))))))))))))))))))))))))
    ),
  )
}

///|
test "moonbit snapshot / 空 test 块" {
  inspect(
    @grammars.moonbit_sexp("test \"t\" {}"),
    content=(
      #|(module (lit:pub) (item (test_decl (string_literal) (block))))
    ),
  )
}

// ============================================================
// 3.3  Grammar Stress Test
// ============================================================

///|
test "moonbit stress / 深层嵌套 if 块" {
  let input = nested_moonbit_function(100)
  let root = parse_moonbit_ok(input)
  assert_true(!@grammars.moonbit_sexp(input).contains("ERROR"))
  @grammars.assert_span_eq(root, 0, input.length())
}

///|
test "moonbit stress / 超长参数列表与连续 statement" {
  let input = wide_moonbit_function(128, 160)
  let root = parse_moonbit_ok(input)
  assert_true(!@grammars.moonbit_sexp(input).contains("ERROR"))
  @grammars.assert_span_eq(root, 0, input.length())
}

// ============================================================
// 4. 新增语法特性测试
// ============================================================

///|
test "moonbit_pipe_operator" {
  let source =
    #|fn transform(xs : Array[Int]) -> Array[Int] {
    #|  xs |> filter(is_even) |> map(double)
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_bitwise_operators" {
  let source =
    #|fn bits(x : Int, y : Int) -> Int {
    #|  let a = x & 0xFF
    #|  let b = x | y
    #|  let c = x ^ y
    #|  let d = x << 2
    #|  let e = x >> 4
    #|  a + b + c + d + e
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_arrow_function" {
  let source =
    #|fn apply() -> Unit {
    #|  let f = x => { x + 1 }
    #|  items.each(x => println(x))
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_fn_expression" {
  let source =
    #|fn higher() -> Unit {
    #|  let f = fn(x : Int) -> Int { x + 1 }
    #|  items.each(fn(x) { println(x) })
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_multiline_parameter_list" {
  let source =
    #|fn body_is_nullable(
    #|  nm : Map[NonTerminalId, Bool],
    #|  body : Array[BodySymbol]
    #|) -> Bool {
    #|  true
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_parameter_list_trailing_comma" {
  let source =
    #|fn body_is_nullable(
    #|  nm : Map[NonTerminalId, Bool],
    #|  body : Array[BodySymbol],
    #|) -> Bool {
    #|  true
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_guard_statement" {
  let source =
    #|fn safe_get(arr : Array[Int], idx : Int) -> Int {
    #|  guard idx >= 0 else { return 0 }
    #|  arr[idx]
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_guard_is_pattern" {
  let source =
    #|fn get_text(res : Resource) -> String {
    #|  guard res is PlainText(text)
    #|  text
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_const_decl" {
  let source =
    #|pub const MAX_SIZE : Int = 1024
    #|const ZERO = 0
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_suberror_decl" {
  let source =
    #|suberror DivError { DivError(String) }
    #|suberror EmptyError
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_for_c_style" {
  let source =
    #|fn count() -> Unit {
    #|  for i = 0; i < 10; i = i + 1 {
    #|    println(i)
    #|  }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_for_c_style_multi_binding" {
  let source =
    #|fn pair() -> Unit {
    #|  for i = 0, j = 10; i < j; i = i + 1, j = j - 1 {
    #|    println(i)
    #|  }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_for_in_two_vars" {
  let source =
    #|fn show_map(m : Map[String, Int]) -> Unit {
    #|  for k, v in m {
    #|    println(k)
    #|  }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_while_nobreak" {
  let source =
    #|fn find(n : Int) -> Int {
    #|  let i = 0
    #|  while i < n {
    #|    break 42
    #|  } nobreak {
    #|    0
    #|  }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_labeled_arguments" {
  let source =
    #|fn create(name~ : String, age~ : Int) -> User {
    #|  { name: name, age: age }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_labeled_call" {
  let source =
    #|fn use_label() -> Unit {
    #|  let u = create(name="Alice", age=30)
    #|  let v = create(name~, age~)
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_is_expression" {
  let source =
    #|fn check(x : Int?) -> Bool {
    #|  x is Some(v) && v > 0
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_or_pattern" {
  let source =
    #|fn classify(x : Shape) -> String {
    #|  match x {
    #|    Circle(r) | Ellipse(r) => "round"
    #|    _ => "other"
    #|  }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_as_pattern" {
  let source =
    #|fn inspect_node(obj : Object) -> Unit {
    #|  match obj {
    #|    Point(_, _) as p => println(p)
    #|    _ => ()
    #|  }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_struct_update" {
  let source =
    #|fn update_email(u : User) -> User {
    #|  { ..u, email: "new@mail.com" }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_hex_number_literal" {
  let source =
    #|let mask = 0xFF00
    #|let bin = 0b1010
    #|let oct = 0o777
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_generic_constraint" {
  let source =
    #|fn[T : Show] display(x : T) -> String {
    #|  x.to_string()
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_generic_multi_constraint" {
  let source =
    #|fn[X : Eq, Y : Show] find(xs : Array[X], y : Y) -> Bool {
    #|  true
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_raise_signature" {
  let source =
    #|fn div(x : Int, y : Int) -> Int raise DivError {
    #|  if y == 0 {
    #|    raise DivError("zero")
    #|  }
    #|  x / y
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_defer" {
  let source =
    #|fn with_cleanup() -> Unit {
    #|  defer cleanup()
    #|  do_work()
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_trait_extend" {
  let source =
    #|pub trait Object : Position + Draw {
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_trait_method_default" {
  let source =
    #|pub trait Greet {
    #|  name(Self) -> String
    #|  greet(Self) -> String = _
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_impl_trait_for_type" {
  let source =
    #|impl Eq for Point with equal(p1, p2) {
    #|  p1.x == p2.x
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_impl_auto" {
  let source = "impl Object for Point\n"
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_mut_struct_field" {
  let source =
    #|struct User {
    #|  id : Int
    #|  mut email : String
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_tuple_struct" {
  let source =
    #|struct UserId(Int)
    #|struct UserInfo(UserId, String)
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_enum_labeled_fields" {
  let source =
    #|enum Tree {
    #|  Nil
    #|  Node(mut value~ : Int, mut left~ : Tree, mut right~ : Tree)
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_test_no_name" {
  let source =
    #|test {
    #|  assert_true(true)
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_compound_assign" {
  let source =
    #|fn inc(x : Int) -> Int {
    #|  let mut a = x
    #|  a += 1
    #|  a -= 2
    #|  a *= 3
    #|  a /= 4
    #|  a
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_slice_syntax" {
  let source =
    #|fn slice_it(arr : Array[Int]) -> Unit {
    #|  let a = arr[1:3]
    #|  let b = arr[2:]
    #|  let c = arr[:5]
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_trait_object_type" {
  let source =
    #|fn use_trait(animals : Array[&Animal]) -> Unit {
    #|  for a in animals {
    #|    println(a.speak())
    #|  }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_attribute_decl" {
  let source =
    #|#callsite(autofill(loc))
    #|fn f(x : Int, loc~ : SourceLoc) -> String {
    #|  x.to_string()
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_range_expressions" {
  let source =
    #|fn ranges() -> Unit {
    #|  for i in 0..<10 {
    #|    println(i)
    #|  }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_number_literal_suffixes" {
  let source =
    #|let a = 42
    #|let b = 1000L
    #|let c = 14U
    #|let d = 18UL
    #|let e = 100N
    #|let f = 3.14
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_byte_literals" {
  let source =
    #|fn bytes_test() -> Unit {
    #|  let b = b'a'
    #|  let bs = b"hello"
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_pub_open_trait" {
  let source =
    #|pub(open) trait Show {
    #|  output(Self, Logger) -> Unit
    #|  to_string(Self) -> String = _
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_impl_with_generics" {
  let source =
    #|pub impl[X : Show] Show for Array[X] with output(self, logger) {
    #|  logger.write_string("array")
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_record_shorthand" {
  let source =
    #|fn make(name : String) -> User {
    #|  let id = 0
    #|  { id, name }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_cascade_operator" {
  let source =
    #|fn build() -> String {
    #|  let result = StringBuilder::new()
    #|  result..write_char('a')..write_string("bc")
    #|  result.to_string()
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_suberror_with_variants" {
  let source =
    #|suberror MyError {
    #|  NotFound
    #|  InvalidInput(String)
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_for_nobreak" {
  let source =
    #|fn sum_even(n : Int) -> Int {
    #|  for i = 1, acc = 0; i <= n; i = i + 1 {
    #|    if i == 0 {
    #|      break 0
    #|    }
    #|  } nobreak {
    #|    acc
    #|  }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_labeled_loop" {
  let source =
    #|fn search() -> Int {
    #|  outer~ : for i in 0..<10 {
    #|    for j in 0..<10 {
    #|      break outer~ 42
    #|    }
    #|  } nobreak {
    #|    0
    #|  }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_real_world_cstnode" {
  // A simplified version of real code from this project
  let source =
    #|pub(all) struct CstNode {
    #|  symbol : Int
    #|  is_named : Bool
    #|  start_byte : Int
    #|  end_byte : Int
    #|  mut children : Array[CstNode]
    #|} derive(Debug)
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_real_world_impl_show" {
  let source =
    #|pub impl Show for Symbol with output(self, logger) {
    #|  match self {
    #|    Terminal(id) => logger.write_string("T")
    #|    NonTerminal(id) => logger.write_string("NT")
    #|    EndOfInput => logger.write_string("$")
    #|  }
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}

///|
test "moonbit_real_world_parse_fn" {
  let source =
    #|pub fn parse(table : ParseTable, input : String) -> Result[CstNode, ParseError] {
    #|  let lexer = LexerEngine::new(table.lexer_dfa)
    #|  let parser = LrParser::new(lexer)
    #|  parser.run(table, input)
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(!node.is_error)
}
