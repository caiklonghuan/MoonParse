///|
/// A normalized mapping segment between the source before and after one edit.
pub(all) struct EditMapSegment {
  old_start : Int
  old_end : Int
  new_start : Int
  new_end : Int
  changed : Bool
}

///|
pub(all) struct EditMap {
  old_length : Int
  new_length : Int
  segments : Array[EditMapSegment]
}

///|
pub fn EditMap::from_edit(old_length : Int, edit : SourceTextEdit) -> EditMap? {
  if old_length < 0 ||
    edit.start_byte < 0 ||
    edit.start_byte > edit.old_end_byte ||
    edit.old_end_byte > old_length {
    return None
  }
  let replacement_length = @utf8.encode(edit.replacement).length()
  let removed_length = edit.old_end_byte - edit.start_byte
  let new_length = old_length - removed_length + replacement_length
  Some({
    old_length,
    new_length,
    segments: [
      {
        old_start: 0,
        old_end: edit.start_byte,
        new_start: 0,
        new_end: edit.start_byte,
        changed: false,
      },
      {
        old_start: edit.start_byte,
        old_end: edit.old_end_byte,
        new_start: edit.start_byte,
        new_end: edit.start_byte + replacement_length,
        changed: true,
      },
      {
        old_start: edit.old_end_byte,
        old_end: old_length,
        new_start: edit.start_byte + replacement_length,
        new_end: new_length,
        changed: false,
      },
    ],
  })
}

///|
pub fn EditMap::old_to_new(self : EditMap, offset : Int) -> Int? {
  if offset < 0 || offset > self.old_length {
    return None
  }
  let changed = self.segments[1]
  if offset <= changed.old_start {
    Some(offset)
  } else if offset >= changed.old_end {
    Some(changed.new_end + offset - changed.old_end)
  } else {
    None
  }
}

///|
pub fn EditMap::new_to_old(self : EditMap, offset : Int) -> Int? {
  if offset < 0 || offset > self.new_length {
    return None
  }
  let changed = self.segments[1]
  if offset <= changed.new_start {
    Some(offset)
  } else if offset >= changed.new_end {
    Some(changed.old_end + offset - changed.new_end)
  } else {
    None
  }
}
