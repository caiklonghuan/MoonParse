///|
fn parse_moonbit_ok(source : String) -> @runtime.CstNode {
  match @grammars.parse_moonbit(source) {
    Ok(node) => node
    Err(e) => {
      println("parse_moonbit failed: \{e.message}")
      panic()
    }
  }
}

///|
test "moonbit_type_alias" {
  let source =
    #|pub type IntList = Array[Int]
  let node = parse_moonbit_ok(source)
  assert_true(not(node.is_error))
}

///|
test "moonbit_struct_and_enum" {
  let source =
    #|pub(all) struct Point {
    #|  row : Int
    #|  column : Int
    #|} derive(Eq, Show)
    #|
    #|enum Token {
    #|  Number(Int)
    #|  Name(String)
    #|}
  let node = parse_moonbit_ok(source)
  assert_true(not(node.is_error))
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
  assert_true(not(node.is_error))
}
