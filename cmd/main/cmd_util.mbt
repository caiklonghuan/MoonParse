///|
// 命令共享工具

///|
fn json_escape(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s.iter() {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      c => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn write_sexp(
  buf : StringBuilder,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> Unit {
  if node.extra {
    return
  }
  if not(node.is_named) && not(node.is_error) {
    return
  }
  let type_name = @query.node_type_name(node, table)
  if node.children.is_empty() {
    buf.write_string("(\{type_name})")
  } else {
    buf.write_string("(\{type_name}")
    for child in node.children {
      if not(child.extra) && (child.is_named || child.is_error) {
        buf.write_char(' ')
        write_sexp(buf, child, input, table)
      }
    }
    buf.write_char(')')
  }
}

///|
fn cst_to_sexp(
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> String {
  let buf = StringBuilder::new()
  write_sexp(buf, node, input, table)
  buf.to_string()
}

///|
fn load_table_from_file(path : String) -> Result[@tablegen.ParseTable, String] {
  match read_bytes(path) {
    Ok(bytes) => @tablegen.deserialize_table(bytes)
    Err(msg) => Err(msg)
  }
}

///|
fn load_table_from_grammar(
  path : String,
) -> Result[@tablegen.ParseTable, String] {
  let src = match read_file(path) {
    Ok(s) => s
    Err(msg) => return Err(msg)
  }
  let grammar = match @grammar.parse_grammar(src) {
    Success(g) => g
    Error(err) => return Err("parse error in '\{path}': \{err.message}")
  }
  match @tablegen.generate_parse_table(grammar) {
    Ok((table, _reports)) => Ok(table)
    Err(msg) => Err(msg)
  }
}
