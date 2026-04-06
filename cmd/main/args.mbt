///|
// args.mbt — CLI 参数解析器

///|
// 各命令的参数结构体

///|
pub struct GenerateArgs {
  /// 语法文件路径（.grammar）
  grammar_file : String
  /// 输出文件路径（默认 <base>.parse_table）
  output : String?
  /// 是否输出 JSON 格式的解析表（调试用）
  json : Bool
  /// 是否打印 LR 项目集和 GOTO 表到 stderr
  diagnostic : Bool
  /// 有歧义冲突时仍然输出（不中止）
  force : Bool
} derive(Show)

///|
pub struct ParseArgs {
  /// 语法文件路径（.grammar），与 table 互斥
  grammar_file : String?
  /// 解析表文件路径（.parse_table），与 grammar_file 互斥
  table_file : String?
  /// 输入文件路径（None = 从 stdin 读取）
  input_file : String?
  /// 输出格式：sexp（默认）或 json
  format : OutputFormat
  /// 是否先输出 token 流
  tokens : Bool
  /// 是否只输出 ERROR 节点摘要
  error_summary : Bool
} derive(Show)

///|
pub struct CheckArgs {
  /// 语法文件路径
  grammar_file : String
} derive(Show)

///|
pub struct FmtArgs {
  /// 语法文件路径
  grammar_file : String
  /// 仅检查，不写入（CI 用）
  check : Bool
  /// 输出到 stdout 而非原地修改
  stdout : Bool
} derive(Show)

///|
pub struct QueryArgs {
  /// S-表达式查询模式字符串
  pattern : String
  /// 输入文件路径（None = 从 stdin 读取）
  input_file : String?
  /// 语法文件路径（与 table_file 互斥）
  grammar_file : String?
  /// 解析表文件路径（与 grammar_file 互斥）
  table_file : String?
  /// 是否输出 JSON 格式
  json : Bool
  /// 是否只输出匹配数量
  count : Bool
} derive(Show)

///|
pub struct TestArgs {
  /// 测试目录路径（默认 grammars/tests/）
  test_dir : String?
} derive(Show)

///|
pub enum OutputFormat {
  Sexp
  Json
} derive(Show, Eq)

///|
/// 解析后的顶层命令
pub enum Command {
  Generate(GenerateArgs)
  Parse(ParseArgs)
  Check(CheckArgs)
  Fmt(FmtArgs)
  Query(QueryArgs)
  Test(TestArgs)
  /// None = 全局帮助，Some(cmd_name) = 子命令帮助
  Help(String?)
  Version
} derive(Show)

///|
// 内部解析状态

///|
/// 消耗 ArgParser 头部的全局 flag：--no-color、--quiet / -q。
/// 识别到后直接调用 reporter 设置函数。
/// 遇到不认识的 flag 或子命令名称时停止扫描。
fn parse_global_flags(p : ArgParser) -> Unit {
  let mut cont = true
  while cont && not(p.at_end()) {
    match p.peek() {
      Some("--no-color") => {
        let _ = p.next()
        set_color_output(Some(false))
      }
      Some("--quiet") | Some("-q") => {
        let _ = p.next()
        set_quiet(true)
      }
      _ => cont = false
    }
  }
}

///|
priv struct ArgParser {
  args : Array[String]
  mut pos : Int
}

///|
fn ArgParser::new(args : Array[String]) -> ArgParser {
  { args, pos: 0 }
}

///|
fn ArgParser::at_end(self : ArgParser) -> Bool {
  self.pos >= self.args.length()
}

///|
fn ArgParser::peek(self : ArgParser) -> String? {
  if self.at_end() {
    None
  } else {
    Some(self.args[self.pos])
  }
}

///|
fn ArgParser::next(self : ArgParser) -> String? {
  if self.at_end() {
    None
  } else {
    let v = self.args[self.pos]
    self.pos = self.pos + 1
    Some(v)
  }
}

