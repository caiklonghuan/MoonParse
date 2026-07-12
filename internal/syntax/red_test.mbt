///|
fn red_fixture() -> (GreenArena, GreenId) raise GreenBuildError {
  let arena = GreenArena::new()
  let left = arena.intern_token(1, "左")
  let newline = arena.intern_token(2, "\r\n", flags={
    ..GreenFlags::plain(),
    extra: true,
  })
  let right = arena.intern_token(1, "🙂")
  let nested = arena.intern_node(11, 1, [
    { green: newline, field_id: None },
    { green: right, field_id: Some(1) },
  ])
  let root = arena.intern_node(10, 0, [
    { green: left, field_id: Some(0) },
    { green: nested, field_id: Some(2) },
  ])
  (arena, root)
}

///|
test "red nodes provide lazy byte spans fields text and parents" {
  let (arena, root_id) = red_fixture()
  let tree = SyntaxTree::new("左\r\n🙂", arena, root_id).unwrap()
  let root = tree.root()
  assert_true(root.start_byte() == 0 && root.end_byte() == 9)
  assert_true(root.text() == "左\r\n🙂")
  let nested = root.child_by_field_id(2).unwrap()
  assert_true(nested.start_byte() == 3 && nested.end_byte() == 9)
  let emoji = nested.child_by_field_id(1).unwrap()
  assert_true(emoji.text() == "🙂")
  assert_true(emoji.start_byte() == 5 && emoji.end_byte() == 9)
  assert_true(emoji.parent().unwrap().green_id() == nested.green_id())
  assert_true(emoji.parent().unwrap().parent().unwrap().green_id() == root_id)
  let span = emoji.span().unwrap()
  assert_true(span.start_point == { row: 1, byte_column: 0 })
  assert_true(span.end_point == { row: 1, byte_column: 4 })
}

///|
test "syntax tree snapshots arena and rejects non-lossless roots" {
  let (arena, root_id) = red_fixture()
  assert_true(SyntaxTree::new("wrong", arena, root_id) is None)
  let tree = SyntaxTree::new("左\r\n🙂", arena, root_id).unwrap()
  let before = tree.root().child_count()
  arena.intern_token(99, "later") |> ignore
  assert_true(tree.root().child_count() == before)
  assert_true(tree.root().text() == "左\r\n🙂")
}

///|
test "tree cursor traverses deterministic source order" {
  let (arena, root_id) = red_fixture()
  let tree = SyntaxTree::new("左\r\n🙂", arena, root_id).unwrap()
  let cursor = TreeCursor::new(tree)
  assert_true(cursor.node().kind_id() == 10)
  assert_true(cursor.goto_first_child())
  assert_true(cursor.node().text() == "左")
  assert_true(cursor.goto_next_sibling())
  assert_true(cursor.node().kind_id() == 11)
  assert_true(cursor.goto_first_child())
  assert_true(cursor.node().text() == "\r\n")
  assert_true(cursor.goto_next_sibling())
  assert_true(cursor.node().text() == "🙂")
  assert_true(!cursor.goto_next_sibling())
  assert_true(cursor.goto_parent())
  assert_true(cursor.node().kind_id() == 11)
  assert_true(cursor.goto_parent())
  assert_true(!cursor.goto_parent())
}
