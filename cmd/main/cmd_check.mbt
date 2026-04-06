///|
// check 命令处理器
// 只做校验，不产生任何文件输出。
// 退出码：0=ok，1=warnings，2=errors
///|
/// check 命令主体。
pub fn cmd_check(args : CheckArgs) -> Int {
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

  // 语义校验
  let val_errors = @grammar.validate_grammar(grammar)
  if not(val_errors.is_empty()) {
    report_validation_errors(val_errors, Some(args.grammar_file))
  }

  // 生成解析表，收集冲突报告
  let (_, conflict_reports) = match @tablegen.generate_parse_table(grammar) {
    Ok(r) => r
    Err(msg) => {
      print_err("error: " + msg)
      return 2
    }
  }
  if not(conflict_reports.is_empty()) {
    report_conflicts(conflict_reports)
  }

  // 按严重程度确定退出码
  let mut has_error = not(val_errors.is_empty())
  let mut has_warn = false
  for r in conflict_reports {
    match r.severity {
      Ambiguous(_) => has_error = true
      Warn(_) | DynamicConflict(_) => has_warn = true
    }
  }

  let err_count = val_errors.length() +
    conflict_reports
    .iter()
    .filter(fn(r) {
      match r.severity {
        Ambiguous(_) => true
        _ => false
      }
    })
    .count()
  let warn_count = conflict_reports
    .iter()
    .filter(fn(r) {
      match r.severity {
        Ambiguous(_) => false
        _ => true
      }
    })
    .count()

  report_summary(err_count, warn_count)

  if has_error {
    2
  } else if has_warn {
    1
  } else {
    0
  }
}
