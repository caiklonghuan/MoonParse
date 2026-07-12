///|
/// Flags stored on immutable green elements. Green elements deliberately carry
/// no source position, parent, snapshot, or source owner.
pub(all) struct GreenFlags {
  named : Bool
  extra : Bool
  error : Bool
  missing : Bool
  fragile_left : Bool
  fragile_right : Bool
} derive(Debug, Eq)

///|
pub fn GreenFlags::plain(named? : Bool = true) -> GreenFlags {
  {
    named,
    extra: false,
    error: false,
    missing: false,
    fragile_left: false,
    fragile_right: false,
  }
}

///|
pub(all) struct GreenId {
  value : Int
} derive(Debug, Eq)

///|
pub(all) struct GreenChild {
  green : GreenId
  field_id : Int?
} derive(Debug, Eq)

///|
pub(all) struct GreenToken {
  kind_id : Int
  text : String
  byte_width : Int
  flags : GreenFlags
} derive(Debug, Eq)

///|
pub(all) struct GreenNode {
  kind_id : Int
  production_id : Int
  children : Array[GreenChild]
  byte_width : Int
  flags : GreenFlags
} derive(Debug, Eq)

///|
pub(all) enum GreenElement {
  Token(GreenToken)
  Node(GreenNode)
} derive(Debug, Eq)

///|
pub(all) suberror GreenBuildError {
  InvalidKind(Int)
  InvalidProduction(Int)
  InvalidField(Int)
  UnknownChild(GreenId)
  MissingElementHasWidth
  WidthOverflow
} derive(Debug, Eq)

///|
struct GreenRecord {
  element : GreenElement
  canonical_key : Bytes
}

///|
/// A parse-local arena and hash-cons table. It is intentionally not global:
/// snapshots share immutable IDs only while they explicitly retain this arena.
pub struct GreenArena {
  records : Array[GreenRecord]
  buckets : Array[Array[Int]]
}

///|
pub fn GreenArena::new(bucket_count? : Int = 256) -> GreenArena {
  let count = if bucket_count <= 0 { 1 } else { bucket_count }
  { records: [], buckets: Array::makei(count, fn(_index) { [] }) }
}

///|
fn emit_u32(out : Array[Byte], value : Int) -> Unit {
  out.push((value & 0xff).to_byte())
  out.push(((value >> 8) & 0xff).to_byte())
  out.push(((value >> 16) & 0xff).to_byte())
  out.push(((value >> 24) & 0xff).to_byte())
}

///|
fn emit_u64(out : Array[Byte], value : Int) -> Unit {
  let wide = value.to_int64()
  for shift = 0; shift < 64; shift = shift + 8 {
    out.push(((wide >> shift) & 0xffL).to_int().to_byte())
  }
}

///|
fn emit_bytes(out : Array[Byte], value : Bytes) -> Unit {
  emit_u32(out, value.length())
  for byte in value {
    out.push(byte)
  }
}

///|
fn flag_byte(flags : GreenFlags) -> Byte {
  let mut bits = 0
  if flags.named {
    bits = bits | 1
  }
  if flags.extra {
    bits = bits | 2
  }
  if flags.error {
    bits = bits | 4
  }
  if flags.missing {
    bits = bits | 8
  }
  if flags.fragile_left {
    bits = bits | 16
  }
  if flags.fragile_right {
    bits = bits | 32
  }
  bits.to_byte()
}

///|
fn bytes_equal(left : Bytes, right : Bytes) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index = 0; index < left.length(); index = index + 1 {
    if left[index] != right[index] {
      return false
    }
  }
  true
}

///|
fn key_hash(key : Bytes, bucket_count : Int) -> Int {
  let mut hash = 2166136261L
  for byte in key {
    hash = (hash ^ byte.to_int().to_int64()) * 16777619L
  }
  let positive = if hash < 0L { -hash } else { hash }
  (positive % bucket_count.to_int64()).to_int()
}

