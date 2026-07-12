///|
// Query WASM 导出

///|
/// 序列化单条 CaptureResult 为 JSON object 字符串
fn capture_to_json(c : @query.CaptureResult, tree : TreeEntry) -> String {
  let node = c.node
  let buf = StringBuilder::new()
  buf.write_char('{')
  write_kvi(buf, "match_id", c.match_id)
  buf.write_char(',')
  // capture_name 经过完整 JSON 转义（write_kvs），而非依赖"字段名已安全"的隐式假设。
  write_kvs(buf, "capture", c.capture_name)
  buf.write_char(',')
  write_kvi(buf, "start", node.start_byte)
  buf.write_char(',')
  write_kvi(buf, "end", node.end_byte)
  buf.write_char(',')
  write_kvi(buf, "start_row", node.start_point.row)
  buf.write_char(',')
  write_kvi(buf, "start_col", node.start_point.column)
  buf.write_char(',')
  write_kvi(buf, "end_row", node.end_point.row)
  buf.write_char(',')
  write_kvi(buf, "end_col", node.end_point.column)
  buf.write_char(',')

  let text = if node.start_byte <= node.end_byte &&
    node.end_byte <= tree.input.length() {
    tree.input[node.start_byte:node.end_byte].to_owned()
  } else {
    ""
  }
  write_kvs(buf, "text", text)
  buf.write_char('}')
  buf.to_string()
}

///|
// WASM 导出

///|
/// 最近一次 query_compile 失败时的错误信息（JSON 对象字符串）
let last_compile_error : Array[String] = [""]

///|
/// 将 S-表达式模式字符串编译为查询对象，返回句柄 ID（失败返回 -1）
pub fn query_compile(pattern_str : String) -> Int {
  match @query.compile(pattern_str) {
    Ok(q) => {
      last_compile_error[0] = ""
      query_registry.register({ query: q })
    }
    Err(@query.ParseError(offset, msg)) => {
      let buf = StringBuilder::new()
      buf.write_string("{\"offset\":")
      buf.write_string(offset.to_string())
      buf.write_string(",\"message\":")
      write_jstr(buf, msg)
      buf.write_char('}')
      last_compile_error[0] = buf.to_string()
      -1
    }
  }
}

///|
/// 返回最近一次 query_compile 失败的错误详情（JSON 对象字符串）
pub fn query_compile_error_last() -> String {
  last_compile_error[0]
}

///|
/// 在指定语法树上执行查询，返回 JSON 字符串（失败或无结果时返回 "[]"）
pub fn query_exec(query_id : Int, tree_id : Int) -> String {
  let qentry = match query_registry.get(query_id) {
    Some(e) => e
    None => return "[]"
  }
  let tree = match tree_registry.get(tree_id) {
    Some(t) => t
    None => return "[]"
  }

  let captures = @query.exec(qentry.query, tree.root, tree.input, tree.table)
  // 序列化为 JSON 数组
  let buf = StringBuilder::new()
  buf.write_char('[')
  for i in 0..<captures.length() {
    if i > 0 {
      buf.write_char(',')
    }
    buf.write_string(capture_to_json(captures[i], tree))
  }
  buf.write_char(']')
  buf.to_string()
}

///|
/// 在指定语法树上运行 locals 查询，返回局部变量解析结果 JSON 对象字符串。
/// 格式：`{"<start_byte>": true, ...}`，每个 key 是被识别为本地引用的节点起始字节。
/// 查询或树无效时返回 "{}"。
pub fn query_resolve_locals(query_id : Int, tree_id : Int) -> String {
  let qentry = match query_registry.get(query_id) {
    Some(e) => e
    None => return "{}"
  }
  let tree = match tree_registry.get(tree_id) {
    Some(t) => t
    None => return "{}"
  }
  let res = @query.resolve_locals(
    tree.root,
    tree.input,
    tree.table,
    qentry.query,
  )
  let buf = StringBuilder::new()
  buf.write_char('{')
  let mut first = true
  res.local_refs.each(fn(k, v) {
    if v {
      if !first {
        buf.write_char(',')
      }
      buf.write_char('"')
      buf.write_string(k.to_string())
      buf.write_string("\":true")
      first = false
    }
  })
  buf.write_char('}')
  buf.to_string()
}

