///|
// JSON 序列化
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

// 辅助：基础 JSON 构造

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

// 子类型序列化

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
// 公开 API

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

  // terminal_names 数组（TerminalId → 名称，runtime 错误信息用）
  let tn_entries : Array[String] = []
  for id, name in table.terminal_names {
    tn_entries.push(jobj([("id", "\{id}"), ("name", jstr(name))]))
  }
  let tn_json = jarray(tn_entries)

  // extras 数组（runtime 跳过不推栈的 token）
  let extras_json = jarray(table.extras.map(fn(tid) { "\{tid}" }))

  jobj([
    ("states", "\{table.states}"),
    ("productions", prods_json),
    ("action", action_json),
    ("goto", goto_json),
    ("symbol_metadata", meta_json),
    ("terminal_patterns", tp_json),
    ("terminal_names", tn_json),
    ("extras", extras_json),
  ])
}

///|
// b 二进制序列化基础设施
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

// BinWriter

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
/// 写入字符串：先写 u16 字符数（小端），再逐字符写 UTF-16 LE（2 字节/字符）
/// 覆盖完整 BMP（U+0000~U+FFFF），包括 CJK；字符数上限 65535
fn BinWriter::write_str(self : BinWriter, s : String) -> Unit {
  self.write_u16_le(s.length())
  for ch in s {
    self.write_u16_le(ch.to_int())
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

// BinError

///|
/// 反序列化期间的读取错误
priv suberror BinError {
  /// 读取超出数据末尾（携带当前偏移描述）
  UnexpectedEof(String)
  /// 数据内容不合规（magic 错误、枚举 tag 越界等）
  InvalidData(String)
}

// BinReader

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
/// 读取字符串：先读 u16 字符数（小端），再逐字符读 UTF-16 LE（2 字节/字符）
fn BinReader::read_str(self : BinReader) -> String raise BinError {
  let n = self.read_u16_le()
  let buf = StringBuilder::new()
  for _ in 0..<n {
    let code = self.read_u16_le()
    buf.write_char(code.unsafe_to_char())
  }
  buf.to_string()
}

// 领域类型序列化辅助
//
// tag 编码（全局固定）：
//   Symbol:      0=Terminal  1=NonTerminal  2=EndOfInput
//   Action:      0=Shift     1=Reduce       2=Accept
//   TerminalDef: 0=Literal   1=Regex        2=AnyChar
//   PrecKind:    0=Left      1=Right        2=Nonassoc  3=Dynamic

// ── Symbol ───────────────────────────────────────────────────────────────────

///|
fn write_symbol(w : BinWriter, sym : Symbol) -> Unit {
  match sym {
    Terminal(id) => {
      w.write_u8(0)
      w.write_u16_le(id)
    }
    NonTerminal(id) => {
      w.write_u8(1)
      w.write_u16_le(id)
    }
    EndOfInput => {
      w.write_u8(2)
      w.write_u16_le(0)
    }
  }
}

///|
fn read_symbol(r : BinReader) -> Symbol raise BinError {
  let tag = r.read_u8()
  let id = r.read_u16_le()
  match tag {
    0 => Terminal(id)
    1 => NonTerminal(id)
    2 => EndOfInput
    _ => raise InvalidData("symbol tag=\{tag}")
  }
}

// ── Action ───────────────────────────────────────────────────────────────────

///|
fn write_action(w : BinWriter, act : Action) -> Unit {
  match act {
    Shift(s) => {
      w.write_u8(0)
      w.write_u16_le(s)
    }
    Reduce(p) => {
      w.write_u8(1)
      w.write_u16_le(p)
    }
    Accept => {
      w.write_u8(2)
      w.write_u16_le(0)
    }
  }
}

///|
fn read_action(r : BinReader) -> Action raise BinError {
  let tag = r.read_u8()
  let target = r.read_u16_le()
  match tag {
    0 => Shift(target)
    1 => Reduce(target)
    2 => Accept
    _ => raise InvalidData("action tag=\{tag}")
  }
}

// ── TerminalDef ──────────────────────────────────────────────────────────────

///|
fn write_terminal_def(w : BinWriter, td : TerminalDef) -> Unit {
  match td {
    Literal(s) => {
      w.write_u8(0)
      w.write_str(s)
    }
    Regex(re) => {
      w.write_u8(1)
      w.write_str(re)
    }
    AnyChar => w.write_u8(2)
  }
}

///|
fn read_terminal_def(r : BinReader) -> TerminalDef raise BinError {
  let tag = r.read_u8()
  match tag {
    0 => Literal(r.read_str())
    1 => Regex(r.read_str())
    2 => AnyChar
    _ => raise InvalidData("terminal_def tag=\{tag}")
  }
}

// ── BodySymbol ───────────────────────────────────────────────────────────────

///|
fn write_body_symbol(w : BinWriter, bs : BodySymbol) -> Unit {
  write_symbol(w, bs.symbol)
  match bs.field_name {
    None => w.write_u8(0)
    Some(name) => {
      w.write_u8(1)
      w.write_str(name)
    }
  }
}

///|
fn read_body_symbol(r : BinReader) -> BodySymbol raise BinError {
  let symbol = read_symbol(r)
  let has_field = r.read_u8()
  let field_name = if has_field == 1 { Some(r.read_str()) } else { None }
  { symbol, field_name }
}

// ── Production ───────────────────────────────────────────────────────────────

///|
fn write_production(w : BinWriter, prod : Production) -> Unit {
  w.write_u16_le(prod.id)
  w.write_u16_le(prod.head)
  w.write_u16_le(prod.body.length())
  for bs in prod.body {
    write_body_symbol(w, bs)
  }
  match prod.prec {
    None => w.write_u8(0)
    Some(p) => {
      w.write_u8(1)
      w.write_u32_le(p)
    }
  }
  match prod.assoc {
    None => w.write_u8(0)
    Some(k) => {
      w.write_u8(1)
      let tag = match k {
        @grammar.PrecKind::Left => 0
        @grammar.PrecKind::Right => 1
        @grammar.PrecKind::Nonassoc => 2
        @grammar.PrecKind::Dynamic => 3
      }
      w.write_u8(tag)
    }
  }
  w.write_str(prod.rule_name)
  // lookahead constraint
  match prod.lookahead {
    None => w.write_u8(0)
    Some(NotFollowedBy(tids)) => {
      w.write_u8(1)
      w.write_u16_le(tids.length())
      for tid in tids {
        w.write_u16_le(tid)
      }
    }
    Some(FollowedBy(tids)) => {
      w.write_u8(2)
      w.write_u16_le(tids.length())
      for tid in tids {
        w.write_u16_le(tid)
      }
    }
  }
}

///|
fn read_production(r : BinReader) -> Production raise BinError {
  let id = r.read_u16_le()
  let head = r.read_u16_le()
  let body_len = r.read_u16_le()
  let body : Array[BodySymbol] = []
  for _ in 0..<body_len {
    body.push(read_body_symbol(r))
  }
  let has_prec = r.read_u8()
  let prec = if has_prec == 1 { Some(r.read_u32_le()) } else { None }
  let has_assoc = r.read_u8()
  let assoc : @grammar.PrecKind? = if has_assoc == 1 {
    let tag = r.read_u8()
    let k : @grammar.PrecKind = match tag {
      0 => @grammar.PrecKind::Left
      1 => @grammar.PrecKind::Right
      2 => @grammar.PrecKind::Nonassoc
      3 => @grammar.PrecKind::Dynamic
      _ => raise InvalidData("prec_kind tag=\{tag}")
    }
    Some(k)
  } else {
    None
  }
  let rule_name = r.read_str()
  let la_tag = r.read_u8()
  let lookahead : LookaheadConstraint? = match la_tag {
    0 => None
    1 => {
      let cnt = r.read_u16_le()
      let tids : Array[TerminalId] = []
      for _ in 0..<cnt {
        tids.push(r.read_u16_le())
      }
      Some(NotFollowedBy(tids))
    }
    2 => {
      let cnt = r.read_u16_le()
      let tids : Array[TerminalId] = []
      for _ in 0..<cnt {
        tids.push(r.read_u16_le())
      }
      Some(FollowedBy(tids))
    }
    _ => raise InvalidData("lookahead tag=\{la_tag}")
  }
  { id, head, body, prec, assoc, rule_name, lookahead }
}

// ── SymbolMeta ───────────────────────────────────────────────────────────────

///|
fn write_symbol_meta(w : BinWriter, meta : SymbolMeta) -> Unit {
  w.write_u8(if meta.is_named { 1 } else { 0 })
  w.write_str(meta.name)
}

///|
fn read_symbol_meta(r : BinReader) -> SymbolMeta raise BinError {
  let is_named = r.read_u8() != 0
  let name = r.read_str()
  { name, is_named }
}

// ── DfaState ─────────────────────────────────────────────────────────────────

///|
fn write_dfa_state(w : BinWriter, state : DfaState) -> Unit {
  w.write_u16_le(state.id)
  // transitions: Map[Char, DfaStateId] — 收集后写 count + 条目
  let trans_entries : Array[(Char, DfaStateId)] = []
  for ch, tgt in state.transitions {
    trans_entries.push((ch, tgt))
  }
  trans_entries.sort_by(fn(a, b) { a.0.to_int().compare(b.0.to_int()) })
  w.write_u16_le(trans_entries.length())
  for entry in trans_entries {
    let (ch, tgt) = entry
    w.write_u16_le(ch.to_int())
    w.write_u16_le(tgt)
  }
  match state.accept {
    None => w.write_u8(0)
    Some(t) => {
      w.write_u8(1)
      w.write_u16_le(t)
    }
  }
}

///|
fn read_dfa_state(r : BinReader) -> DfaState raise BinError {
  let id = r.read_u16_le()
  let trans_count = r.read_u16_le()
  let transitions : Map[Char, DfaStateId] = Map::new()
  for _ in 0..<trans_count {
    let ch_code = r.read_u16_le()
    let tgt = r.read_u16_le()
    transitions.set(ch_code.unsafe_to_char(), tgt)
  }
  let has_accept = r.read_u8()
  let accept = if has_accept == 1 { Some(r.read_u16_le()) } else { None }
  { id, transitions, accept }
}

// ── LexerDfa ─────────────────────────────────────────────────────────────────

///|
fn write_lexer_dfa(w : BinWriter, dfa : LexerDfa) -> Unit {
  w.write_u32_le(dfa.states.length())
  for state in dfa.states {
    write_dfa_state(w, state)
  }
  w.write_u16_le(dfa.start)
  // valid_tokens: Map[StateId, Array[TerminalId]]
  let vt_entries : Array[(StateId, Array[TerminalId])] = []
  for state_id, tids in dfa.valid_tokens {
    vt_entries.push((state_id, tids))
  }
  vt_entries.sort_by(fn(a, b) { a.0.compare(b.0) })
  w.write_u32_le(vt_entries.length())
  for entry in vt_entries {
    let (state_id, tids) = entry
    w.write_u16_le(state_id)
    w.write_u16_le(tids.length())
    for tid in tids {
      w.write_u16_le(tid)
    }
  }
}

///|
fn read_lexer_dfa(r : BinReader) -> LexerDfa raise BinError {
  let states_count = r.read_u32_le()
  let states : Array[DfaState] = []
  for _ in 0..<states_count {
    states.push(read_dfa_state(r))
  }
  let start = r.read_u16_le()
  let vt_count = r.read_u32_le()
  let valid_tokens : Map[StateId, Array[TerminalId]] = Map::new()
  for _ in 0..<vt_count {
    let state_id = r.read_u16_le()
    let tid_count = r.read_u16_le()
    let tids : Array[TerminalId] = []
    for _ in 0..<tid_count {
      tids.push(r.read_u16_le())
    }
    valid_tokens.set(state_id, tids)
  }
  { states, start, valid_tokens }
}

// ── terminal_patterns ────────────────────────────────────────────────────────

///|
fn write_terminal_patterns(
  w : BinWriter,
  patterns : Map[TerminalId, TerminalDef],
) -> Unit {
  let entries : Array[(TerminalId, TerminalDef)] = []
  for tid, td in patterns {
    entries.push((tid, td))
  }
  entries.sort_by(fn(a, b) { a.0.compare(b.0) })
  w.write_u32_le(entries.length())
  for entry in entries {
    let (tid, td) = entry
    w.write_u16_le(tid)
    write_terminal_def(w, td)
  }
}

///|
fn read_terminal_patterns(
  r : BinReader,
) -> Map[TerminalId, TerminalDef] raise BinError {
  let count = r.read_u32_le()
  let patterns : Map[TerminalId, TerminalDef] = Map::new()
  for _ in 0..<count {
    let tid = r.read_u16_le()
    let td = read_terminal_def(r)
    patterns.set(tid, td)
  }
  patterns
}

// 公开 API
//
// 格式版本 1 —— 节区顺序（全部小端）：
//
//   [0] magic        4 B   0x4D 0x50 0x54 0x01  ("MPT\x01")
//   [1] states       u32   LR 状态总数
//   [2] action table       act_count u32
//                          每条：state_id u16, term_id u16,
//                                per_count u8, per_count × write_action(…)
//   [3] goto table         goto_count u32
//                          每条：state_id u16, nt_id u16, target u16
//   [4] productions        prod_count u32, prod_count × write_production(…)
//   [5] lexer dfa          write_lexer_dfa(…)
//   [6] symbol_metadata    meta_count u16, meta_count × write_symbol_meta(…)
//   [7] terminal_patterns  write_terminal_patterns(…)

///|
/// 将 ParseTable 序列化为二进制格式（版本 1，小端字节序）。
///
/// 节区顺序见文件顶部注释；可用 `deserialize_table` 完整还原。
pub fn serialize_table(table : ParseTable) -> Bytes {
  let w = BinWriter::new()

  // [0] magic
  w.write_u8(0x4D)
  w.write_u8(0x50)
  w.write_u8(0x54)
  w.write_u8(0x01)

  // [1] states
  w.write_u32_le(table.states)

  // [2] action table
  // 收集 action 条目：同一 (state, terminal) 下可能有多个 Action（GLR）
  let act_entries : Array[((StateId, TerminalId), Array[Action])] = []
  for key, acts in table.action {
    act_entries.push((key, acts))
  }
  act_entries.sort_by(fn(a, b) {
    let ((sa, ta), _) = a
    let ((sb, tb), _) = b
    if sa != sb {
      sa.compare(sb)
    } else {
      ta.compare(tb)
    }
  })
  w.write_u32_le(act_entries.length())
  for entry in act_entries {
    let ((state, term), acts) = entry
    w.write_u16_le(state)
    w.write_u16_le(term)
    w.write_u8(acts.length())
    for act in acts {
      write_action(w, act)
    }
  }

  // [3] goto table
  let goto_entries : Array[((StateId, NonTerminalId), StateId)] = []
  for key, target in table.goto_table {
    goto_entries.push((key, target))
  }
  goto_entries.sort_by(fn(a, b) {
    let ((sa, na), _) = a
    let ((sb, nb), _) = b
    if sa != sb {
      sa.compare(sb)
    } else {
      na.compare(nb)
    }
  })
  w.write_u32_le(goto_entries.length())
  for entry in goto_entries {
    let ((state, nt), target) = entry
    w.write_u16_le(state)
    w.write_u16_le(nt)
    w.write_u16_le(target)
  }

  // [4] productions
  w.write_u32_le(table.productions.length())
  for prod in table.productions {
    write_production(w, prod)
  }

  // [5] lexer dfa
  write_lexer_dfa(w, table.lexer_dfa)

  // [6] symbol_metadata
  w.write_u16_le(table.symbol_metadata.length())
  for meta in table.symbol_metadata {
    write_symbol_meta(w, meta)
  }

  // [7] terminal_patterns
  write_terminal_patterns(w, table.terminal_patterns)

  // [8] terminal_names
  let tn_entries : Array[(TerminalId, String)] = []
  for tid, name in table.terminal_names {
    tn_entries.push((tid, name))
  }
  tn_entries.sort_by(fn(a, b) { a.0.compare(b.0) })
  w.write_u32_le(tn_entries.length())
  for entry in tn_entries {
    let (tid, name) = entry
    w.write_u16_le(tid)
    w.write_str(name)
  }

  // [9] extras
  let extras_sorted = table.extras.copy()
  extras_sorted.sort_by(fn(a, b) { a.compare(b) })
  w.write_u16_le(extras_sorted.length())
  for tid in extras_sorted {
    w.write_u16_le(tid)
  }

  w.to_bytes()
}

///|
/// 从二进制字节流反序列化 ParseTable。
///
/// 失败时返回 `Err(msg)`，msg 描述出错位置与原因（magic 不符、截断、tag 越界等）。
pub fn deserialize_table(bytes : Bytes) -> Result[ParseTable, String] {
  let r = BinReader::new(bytes)
  try {
    // [0] magic
    let m0 = r.read_u8()
    let m1 = r.read_u8()
    let m2 = r.read_u8()
    let m3 = r.read_u8()
    if m0 != 0x4D || m1 != 0x50 || m2 != 0x54 || m3 != 0x01 {
      raise InvalidData(
        "bad magic: \{m0} \{m1} \{m2} \{m3}, expected 77 80 84 1",
      )
    }

    // [1] states
    let states = r.read_u32_le()

    // [2] action table
    let action : Map[(StateId, TerminalId), Array[Action]] = Map::new()
    let act_count = r.read_u32_le()
    for _ in 0..<act_count {
      let state = r.read_u16_le()
      let term = r.read_u16_le()
      let per = r.read_u8()
      let acts : Array[Action] = []
      for _ in 0..<per {
        acts.push(read_action(r))
      }
      action.set((state, term), acts)
    }

    // [3] goto table
    let goto_table : Map[(StateId, NonTerminalId), StateId] = Map::new()
    let goto_count = r.read_u32_le()
    for _ in 0..<goto_count {
      let state = r.read_u16_le()
      let nt = r.read_u16_le()
      let target = r.read_u16_le()
      goto_table.set((state, nt), target)
    }

    // [4] productions
    let prod_count = r.read_u32_le()
    let productions : Array[Production] = []
    for _ in 0..<prod_count {
      productions.push(read_production(r))
    }

    // [5] lexer dfa
    let lexer_dfa = read_lexer_dfa(r)

    // [6] symbol_metadata
    let meta_count = r.read_u16_le()
    let symbol_metadata : Array[SymbolMeta] = []
    for _ in 0..<meta_count {
      symbol_metadata.push(read_symbol_meta(r))
    }

    // [7] terminal_patterns
    let terminal_patterns = read_terminal_patterns(r)

    // [8] terminal_names
    let tn_count = r.read_u32_le()
    let terminal_names : Map[TerminalId, String] = Map::new()
    for _ in 0..<tn_count {
      let tid = r.read_u16_le()
      let name = r.read_str()
      terminal_names.set(tid, name)
    }

    // [9] extras
    let extras_count = r.read_u16_le()
    let extras : Array[TerminalId] = []
    for _ in 0..<extras_count {
      extras.push(r.read_u16_le())
    }

    Ok({
      states,
      action,
      goto_table,
      productions,
      lexer_dfa,
      symbol_metadata,
      terminal_patterns,
      terminal_names,
      extras,
    })
  } catch {
    UnexpectedEof(msg) => Err("deserialize_table: unexpected EOF at \{msg}")
    InvalidData(msg) => Err("deserialize_table: invalid data: \{msg}")
  }
}
