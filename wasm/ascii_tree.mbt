///|
// ASCII 树形打印
// 将语法树渲染为 ASCII 树形字符串，适合在终端或日志中查看。
///|
/// 将 CstNode 树渲染为 ASCII 树形字符串
pub fn cst_to_ascii_tree(
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> String {
  let buf = StringBuilder::new()
  // 根节点不打印 ├── / └── 连接符
  write_ascii_header(buf, node, input, table, None)
  let n = node.children.length()
  for i in 0..<n {
    let child = node.children[i]
    let cf = if i < node.field_names.length() {
      node.field_names[i]
    } else {
      None
    }
    write_ascii_node(buf, child, input, table, "", i == n - 1, cf)
  }
  buf.to_string()
}

///|
// 打印单行节点摘要（不打印连接符前缀，供根节点使用）
fn write_ascii_header(
  buf : StringBuilder,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  field_name : String?,
) -> Unit {
  if node.is_error {
    buf.write_string("[ERROR] ")
  } else if node.is_missing {
    buf.write_string("[MISSING] ")
  }
  match field_name {
    Some(f) => {
      buf.write_string(f)
      buf.write_string(": ")
    }
    None => ()
  }
  buf.write_string(node_type_name(node, table))
  buf.write_char(' ')
  buf.write_char('(')
  buf.write_string(node.start_byte.to_string())
  buf.write_char('-')
  buf.write_string(node.end_byte.to_string())
  buf.write_char(')')
  if node.children.is_empty() {
    let text = leaf_text(node, input)
    if text != "" {
      buf.write_string(" \"")
      buf.write_string(text)
      buf.write_char('"')
    }
  }
  buf.write_char('\n')
}

///|
// 截取叶节点原文（最多 max_chars 个代码单元，超出加 "…"）
fn leaf_text(node : @runtime.CstNode, input : String) -> String {
  let max_chars = 20
  if node.start_byte > node.end_byte || node.end_byte > input.length() {
    return ""
  }
  let raw = input[node.start_byte:node.end_byte]
  // 将换行/制表符换为可见转义，以免破坏树形排布
  let buf = StringBuilder::new()
  let mut count = 0
  for ch in raw {
    if count >= max_chars {
      buf.write_char('…')
      break
    }
    match ch {
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(ch)
    }
    count = count + 1
  }
  buf.to_string()
}

///|
fn write_ascii_node(
  buf : StringBuilder,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  prefix : String,
  is_last : Bool,
  field_name : String?,
) -> Unit {
  let connector = if is_last { "└── " } else { "├── " }
  buf.write_string(prefix)
  buf.write_string(connector)
  write_ascii_header(buf, node, input, table, field_name)
  // 递归处理子节点
  let next_prefix = if is_last { prefix + "    " } else { prefix + "│   " }
  let n = node.children.length()
  for i in 0..<n {
    let child = node.children[i]
    let cf = if i < node.field_names.length() {
      node.field_names[i]
    } else {
      None
    }
    write_ascii_node(buf, child, input, table, next_prefix, i == n - 1, cf)
  }
}
