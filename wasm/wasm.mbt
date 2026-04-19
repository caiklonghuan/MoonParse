/// WASM 导出接口
/// 将 MoonParse 解析能力暴露给 JS/浏览器/Node.js 调用

///|
/// 递归将 CstNode 序列化为 Tree-Sitter 兼容的 S-表达式写入 buf
/// 将子节点列表写入 sexp，透明展开匿名内部节点（tree-sitter 兼容）
fn write_sexp_children(
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
      write_sexp(buf, child, input, table, cf)
    } else if !child.children.is_empty() {
      // 匿名内部节点（辅助产生式）：透明展开其子节点
      write_sexp_children(buf, child, input, table)
    }
    // 匿名叶节点（终结符）在 sexp 中不显示
  }
}

///|
fn write_sexp(
  buf : StringBuilder,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  field : String?,
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
    write_sexp_children(buf, node, input, table)
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
// 错误扫描辅助（tree_error_summary 用）

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
// 解析器生命周期

///|
/// 从 Grammar DSL 字符串编译解析器，返回解析器句柄 ID。
/// 失败时返回 -1。
let last_dsl_error : Array[String] = [""]

///|
/// 最近一次 parse_full / parse_incremental 的运行时解析错误。
/// 正常情况下为空串；仅在解析表损坏等极端情况下出现。
let last_parse_error_msg : Array[String] = [""]

///|
/// 全局解析配置（GLR 错误恢复参数）。
/// 使用 parse_config_set / parse_config_reset 修改；默认值与 tree-sitter 行为一致。
let global_parse_config : Array[@runtime.ParseConfig] = [
  @runtime.ParseConfig::default(),
]

///|
fn parser_scanner_kind_from_dsl(dsl : String) -> ParserScannerKind {
  if dsl.contains("externals [indent dedent newline]") &&
    (
      dsl.contains(
        "rule suite: simple_statement | newline indent statement+ dedent",
      ) ||
      dsl.contains(
        "rule suite: simple_statement | newline indent newline* statement* simple_statement? dedent",
      )
    ) {
    ParserScannerKind::PythonIndent
  } else {
    ParserScannerKind::None
  }
}

///|
fn parser_scanner_kind_from_builtin_id(
  builtin_id : String,
) -> ParserScannerKind {
  if builtin_id == "python" {
    ParserScannerKind::PythonIndent
  } else {
    ParserScannerKind::None
  }
}

///|
fn register_parser_entry(
  table : @tablegen.ParseTable,
  dsl : String,
  diagnostics : Array[String],
  scanner_kind : ParserScannerKind,
) -> Int {
  parser_registry.register({ table, dsl, diagnostics, scanner_kind })
}

///|
fn parse_full_with_entry(
  entry : ParserEntry,
  source : String,
) -> Result[@runtime.CstNode, @runtime.ParseError] {
  match entry.scanner_kind {
    ParserScannerKind::None =>
      @runtime.parse_with_config(entry.table, source, global_parse_config[0])
    ParserScannerKind::PythonIndent =>
      @runtime.parse_with_stateful_scanner_and_config(
        entry.table,
        source,
        @grammars.python_indent_scanner(entry.table),
        global_parse_config[0],
      )
  }
}

///|
fn parse_incremental_with_entry(
  entry : ParserEntry,
  new_source : String,
  old_tree : @runtime.OldTree?,
  edit : @runtime.InputEdit?,
) -> Result[@runtime.CstNode, @runtime.ParseError] {
  match entry.scanner_kind {
    ParserScannerKind::None =>
      @runtime.parse_with_old_tree_and_config(
        entry.table,
        new_source,
        old_tree,
        edit,
        global_parse_config[0],
      )
    ParserScannerKind::PythonIndent =>
      @runtime.parse_with_old_tree_and_stateful_scanner_and_config(
        entry.table,
        new_source,
        old_tree,
        edit,
        @grammars.python_indent_scanner(entry.table),
        global_parse_config[0],
      )
  }
}

///|
fn should_block_on_validation_error(err : @grammar.ValidationError) -> Bool {
  match err.kind {
    @grammar.ValidationErrorKind::DirectLeftRecursion(_)
    | @grammar.ValidationErrorKind::IndirectLeftRecursion(_) => false
    _ => true
  }
}

///|
fn blocking_validation_errors(
  grammar : @grammar.Grammar,
) -> Array[@grammar.ValidationError] {
  let blocking : Array[@grammar.ValidationError] = []
  for err in @grammar.validate_grammar(grammar) {
    if should_block_on_validation_error(err) {
      blocking.push(err)
    }
  }
  blocking
}

///|
fn validation_error_message(errors : Array[@grammar.ValidationError]) -> String {
  let lines : Array[String] = []
  for err in errors {
    lines.push(err.to_string())
  }
  lines.join("\n")
}

///|
pub fn parser_dsl_error_last() -> String {
  last_dsl_error[0]
}

///|
/// 返回最近一次 parse_full / parse_incremental 的运行时错误信息。
/// 无错误时返回空串 ""。
pub fn parse_error_last() -> String {
  last_parse_error_msg[0]
}

///|
pub fn parser_create_from_dsl(dsl : String) -> Int {
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => {
      last_dsl_error[0] = e.message +
        " at line " +
        e.location.line.to_string() +
        " col " +
        e.location.column.to_string()
      return -1
    }
  }
  let val_errors = blocking_validation_errors(g)
  if !val_errors.is_empty() {
    last_dsl_error[0] = "validation failed:\n" +
      validation_error_message(val_errors)
    return -1
  }
  let (table, conflict_reports) = match @tablegen.generate_parse_table(g) {
    Ok(r) => r
    Err(e) => {
      last_dsl_error[0] = "tablegen error: " + e
      return -1
    }
  }
  let diagnostics : Array[String] = []
  for report in conflict_reports {
    let buf = StringBuilder::new()
    buf.write_char('{')
    let severity_str = match report.severity {
      @tablegen.ConflictSeverity::Warn(desc) => "warn: " + desc
      @tablegen.ConflictSeverity::Ambiguous(desc) => "ambiguous: " + desc
      @tablegen.ConflictSeverity::DynamicConflict(id) =>
        "dynamic_conflict(id=" + id.to_string() + ")"
      @tablegen.ConflictSeverity::Declared(desc) => "declared: " + desc
    }
    write_kvs(buf, "severity", severity_str)
    buf.write_char(',')
    write_kvi(buf, "state", report.state)
    buf.write_char(',')
    write_kvi(buf, "terminal", report.terminal)
    buf.write_char('}')
    diagnostics.push(buf.to_string())
  }
  register_parser_entry(
    table,
    dsl,
    diagnostics,
    parser_scanner_kind_from_dsl(dsl),
  )
}

