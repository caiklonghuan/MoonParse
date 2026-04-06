///|
// parse 命令处理器
///|
// 工具：节点原文切片

///|
fn node_text(node : @runtime.CstNode, input : String) -> String {
  let s = node.start_byte
  let e = node.end_byte
  if s <= e && e <= input.length() {
    input[s:e].to_string()
  } else {
    ""
  }
}

///|
// S-表达式 CST 序列化

///|
/// 将 CST 节点写成 S-表达式（tree-sitter corpus 兼容格式）。
/// 只输出命名节点和 ERROR 节点；匿名/extra 节点跳过。
fn write_sexp(
  buf : StringBuilder,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> Unit {
  // extra 节点（注释/空白）跳过
  if node.extra {
    return
  }
  // 匿名节点跳过（不含 ERROR）
  if not(node.is_named) && not(node.is_error) {
    return
  }
  let type_name = @query.node_type_name(node, table)
  if node.children.is_empty() {
    // 叶节点：显示类型名
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
// JSON CST 序列化（简化版，用于 --format json）

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
fn write_cst_json(
  buf : StringBuilder,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> Unit {
  let type_name = @query.node_type_name(node, table)
  buf.write_string("{\"type\":\"")
  buf.write_string(json_escape(type_name))
  buf.write_string("\"")
  buf.write_string(",\"named\":")
  buf.write_string(if node.is_named { "true" } else { "false" })
  buf.write_string(",\"start\":[")
  buf.write_string("\{node.start_point.row},\{node.start_point.column}")
  buf.write_string("],\"end\":[")
  buf.write_string("\{node.end_point.row},\{node.end_point.column}")
  buf.write_string("]")
  if node.is_error {
    buf.write_string(",\"error\":true")
  }
  if node.is_missing {
    buf.write_string(",\"missing\":true")
  }
  if node.children.is_empty() {
    let text = node_text(node, input)
    buf.write_string(",\"text\":\"")
    buf.write_string(json_escape(text))
    buf.write_string("\"")
  } else {
    buf.write_string(",\"children\":[")
    let mut first = true
    for child in node.children {
      if not(first) {
        buf.write_char(',')
      }
      write_cst_json(buf, child, input, table)
      first = false
    }
    buf.write_char(']')
  }
  buf.write_char('}')
}

///|
fn cst_to_json_str(
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> String {
  let buf = StringBuilder::new()
  write_cst_json(buf, node, input, table)
  buf.to_string()
}

///|
// Token 流输出（--tokens 调试用）

///|
/// 收集 CST 中的叶子节点（即 token），按字节顺序。
fn collect_tokens(
  node : @runtime.CstNode,
  tokens : Array[@runtime.CstNode],
) -> Unit {
  if node.children.is_empty() {
    tokens.push(node)
  } else {
    for child in node.children {
      collect_tokens(child, tokens)
    }
  }
}

///|
fn print_tokens(
  root : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> Unit {
  let tokens : Array[@runtime.CstNode] = []
  collect_tokens(root, tokens)
  for tok in tokens {
    let type_name = @query.node_type_name(tok, table)
    let text = node_text(tok, input)
    let row = tok.start_point.row + 1
    let col = tok.start_point.column + 1
    print_info("  [\{row}:\{col}] \{type_name} \"\{text}\"")
  }
}

///|
// ERROR 节点汇总（--error-summary）

///|
fn collect_errors(
  node : @runtime.CstNode,
  errors : Array[@runtime.CstNode],
) -> Unit {
  if node.is_error {
    errors.push(node)
  }
  for child in node.children {
    collect_errors(child, errors)
  }
}

///|
fn print_error_summary(
  root : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> Unit {
  let errors : Array[@runtime.CstNode] = []
  collect_errors(root, errors)
  if errors.is_empty() {
    print_info("no errors")
    return
  }
  print_info("\{errors.length()} error node(s):")
  for node in errors {
    let type_name = @query.node_type_name(node, table)
    let text = node_text(node, input)
    let row = node.start_point.row + 1
    let col = node.start_point.column + 1
    print_info("  [\{row}:\{col}] \{type_name} \"\{text}\"")
  }
}

///|
// 解析表加载（--grammar 和 --table 互斥）

///|
/// 从 .parse_table 文件（二进制）加载解析表。
fn load_table_from_file(path : String) -> Result[@tablegen.ParseTable, String] {
  match read_bytes(path) {
    Ok(bytes) => @tablegen.deserialize_table(bytes)
    Err(msg) => Err(msg)
  }
}

///|
/// 从 .grammar DSL 文件编译并生成解析表（不产生文件）。
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

///|
/// parse 命令主体。
pub fn cmd_parse(args : ParseArgs) -> Int {
  // 加载解析表
  let table = match (args.grammar_file, args.table_file) {
    (_, Some(tf)) =>
      match load_table_from_file(tf) {
        Ok(t) => t
        Err(msg) => {
          print_err("error: cannot load table '\{tf}': " + msg)
          return 2
        }
      }
    (Some(gf), _) =>
      match load_table_from_grammar(gf) {
        Ok(t) => t
        Err(msg) => {
          print_err("error: cannot compile grammar: " + msg)
          return 2
        }
      }
    (None, None) => {
      print_err("error: --grammar or --table required")
      return 2
    }
  }

  // 读取输入
  let input = match args.input_file {
    None => read_stdin() // --stdin 或默认
    Some(path) =>
      match read_file(path) {
        Ok(s) => s
        Err(msg) => {
          print_err("error: " + msg)
          return 2
        }
      }
  }

  // --tokens: 先打印词法流
  if args.tokens {
    print_info("--- tokens ---")
    let tok_tree = match @runtime.parse(table, input) {
      Ok(root) => root
      Err(e) => {
        report_parse_error(e, args.input_file, Some(input))
        return 2
      }
    }
    print_tokens(tok_tree, input, table)
    print_info("--- tree ---")
  }

  // 解析
  let root = match @runtime.parse(table, input) {
    Ok(r) => r
    Err(e) => {
      report_parse_error(e, args.input_file, Some(input))
      return 2
    }
  }

  // 输出
  if args.error_summary {
    print_error_summary(root, input, table)
  } else {
    match args.format {
      Sexp => print_info(cst_to_sexp(root, input, table))
      Json => print_info(cst_to_json_str(root, input, table))
    }
  }

  // 若有错误节点，以退出码 1 提示
  let errors : Array[@runtime.CstNode] = []
  collect_errors(root, errors)
  if errors.is_empty() {
    0
  } else {
    1
  }
}