///|
// 合法的空 BindingGraph JSON（查询/树无效时返回）
let empty_binding_graph_json : String =
  #|{"uri":"","scopes":[],"definitions":[],"references":[],"edges":[],"diagnostics":[]}

///|
/// 在指定语法树上运行 binding 查询，返回 BindingGraph JSON 字符串。
/// 查询或树无效时返回完整的空 BindingGraph。
pub fn query_resolve_bindings(query_id : Int, tree_id : Int) -> String {
  let qentry = match query_registry.get(query_id) {
    Some(e) => e
    None => return empty_binding_graph_json
  }
  let tree = match tree_registry.get(tree_id) {
    Some(t) => t
    None => return empty_binding_graph_json
  }
  let graph = @query.build_binding_graph(
    tree.root,
    tree.input,
    tree.table,
    qentry.query,
  )
  binding_graph_to_json(graph)
}

///|
/// 释放查询对象，释放后其 ID 不再有效
pub fn query_free(query_id : Int) -> Unit {
  let _ = query_registry.remove(query_id)
}

// ── BindingGraph → JSON 序列化 ──────────────────────────────

///|
fn binding_graph_to_json(g : @query.BindingGraph) -> String {
  let buf = StringBuilder::new()
  buf.write_char('{')

  // uri
  write_kvs(buf, "uri", g.uri)
  buf.write_char(',')

  // scopes
  buf.write_string("\"scopes\":[")
  for i in 0..<g.scopes.length() {
    if i > 0 {
      buf.write_char(',')
    }
    scope_to_json(buf, g.scopes[i])
  }
  buf.write_char(']')
  buf.write_char(',')

  // definitions
  buf.write_string("\"definitions\":[")
  for i in 0..<g.definitions.length() {
    if i > 0 {
      buf.write_char(',')
    }
    definition_to_json(buf, g.definitions[i])
  }
  buf.write_char(']')
  buf.write_char(',')

  // references
  buf.write_string("\"references\":[")
  for i in 0..<g.references.length() {
    if i > 0 {
      buf.write_char(',')
    }
    reference_to_json(buf, g.references[i])
  }
  buf.write_char(']')
  buf.write_char(',')

  // edges
  buf.write_string("\"edges\":[")
  for i in 0..<g.edges.length() {
    if i > 0 {
      buf.write_char(',')
    }
    edge_to_json(buf, g.edges[i])
  }
  buf.write_char(']')
  buf.write_char(',')

  // diagnostics
  buf.write_string("\"diagnostics\":[")
  for i in 0..<g.diagnostics.length() {
    if i > 0 {
      buf.write_char(',')
    }
    diagnostic_to_json(buf, g.diagnostics[i])
  }
  buf.write_char(']')

  buf.write_char('}')
  buf.to_string()
}

///|
fn scope_to_json(buf : StringBuilder, s : @query.BindingScope) -> Unit {
  buf.write_char('{')
  write_kvi(buf, "id", s.id)
  buf.write_char(',')
  write_kvi(buf, "parent", s.parent)
  buf.write_char(',')
  write_kvi(buf, "start_byte", s.start_byte)
  buf.write_char(',')
  write_kvi(buf, "end_byte", s.end_byte)
  buf.write_char(',')
  write_kvs(buf, "kind", scope_kind_str(s.kind))
  buf.write_char('}')
}

