///|
// ─── §7 JSON 序列化 ──────────────────────────────────────────────────────────
//
// Phase 1 只需 JSON，便于调试和与外部工具交互。
// 二进制格式（serialize_table / deserialize_table）留待 Phase 2。
//
// 输出 JSON 结构总览：
// {
//   "states": <int>,
//   "productions": [...],
//   "action": [...],
//   "goto": [...],
//   "symbol_metadata": [...]
// }

// ─── 辅助：基础 JSON 构造 ────────────────────────────────────────────────────

///|
/// 转义 JSON 字符串中的特殊字符
fn json_escape(s : String) -> String {
  let mut out = ""
  for ch in s {
    match ch {
      '"' => out = out + "\\\""
      '\\' => out = out + "\\\\"
      '\n' => out = out + "\\n"
      '\r' => out = out + "\\r"
      '\t' => out = out + "\\t"
      _ => out = out + ch.to_string()
    }
  }
  out
}

///|
/// 构造 JSON 字符串字面量（带引号）
fn jstr(s : String) -> String {
  "\"" + json_escape(s) + "\""
}

///|
/// 将 Array[String] 序列化为 JSON 数组
fn jarray(items : Array[String]) -> String {
  if items.length() == 0 {
    return "[]"
  }
  let mut out = "["
  let mut first = true
  for item in items {
    if first {
      first = false
    } else {
      out = out + ","
    }
    out = out + item
  }
  out + "]"
}

///|
/// 构造 JSON 对象，fields 为 [(key, value_json)]
fn jobj(fields : Array[(String, String)]) -> String {
  if fields.length() == 0 {
    return "{}"
  }
  let mut out = "{"
  let mut first = true
  for kv in fields {
    let (k, v) = kv
    if first {
      first = false
    } else {
      out = out + ","
    }
    out = out + jstr(k) + ":" + v
  }
  out + "}"
}

// ─── 子类型序列化 ────────────────────────────────────────────────────────────

///|
/// Symbol → JSON（"terminal" / "nonterminal" / "eoi"）
fn symbol_to_json(sym : Symbol) -> String {
  match sym {
    Terminal(id) => jobj([("type", jstr("terminal")), ("id", "\{id}")])
    NonTerminal(id) => jobj([("type", jstr("nonterminal")), ("id", "\{id}")])
    EndOfInput => jobj([("type", jstr("eoi"))])
  }
}

///|
/// BodySymbol → JSON
fn body_symbol_to_json(bs : BodySymbol) -> String {
  let sym_json = symbol_to_json(bs.symbol)
  match bs.field_name {
    None => jobj([("symbol", sym_json)])
    Some(name) => jobj([("symbol", sym_json), ("field_name", jstr(name))])
  }
}

///|
/// Action → JSON
fn action_to_json(act : Action) -> String {
  match act {
    Shift(id) => jobj([("type", jstr("shift")), ("state", "\{id}")])
    Reduce(id) => jobj([("type", jstr("reduce")), ("production", "\{id}")])
    Accept => jobj([("type", jstr("accept"))])
  }
}

///|
/// Production → JSON
fn production_to_json(prod : Production) -> String {
  let body_arr = prod.body.map(body_symbol_to_json)
  let fields : Array[(String, String)] = [
    ("id", "\{prod.id}"),
    ("head", "\{prod.head}"),
    ("body", jarray(body_arr)),
    ("rule_name", jstr(prod.rule_name)),
  ]
  match prod.prec {
    Some(p) => fields.push(("prec", "\{p}"))
    None => ()
  }
  match prod.assoc {
    Some(k) => {
      let kstr = match k {
        @grammar.PrecKind::Left => "left"
        @grammar.PrecKind::Right => "right"
        @grammar.PrecKind::Nonassoc => "nonassoc"
        @grammar.PrecKind::Dynamic => "dynamic"
      }
      fields.push(("assoc", jstr(kstr)))
    }
    None => ()
  }
  jobj(fields)
}

///|
/// SymbolMeta → JSON
fn symbol_meta_to_json(meta : SymbolMeta) -> String {
  jobj([
    ("name", jstr(meta.name)),
    ("is_named", if meta.is_named { "true" } else { "false" }),
  ])
}