///|
/// 从下一个位置取 flag 的值参数，若不存在则返回 Err
fn ArgParser::require_value(
  self : ArgParser,
  flag : String,
) -> Result[String, String] {
  match self.next() {
    Some(v) =>
      if v.is_empty() || v[0].to_int() == '-'.to_int() {
        Err("flag \{flag} requires a value")
      } else {
        Ok(v)
      }
    None => Err("flag \{flag} requires a value")
  }
}

///|
// 公开 API

///|
/// 解析命令行参数数组，返回强类型的 Command。
///
/// argv 应为去掉程序名后的参数列表，例如：
///   ["generate", "json.grammar", "--output", "json.parse_table"]
///
/// 错误时返回 Err(usage_hint)，调用方负责打印并以非零退出码退出。
pub fn parse_args(argv : Array[String]) -> Result[Command, String] {
  let p = ArgParser::new(argv)
  // 先处理全局 flag：--no-color / --quiet（允许在子命令之前出现）
  parse_global_flags(p)
  // 无参数：显示全局帮助
  let subcmd = match p.next() {
    None => return Ok(Help(None))
    Some(s) => s
  }
  match subcmd {
    "--help" | "-h" => return Ok(Help(None))
    "--version" | "-v" => return Ok(Version)
    "help" => {
      let sub = p.next()
      return Ok(Help(sub))
    }
    "version" => return Ok(Version)
    "generate" => parse_generate(p)
    "parse" => parse_parse(p)
    "check" => parse_check(p)
    "fmt" => parse_fmt(p)
    "query" => parse_query(p)
    "test" => parse_test(p)
    other => Err("unknown command '\{other}'\n\{global_usage()}")
  }
}

///|
fn parse_generate(p : ArgParser) -> Result[Command, String] {
  let mut grammar_file : String? = None
  let mut output : String? = None
  let mut json = false
  let mut diagnostic = false
  let mut force = false
  while not(p.at_end()) {
    match p.peek() {
      Some("--help") | Some("-h") => return Ok(Help(Some("generate")))
      Some("--output") | Some("-o") => {
        let _ = p.next()
        match p.require_value("--output") {
          Ok(v) => output = Some(v)
          Err(e) => return Err(e)
        }
      }
      Some("--json") => {
        let _ = p.next()
        json = true
      }
      Some("--diagnostic") => {
        let _ = p.next()
        diagnostic = true
      }
      Some("--force") => {
        let _ = p.next()
        force = true
      }
      Some(s) =>
        if s[0].to_int() == '-'.to_int() {
          return Err("unknown flag '\{s}' for generate\n\{generate_usage()}")
        } else {
          let _ = p.next()
          grammar_file = Some(s)
        }
      None => break
    }
  }
  match grammar_file {
    None => Err("generate: grammar file required\n\{generate_usage()}")
    Some(gf) =>
      Ok(Generate({ grammar_file: gf, output, json, diagnostic, force }))
  }
}