///|
/// 释放解析器句柄（从注册表移除；GC 最终回收内存）。
pub fn parser_free(parser_id : Int) -> Unit {
  let _ = parser_registry.remove(parser_id)
}

///|
/// 返回该解析器创建时使用的 DSL 字符串。
pub fn parser_get_dsl(parser_id : Int) -> String {
  match parser_registry.get(parser_id) {
    Some(e) => e.dsl
    None => ""
  }
}

///|
/// 从预编译 JSON 字符串（由 `parser_table_to_json` 导出）快速还原解析器
pub fn parser_create_from_json(json : String) -> Int {
  match @tablegen.table_from_json(json) {
    Ok(table) =>
      register_parser_entry(
        table,
        "",
        [],
        parser_scanner_kind_from_builtin_id(""),
      )
    Err(_) => -1
  }
}

///|
/// 从预编译 JSON 字符串快速还原解析器，并显式标注内置 grammar id。
/// 用于需要外部词法器的预编译内置文法（如 Python）。
pub fn parser_create_from_json_with_builtin(
  builtin_id : String,
  json : String,
) -> Int {
  match @tablegen.table_from_json(json) {
    Ok(table) =>
      register_parser_entry(
        table,
        "",
        [],
        parser_scanner_kind_from_builtin_id(builtin_id),
      )
    Err(_) => -1
  }
}

