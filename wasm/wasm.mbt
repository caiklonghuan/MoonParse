/// WASM 导出接口
/// 将 MoonParse 解析能力暴露给 JS/浏览器/Node.js 调用
///
/// 所有跨边界的复合对象通过整数句柄引用（见 handles.mbt）。
/// JS 侧调用规则：
///   - 返回值 >= 1  → 有效句柄
///   - 返回值 == -1 → 操作失败
///   - 返回空串 ""  → 无效 ID

///|
// ── S-表达式辅助（tree_root_sexp 用）────────────────────────────

///|
/// 递归将 CstNode 序列化为 Tree-Sitter 兼容的 S-表达式写入 buf
fn write_sexp(
  buf : StringBuilder,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  field : String?
) -> Unit {
  // field 前缀
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
    buf.write_string(node_type_name(node, table))
    for i in 0..<node.children.length() {
      let child = node.children[i]
      // 只在 S-表达式中展示命名子节点
      if child.is_named || child.is_error {
        buf.write_char(' ')
        let cf = if i < node.field_names.length() {
          node.field_names[i]
        } else {
          None
        }
        write_sexp(buf, child, input, table, cf)
      }
    }
    buf.write_char(')')
  } else {
    // 匿名叶节点：输出原文
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
// ── 错误扫描辅助（tree_error_summary 用）────────────────────────

///|
/// 深度优先扫描，找到第一个 is_error=true 或 is_missing=true 的节点
fn find_first_error(node : @runtime.CstNode) -> @runtime.CstNode? {
  if node.is_error || node.is_missing {
    return Some(node)
  }
  for child in node.children {
    match find_first_error(child) {
      Some(n) => return Some(n)
      None => ()
    }
  }
  None
}

///|
// ── 解析器生命周期 ───────────────────────────────────────────────

///|
/// 从 Grammar DSL 字符串编译解析器，返回解析器句柄 ID。
/// 失败时返回 -1。
pub fn parser_create_from_dsl(dsl : String) -> Int {
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(_) => return -1
  }
  let table = match @tablegen.generate_parse_table(g) {
    Ok((t, _)) => t
    Err(_) => return -1
  }
  parser_registry.register({ table, dsl })
}

///|
/// 释放解析器句柄（从注册表移除；GC 最终回收内存）。
pub fn parser_free(parser_id : Int) -> Unit {
  let _ = parser_registry.remove(parser_id)
}

///|
/// 从预编译 JSON 字符串（由 `parser_table_to_json` 导出）快速还原解析器。
///
/// 开发流程：
///   1. 调用 `parser_create_from_dsl(dsl)` → parser_id（一次性编译，慢）
///   2. 调用 `parser_table_to_json(parser_id)` → json（保存到 JS 代码中）
///   3. 之后用 `parser_create_from_json(json)` 直接加载（无需重新编译，快）
///
/// 失败时返回 -1。
pub fn parser_create_from_json(json : String) -> Int {
  match @tablegen.table_from_json(json) {
    Ok(table) => parser_registry.register({ table, dsl: "" })
    Err(_) => -1
  }
}

///|
/// 将解析器的 ParseTable 序列化为 JSON 字符串，供 `parser_create_from_json` 加载。
/// parser_id 无效时返回空串 ""。
pub fn parser_table_to_json(parser_id : Int) -> String {
  match parser_registry.get(parser_id) {
    None => ""
    Some(entry) => @tablegen.table_to_json(entry.table)
  }
}

///|
// ── 全量解析 ────────────────────────────────────────────────────

///|
/// 全量解析，返回语法树句柄 ID。
/// 失败时返回 -1。
pub fn parse_full(parser_id : Int, source : String) -> Int {
  match parser_registry.get(parser_id) {
    None => -1
    Some(entry) =>
      match @runtime.parse(entry.table, source) {
        Ok(root) => tree_registry.register({ root, input: source, parser_id })
        Err(_) => -1
      }
  }
}

