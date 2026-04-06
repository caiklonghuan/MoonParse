///|
// Graphviz DOT 导出
//
// 将 CstNode 树渲染为 Graphviz DOT 格式字符串，可直接用 `dot -Tsvg` 等渲染。
///|
/// 将 CstNode 树渲染为 Graphviz DOT 格式字符串。
pub fn cst_to_dot(
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("digraph CST {\n")
  buf.write_string(
    "  node [shape=box, fontname=\"monospace\", style=filled];\n",
  )
  let counter : Counter = { val: 0 }
  let _ = write_dot_node(buf, node, input, table, counter, -1, None)
  buf.write_string("}\n")
  buf.to_string()
}

///|
// 可变计数器包装（MoonBit 闭包捕获 Int 字段需要一个结构体）
struct Counter {
  mut val : Int
}

///|
// HTML 颜色：ERROR=红，命名内部节点=蓝，匿名叶/extras=绿
fn dot_fill_color(node : @runtime.CstNode) -> String {
  if node.is_error || node.is_missing {
    "#f8d7da"
  } else if not(node.children.is_empty()) {
    "#cce5ff"
  } else {
    "#d4edda"
  }
}

///|
// DOT label 中不能含未转义的双引号和反斜杠
fn dot_escape(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
// 递归写节点（DFS），返回本节点 id
fn write_dot_node(
  buf : StringBuilder,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  counter : Counter,
  parent_id : Int,
  field_name : String?,
) -> Int {
  let my_id = counter.val
  counter.val = counter.val + 1

  // 节点标签：类型名 + 位置区间（叶节点含原文）
  let type_name = node_type_name(node, table)
  let label_buf = StringBuilder::new()
  if node.is_error {
    label_buf.write_string("[ERROR] ")
  } else if node.is_missing {
    label_buf.write_string("[MISSING] ")
  }
  label_buf.write_string(type_name)
  label_buf.write_string("\\n(")
  label_buf.write_string(node.start_byte.to_string())
  label_buf.write_char('-')
  label_buf.write_string(node.end_byte.to_string())
  label_buf.write_char(')')
  if node.children.is_empty() {
    let text = leaf_text(node, input)
    if text != "" {
      label_buf.write_string("\\n\\\"")
      label_buf.write_string(dot_escape(text))
      label_buf.write_char('"')
    }
  }

  let fill = dot_fill_color(node)
  buf.write_string("  n")
  buf.write_string(my_id.to_string())
  buf.write_string(" [label=\"")
  buf.write_string(dot_escape(label_buf.to_string()))
  buf.write_string("\", fillcolor=\"")
  buf.write_string(fill)
  buf.write_string("\"];\n")

  // 边：parent → this（带字段名 label）
  if parent_id >= 0 {
    let edge_label = match field_name {
      Some(f) => f
      None => ""
    }
    buf.write_string("  n")
    buf.write_string(parent_id.to_string())
    buf.write_string(" -> n")
    buf.write_string(my_id.to_string())
    if edge_label != "" {
      buf.write_string(" [label=\"")
      buf.write_string(dot_escape(edge_label))
      buf.write_string("\"]")
    }
    buf.write_string(";\n")
  }

  // 递归子节点
  let n = node.children.length()
  for i in 0..<n {
    let child = node.children[i]
    let cf = if i < node.field_names.length() {
      node.field_names[i]
    } else {
      None
    }
    let _ = write_dot_node(buf, child, input, table, counter, my_id, cf)
  }
  my_id
}