///|
/// TerminalDef → JSON
fn terminal_def_to_json(td : TerminalDef) -> String {
  match td {
    Literal(s) => jobj([("type", jstr("literal")), ("value", jstr(s))])
    Regex(re) => jobj([("type", jstr("regex")), ("value", jstr(re))])
    AnyChar => jobj([("type", jstr("anychar"))])
  }
}
// ─── 公开 API ─────────────────────────────────────────────────────────────────

///|
/// 将 ParseTable 序列化为紧凑 JSON 字符串（Phase 1 调试 / 工具链互操作用）。
///
/// JSON 结构：
/// ```json
/// {
///   "states": <int>,
///   "productions": [ { "id":0, "head":0, "body":[...], ... }, ... ],
///   "action": [
///     { "state":<int>, "terminal":<int>, "actions":[...] }, ...
///   ],
///   "goto": [
///     { "state":<int>, "nonterminal":<int>, "target":<int> }, ...
///   ],
///   "symbol_metadata": [
///     { "name":"...", "is_named":true }, ...
///   ]
/// }
/// ```
pub fn table_to_json(table : ParseTable) -> String {
  // productions 数组
  let prods_json = jarray(table.productions.map(production_to_json))

  // action 表 → 数组形式
  let action_entries : Array[String] = []
  for key, actions in table.action {
    let (state, terminal) = key
    let acts_json = jarray(actions.map(action_to_json))
    action_entries.push(
      jobj([
        ("state", "\{state}"),
        ("terminal", "\{terminal}"),
        ("actions", acts_json),
      ]),
    )
  }
  let action_json = jarray(action_entries)

  // goto 表 → 数组形式
  let goto_entries : Array[String] = []
  for key, target in table.goto_table {
    let (state, nt) = key
    goto_entries.push(
      jobj([
        ("state", "\{state}"),
        ("nonterminal", "\{nt}"),
        ("target", "\{target}"),
      ]),
    )
  }
  let goto_json = jarray(goto_entries)

  // symbol_metadata 数组
  let meta_json = jarray(table.symbol_metadata.map(symbol_meta_to_json))

  // terminal_patterns 数组
  let tp_entries : Array[String] = []
  for id, def in table.terminal_patterns {
    tp_entries.push(
      jobj([("id", "\{id}"), ("pattern", terminal_def_to_json(def))]),
    )
  }
  let tp_json = jarray(tp_entries)

  jobj([
    ("states", "\{table.states}"),
    ("productions", prods_json),
    ("action", action_json),
    ("goto", goto_json),
    ("symbol_metadata", meta_json),
    ("terminal_patterns", tp_json),
  ])
}

///|
// ─── §7b 二进制序列化基础设施 ────────────────────────────────────────────────
//
// 格式版本 1（小端字节序）：
//   magic   : [0x4D, 0x50, 0x54, 0x01]   // "MPT\x01"
//   ……其余节区见 serialize_table / deserialize_table 注释……
//
// BinWriter ─ 可增长字节缓冲区
//               write_u8 / write_u16_le / write_u32_le / write_str
//               patch_u32_le（回填已占位的计数字段）/ len / to_bytes
//
// BinError  ─ 反序列化错误类型（UnexpectedEof / InvalidData）
//
// BinReader ─ 固定字节缓冲 + 游标
//               read_u8 / read_u16_le / read_u32_le / read_str / remaining
//
// 字符串编码约定（仅限此包内部）：
//   u16 字节数（小端）+ 各字符低 8 位字节序列。
//   被序列化的字符串（规则名、终结符字面量、正则模式）均为 ASCII，无信息损失。

// ─── BinWriter ────────────────────────────────────────────────────────────────

///|
/// 可增长二进制写入缓冲区（小端字节序）
priv struct BinWriter {
  buf : Array[Byte]
}

///|
fn BinWriter::new() -> BinWriter {
  { buf: [] }
}

///|
fn BinWriter::write_u8(self : BinWriter, v : Int) -> Unit {
  self.buf.push((v & 0xFF).to_byte())
}

///|
fn BinWriter::write_u16_le(self : BinWriter, v : Int) -> Unit {
  self.buf.push((v & 0xFF).to_byte())
  self.buf.push(((v >> 8) & 0xFF).to_byte())
}

