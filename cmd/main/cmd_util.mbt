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
fn write_sexp_children(
  buf : StringBuilder,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> Unit {
  for child in node.children {
    if child.extra {
      continue
    }
    if child.is_named || child.is_error {
      buf.write_char(' ')
      write_sexp(buf, child, input, table)
    } else if !child.children.is_empty() {
      // 匿名内部节点（辅助产生式）：透明展开
      write_sexp_children(buf, child, input, table)
    }
  }
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
  if !node.is_named && !node.is_error {
    return
  }
  let type_name = @query.node_type_name(node, table)
  buf.write_string("(\{type_name}")
  write_sexp_children(buf, node, input, table)
  buf.write_char(')')
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
// Graphviz DOT 导出（--format dot）

///|
/// 对 DOT 节点标签中的特殊字符进行转义（`<`, `>`, `"`, `\`, `|`, `{`, `}`）
fn dot_escape(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s.iter() {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '<' => buf.write_string("\\<")
      '>' => buf.write_string("\\>")
      '{' => buf.write_string("\\{")
      '}' => buf.write_string("\\}")
      '|' => buf.write_string("\\|")
      '\n' => buf.write_string("\\n")
      '\r' => ()
      c => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// 递归将 CST 节点写入 DOT 缓冲区。
/// counter 通过数组模拟可变引用，每次分配新节点 ID 时自增。
fn write_cst_dot(
  buf : StringBuilder,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  counter : Array[Int],
) -> Int {
  let my_id = counter[0]
  counter[0] = counter[0] + 1
  let type_name = @query.node_type_name(node, table)

  // 节点属性
  let shape = if node.is_error {
    "shape=diamond style=filled fillcolor=salmon"
  } else if node.is_missing {
    "shape=diamond style=filled fillcolor=lightyellow"
  } else if node.children.is_empty() {
    // 叶节点：显示类型名 + 文本
    let text = node_text(node, input)
    let label = if text.is_empty() || text == type_name {
      dot_escape(type_name)
    } else {
      dot_escape(type_name) + "\\n\\\"" + dot_escape(text) + "\\\""
    }
    buf.write_string(
      "  n\{my_id} [label=\"\{label}\" shape=ellipse style=filled fillcolor=lightblue];\n",
    )
    return my_id
  } else {
    "shape=box style=filled fillcolor=lightyellow"
  }
  buf.write_string(
    "  n\{my_id} [label=\"\{dot_escape(type_name)}\" \{shape}];\n",
  )

  // 递归子节点并建立边
  for child in node.children {
    let child_id = write_cst_dot(buf, child, input, table, counter)
    let style = if child.extra { " [style=dashed color=gray]" } else { "" }
    buf.write_string("  n\{my_id} -> n\{child_id}\{style};\n")
  }
  my_id
}

///|
/// 将整棵 CST 导出为 Graphviz DOT 格式字符串。
///
/// 生成的图可直接用 `dot -Tsvg` 渲染：
/// ```sh
/// moonparse parse --format dot my.grammar input.txt | dot -Tsvg -o tree.svg
/// ```
fn cst_to_dot(
  root : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("digraph CST {\n")
  buf.write_string("  rankdir=TB;\n")
  buf.write_string("  node [fontname=\"Courier New\" fontsize=11];\n")
  let counter = [0]
  ignore(write_cst_dot(buf, root, input, table, counter))
  buf.write_string("}\n")
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
  let val_errors : Array[@grammar.ValidationError] = []
  for err in @grammar.validate_grammar(grammar) {
    match err.kind {
      @grammar.ValidationErrorKind::DirectLeftRecursion(_)
      | @grammar.ValidationErrorKind::IndirectLeftRecursion(_) => ()
      _ => val_errors.push(err)
    }
  }
  if !val_errors.is_empty() {
    let lines : Array[String] = []
    for err in val_errors {
      lines.push(err.to_string())
    }
    return Err("validation error in '\{path}':\n" + lines.join("\n"))
  }
  match @tablegen.generate_parse_table(grammar) {
    Ok((table, _reports)) => Ok(table)
    Err(msg) => Err(msg)
  }
}
