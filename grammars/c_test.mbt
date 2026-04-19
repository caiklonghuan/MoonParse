///|
fn parse_c_ok(source : String) -> @runtime.CstNode {
  match @grammars.parse_c(source) {
    Ok(node) => node
    Err(e) => {
      println("parse_c failed: \{e.message}")
      panic()
    }
  }
}

///|
fn nested_c_function(depth : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string("int stress(int x) {")
  for i in 0..<depth {
    buf.write_string(" if (x > ")
    buf.write_string(i.to_string())
    buf.write_string(") {")
  }
  buf.write_string(" return x;")
  for _ in 0..<depth {
    buf.write_string(" }")
  }
  buf.write_string(" return 0; }")
  buf.to_string()
}

///|
fn wide_c_function(param_count : Int, statement_count : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string("int wide(")
  for i in 0..<param_count {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string("int a")
    buf.write_string(i.to_string())
  }
  buf.write_string(") {")
  for i in 0..<statement_count {
    buf.write_string(" int x")
    buf.write_string(i.to_string())
    buf.write_string(" = ")
    buf.write_string(i.to_string())
    buf.write_string(";")
  }
  buf.write_string(" return 0; }")
  buf.to_string()
}

///|
test "c_simple_function" {
  let source =
    #|int add(int a, int b) {
    #|  return a + b;
    #|}
  let node = parse_c_ok(source)
  assert_true(!node.is_error)
}

///|
test "c_with_preprocessor_and_for_loop" {
  let source =
    #|#include <stdio.h>
    #|int main() {
    #|  for (int i = 0; i < 3; i = i + 1) {
    #|    printf("%d", i);
    #|  }
    #|  return 0;
    #|}
  let node = parse_c_ok(source)
  assert_true(!node.is_error)
}

///|
test "c_top_level_declaration" {
  let node = parse_c_ok("const char *name = \"MoonParse\";")
  assert_true(!node.is_error)
}

///|
test "c_struct_type_in_declaration" {
  // C grammar supports struct as a type specifier (not body definitions)
  let node = parse_c_ok("struct Point *p;")
  assert_true(!node.is_error)
}

///|
test "c_static_function_with_pointer" {
  let source =
    #|static int dot(struct Point *a, struct Point *b) {
    #|  return a->x * b->x + a->y * b->y;
    #|}
  let node = parse_c_ok(source)
  assert_true(!node.is_error)
}

///|
test "c_while_loop" {
  let source =
    #|void count(int n) {
    #|  int i = 0;
    #|  while (i < n) {
    #|    i = i + 1;
    #|  }
    #|}
  let node = parse_c_ok(source)
  assert_true(!node.is_error)
}

///|
test "c_char_literal_and_string_escape" {
  let source =
    #|int f() {
    #|  char c = 'A';
    #|  const char *s = "hello\nworld";
    #|  return 0;
    #|}
  let node = parse_c_ok(source)
  assert_true(!node.is_error)
}

///|
test "c_if_else_chain" {
  let source =
    #|int sign(int x) {
    #|  if (x > 0) return 1;
    #|  else if (x < 0) return -1;
    #|  else return 0;
    #|}
  let node = parse_c_ok(source)
  assert_true(!node.is_error)
}

///|
test "c_hex_number_literal" {
  let node = parse_c_ok("unsigned int mask = 0xFF00uL;")
  assert_true(!node.is_error)
}

// ============================================================
// 1.4  最小结构 snapshot 集
// ============================================================

///|
test "c snapshot / 空函数体" {
  inspect(
    @grammars.c_sexp("void f() {}"),
    content=(
      #|(translation_unit (EOF) (item (function_definition (declaration_specifiers (declaration_specifier (type_specifier))) (declarator (identifier) (function_suffix)) (compound_statement))))
    ),
  )
}

///|
test "c snapshot / 全局变量声明" {
  inspect(
    @grammars.c_sexp("int x;"),
    content=(
      #|(translation_unit (EOF) (item (declaration (declaration_specifiers (declaration_specifier (type_specifier))) (init_declarator_list (init_declarator (declarator (identifier)))))))
    ),
  )
}

///|
test "c snapshot / return 语句" {
  inspect(
    @grammars.c_sexp("int f() { return 0; }"),
    content=(
      #|(translation_unit (EOF) (item (function_definition (declaration_specifiers (declaration_specifier (type_specifier))) (declarator (identifier) (function_suffix)) (compound_statement (block_item (statement (return_statement (expression (assignment_expression (conditional_expression (logical_or_expression (logical_and_expression (bitwise_or_expression (bitwise_xor_expression (bitwise_and_expression (equality_expression (relational_expression (shift_expression (additive_expression (multiplicative_expression (unary_expression (postfix_expression (primary_expression (number_literal))))))))))))))))))))))))
    ),
  )
}

///|
test "c_bitwise_operators" {
  let source =
    #|int f(int a, int b, int n) {
    #|  int x = a & b;
    #|  int y = a | b;
    #|  int z = a ^ b;
    #|  int s = a << n;
    #|  int t = a >> n;
    #|  a &= 0xFF;
    #|  b |= 0x01;
    #|  b ^= 0xF0;
    #|  s <<= 1;
    #|  t >>= 2;
    #|  return x | y | z | s | t;
    #|}
  let node = parse_c_ok(source)
  assert_true(!node.is_error)
}

///|
test "c_do_while_loop" {
  let source =
    #|void f(int n) {
    #|  int i = 0;
    #|  do {
    #|    i = i + 1;
    #|  } while (i < n);
    #|}
  let node = parse_c_ok(source)
  assert_true(!node.is_error)
}

///|
test "c_switch_statement" {
  let source =
    #|int sign(int x) {
    #|  switch (x) {
    #|    case 0:
    #|      return 0;
    #|    case 1:
    #|    case 2:
    #|      return 1;
    #|    default:
    #|      return -1;
    #|  }
    #|}
  let node = parse_c_ok(source)
  assert_true(!node.is_error)
}

// ============================================================
// 3.3  Grammar Stress Test
// ============================================================

///|
test "c stress / 深层嵌套 if 链" {
  let input = nested_c_function(100)
  let root = parse_c_ok(input)
  assert_true(!@grammars.c_sexp(input).contains("ERROR"))
  @grammars.assert_span_eq(root, 0, input.length())
}

///|
test "c stress / 超长参数列表与连续 statement" {
  let input = wide_c_function(128, 192)
  let root = parse_c_ok(input)
  assert_true(!@grammars.c_sexp(input).contains("ERROR"))
  @grammars.assert_span_eq(root, 0, input.length())
}
