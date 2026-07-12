///|
test "green tree is lossless and node widths equal child widths" {
  let arena = GreenArena::new()
  let name = arena.intern_token(1, "变量")
  let plain_flags = GreenFlags::plain()
  let space = arena.intern_token(2, " ", flags={ ..plain_flags, extra: true })
  let equal = arena.intern_token(3, "=")
  let value = arena.intern_token(4, "🙂")
  let root = arena.intern_node(10, 0, [
    { green: name, field_id: Some(0) },
    { green: space, field_id: None },
    { green: equal, field_id: None },
    { green: value, field_id: Some(1) },
  ])
  assert_true(arena.lossless_text(root) == Some("变量 =🙂"))
  assert_true(arena.byte_width(root) == Some(12))
}

///|
test "green interning shares structure and survives forced hash collisions" {
  let arena = GreenArena::new(bucket_count=1)
  let left = arena.intern_token(1, "left")
  let right = arena.intern_token(1, "right")
  let left_again = arena.intern_token(1, "left")
  assert_true(left == left_again)
  assert_true(left != right)
  let first = arena.intern_node(2, 7, [{ green: left, field_id: Some(0) }])
  let same = arena.intern_node(2, 7, [{ green: left_again, field_id: Some(0) }])
  let different = arena.intern_node(2, 7, [{ green: right, field_id: Some(0) }])
  assert_true(first == same)
  assert_true(first != different)
  assert_true(arena.element_count() == 4)
}

///|
test "fields and productions participate in green identity" {
  let arena = GreenArena::new(bucket_count=1)
  let token = arena.intern_token(1, "x")
  let a = arena.intern_node(2, 0, [{ green: token, field_id: Some(0) }])
  let b = arena.intern_node(2, 1, [{ green: token, field_id: Some(0) }])
  let c = arena.intern_node(2, 0, [{ green: token, field_id: Some(1) }])
  assert_true(a != b)
  assert_true(a != c)
}

///|
test "returned node views cannot mutate the interned green tree" {
  let arena = GreenArena::new()
  let x = arena.intern_token(1, "x")
  let y = arena.intern_token(1, "y")
  let root = arena.intern_node(2, 0, [{ green: x, field_id: None }])
  match arena.get(root) {
    Some(Node(node)) => node.children[0] = { green: y, field_id: None }
    _ => fail("expected green node")
  }
  assert_true(arena.lossless_text(root) == Some("x"))
}

///|
test "missing elements are zero width and invalid missing text is rejected" {
  let arena = GreenArena::new()
  let plain_flags = GreenFlags::plain()
  let missing_flags = { ..plain_flags, missing: true }
  let missing = arena.intern_token(9, "", flags=missing_flags)
  assert_true(arena.byte_width(missing) == Some(0))
  let rejected = try {
    arena.intern_token(9, "x", flags=missing_flags) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "invalid child IDs and negative semantic IDs are rejected" {
  let arena = GreenArena::new()
  let bad_kind = try {
    arena.intern_token(-1, "x") |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(bad_kind)
  let bad_child = try {
    arena.intern_node(1, 0, [{ green: { value: 99 }, field_id: None }])
    |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(bad_child)
  let token = arena.intern_token(1, "x")
  let bad_field = try {
    arena.intern_node(1, 0, [{ green: token, field_id: Some(-1) }]) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(bad_field)
}
