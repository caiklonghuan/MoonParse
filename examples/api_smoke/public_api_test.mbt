///|
let smoke_dsl =
  #|start document
  #|rule document: number
  #|rule number: /[0-9]+/

///|
test "public root API compiles and parses" {
  let compiled = match @moonparse.compile_dsl(smoke_dsl) {
    Ok(value) => value
    Err(error) => fail("compile_dsl failed: \{error.message}")
  }
  assert_true(compiled.table.states > 0)
  let parsed = match @moonparse.parse_dsl(smoke_dsl, "42") {
    Ok(value) => value
    Err(error) => fail("parse_dsl failed: \{error.message}")
  }
  assert_eq(parsed.source, "42")
}

///|
test "public grammar runtime and query APIs compose" {
  let grammar = match @grammar.parse_grammar(smoke_dsl) {
    Success(value) => value
    Error(error) => fail("parse_grammar failed: \{error.message}")
  }
  let table = match @tablegen.generate_parse_table(grammar) {
    Ok((value, _)) => value
    Err(message) => fail("generate_parse_table failed: \{message}")
  }
  let root = match @runtime.parse(table, "42") {
    Ok(value) => value
    Err(error) => fail("runtime parse failed: \{error.message}")
  }
  let query = match @query.compile("(number) @value") {
    Ok(value) => value
    Err(error) => fail("query compile failed: \{error}")
  }
  let captures = @query.exec(query, root, "42", table)
  assert_true(captures.length() > 0)
}