///|
fn BinWriter::write_u32_le(self : BinWriter, v : Int) -> Unit {
  self.buf.push((v & 0xFF).to_byte())
  self.buf.push(((v >> 8) & 0xFF).to_byte())
  self.buf.push(((v >> 16) & 0xFF).to_byte())
  self.buf.push(((v >> 24) & 0xFF).to_byte())
}

///|
/// 写入字符串：先写 u16 字节数（小端），再逐字符写低 8 位字节
fn BinWriter::write_str(self : BinWriter, s : String) -> Unit {
  self.write_u16_le(s.length())
  for ch in s {
    self.write_u8(ch.to_int() & 0xFF)
  }
}

///|
/// 回填：将 v 以小端 u32 写入已预留的 offset 处（用于事后修正计数 / 长度字段）
fn BinWriter::patch_u32_le(self : BinWriter, offset : Int, v : Int) -> Unit {
  self.buf[offset] = (v & 0xFF).to_byte()
  self.buf[offset + 1] = ((v >> 8) & 0xFF).to_byte()
  self.buf[offset + 2] = ((v >> 16) & 0xFF).to_byte()
  self.buf[offset + 3] = ((v >> 24) & 0xFF).to_byte()
}

///|
/// 当前已写入字节数（可作为 patch_u32_le 的 offset 参数）
fn BinWriter::len(self : BinWriter) -> Int {
  self.buf.length()
}

///|
/// 将缓冲区内容转换为不可变 Bytes
fn BinWriter::to_bytes(self : BinWriter) -> Bytes {
  Bytes::makei(self.buf.length(), fn(i) { self.buf[i] })
}

// ─── BinError ─────────────────────────────────────────────────────────────────

///|
/// 反序列化期间的读取错误
priv suberror BinError {
  /// 读取超出数据末尾（携带当前偏移描述）
  UnexpectedEof(String)
  /// 数据内容不合规（magic 错误、枚举 tag 越界等）
  InvalidData(String)
}

// ─── BinReader ────────────────────────────────────────────────────────────────

///|
/// 固定字节缓冲读取器（小端字节序，带游标）
priv struct BinReader {
  data : Bytes
  mut pos : Int
}

///|
fn BinReader::new(data : Bytes) -> BinReader {
  { data, pos: 0 }
}

///|
/// 游标之后的剩余可读字节数
fn BinReader::remaining(self : BinReader) -> Int {
  self.data.length() - self.pos
}

///|
fn BinReader::read_u8(self : BinReader) -> Int raise BinError {
  if self.pos >= self.data.length() {
    raise UnexpectedEof("offset=\{self.pos}")
  }
  let v = self.data[self.pos].to_int()
  self.pos = self.pos + 1
  v
}

///|
fn BinReader::read_u16_le(self : BinReader) -> Int raise BinError {
  let lo = self.read_u8()
  let hi = self.read_u8()
  lo | (hi << 8)
}

///|
fn BinReader::read_u32_le(self : BinReader) -> Int raise BinError {
  let b0 = self.read_u8()
  let b1 = self.read_u8()
  let b2 = self.read_u8()
  let b3 = self.read_u8()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
/// 读取字符串：先读 u16 字节数（小端），再逐字节还原为字符（低 8 位即 Unicode 码点）
fn BinReader::read_str(self : BinReader) -> String raise BinError {
  let n = self.read_u16_le()
  let mut s = ""
  for _ in 0..<n {
    let b = self.read_u8()
    s = s + b.unsafe_to_char().to_string()
  }
  s
}

// ─── 公开 API（Phase 2 实现，当前为桩） ──────────────────────────────────────

///|
/// 将 ParseTable 序列化为二进制格式（Phase 2 实现，当前返回空字节）。
pub fn serialize_table(_table : ParseTable) -> Bytes {
  Bytes::new(0)
}

///|
/// 从二进制字节反序列化 ParseTable（Phase 2 实现，当前返回 Err）。
pub fn deserialize_table(_bytes : Bytes) -> Result[ParseTable, String] {
  Err("deserialize_table: not implemented yet")
}
