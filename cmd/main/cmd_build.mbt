///|
// build 命令处理器
// grammar → parse_table → build/parser.parse_table [+ build/parser.wasm]

///|
/// 判断字符串是否以指定后缀结尾
fn build_ends_with(s : String, suffix : String) -> Bool {
  let n = s.length()
  let sl = suffix.length()
  if n < sl {
    return false
  }
  for i in 0..<sl {
    if s[n - sl + i] != suffix[i] {
      return false
    }
  }
  true
}

///|
/// build 命令主体。
/// 输入：.grammar 或 .parse_table 文件
/// 输出：<outdir>/parser.parse_table  [+ <outdir>/parser.wasm]
/// 返回退出码：0=成功，1=有警告/冲突，2=致命错误。
pub fn cmd_build(args : BuildArgs) -> Int {
  let outdir = match args.outdir {
    Some(d) => d
    None => "build"
  }

  // 创建输出目录
  match make_dir(outdir) {
    Ok(_) => ()
    Err(msg) => {
      print_err("error: " + msg)
      return 2
    }
  }

  // 读取/生成 parse table 的二进制内容
  let (table_bytes, exit_code) = if build_ends_with(args.input, ".parse_table") {
    // 直接复制已有 .parse_table 文件
    match read_bytes(args.input) {
      Ok(b) => (b, 0)
      Err(msg) => {
        print_err("error: " + msg)
        return 2
      }
    }
  } else {
    // 从 .grammar 文件生成
    let result = build_from_grammar(args.input)
    match result {
      Err(code) => return code
      Ok(pair) => pair
    }
  }

  // 写入 <outdir>/parser.parse_table
  let table_path = outdir + "/parser.parse_table"
  match write_bytes(table_path, table_bytes) {
    Ok(_) => ()
    Err(msg) => {
      print_err("error: " + msg)
      return 2
    }
  }
  print_info("written: " + table_path)

  // --wasm: 同时写入 <outdir>/parser.wasm（同一二进制，不同扩展名）
  if args.wasm {
    let wasm_path = outdir + "/parser.wasm"
    match write_bytes(wasm_path, table_bytes) {
      Ok(_) => ()
      Err(msg) => {
        print_err("error: " + msg)
        return 2
      }
    }
    print_info("written: " + wasm_path)
  }

  exit_code
}

///|
/// 从 .grammar 文件生成 parse table 二进制，返回 (bytes, exit_code) 或 Err(fatal_exit_code)
fn build_from_grammar(grammar_file : String) -> Result[(Bytes, Int), Int] {
  // 读取语法文件
  let src = match read_file(grammar_file) {
    Ok(s) => s
    Err(msg) => {
      print_err("error: " + msg)
      return Err(2)
    }
  }

  // 解析 DSL
  let grammar = match @grammar.parse_grammar(src) {
    Success(g) => g
    Error(err) => {
      report_grammar_parse_error(err, Some(grammar_file), Some(src))
      return Err(2)
    }
  }

  // 语义校验
  let val_all = @grammar.validate_grammar(grammar)
  let val_errors : Array[@grammar.ValidationError] = []
  let val_warnings : Array[@grammar.ValidationError] = []
  for e in val_all {
    match e.kind {
      @grammar.ValidationErrorKind::DirectLeftRecursion(_)
      | @grammar.ValidationErrorKind::IndirectLeftRecursion(_) =>
        val_warnings.push(e)
      _ => val_errors.push(e)
    }
  }
  if !val_warnings.is_empty() {
    report_validation_warnings(val_warnings, Some(grammar_file))
  }
  if !val_errors.is_empty() {
    report_validation_errors(val_errors, Some(grammar_file))
    return Err(2)
  }

  // 生成 LALR 解析表
  let (table, conflict_reports) = match
    @tablegen.generate_parse_table(grammar) {
    Ok(r) => r
    Err(msg) => {
      print_err("error: " + msg)
      return Err(2)
    }
  }

  if !conflict_reports.is_empty() {
    report_conflicts(conflict_reports)
  }

  let mut summary_warns = val_warnings.length()
  for r in conflict_reports {
    match r.severity {
      Ambiguous(_) => {
        print_err(
          "error: ambiguity conflicts found; use 'moonparse generate --force' to override",
        )
        return Err(2)
      }
      _ => summary_warns = summary_warns + 1
    }
  }

  let bytes = @tablegen.serialize_table(table)
  let exit_code = if summary_warns > 0 { 1 } else { 0 }
  Ok((bytes, exit_code))
}