///|
/// 从预先序列化的二进制解析表（由 `@tablegen.serialize_table` 生成）直接加载解析器。
/// 用于生产环境：跳过 DSL 编译和 JSON 解析，启动最快。
/// 失败时返回 -1。
pub fn parser_create_from_bytes(table_bytes : Bytes) -> Int {
  match @tablegen.deserialize_table(table_bytes) {
    Ok(table) => register_parser_entry(table, "", [], ParserScannerKind::None)
    Err(_) => -1
  }
}

///|
// Base64 编解码（用于 JS ↔ WASM 二进制表桥接）

///|

///|
fn base64_char_value(c_code : Int) -> Int {
  if c_code >= 65 && c_code <= 90 {
    c_code - 65
  } else if c_code >= 97 && c_code <= 122 {
    c_code - 97 + 26
  } else if c_code >= 48 && c_code <= 57 {
    c_code - 48 + 52
  } else if c_code == 43 {
    62
  } else if c_code == 47 {
    63
  } else {
    -1
  }
}

///|
fn base64_encode_char(idx : Int) -> Char {
  if idx < 26 {
    (65 + idx).unsafe_to_char()
  } else if idx < 52 {
    (97 + idx - 26).unsafe_to_char()
  } else if idx < 62 {
    (48 + idx - 52).unsafe_to_char()
  } else if idx == 62 {
    '+'
  } else {
    '/'
  }
}

///|
fn base64_to_bytes(input : String) -> Bytes? {
  let arr : Array[Byte] = []
  let mut accum = 0
  let mut bits = 0
  for idx in 0..<input.length() {
    let c = input[idx].to_int()
    if c == 61 {
      break
    }
    let val = base64_char_value(c)
    if val < 0 {
      return None
    }
    accum = (accum << 6) | val
    bits = bits + 6
    if bits >= 8 {
      bits = bits - 8
      arr.push(((accum >> bits) & 0xFF).to_byte())
    }
  }
  Some(Bytes::makei(arr.length(), fn(i) { arr[i] }))
}

///|
fn bytes_to_base64(data : Bytes) -> String {
  let buf = StringBuilder::new()
  let len = data.length()
  let mut i = 0
  while i + 2 < len {
    let b0 = data[i].to_int()
    let b1 = data[i + 1].to_int()
    let b2 = data[i + 2].to_int()
    buf.write_char(base64_encode_char((b0 >> 2) & 0x3F))
    buf.write_char(base64_encode_char(((b0 << 4) | (b1 >> 4)) & 0x3F))
    buf.write_char(base64_encode_char(((b1 << 2) | (b2 >> 6)) & 0x3F))
    buf.write_char(base64_encode_char(b2 & 0x3F))
    i = i + 3
  }
  let remaining = len - i
  if remaining == 1 {
    let b0 = data[i].to_int()
    buf.write_char(base64_encode_char((b0 >> 2) & 0x3F))
    buf.write_char(base64_encode_char((b0 << 4) & 0x3F))
    buf.write_char('=')
    buf.write_char('=')
  } else if remaining == 2 {
    let b0 = data[i].to_int()
    let b1 = data[i + 1].to_int()
    buf.write_char(base64_encode_char((b0 >> 2) & 0x3F))
    buf.write_char(base64_encode_char(((b0 << 4) | (b1 >> 4)) & 0x3F))
    buf.write_char(base64_encode_char((b1 << 2) & 0x3F))
    buf.write_char('=')
  }
  buf.to_string()
}

///|
/// 从 Base64 编码的二进制解析表直接加载解析器。
/// JS 端将 Uint8Array 转为 Base64 字符串后调用此函数。
/// 失败时返回 -1。
pub fn parser_create_from_base64(base64_str : String) -> Int {
  match base64_to_bytes(base64_str) {
    None => -1
    Some(table_bytes) =>
      match @tablegen.deserialize_table(table_bytes) {
        Ok(table) =>
          register_parser_entry(table, "", [], ParserScannerKind::None)
        Err(_) => -1
      }
  }
}

