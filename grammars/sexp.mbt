///|
// CST → S-expression 序列化

///|
fn sexp_type_name(
  node : @runtime.CstNode,
  table : @tablegen.ParseTable,
) -> String {
  if node.is_error {
    return "ERROR"
  }
  if node.symbol == @runtime.sym_error {
    return "ERROR"
  }
  if node.children.is_empty() {
    if node.symbol == @runtime.sym_end {
      return "EOF"
    }
    match table.terminal_names.get(node.symbol) {
      Some(name) => name
      None => "<t:" + node.symbol.to_string() + ">"
    }
  } else {
    let meta = table.symbol_metadata
    if node.symbol >= 0 && node.symbol < meta.length() {
      let alias_nm : String? = if node.production_id >= 0 &&
        node.production_id < table.productions.length() {
        table.productions[node.production_id].alias_name
      } else {
        None
      }
      match alias_nm {
        Some(nm) => nm
        None => meta[node.symbol].name
      }
    } else {
      "<nt:" + node.symbol.to_string() + ">"
    }
  }
}

///|
fn write_sexp_children_impl(
  buf : StringBuilder,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> Unit {
  for i in 0..<node.children.length() {
    let child = node.children[i]
    if child.is_named || child.is_error {
      buf.write_char(' ')
      let cf = if i < node.field_names.length() {
        node.field_names[i]
      } else {
        None
      }
      write_sexp_impl(buf, child, input, table, cf)
    } else if !child.children.is_empty() {
      // 匿名内部节点：透明展开其子节点
      write_sexp_children_impl(buf, child, input, table)
    }
    // 匿名叶节点（标点、关键字）在 sexp 中省略
  }
}

///|
fn write_sexp_impl(
  buf : StringBuilder,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  field : String?,
) -> Unit {
  match field {
    Some(f) => {
      buf.write_string(f)
      buf.write_char(':')
      buf.write_char(' ')
    }
    None => ()
  }
  if node.is_named || node.is_error {
    buf.write_char('(')
    buf.write_string(sexp_type_name(node, table))
    write_sexp_children_impl(buf, node, input, table)
    buf.write_char(')')
  } else {
    // 匿名叶节点：输出原文（仅在被显式调用时，如 ERROR 子节点）
    buf.write_char('"')
    let text = if node.start_byte <= node.end_byte &&
      node.end_byte <= input.length() {
      input[node.start_byte:node.end_byte].to_string()
    } else {
      ""
    }
    for ch in text {
      if ch == '"' || ch == '\\' {
        buf.write_char('\\')
      }
      buf.write_char(ch)
    }
    buf.write_char('"')
  }
}

///|
/// 将 CST 节点序列化为 tree-sitter 风格的 S-expression 字符串。
/// 仅命名节点和 ERROR 节点可见；匿名终结符被省略。
fn cst_to_sexp(
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> String {
  let buf = StringBuilder::new()
  write_sexp_impl(buf, node, input, table, None)
  buf.to_string()
}

///|
fn write_tree_impl(
  buf : StringBuilder,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  indent : Int,
  field : String?,
) -> Unit {
  // 跳过零宽度的匿名叶节点（内部 epsilon / lookahead 构件）
  if node.children.is_empty() &&
    !node.is_named &&
    !node.is_error &&
    node.start_byte == node.end_byte {
    return
  }
  for _ in 0..<indent {
    buf.write_string("  ")
  }
  match field {
    Some(f) => {
      buf.write_string(f)
      buf.write_string(": ")
    }
    None => ()
  }
  let name = sexp_type_name(node, table)
  buf.write_char('[')
  buf.write_string(name)
  buf.write_char(']')
  // 叶节点或匿名节点：追加原文
  if node.children.is_empty() {
    let text = if node.start_byte < node.end_byte &&
      node.end_byte <= input.length() {
      input[node.start_byte:node.end_byte].to_string()
    } else {
      ""
    }
    if text != "" {
      buf.write_string("  \"")
      buf.write_string(text)
      buf.write_char('"')
    }
    buf.write_char('\n')
  } else {
    buf.write_char('\n')
    for i in 0..<node.children.length() {
      let child = node.children[i]
      let cf = if i < node.field_names.length() {
        node.field_names[i]
      } else {
        None
      }
      write_tree_impl(buf, child, input, table, indent + 1, cf)
    }
  }
}

///|
/// 将 CST 节点序列化为缩进树形字符串，所有节点（含匿名终结符）均可见，
/// 叶节点同时显示对应的源码文本。便于在测试中直观查看树结构。
fn cst_to_tree(
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> String {
  let buf = StringBuilder::new()
  write_tree_impl(buf, node, input, table, 0, None)
  buf.to_string()
}