///|
/// 将语法树序列化为 JSON 字符串返回。
/// tree_id 无效时返回空串 ""。
pub fn tree_to_json(tree_id : Int) -> String {
  match tree_registry.get(tree_id) {
    None => ""
    Some(entry) => {
      match parser_registry_for_tree(tree_id) {
        None => ""
        Some(table) => cst_to_json(entry.root, entry.input, table)
      }
    }
  }
}

///|
/// 释放语法树句柄。
pub fn tree_free(tree_id : Int) -> Unit {
  let _ = tree_registry.remove(tree_id)
}

///|
// ── 增量解析 ────────────────────────────────────────────────────

///|
/// 增量解析：在旧树基础上应用一次文本编辑，复用未受影响的子树。
///
/// edit 参数（9 个 Int，对应 @runtime.InputEdit 的 6 个字段，Point 展开）：
///   start_byte, old_end_byte, new_end_byte,
///   start_row, start_col,
///   old_end_row, old_end_col,
///   new_end_row, new_end_col
///
/// 返回新的 tree_id；失败返回 -1。
pub fn parse_incremental(
  parser_id : Int,
  old_tree_id : Int,
  new_source : String,
  start_byte : Int,
  old_end_byte : Int,
  new_end_byte : Int,
  start_row : Int,
  start_col : Int,
  old_end_row : Int,
  old_end_col : Int,
  new_end_row : Int,
  new_end_col : Int
) -> Int {
  let entry = match parser_registry.get(parser_id) {
    None => return -1
    Some(e) => e
  }
  let old_tree : @runtime.OldTree? = match tree_registry.get(old_tree_id) {
    None => None
    Some(te) => Some({ root: te.root, old_input: te.input })
  }
  let edit : @runtime.InputEdit? = Some({
    start_byte,
    old_end_byte,
    new_end_byte,
    start_point: { row: start_row, column: start_col },
    old_end_point: { row: old_end_row, column: old_end_col },
    new_end_point: { row: new_end_row, column: new_end_col },
  })
  match @runtime.parse_with_old_tree(entry.table, new_source, old_tree, edit) {
    Ok(root) => tree_registry.register({ root, input: new_source, parser_id })
    Err(_) => -1
  }
}

///|
// ── 节点查询 ─────────────────────────────────────────────────────

///|
/// 返回语法树根节点的 S-表达式（Tree-Sitter 兼容格式）。
/// tree_id 无效时返回空串 ""。
pub fn tree_root_sexp(tree_id : Int) -> String {
  match tree_registry.get(tree_id) {
    None => ""
    Some(entry) =>
      match parser_registry_for_tree(tree_id) {
        None => ""
        Some(table) => {
          let buf = StringBuilder::new()
          write_sexp(buf, entry.root, entry.input, table, None)
          buf.to_string()
        }
      }
  }
}

///|
/// 返回错误状态摘要：无错误时返回 "ok"，有错误时返回 "error:行:列"。
/// tree_id 无效时返回 "invalid"。
pub fn tree_error_summary(tree_id : Int) -> String {
  match tree_registry.get(tree_id) {
    None => "invalid"
    Some(entry) =>
      match find_first_error(entry.root) {
        None => "ok"
        Some(n) =>
          "error:" +
          n.start_point.row.to_string() +
          ":" +
          n.start_point.column.to_string()
      }
  }
}

///|
// ── 工具函数 ──────────────────────────────────────────────────────

///|
/// 返回 MoonParse 版本字符串，供 JS 端判断 API 兼容性。
pub fn moonparse_version() -> String {
  "0.1.0"
}

///|
// ── 内部辅助 ─────────────────────────────────────────────────────

///|
/// 通过 tree_id 找到对应的 ParseTable（直接经由 TreeEntry.parser_id 反查）。
fn parser_registry_for_tree(tree_id : Int) -> @tablegen.ParseTable? {
  match tree_registry.get(tree_id) {
    None => None
    Some(te) =>
      match parser_registry.get(te.parser_id) {
        None => None
        Some(pe) => Some(pe.table)
      }
  }
}
