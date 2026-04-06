///|
// HTML 树可视化
// 将 CstNode 树渲染为独立的 HTML 字符串，可直接写入 .html 文件或通过

///|
/// 将 CstNode 树渲染为独立 HTML 字符串。
///
/// 返回值是完整的 `<!DOCTYPE html>…</html>` 文档，可直接保存为 .html 文件。
pub fn cst_to_html(
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> String {
  let buf = StringBuilder::new()
  let header =
    #|<!DOCTYPE html>
    #|<html lang="en">
    #|<head>
    #|<meta charset="utf-8">
    #|<title>CST</title>
    #|<style>
    #|body { font-family: monospace; font-size: 14px; padding: 1em; }
    #|details { margin-left: 1.2em; }
    #|summary { cursor: pointer; display: inline-block; padding: 1px 4px;
    #|           border-radius: 4px; }
    #|summary:hover { opacity: 0.8; }
    #|.named   { background: #cce5ff; }
    #|.anon    { background: #d4edda; }
    #|.error   { background: #f8d7da; font-weight: bold; }
    #|.missing { background: #fff3cd; font-style: italic; }
    #|.field   { color: #6c757d; font-size: 0.9em; }
    #|.text    { color: #495057; margin-left: 0.4em; }
    #|.pos     { color: #868e96; font-size: 0.85em; margin-left: 0.3em; }
    #|</style>
    #|</head>
    #|<body>
    #|<h2>CST</h2>
    #|
  buf.write_string(header)
  write_html_node(buf, node, input, table, None, true)
  let footer =
    #|
    #|</body>
    #|</html>
  buf.write_string(footer)
  buf.to_string()
}

///|
// HTML 属性值转义（安全写入 href/title 等）
fn html_attr_escape(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    match ch {
      '"' => buf.write_string("&quot;")
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
// HTML 内容转义
fn html_escape(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    match ch {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
// 叶节点原文（最多 40 代码单元，超出加 "…"，并做 HTML 转义）
fn html_leaf_text(node : @runtime.CstNode, input : String) -> String {
  let max_chars = 40
  if node.start_byte > node.end_byte || node.end_byte > input.length() {
    return ""
  }
  let raw = input[node.start_byte:node.end_byte]
  let buf = StringBuilder::new()
  let mut count = 0
  for ch in raw {
    if count >= max_chars {
      buf.write_char('…')
      break
    }
    match ch {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '\n' => buf.write_string("<span style='color:#aaa'>\\n</span>")
      '\r' => buf.write_string("<span style='color:#aaa'>\\r</span>")
      '\t' => buf.write_string("<span style='color:#aaa'>\\t</span>")
      _ => buf.write_char(ch)
    }
    count = count + 1
  }
  buf.to_string()
}

///|
// 递归写 HTML 节点
fn write_html_node(
  buf : StringBuilder,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  field_name : String?,
  open : Bool, // details open 属性（根和第一级默认打开）
) -> Unit {
  let type_name = node_type_name(node, table)
  let css_class = if node.is_error {
    "error"
  } else if node.is_missing {
    "missing"
  } else if node.is_named {
    "named"
  } else {
    "anon"
  }
  let has_children = not(node.children.is_empty())
  let pos = "(" +
    node.start_byte.to_string() +
    "-" +
    node.end_byte.to_string() +
    ")"

  if has_children {
    buf.write_string("<details")
    if open {
      buf.write_string(" open")
    }
    buf.write_string("><summary class=\"")
    buf.write_string(css_class)
    buf.write_string("\">")
    match field_name {
      Some(f) => {
        buf.write_string("<span class=\"field\">")
        buf.write_string(html_escape(f))
        buf.write_string(": </span>")
      }
      None => ()
    }
    buf.write_string(html_escape(type_name))
    buf.write_string("<span class=\"pos\"> ")
    buf.write_string(html_attr_escape(pos))
    buf.write_string("</span></summary>\n")
    let n = node.children.length()
    for i in 0..<n {
      let child = node.children[i]
      let cf = if i < node.field_names.length() {
        node.field_names[i]
      } else {
        None
      }
      write_html_node(buf, child, input, table, cf, open && i < 3)
    }
    buf.write_string("</details>\n")
  } else {
    // 叶节点：span 行内展示
    buf.write_string("<div class=\"leaf\"><span class=\"")
    buf.write_string(css_class)
    buf.write_string("\">")
    match field_name {
      Some(f) => {
        buf.write_string("<span class=\"field\">")
        buf.write_string(html_escape(f))
        buf.write_string(": </span>")
      }
      None => ()
    }
    buf.write_string(html_escape(type_name))
    buf.write_string("<span class=\"pos\"> ")
    buf.write_string(html_attr_escape(pos))
    buf.write_string("</span></span>")
    let text = html_leaf_text(node, input)
    if text != "" {
      buf.write_string("<span class=\"text\">\"")
      buf.write_string(text)
      buf.write_string("\"</span>")
    }
    buf.write_string("</div>\n")
  }
}