///|
fn parse_parse(p : ArgParser) -> Result[Command, String] {
  let mut grammar_file : String? = None
  let mut table_file : String? = None
  let mut input_file : String? = None
  let mut format = Sexp
  let mut tokens = false
  let mut error_summary = false
  while not(p.at_end()) {
    match p.peek() {
      Some("--help") | Some("-h") => return Ok(Help(Some("parse")))
      Some("--grammar") | Some("-g") => {
        let _ = p.next()
        match p.require_value("--grammar") {
          Ok(v) => grammar_file = Some(v)
          Err(e) => return Err(e)
        }
      }
      Some("--table") | Some("-t") => {
        let _ = p.next()
        match p.require_value("--table") {
          Ok(v) => table_file = Some(v)
          Err(e) => return Err(e)
        }
      }
      Some("--format") => {
        let _ = p.next()
        match p.require_value("--format") {
          Ok("sexp") => format = Sexp
          Ok("json") => format = Json
          Ok(v) =>
            return Err(
              "unknown format '\{v}', expected 'sexp' or 'json'\n\{parse_usage()}",
            )
          Err(e) => return Err(e)
        }
      }
      Some("--tokens") => {
        let _ = p.next()
        tokens = true
      }
      Some("--error-summary") => {
        let _ = p.next()
        error_summary = true
      }
      Some("--stdin") => {
        let _ = p.next()
        input_file = None // 保持 None 表示 stdin
      }
      Some(s) =>
        if s[0].to_int() == '-'.to_int() {
          return Err("unknown flag '\{s}' for parse\n\{parse_usage()}")
        } else {
          let _ = p.next()
          // 首个位置参数：无 --grammar/--table 时视为 grammar_file；
          // 第二个位置参数视为 input_file
          if grammar_file.is_empty() && table_file.is_empty() {
            grammar_file = Some(s)
          } else {
            input_file = Some(s)
          }
        }
      None => break
    }
  }
  if grammar_file is Some(_) && table_file is Some(_) {
    return Err(
      "parse: cannot use --grammar and --table together\n\{parse_usage()}",
    )
  }
  if grammar_file.is_empty() && table_file.is_empty() {
    return Err("parse: grammar or table file required\n\{parse_usage()}")
  }
  Ok(
    Parse({
      grammar_file,
      table_file,
      input_file,
      format,
      tokens,
      error_summary,
    }),
  )
}

///|
fn parse_check(p : ArgParser) -> Result[Command, String] {
  let mut grammar_file : String? = None
  while not(p.at_end()) {
    match p.peek() {
      Some("--help") | Some("-h") => return Ok(Help(Some("check")))
      Some(s) =>
        if s[0].to_int() == '-'.to_int() {
          return Err("unknown flag '\{s}' for check\n\{check_usage()}")
        } else {
          let _ = p.next()
          grammar_file = Some(s)
        }
      None => break
    }
  }
  match grammar_file {
    None => Err("check: grammar file required\n\{check_usage()}")
    Some(gf) => Ok(Check({ grammar_file: gf }))
  }
}

///|
fn parse_fmt(p : ArgParser) -> Result[Command, String] {
  let mut grammar_file : String? = None
  let mut check = false
  let mut stdout = false
  while not(p.at_end()) {
    match p.peek() {
      Some("--help") | Some("-h") => return Ok(Help(Some("fmt")))
      Some("--check") => {
        let _ = p.next()
        check = true
      }
      Some("--stdout") => {
        let _ = p.next()
        stdout = true
      }
      Some(s) =>
        if s[0].to_int() == '-'.to_int() {
          return Err("unknown flag '\{s}' for fmt\n\{fmt_usage()}")
        } else {
          let _ = p.next()
          grammar_file = Some(s)
        }
      None => break
    }
  }
  match grammar_file {
    None => Err("fmt: grammar file required\n\{fmt_usage()}")
    Some(gf) => Ok(Fmt({ grammar_file: gf, check, stdout }))
  }
}

///|
fn parse_query(p : ArgParser) -> Result[Command, String] {
  let mut pattern : String? = None
  let mut input_file : String? = None
  let mut grammar_file : String? = None
  let mut table_file : String? = None
  let mut json = false
  let mut count = false
  while not(p.at_end()) {
    match p.peek() {
      Some("--help") | Some("-h") => return Ok(Help(Some("query")))
      Some("--grammar") | Some("-g") => {
        let _ = p.next()
        match p.require_value("--grammar") {
          Ok(v) => grammar_file = Some(v)
          Err(e) => return Err(e)
        }
      }
      Some("--table") | Some("-t") => {
        let _ = p.next()
        match p.require_value("--table") {
          Ok(v) => table_file = Some(v)
          Err(e) => return Err(e)
        }
      }
      Some("--json") => {
        let _ = p.next()
        json = true
      }
      Some("--count") => {
        let _ = p.next()
        count = true
      }
      Some(s) =>
        if s[0].to_int() == '-'.to_int() {
          return Err("unknown flag '\{s}' for query\n\{query_usage()}")
        } else {
          let _ = p.next()
          // 第一个位置参数：pattern；第二个：input_file
          if pattern.is_empty() {
            pattern = Some(s)
          } else {
            input_file = Some(s)
          }
        }
      None => break
    }
  }
  if grammar_file is Some(_) && table_file is Some(_) {
    return Err(
      "query: cannot use --grammar and --table together\n\{query_usage()}",
    )
  }
  match pattern {
    None => Err("query: pattern required\n\{query_usage()}")
    Some(pat) => {
      if grammar_file.is_empty() && table_file.is_empty() {
        return Err("query: --grammar or --table required\n\{query_usage()}")
      }
      Ok(
        Query({
          pattern: pat,
          input_file,
          grammar_file,
          table_file,
          json,
          count,
        }),
      )
    }
  }
}

