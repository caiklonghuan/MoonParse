///|
priv struct ManifestJsonParser {
  bytes : Bytes
  end : Int
  mut cursor : Int
}

///|
fn manifest_is_digit(byte : Byte) -> Bool {
  byte >= b'0' && byte <= b'9'
}

///|
fn manifest_is_lower_hex(byte : Byte) -> Bool {
  manifest_is_digit(byte) || (byte >= b'a' && byte <= b'f')
}

///|
fn manifest_hex_value(byte : Byte) -> Int {
  if manifest_is_digit(byte) {
    byte.to_int() - b'0'.to_int()
  } else {
    byte.to_int() - b'a'.to_int() + 10
  }
}

///|
fn manifest_utf16_units(bytes : Bytes) -> Array[Int] {
  let units : Array[Int] = []
  let mut cursor = 0
  while cursor < bytes.length() {
    let first = bytes[cursor].to_int()
    let (codepoint, width) = if first < 0x80 {
      (first, 1)
    } else if first < 0xE0 {
      (((first & 0x1F) << 6) | (bytes[cursor + 1].to_int() & 0x3F), 2)
    } else if first < 0xF0 {
      (
        ((first & 0x0F) << 12) |
        ((bytes[cursor + 1].to_int() & 0x3F) << 6) |
        (bytes[cursor + 2].to_int() & 0x3F),
        3,
      )
    } else {
      (
        ((first & 0x07) << 18) |
        ((bytes[cursor + 1].to_int() & 0x3F) << 12) |
        ((bytes[cursor + 2].to_int() & 0x3F) << 6) |
        (bytes[cursor + 3].to_int() & 0x3F),
        4,
      )
    }
    if codepoint <= 0xFFFF {
      units.push(codepoint)
    } else {
      let scalar = codepoint - 0x10000
      units.push(0xD800 + (scalar >> 10))
      units.push(0xDC00 + (scalar & 0x3FF))
    }
    cursor = cursor + width
  }
  units
}

///|
fn manifest_compare_bytes(left : Bytes, right : Bytes) -> Int {
  let left = manifest_utf16_units(left)
  let right = manifest_utf16_units(right)
  let common = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for index in 0..<common {
    if left[index] < right[index] {
      return -1
    }
    if left[index] > right[index] {
      return 1
    }
  }
  if left.length() < right.length() {
    -1
  } else if left.length() > right.length() {
    1
  } else {
    0
  }
}

///|
fn ManifestJsonParser::take(self : ManifestJsonParser) -> Byte? {
  if self.cursor >= self.end {
    None
  } else {
    let byte = self.bytes[self.cursor]
    self.cursor = self.cursor + 1
    Some(byte)
  }
}

///|
fn ManifestJsonParser::consume_literal(
  self : ManifestJsonParser,
  literal : Bytes,
) -> Result[Unit, PackValidationError] {
  for expected in literal {
    match self.take() {
      Some(actual) if actual == expected => ()
      _ => return Err(InvalidManifestJson)
    }
  }
  Ok(())
}

///|
fn manifest_append_utf8(
  parser : ManifestJsonParser,
  output : Array[Byte],
  first : Byte,
) -> Result[Unit, PackValidationError] {
  let first_int = first.to_int()
  let length = if first_int >= 0xC2 && first_int <= 0xDF {
    2
  } else if first_int >= 0xE0 && first_int <= 0xEF {
    3
  } else if first_int >= 0xF0 && first_int <= 0xF4 {
    4
  } else {
    return Err(InvalidManifestUtf8)
  }
  if parser.cursor + length - 1 > parser.end {
    return Err(InvalidManifestUtf8)
  }
  let second = parser.bytes[parser.cursor].to_int()
  if second < 0x80 ||
    second > 0xBF ||
    (first_int == 0xE0 && second < 0xA0) ||
    (first_int == 0xED && second > 0x9F) ||
    (first_int == 0xF0 && second < 0x90) ||
    (first_int == 0xF4 && second > 0x8F) {
    return Err(InvalidManifestUtf8)
  }
  for offset in 2..<length {
    let continuation = parser.bytes[parser.cursor + offset - 1].to_int()
    if continuation < 0x80 || continuation > 0xBF {
      return Err(InvalidManifestUtf8)
    }
  }
  output.push(first)
  for _ in 1..<length {
    output.push(parser.bytes[parser.cursor])
    parser.cursor = parser.cursor + 1
  }
  Ok(())
}

