///|
// fmt 命令处理器
//
// 将 .grammar 文件格式化为规范形式：
//   默认：原地覆写
//   --check：只检查，不写入（CI 用，不一致时退出码 1）
//   --stdout：格式化结果输出到 stdout

///|
/// fmt 命令主体。
pub fn cmd_fmt(args : FmtArgs) -> Int {
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

  // 规范化格式化
  let formatted = @grammar.grammar_to_string(grammar)

  // 根据 flags 决定行为
  if args.check {
    // --check：比对原文，不一致时返回退出码 1
    if formatted == src {
      // 状态报告属于诊断输出，发到 stderr
      print_err("\{args.grammar_file}: ok")
      0
    } else {
      print_err("\{args.grammar_file}: not formatted")
      1
    }
  } else if args.stdout {
    // --stdout：格式化结果是主要输出，发到 stdout
    print_info(formatted)
    0
  } else {
    // 默认：原地覆写
    match write_file(args.grammar_file, formatted) {
      Ok(_) => {
        // 状态报告发到 stderr
        print_err("\{args.grammar_file}: formatted")
        0
      }
      Err(msg) => {
        print_err("error: " + msg)
        2
      }
    }
  }
}