///|
fn parse_test(p : ArgParser) -> Result[Command, String] {
  let mut test_dir : String? = None
  while not(p.at_end()) {
    match p.peek() {
      Some("--help") | Some("-h") => return Ok(Help(Some("test")))
      Some(s) =>
        if s[0].to_int() == '-'.to_int() {
          return Err("unknown flag '\{s}' for test")
        } else {
          let _ = p.next()
          test_dir = Some(s)
        }
      None => break
    }
  }
  Ok(Test({ test_dir, }))
}

///|
// 使用帮助文本

///|
pub fn global_usage() -> String {
  (
    #|Usage: moonparse [global-options] <command> [options]
    #|
    #|Commands:
    #|  generate <file.grammar>   Compile grammar to .parse_table
    #|  parse    <file.grammar>   Parse input and print CST
    #|  check    <file.grammar>   Validate grammar and report conflicts
    #|  fmt      <file.grammar>   Format a .grammar file
    #|  query    <pattern>        Run S-expression query on CST
    #|  test     [dir]            Run corpus test cases
    #|
    #|Global options (before <command>):
    #|  --no-color     Disable ANSI color output
    #|  -q, --quiet    Suppress informational output (errors/warnings still shown)
    #|
    #|Options:
    #|  -h, --help     Show help
    #|  -v, --version  Show version
    #|
    #|Run 'moonparse help <command>' for command-specific help.
  )
}

///|
pub fn generate_usage() -> String {
  (
    #|Usage: moonparse generate <file.grammar> [options]
    #|
    #|Options:
    #|  -o, --output <path>   Output file (default: <base>.parse_table)
    #|  --json                Output JSON format parse table (debug)
    #|  --diagnostic          Print LR item sets and GOTO table to stderr
    #|  --force               Output despite ambiguity conflicts
    #|  -h, --help            Show this help
  )
}

///|
pub fn parse_usage() -> String {
  (
    #|Usage: moonparse parse <file.grammar> [input-file] [options]
    #|
    #|Options:
    #|  -g, --grammar <file>  Grammar file (.grammar)
    #|  -t, --table   <file>  Parse table file (.parse_table)
    #|  --format <sexp|json>  Output format (default: sexp)
    #|  --tokens              Also print token stream
    #|  --error-summary       Only print ERROR node summary
    #|  --stdin               Read input from stdin
    #|  -h, --help            Show this help
  )
}

///|
pub fn check_usage() -> String {
  (
    #|Usage: moonparse check <file.grammar>
    #|
    #|Exit codes: 0 = ok, 1 = warnings, 2 = errors
    #|
    #|Options:
    #|  -h, --help  Show this help
  )
}

///|
pub fn fmt_usage() -> String {
  (
    #|Usage: moonparse fmt <file.grammar> [options]
    #|
    #|Options:
    #|  --check   Check only, do not write (for CI)
    #|  --stdout  Write result to stdout instead of in-place
    #|  -h, --help  Show this help
  )
}

///|
pub fn query_usage() -> String {
  (
    #|Usage: moonparse query <pattern> [input-file] [options]
    #|
    #|Options:
    #|  -g, --grammar <file>  Grammar file (.grammar)
    #|  -t, --table   <file>  Parse table file (.parse_table)
    #|  --json                Output JSON format
    #|  --count               Only print match count
    #|  -h, --help            Show this help
  )
}
