///|
fn lp_base64_value(code : Int) -> Int {
  if code >= 65 && code <= 90 {
    code - 65
  } else if code >= 97 && code <= 122 {
    code - 97 + 26
  } else if code >= 48 && code <= 57 {
    code - 48 + 52
  } else if code == 43 {
    62
  } else if code == 47 {
    63
  } else {
    -1
  }
}

///|
fn lp_base64_char(index : Int) -> Char {
  if index < 26 {
    (65 + index).unsafe_to_char()
  } else if index < 52 {
    (97 + index - 26).unsafe_to_char()
  } else if index < 62 {
    (48 + index - 52).unsafe_to_char()
  } else if index == 62 {
    '+'
  } else {
    '/'
  }
}

///|
fn lp_base64_decode(input : String) -> Bytes? {
  let values : Array[Byte] = []
  let mut accumulator = 0
  let mut bits = 0
  for index in 0..<input.length() {
    let code = input[index].to_int()
    if code == 61 {
      break
    }
    let value = lp_base64_value(code)
    if value < 0 {
      return None
    }
    accumulator = (accumulator << 6) | value
    bits = bits + 6
    if bits >= 8 {
      bits = bits - 8
      values.push(((accumulator >> bits) & 0xFF).to_byte())
    }
  }
  Some(Bytes::makei(values.length(), fn(index) { values[index] }))
}

///|
fn lp_base64_encode(data : Bytes) -> String {
  let buffer = StringBuilder::new()
  let mut index = 0
  while index + 2 < data.length() {
    let a = data[index].to_int()
    let b = data[index + 1].to_int()
    let c = data[index + 2].to_int()
    buffer.write_char(lp_base64_char((a >> 2) & 0x3F))
    buffer.write_char(lp_base64_char(((a << 4) | (b >> 4)) & 0x3F))
    buffer.write_char(lp_base64_char(((b << 2) | (c >> 6)) & 0x3F))
    buffer.write_char(lp_base64_char(c & 0x3F))
    index = index + 3
  }
  if data.length() - index == 1 {
    let a = data[index].to_int()
    buffer.write_char(lp_base64_char((a >> 2) & 0x3F))
    buffer.write_char(lp_base64_char((a << 4) & 0x3F))
    buffer.write_string("==")
  } else if data.length() - index == 2 {
    let a = data[index].to_int()
    let b = data[index + 1].to_int()
    buffer.write_char(lp_base64_char((a >> 2) & 0x3F))
    buffer.write_char(lp_base64_char(((a << 4) | (b >> 4)) & 0x3F))
    buffer.write_char(lp_base64_char((b << 2) & 0x3F))
    buffer.write_char('=')
  }
  buffer.to_string()
}

///|
fn lp_json_string(value : String) -> String {
  let buffer = StringBuilder::new()
  buffer.write_char('"')
  for char in value {
    match char {
      '"' => buffer.write_string("\\\"")
      '\\' => buffer.write_string("\\\\")
      '\n' => buffer.write_string("\\n")
      '\r' => buffer.write_string("\\r")
      '\t' => buffer.write_string("\\t")
      '\b' => buffer.write_string("\\b")
      '\u{000C}' => buffer.write_string("\\f")
      _ => buffer.write_char(char)
    }
  }
  buffer.write_char('"')
  buffer.to_string()
}

///|
fn lp_json_optional(value : String?) -> String {
  match value {
    Some(value) => lp_json_string(value)
    None => "null"
  }
}