///|
/// 将解析器的 ParseTable 序列化为 Base64 编码字符串。
/// JS 端将 Base64 字符串转为 Uint8Array 即可得到二进制表。
pub fn parser_table_to_base64(parser_id : Int) -> String {
  match parser_registry.get(parser_id) {
    None => ""
    Some(entry) => bytes_to_base64(@tablegen.serialize_table(entry.table))
  }
}

///|
/// 从 grammar_to_json 格式的 Grammar JSON 字符串编译解析器，返回解析器句柄 ID。
/// 失败时返回 -1，可通过 parser_dsl_error_last() 查询错误信息。
pub fn parser_create_from_grammar_json(grammar_json : String) -> Int {
  let g = match @grammar.grammar_from_json(grammar_json) {
    @grammar.ParseResult::Success(g) => g
    @grammar.ParseResult::Error(e) => {
      last_dsl_error[0] = "grammar_from_json: " + e.message
      return -1
    }
  }
  let val_errors = blocking_validation_errors(g)
  if !val_errors.is_empty() {
    last_dsl_error[0] = "validation failed:\n" +
      validation_error_message(val_errors)
    return -1
  }
  let (table, conflict_reports) = match @tablegen.generate_parse_table(g) {
    Ok(r) => r
    Err(e) => {
      last_dsl_error[0] = "tablegen error: " + e
      return -1
    }
  }
  let diagnostics : Array[String] = []
  for report in conflict_reports {
    let buf = StringBuilder::new()
    buf.write_char('{')
    let severity_str = match report.severity {
      @tablegen.ConflictSeverity::Warn(desc) => "warn: " + desc
      @tablegen.ConflictSeverity::Ambiguous(desc) => "ambiguous: " + desc
      @tablegen.ConflictSeverity::DynamicConflict(id) =>
        "dynamic_conflict(id=" + id.to_string() + ")"
      @tablegen.ConflictSeverity::Declared(desc) => "declared: " + desc
    }
    write_kvs(buf, "severity", severity_str)
    buf.write_char(',')
    write_kvi(buf, "state", report.state)
    buf.write_char(',')
    write_kvi(buf, "terminal", report.terminal)
    buf.write_char('}')
    diagnostics.push(buf.to_string())
  }
  register_parser_entry(
    table,
    grammar_json,
    diagnostics,
    ParserScannerKind::None,
  )
}

///|
/// 将解析器的 ParseTable 序列化为 JSON 字符串，供 `parser_create_from_json` 加载
/// parser_id 无效时返回空串 ""。
pub fn parser_table_to_json(parser_id : Int) -> String {
  match parser_registry.get(parser_id) {
    None => ""
    Some(entry) => @tablegen.table_to_json(entry.table)
  }
}

///|
/// 将解析器的 ParseTable 序列化为二进制字节，供 `parser_create_from_bytes` 加载。
/// parser_id 无效时返回空 Bytes。
pub fn parser_table_to_bytes(parser_id : Int) -> Bytes {
  match parser_registry.get(parser_id) {
    None => Bytes::new(0)
    Some(entry) => @tablegen.serialize_table(entry.table)
  }
}

///|
// 全量解析

///|
/// 全量解析，返回语法树句柄 ID。
/// 失败时返回 -1，可通过 parse_error_last() 查询错误原因。
pub fn parse_full(parser_id : Int, source : String) -> Int {
  match parser_registry.get(parser_id) {
    None => {
      last_parse_error_msg[0] = "invalid parser id"
      -1
    }
    Some(entry) =>
      match parse_full_with_entry(entry, source) {
        Ok(root) => {
          last_parse_error_msg[0] = ""
          tree_registry.register({ root, input: source, table: entry.table })
        }
        Err(e) => {
          last_parse_error_msg[0] = e.message
          -1
        }
      }
  }
}

///|
/// 将语法树序列化为 JSON 字符串返回。
/// tree_id 无效时返回空串 ""。
pub fn tree_to_json(tree_id : Int) -> String {
  match tree_registry.get(tree_id) {
    None => ""
    Some(entry) =>
      match parser_registry_for_tree(tree_id) {
        None => ""
        Some(table) => cst_to_json(entry.root, entry.input, table)
      }
  }
}

