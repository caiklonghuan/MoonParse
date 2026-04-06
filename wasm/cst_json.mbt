///|
// CstNode → JSON 序列化
//
// 职责：将 @runtime.CstNode 树递归序列化为 JSON 字符串，供 JS 侧消费。
// 使用 StringBuilder 直写，避免 O(n²) 字符串拼接。

///|
// 节点类型名查表

///|
/// 从 ParseTable 反查节点的类型名称字符串
///
/// - is_error = true → "ERROR"
/// - 叶节点（children 为空）：symbol 是 TerminalId，从 terminal_names 查
/// - 内部节点：symbol 是 NonTerminalId，从 symbol_metadata 查
fn node_type_name(
  node : @runtime.CstNode,
  table : @tablegen.ParseTable,
) -> String {
  if node.is_error {
    return "ERROR"
  }
  if node.symbol == @runtime.sym_error ||
    node.symbol == @runtime.sym_error_repeat {
    return "ERROR"
  }
  if node.children.is_empty() {
    // 叶节点：symbol 是 TerminalId
    if node.symbol == @runtime.sym_end {
      return "EOF"
    }
    match table.terminal_names.get(node.symbol) {
      Some(name) => name
      None => "<terminal:" + node.symbol.to_string() + ">"
    }
  } else {
    // 内部节点：symbol 是 NonTerminalId（下标索引 symbol_metadata）
    let meta = table.symbol_metadata
    if node.symbol >= 0 && node.symbol < meta.length() {
      // 优先查 alias（按产生式 ID 还原别名）
      let alias_nm : String? = if node.production_id >= 0 &&
        node.production_id < table.productions.length() {
        table.productions[node.production_id].alias_name
      } else {
        None
      }
      match alias_nm {
        Some(name) => name
        None => meta[node.symbol].name
      }
    } else {
      "<nonterminal:" + node.symbol.to_string() + ">"
    }
  }
}

///|
// 核心递归写节点

///|
/// 递归将 node 序列化为 JSON 写入 buf
///
/// - field : 来自父节点 field_names[i]，非 None 时输出 "field" 键
/// - input : 原始完整输入字符串，用于叶节点 "text" 字段
fn write_node(
  buf : StringBuilder,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  field : String?,
) -> Unit {
  buf.write_char('{')
  let mut comma = false

  // "type"
  write_kvs(buf, "type", node_type_name(node, table))
  comma = true

  // "field"（来自父节点的 field_names，只在非 None 时输出）
  match field {
    Some(f) => {
      buf.write_char(',')
      write_kvs(buf, "field", f)
    }
    None => ()
  }
  let _ = comma // 后续统一用 comma 标记

  // "is_named"
  buf.write_char(',')
  write_kvb(buf, "is_named", node.is_named)

  // "is_error"
  buf.write_char(',')
  write_kvb(buf, "is_error", node.is_error)

  // "is_missing"
  buf.write_char(',')
  write_kvb(buf, "is_missing", node.is_missing)

  // "extra"
  buf.write_char(',')
  write_kvb(buf, "extra", node.extra)

  // 位置信息
  buf.write_char(',')
  write_kvi(buf, "start_byte", node.start_byte)
  buf.write_char(',')
  write_kvi(buf, "end_byte", node.end_byte)
  buf.write_char(',')
  write_kvi(buf, "start_row", node.start_point.row)
  buf.write_char(',')
  write_kvi(buf, "start_col", node.start_point.column)
  buf.write_char(',')
  write_kvi(buf, "end_row", node.end_point.row)
  buf.write_char(',')
  write_kvi(buf, "end_col", node.end_point.column)

  // "text"：仅叶节点输出原文，用字符位置切片
  if node.children.is_empty() {
    buf.write_char(',')
    let text = if node.start_byte <= node.end_byte &&
      node.end_byte <= input.length() {
      input[node.start_byte:node.end_byte].to_string()
    } else {
      ""
    }
    write_kvs(buf, "text", text)
  }

  // "children"：递归序列化子节点
  if not(node.children.is_empty()) {
    buf.write_char(',')
    write_jstr(buf, "children")
    buf.write_char(':')
    buf.write_char('[')
    let n = node.children.length()
    for i in 0..<n {
      if i > 0 {
        buf.write_char(',')
      }
      let child = node.children[i]
      let child_field = if i < node.field_names.length() {
        node.field_names[i]
      } else {
        None
      }
      write_node(buf, child, input, table, child_field)
    }
    buf.write_char(']')
  }

  buf.write_char('}')
}

///|
// 公开入口

///|
/// 将 CST 树序列化为 JSON 字符串
///
/// # 参数
/// - node  : CST 根节点（来自 @runtime.parse）
/// - input : 解析时使用的原始输入字符串（用于叶节点 text 字段）
/// - table : 对应的 ParseTable（用于符号名称反查）
pub fn cst_to_json(
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> String {
  let buf = StringBuilder::new()
  write_node(buf, node, input, table, None)
  buf.to_string()
}
