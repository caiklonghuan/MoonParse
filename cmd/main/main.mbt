///|
// main.mbt — 入口与命令分发

///|
fn main {
  // 初始化 reporter（自动检测终端颜色）
  init_reporter()

  // 获取命令行参数（跳过程序名，即第一个元素）
  let all_args = @env.args()
  let argv = if all_args.is_empty() { [] } else { all_args[1:].to_array() }

  // 解析参数
  let code = match parse_args(argv) {
    Err(msg) => {
      print_err(msg)
      2
    }
    Ok(cmd) =>
      match cmd {
        Help(sub) => {
          print_info(
            match sub {
              None => global_usage()
              Some("generate") => generate_usage()
              Some("parse") => parse_usage()
              Some("check") => check_usage()
              Some("fmt") => fmt_usage()
              Some("query") => query_usage()
              Some(other) => "unknown command '\{other}'\n\{global_usage()}"
            },
          )
          0
        }
        Version => {
          print_info("moonparse 0.1.0")
          0
        }
        Generate(args) => cmd_generate(args)
        Parse(args) => cmd_parse(args)
        Check(args) => cmd_check(args)
        Fmt(args) => cmd_fmt(args)
        Query(args) => cmd_query(args)
        Test(args) => cmd_run_tests(args)
      }
  }

  if code != 0 {
    process_exit(code)
  }
}
