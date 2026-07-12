///|
fn assert_some_int(value : Int?, expected : Int) -> Unit raise {
  match value {
    Some(actual) => assert_eq(actual, expected)
    None => fail("expected mapped offset")
  }
}

///|
test "EditMap maps unchanged prefixes and shifted suffixes" {
  let edit : SourceTextEdit = {
    start_byte: 2,
    old_end_byte: 5,
    replacement: "你",
  }
  guard EditMap::from_edit(8, edit) is Some(map) else {
    fail("valid edit must produce a map")
  }
  assert_eq(map.old_length, 8)
  assert_eq(map.new_length, 8)
  assert_some_int(map.old_to_new(0), 0)
  assert_some_int(map.old_to_new(2), 2)
  assert_true(map.old_to_new(3) is None)
  assert_some_int(map.old_to_new(5), 5)
  assert_some_int(map.old_to_new(8), 8)
}

///|
test "EditMap handles insertion and deletion boundary bias deterministically" {
  let insertion : SourceTextEdit = {
    start_byte: 1,
    old_end_byte: 1,
    replacement: "xy",
  }
  guard EditMap::from_edit(3, insertion) is Some(insert_map) else {
    fail("valid insertion must map")
  }
  assert_some_int(insert_map.old_to_new(1), 1)
  assert_some_int(insert_map.old_to_new(2), 4)
  assert_true(insert_map.new_to_old(2) is None)
  assert_some_int(insert_map.new_to_old(3), 1)

  let deletion : SourceTextEdit = {
    start_byte: 1,
    old_end_byte: 3,
    replacement: "",
  }
  guard EditMap::from_edit(4, deletion) is Some(delete_map) else {
    fail("valid deletion must map")
  }
  assert_true(delete_map.old_to_new(2) is None)
  assert_some_int(delete_map.old_to_new(3), 1)
  assert_some_int(delete_map.new_to_old(1), 1)
}

///|
test "EditMap rejects invalid ranges before arithmetic" {
  let invalid : SourceTextEdit = {
    start_byte: 4,
    old_end_byte: 2,
    replacement: "x",
  }
  assert_true(EditMap::from_edit(5, invalid) is None)
}
