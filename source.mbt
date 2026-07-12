///|
/// Immutable validated UTF-8 source owned by the public facade.
pub struct Source {
  text : String
  bytes : Bytes
}

///|
/// A sequential replacement in the coordinates visible when it is applied.
pub struct TextEdit {
  start_byte : Int
  old_end_byte : Int
  text : String
}

///|
pub fn Source::from_string(text : String) -> Source {
  { text, bytes: @utf8.encode(text) }
}

///|
pub fn Source::from_utf8(bytes : Bytes) -> Source raise SourceError {
  try @utf8.decode(bytes) catch {
    @utf8.Malformed(rest) => raise InvalidUtf8(bytes.length() - rest.length())
  } noraise {
    text => Source::from_string(text)
  }
}

///|
pub fn Source::byte_length(self : Source) -> Int {
  self.bytes.length()
}

///|
pub fn Source::to_bytes(self : Source) -> Bytes {
  self.bytes[:].to_owned()
}

///|
pub fn Source::slice(
  self : Source,
  range : ByteRange,
) -> String raise SourceError {
  let length = self.byte_length()
  let index = @syntax.SourceIndex::new(self.text)
  if range.start_byte < 0 ||
    range.end_byte < range.start_byte ||
    range.end_byte > length {
    raise InvalidByteRange(range.start_byte, range.end_byte, length)
  }
  if !index.is_boundary(range.start_byte) {
    raise SplitUtf8CodePoint(range.start_byte)
  }
  if !index.is_boundary(range.end_byte) {
    raise SplitUtf8CodePoint(range.end_byte)
  }
  @utf8.decode_lossy(self.bytes[range.start_byte:range.end_byte])
}

///|
pub fn TextEdit::replace(
  start_byte~ : Int,
  old_end_byte~ : Int,
  text~ : String,
) -> TextEdit {
  { start_byte, old_end_byte, text }
}

///|
pub fn TextEdit::replace_utf8(
  start_byte~ : Int,
  old_end_byte~ : Int,
  bytes~ : Bytes,
) -> TextEdit raise SourceError {
  try @utf8.decode(bytes) catch {
    @utf8.Malformed(rest) => raise InvalidUtf8(bytes.length() - rest.length())
  } noraise {
    text => TextEdit::replace(start_byte~, old_end_byte~, text~)
  }
}
