///|
fn leaf(
  kind_id : Int,
  named : Bool,
  token : String?,
  text : String,
  start : Int,
  end : Int,
) -> RuntimeNode {
  {
    kind_id,
    named,
    anonymous_token: token,
    text,
    start_byte: start,
    end_byte: end,
    children: [],
    child_fields: [],
  }
}

///|
fn fixture_tree() -> RuntimeNode {
  {
    kind_id: 0,
    named: true,
    anonymous_token: None,
    text: "foo+12",
    start_byte: 0,
    end_byte: 6,
    children: [
      leaf(1, true, None, "foo", 0, 3),
      leaf(-1, false, Some("+"), "+", 3, 4),
      leaf(2, true, None, "12", 4, 6),
      leaf(3, true, None, "", 6, 6),
    ],
    child_fields: [Some(0), None, Some(1), None],
  }
}

///|
fn fixture_schema() -> @query_ir.QuerySchema {
  @query_ir.QuerySchema::new(
    ["source", "identifier", "number", "eof"],
    ["left", "right"],
    anonymous_tokens=["+"],
  )
}

///|
test "full interpreter matches fields anonymous tokens captures and predicates" {
  let source =
    #|(source
    #|  left: (identifier) @name
    #|  "+"
    #|  right: (number) @value) @expression
    #|#eq? @name "foo"
    #|#match? @value "^[0-9]+$"
    #|#not-match? @name "^_"
    #|#any-of? @name "foo" "bar"
  let query = @query_ir.compile_query(source, fixture_schema())
  let captures = execute_query(query, fixture_tree(), "foo+12")
  assert_eq(captures.length(), 3)
  assert_eq(captures[0].name, "name")
  assert_eq(captures[1].name, "expression")
  assert_eq(captures[2].name, "value")
  assert_true(captures[0].node_preorder_path == [0])
  assert_true(captures[1].node_preorder_path == [])
  assert_true(captures[2].node_preorder_path == [2])
}

///|
test "sibling anchors reject gaps while unanchored patterns may skip" {
  let anchored = @query_ir.compile_query(
    "(source (identifier) . (number)) @hit",
    fixture_schema(),
  )
  assert_eq(execute_query(anchored, fixture_tree(), "foo+12").length(), 0)
  let unanchored = @query_ir.compile_query(
    "(source (identifier) (number)) @hit",
    fixture_schema(),
  )
  assert_eq(execute_query(unanchored, fixture_tree(), "foo+12").length(), 1)
}

///|
test "alternation quantifiers preserve every canonical match occurrence" {
  let query = @query_ir.compile_query(
    "(source [(identifier) (number)]+ @item) @root",
    fixture_schema(),
  )
  let captures = execute_query(query, fixture_tree(), "foo+12")
  assert_eq(captures.length(), 4)
  assert_eq(captures[0].name, "item")
  assert_eq(captures[1].name, "root")
  assert_eq(captures[2].name, "root")
  assert_eq(captures[3].name, "item")
  assert_true(captures[1].match_key != captures[2].match_key)
}

///|
test "duplicate capture declarations keep source declaration indexes" {
  let query = @query_ir.compile_query(
    "(source (identifier) @item (number) @item) @root",
    fixture_schema(),
  )
  let captures = execute_query(query, fixture_tree(), "foo+12")
  assert_eq(captures.length(), 3)
  assert_eq(captures[0].capture_declaration_index, 0)
  assert_eq(captures[1].capture_declaration_index, 2)
  assert_eq(captures[2].capture_declaration_index, 1)
}

///|
test "capture order and match keys are deterministic across executions" {
  let query = @query_ir.compile_query(
    "(identifier) @value\n(number) @value\n(eof) @value",
    fixture_schema(),
  )
  let first = execute_query(query, fixture_tree(), "foo+12")
  assert_eq(first.length(), 3)
  assert_eq(first[0].start_byte, 0)
  assert_eq(first[1].start_byte, 4)
  assert_eq(first[2].start_byte, 6)
  for _ in 0..<20 {
    assert_true(execute_query(query, fixture_tree(), "foo+12") == first)
  }
}

