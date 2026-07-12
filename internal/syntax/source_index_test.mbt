///|
fn assert_point(
  point : SourcePoint?,
  row : Int,
  byte_column : Int,
) -> Unit raise {
  match point {
    Some(actual) => {
      assert_eq(actual.row, row)
      assert_eq(actual.byte_column, byte_column)
    }
    None => fail("expected a point")
  }
}

///|
test "SourceIndex maps CRLF byte positions without losing the LF offset" {
  let index = SourceIndex::new("a\r\nb")
  assert_eq(index.byte_length(), 4)
  assert_point(index.point_at(1), 0, 1)
  assert_point(index.point_at(2), 0, 2)
  assert_point(index.point_at(3), 1, 0)
  match index.byte_at({ row: 0, byte_column: 2 }) {
    Some(offset) => assert_eq(offset, 2)
    None => fail("expected LF offset")
  }
  match index.byte_at({ row: 1, byte_column: 0 }) {
    Some(offset) => assert_eq(offset, 3)
    None => fail("expected next-line offset")
  }
}

///|
test "SourceIndex requires UTF-8 code point boundaries" {
  let index = SourceIndex::new("a你b")
  assert_eq(index.byte_length(), 5)
  assert_true(index.is_boundary(1))
  assert_true(!index.is_boundary(2))
  assert_true(!index.is_boundary(3))
  assert_true(index.is_boundary(4))
  assert_true(index.point_at(2) is None)
  match index.byte_at({ row: 0, byte_column: 4 }) {
    Some(offset) => assert_eq(offset, 4)
    None => fail("expected boundary after multibyte character")
  }
}

///|
test "SourceIndex applies sequential edits in their visible coordinates" {
  let index = SourceIndex::new("a\r\nb")
  let edits : Array[SourceTextEdit] = [
    { start_byte: 1, old_end_byte: 3, replacement: "\n" },
    { start_byte: 2, old_end_byte: 2, replacement: "你" },
  ]
  match index.apply_many(edits) {
    Some(next) => {
      assert_eq(next.source, "a\n你b")
      assert_point(next.point_at(2), 1, 0)
      assert_point(next.point_at(5), 1, 3)
    }
    None => fail("valid sequential edits must apply")
  }
}

///|
test "SourceIndex rejects a split UTF-8 edit without partial mutation" {
  let index = SourceIndex::new("你")
  let edit : SourceTextEdit = {
    start_byte: 1,
    old_end_byte: 1,
    replacement: "x",
  }
  assert_true(index.apply(edit) is None)
}
