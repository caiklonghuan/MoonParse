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
/// Phase 2 占位：二进制序列化（未实现）
pub fn serialize_table(_table : ParseTable) -> Bytes {
  Bytes::new(0)
}

///|
/// Phase 2 占位：二进制反序列化（未实现）
pub fn deserialize_table(_bytes : Bytes) -> Result[ParseTable, String] {
  Err("deserialize_table: not implemented in Phase 1")
}
