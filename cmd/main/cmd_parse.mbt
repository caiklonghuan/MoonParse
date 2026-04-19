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
      if !first {
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
    // tokens 是调试信息，输出到 stderr
    print_err("  [\{row}:\{col}] \{type_name} \"\{text}\"")
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

  // 解析
  let root = match @runtime.parse(table, input) {
    Ok(r) => r
    Err(e) => {
      report_parse_error(e, args.input_file, Some(input))
      return 2
    }
  }

  if args.tokens {
    // 分隔线和 token 流是调试信息，输出到 stderr，不污染 stdout 结果
    print_err("--- tokens ---")
    print_tokens(root, input, table)
    print_err("--- tree ---")
  }

  // 输出
  if args.error_summary {
    print_error_summary(root, input, table)
  } else {
    match args.format {
      Sexp => print_info(cst_to_sexp(root, input, table))
      Json => print_info(cst_to_json_str(root, input, table))
      Dot => print_info(cst_to_dot(root, input, table))
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
