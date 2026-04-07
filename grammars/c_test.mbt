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
test "c_simple_function" {
  let source =
    #|int add(int a, int b) {
    #|  return a + b;
    #|}
  let node = parse_c_ok(source)
  assert_true(not(node.is_error))
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
  assert_true(not(node.is_error))
}

///|
test "c_top_level_declaration" {
  let node = parse_c_ok("const char *name = \"MoonParse\";")
  assert_true(not(node.is_error))
}
