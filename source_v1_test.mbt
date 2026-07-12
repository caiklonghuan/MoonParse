///|
test "Source uses UTF-8 byte ranges and defensive byte copies" {
  let source = @MoonParse.Source::from_string("a你\r\nb")
  assert_eq(source.byte_length(), 7)
  assert_eq(source.slice({ start_byte: 1, end_byte: 4 }), "你")
  let bytes = source.to_bytes()
  assert_eq(bytes.length(), 7)
  assert_eq(bytes[0], b'a')
  assert_eq(source.slice({ start_byte: 0, end_byte: 1 }), "a")
}

///|
test "Source rejects split UTF-8 and out-of-bounds ranges" {
  let source = @MoonParse.Source::from_string("你")
  try source.slice({ start_byte: 1, end_byte: 2 }) catch {
    @MoonParse.SplitUtf8CodePoint(offset) => assert_eq(offset, 1)
    _ => fail("expected SplitUtf8CodePoint")
  } noraise {
    _ => fail("split range must fail")
  }
  try source.slice({ start_byte: 0, end_byte: 4 }) catch {
    @MoonParse.InvalidByteRange(start, end, length) => {
      assert_eq(start, 0)
      assert_eq(end, 4)
      assert_eq(length, 3)
    }
    _ => fail("expected InvalidByteRange")
  } noraise {
    _ => fail("out-of-bounds range must fail")
  }
}

///|
test "TextEdit constructors preserve validated replacement bytes" {
  ignore(@MoonParse.TextEdit::replace(start_byte=0, old_end_byte=0, text="你"))
  let bytes = @utf8.encode("ok")
  ignore(
    @MoonParse.TextEdit::replace_utf8(start_byte=0, old_end_byte=0, bytes~),
  )
}