///|
/// 释放语法树句柄。
pub fn tree_free(tree_id : Int) -> Unit {
  let _ = tree_registry.remove(tree_id)
}

///|
/// 增量解析：在旧树基础上应用一次文本编辑，复用未受影响的子树。
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
  new_end_col : Int,
) -> Int {
  let entry = match parser_registry.get(parser_id) {
    None => return -1
    Some(e) => e
  }
  let old_tree : @runtime.OldTree? = match tree_registry.get(old_tree_id) {
    None => return -1
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
  match parse_incremental_with_entry(entry, new_source, old_tree, edit) {
    Ok(root) => {
      last_parse_error_msg[0] = ""
      tree_registry.register({ root, input: new_source, table: entry.table })
    }
    Err(e) => {
      last_parse_error_msg[0] = e.message
      -1
    }
  }
}

///|
// 节点查询

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
// 工具函数

///|
/// 返回 MoonParse 版本字符串，供 JS 端判断 API 兼容性。
pub fn moonparse_version() -> String {
  "0.1.0"
}

///|
/// 返回解析器编译时产生的诊断条目（冲突报告）JSON 数组字符串。
pub fn parser_diagnostics_json(parser_id : Int) -> String {
  match parser_registry.get(parser_id) {
    None => "[]"
    Some(entry) =>
      if entry.diagnostics.is_empty() {
        "[]"
      } else {
        let buf = StringBuilder::new()
        buf.write_char('[')
        let mut first = true
        for d in entry.diagnostics {
          if !first {
            buf.write_char(',')
          }
          buf.write_string(d)
          first = false
        }
        buf.write_char(']')
        buf.to_string()
      }
  }
}

///|
/// 通过 tree_id 找到对应的 ParseTable（直接经由 TreeEntry.parser_id 反查）。
fn parser_registry_for_tree(tree_id : Int) -> @tablegen.ParseTable? {
  match tree_registry.get(tree_id) {
    None => None
    Some(te) => Some(te.table)
  }
}

///|
/// 从 JSON 对象字符串中读取指定字段的整数值。
/// 格式：`{"field": 123, ...}`（字段值必须为不带引号的整数）。
/// 字段不存在或值非整数时返回 None
/// 会跳过 JSON 字符串内容，避免字符串值被误识别为字段名。
fn extract_int_field(json : String, field : String) -> Int? {
  let needle = "\"" + field + "\":"
  let n = needle.length()
  let l = json.length()
  let mut i = 0
  while i < l {
    // 先尝试在当前位置匹配 needle（needle 以 " 开头）
    if i + n <= l {
      let mut matched = true
      let mut j = 0
      while j < n {
        if json[i + j] != needle[j] {
          matched = false
          j = n // break
        } else {
          j = j + 1
        }
      }
      if matched {
        // 找到键，解析冒号后的整数值
        let mut k = i + n
        while k < l && (json[k] == ' ' || json[k] == '\t') {
          k = k + 1
        }
        let neg = k < l && json[k] == '-'
        if neg {
          k = k + 1
        }
        // 至少需要一个数字；否则值类型不符，返回 None
        if k >= l || json[k] < '0' || json[k] > '9' {
          return None
        }
        let mut val = 0
        while k < l && json[k] >= '0' && json[k] <= '9' {
          val = val * 10 + (json[k].to_int() - 48)
          k = k + 1
        }
        return Some(if neg { -val } else { val })
      }
    }
    // 当前位置未匹配；若是 JSON 字符串开头，跳过整个字符串（含转义字符）
    // 防止字符串值内容被误识别为字段名
    if json[i] == '"' {
      i = i + 1
      while i < l {
        if json[i] == '\\' {
          i = i + 2 // 跳过转义序列（含 \"）
        } else if json[i] == '"' {
          i = i + 1 // 字符串结束
          break
        } else {
          i = i + 1
        }
      }
    } else {
      i = i + 1
    }
  }
  None
}

///|
// 对外接口与 web-tree-sitter 保持相同命名约定，便于工具生态复用。
// 所有函数均为薄封装，不含业务逻辑。

///|
/// 从 Grammar DSL 字符串创建解析器，返回句柄 ID（失败返回 -1）。
pub fn wasm_create_parser(dsl : String) -> Int {
  parser_create_from_dsl(dsl)
}

///|
/// 从预编译 JSON 表快速还原解析器（失败返回 -1）。
pub fn wasm_create_parser_from_json(table_json : String) -> Int {
  parser_create_from_json(table_json)
}

///|
/// 全量解析源代码，直接返回语法树 JSON 字符串。
pub fn wasm_parse(parser_id : Int, source : String) -> String {
  let tid = parse_full(parser_id, source)
  if tid < 0 {
    return ""
  }
  let result = tree_to_json(tid)
  tree_free(tid)
  result
}

///|
/// 增量解析：在旧树基础上应用一次文本编辑，返回新语法树 JSON 字符串。
pub fn wasm_parse_incremental(
  parser_id : Int,
  source : String,
  old_tree_id : Int,
  changes_json : String,
) -> String {
  let start_byte = match extract_int_field(changes_json, "start_byte") {
    Some(v) => v
    None => return ""
  }
  let old_end_byte = match extract_int_field(changes_json, "old_end_byte") {
    Some(v) => v
    None => return ""
  }
  let new_end_byte = match extract_int_field(changes_json, "new_end_byte") {
    Some(v) => v
    None => return ""
  }
  let start_row = match extract_int_field(changes_json, "start_row") {
    Some(v) => v
    None => return ""
  }
  let start_col = match extract_int_field(changes_json, "start_col") {
    Some(v) => v
    None => return ""
  }
  let old_end_row = match extract_int_field(changes_json, "old_end_row") {
    Some(v) => v
    None => return ""
  }
  let old_end_col = match extract_int_field(changes_json, "old_end_col") {
    Some(v) => v
    None => return ""
  }
  let new_end_row = match extract_int_field(changes_json, "new_end_row") {
    Some(v) => v
    None => return ""
  }
  let new_end_col = match extract_int_field(changes_json, "new_end_col") {
    Some(v) => v
    None => return ""
  }
  let tid = parse_incremental(
    parser_id, old_tree_id, source, start_byte, old_end_byte, new_end_byte, start_row,
    start_col, old_end_row, old_end_col, new_end_row, new_end_col,
  )
  if tid < 0 {
    return ""
  }
  tree_free(old_tree_id)
  let result = tree_to_json(tid)
  tree_free(tid)
  result
}

///|
/// 返回语法树根节点的 S-表达式字符串（Tree-Sitter 兼容格式）。
pub fn wasm_node_sexp(tree_id : Int) -> String {
  tree_root_sexp(tree_id)
}

///|
/// 一次性编译并执行结构化查询，返回捕获结果 JSON 数组字符串。
pub fn wasm_query(tree_id : Int, pattern : String) -> String {
  let qid = query_compile(pattern)
  if qid < 0 {
    return "[]"
  }
  let result = query_exec(qid, tree_id)
  query_free(qid)
  result
}

///|
/// 释放语法树句柄。
pub fn wasm_free_tree(tree_id : Int) -> Unit {
  tree_free(tree_id)
}

///|
/// 释放解析器句柄。
pub fn wasm_free_parser(parser_id : Int) -> Unit {
  parser_free(parser_id)
}

///|
// 文法校验 API

///|
/// 对 DSL 字符串做纯语法 + 语义校验（不执行 tablegen），返回 JSON 数组字符串。
/// 无错误时返回 "[]"；有错误时返回 [{"rule":...,"kind":...,"message":..., ...}, ...]。
/// DSL 本身解析失败时返回包含单条 parse error 的数组。
pub fn grammar_validate_dsl(dsl : String) -> String {
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => {
      let buf = StringBuilder::new()
      buf.write_string("[{")
      write_kvs(buf, "rule", "")
      buf.write_char(',')
      write_kvs(buf, "kind", "ParseError")
      buf.write_char(',')
      write_kvs(
        buf,
        "message",
        e.message +
        " at line " +
        e.location.line.to_string() +
        " col " +
        e.location.column.to_string(),
      )
      buf.write_string("}]")
      return buf.to_string()
    }
  }
  let errors = @grammar.validate_grammar(g)
  if errors.is_empty() {
    return "[]"
  }
  let buf = StringBuilder::new()
  buf.write_char('[')
  for i in 0..<errors.length() {
    if i > 0 {
      buf.write_char(',')
    }
    let err = errors[i]
    buf.write_char('{')
    write_kvs(buf, "rule", err.rule)
    buf.write_char(',')
    write_kvs(buf, "message", err.to_string())
    buf.write_char('}')
  }
  buf.write_char(']')
  buf.to_string()
}

