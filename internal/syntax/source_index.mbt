///|
/// A zero-based UTF-8 byte point. It is internal until the root facade is
/// implemented in M2-C12.
pub(all) struct SourcePoint {
  row : Int
  byte_column : Int
} derive(Eq, Debug)

///|
/// A replacement expressed in the source coordinates visible immediately
/// before it is applied.
pub(all) struct SourceTextEdit {
  start_byte : Int
  old_end_byte : Int
  replacement : String
} derive(Eq, Debug)

///|
/// Immutable source bytes and logical line starts. `bytes`, not MoonBit String
/// character indexes, is the coordinate authority for every public operation.
pub(all) struct SourceIndex {
  source : String
  bytes : Bytes
  line_starts : Array[Int]
}

///|
fn byte_at(bytes : Bytes, offset : Int) -> Int {
  bytes[offset].to_int()
}

///|
fn is_utf8_boundary(bytes : Bytes, offset : Int) -> Bool {
  if offset < 0 || offset > bytes.length() {
    false
  } else if offset == bytes.length() {
    true
  } else {
    (byte_at(bytes, offset) & 0xC0) != 0x80
  }
}

///|
fn line_starts(bytes : Bytes) -> Array[Int] {
  let starts : Array[Int] = [0]
  let mut offset = 0
  while offset < bytes.length() {
    let byte = byte_at(bytes, offset)
    if byte == 0x0A {
      starts.push(offset + 1)
    } else if byte == 0x0D &&
      (offset + 1 == bytes.length() || byte_at(bytes, offset + 1) != 0x0A) {
      starts.push(offset + 1)
    }
    offset = offset + 1
  }
  starts
}

///|
pub fn SourceIndex::new(source : String) -> SourceIndex {
  let bytes = @utf8.encode(source)
  { source, bytes, line_starts: line_starts(bytes) }
}

///|
pub fn SourceIndex::byte_length(self : SourceIndex) -> Int {
  self.bytes.length()
}

///|
pub fn SourceIndex::is_boundary(self : SourceIndex, offset : Int) -> Bool {
  is_utf8_boundary(self.bytes, offset)
}

///|
pub fn SourceIndex::point_at(self : SourceIndex, offset : Int) -> SourcePoint? {
  if !is_utf8_boundary(self.bytes, offset) {
    return None
  }
  let mut row = 0
  let mut column = 0
  let mut cursor = 0
  while cursor < offset {
    let byte = byte_at(self.bytes, cursor)
    if byte == 0x0A {
      row = row + 1
      column = 0
    } else if byte == 0x0D &&
      (
        cursor + 1 == self.bytes.length() ||
        byte_at(self.bytes, cursor + 1) != 0x0A
      ) {
      row = row + 1
      column = 0
    } else {
      column = column + 1
    }
    cursor = cursor + 1
  }
  Some({ row, byte_column: column })
}

///|
pub fn SourceIndex::byte_at(self : SourceIndex, point : SourcePoint) -> Int? {
  if point.row < 0 || point.byte_column < 0 {
    return None
  }
  let mut row = 0
  let mut column = 0
  let mut cursor = 0
  while cursor < self.bytes.length() {
    if row == point.row && column == point.byte_column {
      return Some(cursor)
    }
    let byte = byte_at(self.bytes, cursor)
    if byte == 0x0A {
      row = row + 1
      column = 0
    } else if byte == 0x0D &&
      (
        cursor + 1 == self.bytes.length() ||
        byte_at(self.bytes, cursor + 1) != 0x0A
      ) {
      row = row + 1
      column = 0
    } else {
      column = column + 1
    }
    cursor = cursor + 1
  }
  if row == point.row && column == point.byte_column {
    Some(cursor)
  } else {
    None
  }
}

///|
pub fn SourceIndex::apply(
  self : SourceIndex,
  edit : SourceTextEdit,
) -> SourceIndex? {
  if edit.start_byte > edit.old_end_byte ||
    !is_utf8_boundary(self.bytes, edit.start_byte) ||
    !is_utf8_boundary(self.bytes, edit.old_end_byte) {
    None
  } else {
    Some(
      SourceIndex::new(
        @utf8.decode_lossy(self.bytes[:edit.start_byte]) +
        edit.replacement +
        @utf8.decode_lossy(self.bytes[edit.old_end_byte:]),
      ),
    )
  }
}

///|
pub fn SourceIndex::apply_many(
  self : SourceIndex,
  edits : Array[SourceTextEdit],
) -> SourceIndex? {
  let mut current = self
  for edit in edits {
    match current.apply(edit) {
      Some(next) => current = next
      None => return None
    }
  }
  Some(current)
}