///|
test "range semantics include intersections and handle zero-width captures" {
  let query = @query_ir.compile_query(
    "(identifier) @value\n(number) @value\n(eof) @value",
    fixture_schema(),
  )
  let middle = execute_query(query, fixture_tree(), "foo+12", within={
    start_byte: 2,
    end_byte: 5,
  })
  assert_eq(middle.length(), 2)
  let all = execute_query(query, fixture_tree(), "foo+12")
  assert_eq(all.length(), 3)
  let empty = execute_query(query, fixture_tree(), "foo+12", within={
    start_byte: 6,
    end_byte: 6,
  })
  assert_eq(empty.length(), 0)
}

///|
test "invalid ranges trees and match budgets fail without partial results" {
  let query = @query_ir.compile_query("_ @node", fixture_schema())
  try
    execute_query(query, fixture_tree(), "foo+12", within={
      start_byte: 0,
      end_byte: 7,
    })
  catch {
    InvalidRange => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected invalid range")
  }
  try execute_query(query, fixture_tree(), "foo+12", match_limit=2) catch {
    MatchLimitExceeded(2) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected match budget failure")
  }
  let invalid = { ..fixture_tree(), child_fields: [] }
  try execute_query(query, invalid, "foo+12") catch {
    InvalidTree(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected invalid tree")
  }
}

///|
test "range validation uses UTF-8 byte boundaries" {
  let tree = leaf(1, true, None, "中", 0, 3)
  let query = @query_ir.compile_query("(identifier) @value", fixture_schema())
  try
    execute_query(query, tree, "中", within={ start_byte: 1, end_byte: 3 })
  catch {
    InvalidRange => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected split UTF-8 range rejection")
  }
}

///|
test "green arena adapter supplies lossless spans fields and anonymous tokens" {
  let arena = @syntax.GreenArena::new()
  let identifier = arena.intern_token(1, "foo")
  let plus = arena.intern_token(
    4,
    "+",
    flags=@syntax.GreenFlags::plain(named=false),
  )
  let number = arena.intern_token(2, "12")
  let root = arena.intern_node(0, 0, [
    { green: identifier, field_id: Some(0) },
    { green: plus, field_id: None },
    { green: number, field_id: Some(1) },
  ])
  let adapted = adapt_green_tree(arena, root)
  assert_eq(adapted.text, "foo+12")
  assert_eq(adapted.children[2].start_byte, 4)
  assert_true(adapted.children[1].anonymous_token == Some("+"))
  let query = @query_ir.compile_query(
    "(source left: (identifier) @name \"+\" right: (number) @value)",
    fixture_schema(),
  )
  assert_eq(execute_query(query, adapted, "foo+12").length(), 2)
}

///|
test "red syntax adapter preserves spans fields and anonymous tokens" {
  let arena = @syntax.GreenArena::new()
  let identifier = arena.intern_token(1, "foo")
  let plus = arena.intern_token(
    4,
    "+",
    flags=@syntax.GreenFlags::plain(named=false),
  )
  let number = arena.intern_token(2, "12")
  let root = arena.intern_node(0, 0, [
    { green: identifier, field_id: Some(0) },
    { green: plus, field_id: None },
    { green: number, field_id: Some(1) },
  ])
  let tree = @syntax.SyntaxTree::new("foo+12", arena, root).unwrap()
  let adapted = adapt_red_tree(tree.root())
  assert_true(adapted.text == "foo+12")
  assert_true(adapted.children[2].start_byte == 4)
  assert_true(adapted.children[1].anonymous_token == Some("+"))
}

///|
test "predicate optional quantifier consumes at most one scalar" {
  let query = @query_ir.compile_query(
    (
      #|(identifier) @value
      #|#match? @value "^a?b$"
    ),
    fixture_schema(),
  )
  let valid = leaf(1, true, None, "ab", 0, 2)
  let invalid = leaf(1, true, None, "aab", 0, 3)
  assert_true(execute_query(query, valid, "ab").length() == 1)
  assert_true(execute_query(query, invalid, "aab").is_empty())
}