///|
/// 返回所有内置文法字符串，JSON 对象格式 {"id": "dsl", ...}。
/// 用于网站前端自动同步内置语言预设，确保与 grammars/*.mbt 保持一致。
pub fn builtin_grammars_json() -> String {
  let buf = StringBuilder::new()
  buf.write_char('{')
  write_kvs(buf, "json", @grammars.json_grammar)
  buf.write_char(',')
  write_kvs(buf, "json5", @grammars.json5_grammar)
  buf.write_char(',')
  write_kvs(buf, "c", @grammars.c_grammar)
  buf.write_char(',')
  write_kvs(buf, "moonbit", @grammars.moonbit_grammar)
  buf.write_char(',')
  write_kvs(buf, "python", @grammars.python_grammar)
  buf.write_char('}')
  buf.to_string()
}

///|
// 字节偏移工具

///|
/// 将行内字节偏移转换为字符列号（处理 UTF-8 多字节字符）。
/// 参数：source 为完整源代码，line 为行号（0-based），col_bytes 为行内字节偏移。
/// 内部调用 @runtime.byte_offset_to_char_col。
pub fn tree_byte_offset_to_char_col(
  source : String,
  line : Int,
  col_bytes : Int,
) -> Int {
  @runtime.byte_offset_to_char_col(source, line, col_bytes)
}

