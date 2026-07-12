///|
fn schema() -> QuerySchema {
  QuerySchema::new(
    ["source_file", "function_definition", "identifier", "parameters", "number"],
    ["name", "parameters", "body"],
    anonymous_tokens=["()", "+", "中"],
  )
}

///|
test "golden query v1 surface compiles to stable IR" {
  let source =
    #|(function_definition
    #|  . name: (identifier) @name
    #|  parameters: [(parameters) "()"]? @params
    #|  (number)* @number .) @definition
    #|#not-eq? @name "main"
    #|#match? @name "^[a-z]"
    #|#not-match? @name "^_"
    #|#eq? @params "()"
    #|#any-of? @name "run" "build"
  let query = compile_query(source, schema())
  assert_eq(query.pattern_count(), 1)
  let patterns = query.patterns()
  assert_eq(patterns[0].index, 0)
  assert_true(
    patterns[0].capture_names == ["name", "params", "number", "definition"],
  )
  assert_true(patterns[0].root_capture_index == Some(3))
  assert_eq(patterns[0].predicates.length(), 5)
  guard patterns[0].root is Named(1, "function_definition", children) else {
    fail("expected named root")
  }
  assert_eq(children.length(), 3)
  assert_true(children[0].field_id == Some(0))
  assert_true(children[0].anchor_before)
  assert_true(children[2].anchor_after)
  assert_true(children[1].quantifier == ZeroOrOne)
  assert_true(children[2].quantifier == ZeroOrMore)
}

///|
test "anonymous wildcard alternation and plus are represented" {
  let query = compile_query(
    "(source_file [(identifier) \"+\" _]+ @item)",
    schema(),
  )
  guard query.patterns()[0].root is Named(_, _, [child]) else {
    fail("expected one child")
  }
  assert_true(child.quantifier == OneOrMore)
  assert_true(
    child.expr
    is Alternation([Named(_, "identifier", _), Anonymous("+"), Wildcard]),
  )
}

///|
test "bytecode is deterministic and source ordered" {
  let source = "(identifier) @name\n#eq? @name \"x\"\n(number) @value"
  let first = compile_query(source, schema()).bytecode()
  for _ in 0..<20 {
    assert_eq(compile_query(source, schema()).bytecode(), first)
  }
  assert_true(first is [b'M', b'Q', b'R', b'Y', 1, 0, 0, 0, ..])
}

///|
test "simple bytecode has an exact golden encoding" {
  let actual = compile_query("(identifier) @name", schema()).bytecode()
  let expected : Bytes = [
    77, 81, 82, 89, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 4, 0, 0, 0,
    110, 97, 109, 101, 0, 0, 0, 0, 16, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255,
  ]
  assert_eq(actual, expected)
}

///|
test "repeated capture names retain declaration order" {
  let query = compile_query(
    "(source_file [(identifier) (number)] @value (identifier) @value)",
    schema(),
  )
  assert_true(query.patterns()[0].capture_names == ["value", "value"])
}

///|
test "unknown names and invalid capture references are rejected" {
  try compile_query("(missing)", schema()) catch {
    UnknownNode("missing") => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected unknown node")
  }
  try compile_query("\"missing-token\"", schema()) catch {
    UnknownNode("missing-token") => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected unknown anonymous token")
  }
  try compile_query("(identifier unknown: (number))", schema()) catch {
    UnknownField("unknown") => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected unknown field")
  }
  try compile_query("(identifier) @name\n#eq? @other \"x\"", schema()) catch {
    UnknownCapture("other") => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected unknown capture")
  }
}

///|
test "v1 unsupported features fail explicitly" {
  try compile_query("(identifier) @x\n#set! @x \"value\"", schema()) catch {
    UnsupportedFeature("predicate #set") => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected unsupported predicate")
  }
  try compile_query("(source_file !body)", schema()) catch {
    UnsupportedFeature("negated fields") => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected unsupported negated field")
  }
}

///|
test "parse errors report UTF-8 byte offsets" {
  try compile_query("\"中\" )", schema()) catch {
    ParseError(6, _) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected parse error")
  }
}