///|
fn ManifestJsonParser::parse_string(
  self : ManifestJsonParser,
) -> Result[Bytes, PackValidationError] {
  match self.take() {
    Some(b'"') => ()
    _ => return Err(InvalidManifestJson)
  }
  let output : Array[Byte] = []
  for ;; {
    let byte = match self.take() {
      Some(value) => value
      None => return Err(InvalidManifestJson)
    }
    if byte == b'"' {
      return Ok(Bytes::makei(output.length(), fn(index) { output[index] }))
    }
    if byte == b'\\' {
      let escaped = match self.take() {
        Some(value) => value
        None => return Err(InvalidManifestJson)
      }
      match escaped {
        b'"' => output.push(b'"')
        b'\\' => output.push(b'\\')
        b'b' => output.push(0x08)
        b't' => output.push(0x09)
        b'n' => output.push(0x0A)
        b'f' => output.push(0x0C)
        b'r' => output.push(0x0D)
        b'u' => {
          if self.cursor + 4 > self.end ||
            self.bytes[self.cursor] != b'0' ||
            self.bytes[self.cursor + 1] != b'0' ||
            !manifest_is_lower_hex(self.bytes[self.cursor + 2]) ||
            !manifest_is_lower_hex(self.bytes[self.cursor + 3]) {
            return Err(NonCanonicalManifestJson)
          }
          let value = manifest_hex_value(self.bytes[self.cursor + 2]) * 16 +
            manifest_hex_value(self.bytes[self.cursor + 3])
          self.cursor = self.cursor + 4
          if value >= 0x20 ||
            value == 0x08 ||
            value == 0x09 ||
            value == 0x0A ||
            value == 0x0C ||
            value == 0x0D {
            return Err(NonCanonicalManifestJson)
          }
          output.push(value.to_byte())
        }
        _ => return Err(NonCanonicalManifestJson)
      }
    } else if byte.to_int() < 0x20 {
      return Err(InvalidManifestJson)
    } else if byte.to_int() < 0x80 {
      output.push(byte)
    } else {
      match manifest_append_utf8(self, output, byte) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
  }
}

///|
fn manifest_ascii_string(bytes : Bytes, start : Int, end : Int) -> String {
  let chars : Array[Char] = []
  for index in start..<end {
    chars.push(bytes[index].to_char())
  }
  String::from_array(chars)
}

///|
fn ManifestJsonParser::parse_number(
  self : ManifestJsonParser,
) -> Result[Unit, PackValidationError] {
  let number_start = self.cursor
  let negative = self.bytes[self.cursor] == b'-'
  if negative {
    self.cursor = self.cursor + 1
    if self.cursor >= self.end {
      return Err(InvalidManifestNumber)
    }
  }
  if self.bytes[self.cursor] == b'0' {
    self.cursor = self.cursor + 1
    if self.cursor < self.end && manifest_is_digit(self.bytes[self.cursor]) {
      return Err(InvalidManifestNumber)
    }
  } else if self.bytes[self.cursor] >= b'1' && self.bytes[self.cursor] <= b'9' {
    self.cursor = self.cursor + 1
    while self.cursor < self.end && manifest_is_digit(self.bytes[self.cursor]) {
      self.cursor = self.cursor + 1
    }
  } else {
    return Err(InvalidManifestNumber)
  }
  if self.cursor < self.end && self.bytes[self.cursor] == b'.' {
    self.cursor = self.cursor + 1
    if self.cursor >= self.end || !manifest_is_digit(self.bytes[self.cursor]) {
      return Err(InvalidManifestNumber)
    }
    while self.cursor < self.end && manifest_is_digit(self.bytes[self.cursor]) {
      self.cursor = self.cursor + 1
    }
  }
  if self.cursor < self.end &&
    (self.bytes[self.cursor] == b'e' || self.bytes[self.cursor] == b'E') {
    self.cursor = self.cursor + 1
    if self.cursor < self.end &&
      (self.bytes[self.cursor] == b'+' || self.bytes[self.cursor] == b'-') {
      self.cursor = self.cursor + 1
    }
    if self.cursor >= self.end || !manifest_is_digit(self.bytes[self.cursor]) {
      return Err(InvalidManifestNumber)
    }
    while self.cursor < self.end && manifest_is_digit(self.bytes[self.cursor]) {
      self.cursor = self.cursor + 1
    }
  }
  let lexeme = manifest_ascii_string(self.bytes, number_start, self.cursor)
  let value = @string.parse_double(lexeme) catch {
    _ => return Err(InvalidManifestNumber)
  }
  if value.is_nan() || value.is_inf() || value.to_string() != lexeme {
    return Err(InvalidManifestNumber)
  }
  Ok(())
}

///|
fn ManifestJsonParser::parse_array(
  self : ManifestJsonParser,
  depth : Int,
) -> Result[Unit, PackValidationError] {
  self.cursor = self.cursor + 1
  if self.cursor < self.end && self.bytes[self.cursor] == b']' {
    self.cursor = self.cursor + 1
    return Ok(())
  }
  for ;; {
    match self.parse_value(depth + 1) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.take() {
      Some(b',') => ()
      Some(b']') => return Ok(())
      _ => return Err(InvalidManifestJson)
    }
  }
}

///|
fn ManifestJsonParser::parse_object(
  self : ManifestJsonParser,
  depth : Int,
) -> Result[Unit, PackValidationError] {
  self.cursor = self.cursor + 1
  if self.cursor < self.end && self.bytes[self.cursor] == b'}' {
    self.cursor = self.cursor + 1
    return Ok(())
  }
  let mut previous_key : Bytes? = None
  for ;; {
    if self.cursor < self.end &&
      (
        self.bytes[self.cursor] == b' ' ||
        self.bytes[self.cursor] == b'\t' ||
        self.bytes[self.cursor] == b'\r' ||
        self.bytes[self.cursor] == b'\n'
      ) {
      return Err(NonCanonicalManifestJson)
    }
    let key = match self.parse_string() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    match previous_key {
      Some(previous) => {
        let order = manifest_compare_bytes(previous, key)
        if order == 0 {
          return Err(DuplicateManifestKey)
        }
        if order > 0 {
          return Err(NonCanonicalManifestJson)
        }
      }
      None => ()
    }
    previous_key = Some(key)
    match self.take() {
      Some(b':') => ()
      _ => return Err(InvalidManifestJson)
    }
    match self.parse_value(depth + 1) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.take() {
      Some(b',') => ()
      Some(b'}') => return Ok(())
      _ => return Err(InvalidManifestJson)
    }
  }
}

///|
fn ManifestJsonParser::parse_value(
  self : ManifestJsonParser,
  depth : Int,
) -> Result[Unit, PackValidationError] {
  if depth > 64 || self.cursor >= self.end {
    return Err(InvalidManifestJson)
  }
  match self.bytes[self.cursor] {
    b'{' => self.parse_object(depth)
    b'[' => self.parse_array(depth)
    b'"' =>
      match self.parse_string() {
        Ok(_) => Ok(())
        Err(error) => Err(error)
      }
    b't' => self.consume_literal(b"true")
    b'f' => self.consume_literal(b"false")
    b'n' => self.consume_literal(b"null")
    b'-' | b'0'..=b'9' => self.parse_number()
    b' ' | b'\t' | b'\r' | b'\n' => Err(NonCanonicalManifestJson)
    _ => Err(InvalidManifestJson)
  }
}

///|
fn validate_manifest_json(
  bytes : Bytes,
  start : Int,
  length : Int,
) -> Result[Unit, PackValidationError] {
  if length < 2 || bytes[start] != b'{' {
    return Err(InvalidManifestJson)
  }
  let parser : ManifestJsonParser = {
    bytes,
    end: start + length,
    cursor: start,
  }
  match parser.parse_object(0) {
    Err(error) => Err(error)
    Ok(_) if parser.cursor != parser.end =>
      if parser.bytes[parser.cursor] == b' ' ||
        parser.bytes[parser.cursor] == b'\t' ||
        parser.bytes[parser.cursor] == b'\r' ||
        parser.bytes[parser.cursor] == b'\n' {
        Err(NonCanonicalManifestJson)
      } else {
        Err(InvalidManifestJson)
      }
    Ok(_) => Ok(())
  }
}