///|
// ParseConfig 配置 API

///|
/// 覆盖全局 GLR 错误恢复配置。各字段传 -1 表示保留当前值。
/// 调用后对所有后续的 parse_full / parse_incremental 生效。
pub fn parse_config_set(
  error_cost_per_skipped_tree : Int,
  error_cost_per_skipped_char : Int,
  error_cost_per_skipped_line : Int,
  error_cost_per_missing_tree : Int,
  error_cost_per_recovery : Int,
  max_version_count : Int,
  max_version_count_overflow : Int,
) -> Unit {
  let cur = global_parse_config[0]
  global_parse_config[0] = {
    error_cost_per_skipped_tree: if error_cost_per_skipped_tree >= 0 {
      error_cost_per_skipped_tree
    } else {
      cur.error_cost_per_skipped_tree
    },
    error_cost_per_skipped_char: if error_cost_per_skipped_char >= 0 {
      error_cost_per_skipped_char
    } else {
      cur.error_cost_per_skipped_char
    },
    error_cost_per_skipped_line: if error_cost_per_skipped_line >= 0 {
      error_cost_per_skipped_line
    } else {
      cur.error_cost_per_skipped_line
    },
    error_cost_per_missing_tree: if error_cost_per_missing_tree >= 0 {
      error_cost_per_missing_tree
    } else {
      cur.error_cost_per_missing_tree
    },
    error_cost_per_recovery: if error_cost_per_recovery >= 0 {
      error_cost_per_recovery
    } else {
      cur.error_cost_per_recovery
    },
    max_version_count: if max_version_count >= 0 {
      max_version_count
    } else {
      cur.max_version_count
    },
    max_version_count_overflow: if max_version_count_overflow >= 0 {
      max_version_count_overflow
    } else {
      cur.max_version_count_overflow
    },
  }
}

///|
/// 将全局 GLR 错误恢复配置重置为默认值。
pub fn parse_config_reset() -> Unit {
  global_parse_config[0] = @runtime.ParseConfig::default()
}
