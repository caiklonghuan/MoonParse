///|
fn emit_u8(out : Array[Byte], value : Int) -> Unit {
  out.push(value.to_byte())
}

///|
fn emit_u32(out : Array[Byte], value : Int) -> Unit {
  out.push((value & 0xff).to_byte())
  out.push(((value >> 8) & 0xff).to_byte())
  out.push(((value >> 16) & 0xff).to_byte())
  out.push(((value >> 24) & 0xff).to_byte())
}

///|
fn emit_string(out : Array[Byte], value : String) -> Unit {
  let encoded = @utf8.encode(value)
  emit_u32(out, encoded.length())
  for byte in encoded {
    out.push(byte)
  }
}

///|
fn emit_expr(out : Array[Byte], expr : QueryExpr) -> Unit {
  match expr {
    Named(id, _, children) => {
      emit_u8(out, 0x10)
      emit_u32(out, id)
      emit_u32(out, children.length())
      for child in children {
        emit_u8(out, 0x20)
        emit_u32(out, child.field_id.unwrap_or(-1))
        emit_u8(
          out,
          match child.quantifier {
            One => 0
            ZeroOrOne => 1
            ZeroOrMore => 2
            OneOrMore => 3
          },
        )
        emit_u32(out, child.capture_index.unwrap_or(-1))
        emit_u8(out, if child.anchor_before { 1 } else { 0 })
        emit_u8(out, if child.anchor_after { 1 } else { 0 })
        emit_expr(out, child.expr)
      }
    }
    Anonymous(text) => {
      emit_u8(out, 0x11)
      emit_string(out, text)
    }
    Wildcard => emit_u8(out, 0x12)
    Alternation(items) => {
      emit_u8(out, 0x13)
      emit_u32(out, items.length())
      for item in items {
        emit_expr(out, item)
      }
    }
  }
}

///|
fn emit_predicate(out : Array[Byte], predicate : QueryPredicate) -> Unit {
  match predicate {
    Eq(capture, value) => {
      emit_u8(out, 0x30)
      emit_string(out, capture)
      emit_string(out, value)
    }
    NotEq(capture, value) => {
      emit_u8(out, 0x31)
      emit_string(out, capture)
      emit_string(out, value)
    }
    Match(capture, value) => {
      emit_u8(out, 0x32)
      emit_string(out, capture)
      emit_string(out, value)
    }
    NotMatch(capture, value) => {
      emit_u8(out, 0x33)
      emit_string(out, capture)
      emit_string(out, value)
    }
    AnyOf(capture, values) => {
      emit_u8(out, 0x34)
      emit_string(out, capture)
      emit_u32(out, values.length())
      for value in values {
        emit_string(out, value)
      }
    }
  }
}

///|
fn encode_query_bytecode(patterns : Array[QueryPattern]) -> Bytes {
  let out : Array[Byte] = [b'M', b'Q', b'R', b'Y', 1, 0, 0, 0]
  emit_u32(out, patterns.length())
  for pattern in patterns {
    emit_u8(out, 0x01)
    emit_u32(out, pattern.index)
    emit_u32(out, pattern.capture_names.length())
    for name in pattern.capture_names {
      emit_string(out, name)
    }
    emit_u32(out, pattern.root_capture_index.unwrap_or(-1))
    emit_expr(out, pattern.root)
    emit_u32(out, pattern.predicates.length())
    for predicate in pattern.predicates {
      emit_predicate(out, predicate)
    }
    emit_u8(out, 0xff)
  }
  Bytes::from_array(out)
}
