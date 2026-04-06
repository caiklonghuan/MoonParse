///|
// generate 命令处理器

///|
/// 将 .grammar 文件路径转换为默认的 .parse_table 输出路径。
fn derive_output_path(grammar_file : String) -> String {
  let n = grammar_file.length()
  let suffix = ".grammar"
  let sl = suffix.length()
  if n > sl {
    let mut matches = true
    for i in 0..<sl {
      if grammar_file[n - sl + i] != suffix[i] {
        matches = false
        break
      }
    }
    if matches {
      return grammar_file[0:n - sl].to_string() + ".parse_table"
    }
  }
  grammar_file + ".parse_table"
}

///|
/// generate 命令主体。
/// 返回退出码：0=成功，1=有警告/冲突，2=致命错误。
pub fn cmd_generate(args : GenerateArgs) -> Int {
  // 读取语法文件
  let src = match read_file(args.grammar_file) {
    Ok(s) => s
    Err(msg) => {
      print_err("error: " + msg)
      return 2
    }
  }

  // 解析 DSL
  let grammar = match @grammar.parse_grammar(src) {
    Success(g) => g
    Error(err) => {
      report_grammar_parse_error(err, Some(args.grammar_file), Some(src))
      return 2
    }
  }

  // 语义校验：有错误则中止（除非 --force）
  let val_errors = @grammar.validate_grammar(grammar)
  if not(val_errors.is_empty()) {
    report_validation_errors(val_errors, Some(args.grammar_file))
    if not(args.force) {
      return 2
    }
  }

  // 生成 LALR 解析表
  let (table, conflict_reports) = match
    @tablegen.generate_parse_table(grammar) {
    Ok(r) => r
    Err(msg) => {
      print_err("error: " + msg)
      return 2
    }
  }

  // 打印冲突报告到 stderr
  if not(conflict_reports.is_empty()) {
    report_conflicts(conflict_reports)
  }

  // --diagnostic: 将完整解析表 JSON 打印到 stderr
  if args.diagnostic {
    print_err("--- diagnostic: parse table ---")
    print_err(@tablegen.table_to_json(table))
  }

  // 检测歧义冲突
  let mut has_ambiguous = false
  for r in conflict_reports {
    match r.severity {
      Ambiguous(_) => has_ambiguous = true
      _ => ()
    }
  }
  if has_ambiguous && not(args.force) {
    print_err("error: ambiguity conflicts found; use --force to output anyway")
    return 2
  }

  // 确定输出路径
  let output_path = match args.output {
    Some(p) => p
    None => derive_output_path(args.grammar_file)
  }

  // 序列化并写入文件
  if args.json {
    // --json 模式：纯 JSON 文本
    match write_file(output_path, @tablegen.table_to_json(table)) {
      Ok(_) => ()
      Err(msg) => {
        print_err("error: " + msg)
        return 2
      }
    }
  } else {
    // 二进制格式（默认）
    let bytes = @tablegen.serialize_table(table)
    match write_bytes(output_path, bytes) {
      Ok(_) => ()
      Err(msg) => {
        print_err("error: " + msg)
        return 2
      }
    }
  }

  // 统计诊断汇总（按错误/警告分种类计数）
  let mut summary_errors = val_errors.length()
  let mut summary_warns = 0
  for r in conflict_reports {
    match r.severity {
      Ambiguous(_) => summary_errors = summary_errors + 1
      _ => summary_warns = summary_warns + 1
    }
  }
  report_summary(summary_errors, summary_warns)
  print_info("written: " + output_path)
  if summary_errors > 0 || summary_warns > 0 {
    1
  } else {
    0
  }
}