///|
fn GreenArena::intern(
  self : GreenArena,
  element : GreenElement,
  key : Bytes,
) -> GreenId {
  let bucket_index = key_hash(key, self.buckets.length())
  let bucket = self.buckets[bucket_index]
  for record_index in bucket {
    if bytes_equal(self.records[record_index].canonical_key, key) {
      return { value: record_index }
    }
  }
  let value = self.records.length()
  self.records.push({ element, canonical_key: key })
  bucket.push(value)
  { value, }
}

///|
pub fn GreenArena::intern_token(
  self : GreenArena,
  kind_id : Int,
  text : String,
  flags? : GreenFlags = GreenFlags::plain(),
) -> GreenId raise GreenBuildError {
  if kind_id < 0 {
    raise InvalidKind(kind_id)
  }
  let bytes = @utf8.encode(text)
  if flags.missing && bytes.length() != 0 {
    raise MissingElementHasWidth
  }
  let key : Array[Byte] = [0]
  emit_u32(key, kind_id)
  emit_u64(key, bytes.length())
  key.push(flag_byte(flags))
  emit_bytes(key, bytes)
  self.intern(
    Token({ kind_id, text, byte_width: bytes.length(), flags }),
    Bytes::from_array(key),
  )
}

///|
pub fn GreenArena::intern_node(
  self : GreenArena,
  kind_id : Int,
  production_id : Int,
  children : Array[GreenChild],
  flags? : GreenFlags = GreenFlags::plain(),
) -> GreenId raise GreenBuildError {
  if kind_id < 0 {
    raise InvalidKind(kind_id)
  }
  if production_id < 0 {
    raise InvalidProduction(production_id)
  }
  let mut width = 0
  for child in children {
    if child.green.value < 0 || child.green.value >= self.records.length() {
      raise UnknownChild(child.green)
    }
    match child.field_id {
      Some(field) if field < 0 => raise InvalidField(field)
      _ => ()
    }
    let child_width = match self.records[child.green.value].element {
      Token(token) => token.byte_width
      Node(node) => node.byte_width
    }
    if child_width > 0x7fffffff - width {
      raise WidthOverflow
    }
    width = width + child_width
  }
  if flags.missing && width != 0 {
    raise MissingElementHasWidth
  }
  let key : Array[Byte] = [1]
  emit_u32(key, kind_id)
  emit_u32(key, production_id)
  emit_u64(key, width)
  key.push(flag_byte(flags))
  emit_u32(key, children.length())
  for child in children {
    match child.field_id {
      None => key.push(0)
      Some(field) => {
        key.push(1)
        emit_u32(key, field)
      }
    }
    emit_bytes(key, self.records[child.green.value].canonical_key)
  }
  self.intern(
    Node({
      kind_id,
      production_id,
      children: children.copy(),
      byte_width: width,
      flags,
    }),
    Bytes::from_array(key),
  )
}

///|
pub fn GreenArena::get(self : GreenArena, id : GreenId) -> GreenElement? {
  if id.value < 0 || id.value >= self.records.length() {
    None
  } else {
    match self.records[id.value].element {
      Token(token) => Some(Token(token))
      Node(node) => Some(Node({ ..node, children: node.children.copy() }))
    }
  }
}

///|
pub fn GreenArena::byte_width(self : GreenArena, id : GreenId) -> Int? {
  match self.get(id) {
    Some(Token(token)) => Some(token.byte_width)
    Some(Node(node)) => Some(node.byte_width)
    None => None
  }
}

///|
pub fn GreenArena::element_count(self : GreenArena) -> Int {
  self.records.length()
}

///|
fn GreenArena::append_text(
  self : GreenArena,
  id : GreenId,
  out : Array[String],
) -> Bool {
  match self.get(id) {
    None => false
    Some(Token(token)) => {
      out.push(token.text)
      true
    }
    Some(Node(node)) => {
      for child in node.children {
        if !self.append_text(child.green, out) {
          return false
        }
      }
      true
    }
  }
}

///|
pub fn GreenArena::lossless_text(self : GreenArena, root : GreenId) -> String? {
  let parts : Array[String] = []
  if self.append_text(root, parts) {
    Some(parts.join(""))
  } else {
    None
  }
}
