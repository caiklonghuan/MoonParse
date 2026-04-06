///|
// 命令处理器
//
// 流程：加载解析表 → 解析输入 → 编译查询 → 执行查询 → 格式化输出捕获结果

///|
// 输出格式化

///|
/// 文本格式输出捕获结果
fn print_captures_text(
  results : Array[@query.CaptureResult],
  input : String,
) -> Unit {
  if results.is_empty() {
    return
  }
  let mut last_id = -1
  for r in results {
    if r.match_id != last_id {
      print_info("match \{r.match_id}:")
      last_id = r.match_id
    }
    let node = r.node
    let sr = node.start_point.row + 1
    let sc = node.start_point.column + 1
    let er = node.end_point.row + 1
    let ec = node.end_point.column + 1
    let text = if node.start_byte <= node.end_byte &&
      node.end_byte <= input.length() {
      input[node.start_byte:node.end_byte].to_string()
    } else {
      ""
    }
    print_info("  @\{r.capture_name}  [\{sr}:\{sc}-\{er}:\{ec}]  \"\{text}\"")
  }
}

///|
/// JSON 格式输出捕获结果（--json）
fn print_captures_json(
  results : Array[@query.CaptureResult],
  input : String,
) -> Unit {
  let buf = StringBuilder::new()
  buf.write_char('[')
  let mut first = true
  for r in results {
    if not(first) {
      buf.write_char(',')
    }
    let node = r.node
    let text = if node.start_byte <= node.end_byte &&
      node.end_byte <= input.length() {
      input[node.start_byte:node.end_byte].to_string()
    } else {
      ""
    }
    buf.write_string("{\"match_id\":\{r.match_id}")
    buf.write_string(",\"capture\":\"@\{r.capture_name}\"")
    buf.write_string(
      ",\"start\":[\{node.start_point.row},\{node.start_point.column}]",
    )
    buf.write_string(
      ",\"end\":[\{node.end_point.row},\{node.end_point.column}]",
    )
    buf.write_string(",\"text\":\"")
    buf.write_string(json_escape(text))
    buf.write_string("\"}")
    first = false
  }
  buf.write_char(']')
  print_info(buf.to_string())
}

///|
/// query 命令主体
pub fn cmd_query(args : QueryArgs) -> Int {
  // 1. 加载解析表
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
    None => read_stdin()
    Some(path) =>
      match read_file(path) {
        Ok(s) => s
        Err(msg) => {
          print_err("error: " + msg)
          return 2
        }
      }
  }

  // 解析输入
  let root = match @runtime.parse(table, input) {
    Ok(r) => r
    Err(e) => {
      report_parse_error(e, args.input_file, Some(input))
      return 2
    }
  }

  // 编译查询模式
  let compiled = match @query.compile(args.pattern) {
    Ok(q) => q
    Err(e) => {
      report_query_error(e, Some(args.pattern))
      return 2
    }
  }

  // 执行查询
  let results = @query.exec(compiled, root, input, table)

  // 输出结果
  if args.count {
    // --count: 只输出匹配总数
    let mut max_id = -1
    for r in results {
      if r.match_id > max_id {
        max_id = r.match_id
      }
    }
    print_info("\{max_id + 1}")
  } else if args.json {
    print_captures_json(results, input)
  } else {
    print_captures_text(results, input)
  }

  0
}