///|
fn definition_to_json(
  buf : StringBuilder,
  d : @query.BindingDefinition,
) -> Unit {
  buf.write_char('{')
  write_kvi(buf, "id", d.id)
  buf.write_char(',')
  write_kvs(buf, "name", d.name)
  buf.write_char(',')
  write_kvs(buf, "kind", symbol_kind_str(d.kind))
  buf.write_char(',')
  write_kvs(buf, "ns", namespace_str(d.ns))
  buf.write_char(',')
  write_kvi(buf, "scope_id", d.scope_id)
  buf.write_char(',')
  write_kvi(buf, "start_byte", d.start_byte)
  buf.write_char(',')
  write_kvi(buf, "end_byte", d.end_byte)
  buf.write_char(',')
  write_kvi(buf, "declaration_start_byte", d.declaration_start_byte)
  buf.write_char(',')
  write_kvi(buf, "declaration_end_byte", d.declaration_end_byte)
  buf.write_char('}')
}

///|
fn reference_to_json(buf : StringBuilder, r : @query.BindingReference) -> Unit {
  buf.write_char('{')
  write_kvi(buf, "id", r.id)
  buf.write_char(',')
  write_kvs(buf, "name", r.name)
  buf.write_char(',')
  write_kvs(buf, "kind", symbol_kind_str(r.kind))
  buf.write_char(',')
  write_kvs(buf, "ns", namespace_str(r.ns))
  buf.write_char(',')
  write_kvi(buf, "scope_id", r.scope_id)
  buf.write_char(',')
  write_kvi(buf, "start_byte", r.start_byte)
  buf.write_char(',')
  write_kvi(buf, "end_byte", r.end_byte)
  buf.write_char(',')
  write_kvb(buf, "diagnose_unresolved", r.diagnose_unresolved)
  buf.write_char('}')
}

///|
fn edge_to_json(buf : StringBuilder, e : @query.BindingEdge) -> Unit {
  buf.write_char('{')
  write_kvi(buf, "reference_id", e.reference_id)
  buf.write_char(',')
  write_kvi(buf, "definition_id", e.definition_id)
  buf.write_char('}')
}

///|
fn diagnostic_to_json(
  buf : StringBuilder,
  d : @query.BindingDiagnostic,
) -> Unit {
  buf.write_char('{')
  write_kvs(buf, "kind", diag_kind_str(d.kind))
  buf.write_char(',')
  write_kvs(buf, "message", d.message)
  buf.write_char(',')
  write_kvi(buf, "reference_id", d.reference_id)
  buf.write_char(',')
  write_kvi(buf, "definition_id", d.definition_id)
  buf.write_char(',')
  write_kvi(buf, "start_byte", d.start_byte)
  buf.write_char(',')
  write_kvi(buf, "end_byte", d.end_byte)
  buf.write_char('}')
}

// ── enum → string ──────────────────────────────────────────

///|
fn scope_kind_str(k : @query.ScopeKind) -> String {
  match k {
    Module => "module"
    Function => "function"
    Block => "block"
    Class => "class"
    Loop => "loop"
    Rule => "rule"
  }
}

///|
fn symbol_kind_str(k : @query.SymbolKind) -> String {
  match k {
    Variable => "variable"
    Constant => "constant"
    Function => "function"
    Method => "method"
    Type => "type"
    Struct => "struct"
    Enum => "enum"
    Trait => "trait"
    Field => "field"
    EnumMember => "enum_member"
    Parameter => "parameter"
    TypeParameter => "type_parameter"
    Rule => "rule"
    Token => "token"
  }
}

///|
fn namespace_str(ns : @query.NameSpace) -> String {
  match ns {
    Value => "value"
    Type => "type"
    Member => "member"
    Rule => "rule"
  }
}

///|
fn diag_kind_str(k : @query.BindingDiagKind) -> String {
  match k {
    Unresolved => "unresolved"
    Duplicate => "duplicate"
    Ambiguous => "ambiguous"
  }
}

// (empty_binding_graph_json 已移至 query_resolve_bindings 之前)
