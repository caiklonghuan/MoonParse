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
test "json5_trailing_commas_and_single_quotes" {
  let source =
    #|{ unquoted: 'value', list: [1, 2, 3,], }
  let node = parse_json5_ok(source)
  assert_true(not(node.is_error))
}

///|
test "json5_hex_and_special_numbers" {
  let node = parse_json5_ok("{hex: 0x2a, pos: +Infinity, bad: NaN}")
  assert_true(not(node.is_error))
}

///|
test "json5_nested_objects" {
  let node = parse_json5_ok(
    "{cfg: {name: 'moon', enabled: true,}, nums: [1, .5, -3.0]}",
  )
  assert_true(not(node.is_error))
}
