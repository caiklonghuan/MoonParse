///|
fn rust_raw_table() -> @tablegen.ParseTable {
  let grammar = match
    @grammar.parse_grammar(
      "start source\nexternals [raw_string_literal]\nrule source: raw_string_literal\n",
    ) {
    Success(value) => value
    Error(error) => abort("rust scanner grammar parse failed: \{error.message}")
  }
  match @tablegen.generate_parse_table(grammar) {
    Ok((table, _)) => table
    Err(message) => abort("rust scanner table generation failed: \{message}")
  }
}

///|
test "tree-sitter-rust scanner scans raw string variants" {
  let table = rust_raw_table()
  let scanner = tree_sitter_rust_scanner(table)
  let raw_id = table.external_token_ids[0]
  assert_true(scanner.scan("r\"abc\"", 0, [raw_id]) == Some((raw_id, 6)))
  assert_true(scanner.scan("r#\"a\"b\"#", 0, [raw_id]) == Some((raw_id, 8)))
  assert_true(scanner.scan("r###\"x\"###", 0, [raw_id]) == Some((raw_id, 10)))
  assert_true(scanner.scan("not_raw", 0, [raw_id]) == None)
}

///|
test "tree-sitter-rust scanner recovers unterminated raw strings" {
  let table = rust_raw_table()
  let scanner = tree_sitter_rust_scanner(table)
  let raw_id = table.external_token_ids[0]
  let input = "r##\"unterminated"
  assert_true(
    scanner.scan(input, 0, [raw_id]) == Some((raw_id, input.length())),
  )
}

///|
test "tree-sitter-rust scanner clone keeps independent state" {
  let table = rust_raw_table()
  let raw_id = table.external_token_ids[0]
  let scanner = tree_sitter_rust_scanner(table)
  let cloned = scanner.clone_scanner()
  assert_true(scanner.scan("r\"a\"", 0, [raw_id]) == Some((raw_id, 4)))
  assert_true(cloned.scan("r#\"b\"#", 0, [raw_id]) == Some((raw_id, 6)))
}
