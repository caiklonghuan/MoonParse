///|
fn parse_python_ok(source : String) -> @runtime.CstNode {
  match @grammars.parse_python(source) {
    Ok(node) => node
    Err(e) => {
      println("parse_python failed: \{e.message}")
      panic()
    }
  }
}

///|
test "python_nested_if_in_function" {
  let source =
    #|def fib(n):
    #|    if n <= 1:
    #|        return n
    #|    return fib(n - 1) + fib(n - 2)
  let node = parse_python_ok(source)
  assert_true(not(node.is_error))
}

///|
test "python_class_with_method" {
  let source =
    #|class Point:
    #|    def x(self):
    #|        return 1
  let node = parse_python_ok(source)
  assert_true(not(node.is_error))
}

///|
test "python_inline_for_loop" {
  let source =
    #|for value in [1, 4, 9]: print(value)
  let node = parse_python_ok(source)
  assert_true(not(node.is_error))
}
