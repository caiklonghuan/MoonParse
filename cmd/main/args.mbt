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
  force : Bool
} derive(Debug)

///|
pub struct ParseArgs {
  /// 语法文件路径（.grammar），与 table 互斥
  grammar_file : String?
  /// 解析表文件路径（.parse_table），与 grammar_file 互斥
  table_file : String?
  bundle_file : String?
  /// 输入文件路径（None = 从 stdin 读取）
  input_file : String?
  /// 输出格式：sexp（默认）/ json / dot / tree
  format : OutputFormat
  /// 直接输出到指定文件；None = 默认写到 stdout
  output : String?
  /// 输出目录；会按输入文件名自动生成输出文件名
  outdir : String?
  /// 是否先输出 token 流
  tokens : Bool
  /// 是否只输出 ERROR 节点摘要
  error_summary : Bool
} derive(Debug)

///|
pub struct CheckArgs {
  /// 语法文件路径
  grammar_file : String
  conflict_detail : Bool
} derive(Debug)

///|
pub struct FmtArgs {
  /// 语法文件路径
  grammar_file : String
  /// 仅检查，不写入（CI 用）
  check : Bool
  /// 输出到 stdout 而非原地修改
  stdout : Bool
} derive(Debug)

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
  bundle_file : String?
  /// 是否输出 JSON 格式
  json : Bool
  /// 是否只输出匹配数量
  count : Bool
} derive(Debug)

///|
pub struct TestArgs {
  /// 测试目标规范字符串，支持 "grammar:corpus" 或单独 corpus 路径（自动旁推 .grammar）
  test_dir : String?
} derive(Debug)

///|
pub enum OutputFormat {
  Sexp
  Json
  /// Graphviz DOT 格式，输出后可用 `dot -Tsvg` 渲染为 SVG
  Dot
  /// 带 spans 和叶子文本的树形文本，便于和 website 树面板对照
  Tree
} derive(Debug, Eq)

///|
pub struct BuildArgs {
  /// 输入文件（.grammar 或 .parse_table）
  input : String
  /// 输出目录（默认 build/）
  outdir : String?
  /// 是否同时输出 wasm 扩展名产物
  wasm : Bool
  conflict_detail : Bool
} derive(Debug)

///|
pub struct WasmArgs {
  /// 语法文件路径（.grammar），与 table_file 互斥
  grammar_file : String?
  /// 解析表文件路径（.parse_table），与 grammar_file 互斥
  table_file : String?
  /// 输出目录（默认 dist/）
  outdir : String?
} derive(Debug)

///|
pub enum DumpTarget {
  Ir
  Table
  Automaton
} derive(Debug)

///|
pub struct DumpArgs {
  /// 子目标：ir / table / automaton
  target : DumpTarget
  /// 输入文件（.grammar 或 .parse_table）
  input : String
} derive(Debug)

///|
pub struct CleanArgs {
  /// 是否跳过确认，直接执行（保留字段，当前始终直接执行）
  force : Bool
} derive(Debug)

///|
pub(all) enum PackOutputFormat {
  Human
  Json
} derive(Debug, Eq)

///|
pub(all) struct PackInitArgs {
  id : String?
  name : String?
  entry_rule : String?
  extensions : Array[String]
  maturity : String?
  directory : String?
  format : PackOutputFormat
} derive(Debug)

///|
pub(all) struct PackCheckArgs {
  directory : String
  format : PackOutputFormat
} derive(Debug)

///|
pub(all) struct PackTestArgs {
  directory : String
  update : Bool
  format : PackOutputFormat
} derive(Debug)

///|
pub(all) struct PackBuildArgs {
  directory : String
  output : String?
  targets : Array[PackBuildTarget]
  out_dir : String?
  package_name : String?
  format : PackOutputFormat
} derive(Debug)

///|
pub(all) struct PackImportTreeSitterArgs {
  source_dir : String
  directory : String
  id : String?
  name : String?
  version : String?
  extensions : Array[String]
  format : PackOutputFormat
} derive(Debug)

///|
pub(all) struct PackExportTreeSitterArgs {
  directory : String
  output : String
  format : PackOutputFormat
} derive(Debug)

///|
pub(all) enum PackBuildTarget {
  Bundle
  Moonbit
  Wasm
  Npm
  Lsp
  Vscode
  Web
} derive(Debug, Eq)

///|
pub(all) enum PackCommand {
  Init(PackInitArgs)
  Check(PackCheckArgs)
  Test(PackTestArgs)
  Build(PackBuildArgs)
  ImportTreeSitter(PackImportTreeSitterArgs)
  ExportTreeSitter(PackExportTreeSitterArgs)
} derive(Debug)

///|
/// 解析后的顶层命令
pub enum Command {
  Generate(GenerateArgs)
  Parse(ParseArgs)
  Check(CheckArgs)
  Fmt(FmtArgs)
  Query(QueryArgs)
  Test(TestArgs)
  Build(BuildArgs)
  Wasm(WasmArgs)
  Dump(DumpArgs)
  Clean(CleanArgs)
  Pack(PackCommand)
  /// None = 全局帮助，Some(cmd_name) = 子命令帮助
  Help(String?)
  Version
} derive(Debug)

///|
pub impl Show for GenerateArgs with fn output(self, logger) {
  logger.write_string(
    "GenerateArgs(grammar_file: \{self.grammar_file}, output: \{to_repr(self.output)}, json: \{self.json}, diagnostic: \{self.diagnostic}, force: \{self.force})",
  )
}

///|
pub impl Show for ParseArgs with fn output(self, logger) {
  logger.write_string(
    "ParseArgs(grammar_file: \{to_repr(self.grammar_file)}, table_file: \{to_repr(self.table_file)}, bundle_file: \{to_repr(self.bundle_file)}, input_file: \{to_repr(self.input_file)}, format: \{self.format}, output: \{to_repr(self.output)}, outdir: \{to_repr(self.outdir)}, tokens: \{self.tokens}, error_summary: \{self.error_summary})",
  )
}

///|
pub impl Show for CheckArgs with fn output(self, logger) {
  logger.write_string(
    "CheckArgs(grammar_file: \{self.grammar_file}, conflict_detail: \{self.conflict_detail})",
  )
}

///|
pub impl Show for FmtArgs with fn output(self, logger) {
  logger.write_string(
    "FmtArgs(grammar_file: \{self.grammar_file}, check: \{self.check}, stdout: \{self.stdout})",
  )
}

///|
pub impl Show for QueryArgs with fn output(self, logger) {
  logger.write_string(
    "QueryArgs(pattern: \{to_repr(self.pattern)}, input_file: \{to_repr(self.input_file)}, grammar_file: \{to_repr(self.grammar_file)}, table_file: \{to_repr(self.table_file)}, bundle_file: \{to_repr(self.bundle_file)}, json: \{self.json}, count: \{to_repr(self.count)})",
  )
}

///|
pub impl Show for TestArgs with fn output(self, logger) {
  logger.write_string("TestArgs(test_dir: \{to_repr(self.test_dir)})")
}

///|
pub impl Show for BuildArgs with fn output(self, logger) {
  logger.write_string(
    "BuildArgs(input: \{self.input}, outdir: \{to_repr(self.outdir)}, wasm: \{self.wasm}, conflict_detail: \{self.conflict_detail})",
  )
}

///|
pub impl Show for WasmArgs with fn output(self, logger) {
  logger.write_string(
    "WasmArgs(grammar_file: \{to_repr(self.grammar_file)}, table_file: \{to_repr(self.table_file)}, outdir: \{to_repr(self.outdir)})",
  )
}

///|
pub impl Show for DumpTarget with fn output(self, logger) {
  match self {
    Ir => logger.write_string("Ir")
    Table => logger.write_string("Table")
    Automaton => logger.write_string("Automaton")
  }
}

///|
pub impl Show for DumpArgs with fn output(self, logger) {
  logger.write_string("DumpArgs(target: \{self.target}, input: \{self.input})")
}

///|
pub impl Show for CleanArgs with fn output(self, logger) {
  logger.write_string("CleanArgs(force: \{self.force})")
}

///|
pub impl Show for OutputFormat with fn output(self, logger) {
  match self {
    Sexp => logger.write_string("Sexp")
    Json => logger.write_string("Json")
    Dot => logger.write_string("Dot")
    Tree => logger.write_string("Tree")
  }
}

///|
pub impl Show for Command with fn output(self, logger) {
  match self {
    Generate(args) => logger.write_string("Generate(\{args})")
    Parse(args) => logger.write_string("Parse(\{args})")
    Check(args) => logger.write_string("Check(\{args})")
    Fmt(args) => logger.write_string("Fmt(\{args})")
    Query(args) => logger.write_string("Query(\{args})")
    Test(args) => logger.write_string("Test(\{args})")
    Build(args) => logger.write_string("Build(\{args})")
    Wasm(args) => logger.write_string("Wasm(\{args})")
    Dump(args) => logger.write_string("Dump(\{args})")
    Clean(args) => logger.write_string("Clean(\{args})")
    Pack(_) => logger.write_string("Pack")
    Help(sub) => logger.write_string("Help(\{to_repr(sub)})")
    Version => logger.write_string("Version")
  }
}

///|
// 内部解析状态

///|
/// 消耗 ArgParser 头部的全局 flag：--no-color、--quiet / -q
fn parse_global_flags(p : ArgParser) -> Unit {
  let mut cont = true
  while cont && !p.at_end() {
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
/// 解析命令行参数数组，返回强类型的 Command
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
    "build" => parse_build(p)
    "wasm" => parse_wasm(p)
    "dump" => parse_dump(p)
    "clean" => parse_clean(p)
    "pack" => parse_pack(p)
    other => Err("unknown command '\{other}'\n\{global_usage()}")
  }
}

///|
fn parse_pack(p : ArgParser) -> Result[Command, String] {
  let mut format = PackOutputFormat::Human
  if p.peek() == Some("--format") {
    ignore(p.next())
    match p.require_value("--format") {
      Ok("human") => format = Human
      Ok("json") => format = Json
      Ok(value) =>
        return Err("pack: unknown format '" + value + "'\n" + pack_usage())
      Err(error) => return Err(error)
    }
  }
  let sub = match p.next() {
    Some(value) => value
    None => return Err("pack: subcommand required\n" + pack_usage())
  }
  match sub {
    "init" => parse_pack_init(p, format)
    "check" => parse_pack_check(p, format)
    "test" => parse_pack_test(p, format)
    "build" => parse_pack_build(p, format)
    "import-tree-sitter" => parse_pack_import_tree_sitter(p, format)
    "export-tree-sitter" => parse_pack_export_tree_sitter(p, format)
    "help" | "--help" | "-h" => Ok(Help(Some("pack")))
    other => Err("pack: unknown subcommand '" + other + "'\n" + pack_usage())
  }
}

///|
fn parse_pack_export_tree_sitter(
  p : ArgParser,
  format : PackOutputFormat,
) -> Result[Command, String] {
  let mut directory : String? = None
  let mut output : String? = None
  while !p.at_end() {
    match p.next() {
      Some("--output") | Some("-o") =>
        match p.require_value("--output") {
          Ok(value) => output = Some(value)
          Err(error) => return Err(error)
        }
      Some("--help") | Some("-h") => return Ok(Help(Some("pack")))
      Some(value) =>
        if value.has_prefix("-") {
          return Err("pack export-tree-sitter: unknown flag '" + value + "'")
        } else if directory is Some(_) {
          return Err(
            "pack export-tree-sitter: only one pack directory is allowed",
          )
        } else {
          directory = Some(value)
        }
      None => ()
    }
  }
  match (directory, output) {
    (Some(directory), Some(output)) =>
      Ok(Pack(ExportTreeSitter({ directory, output, format })))
    (None, _) =>
      Err("pack export-tree-sitter: pack directory required\n" + pack_usage())
    (_, None) =>
      Err(
        "pack export-tree-sitter: -o <grammar.json> required\n" + pack_usage(),
      )
  }
}

///|
fn parse_pack_import_tree_sitter(
  p : ArgParser,
  format : PackOutputFormat,
) -> Result[Command, String] {
  let mut source_dir : String? = None
  let mut directory : String? = None
  let mut id : String? = None
  let mut name : String? = None
  let mut version : String? = None
  let extensions : Array[String] = []
  while !p.at_end() {
    match p.next() {
      Some("--dir") =>
        match p.require_value("--dir") {
          Ok(value) => directory = Some(value)
          Err(error) => return Err(error)
        }
      Some("--id") =>
        match p.require_value("--id") {
          Ok(value) => id = Some(value)
          Err(error) => return Err(error)
        }
      Some("--name") =>
        match p.require_value("--name") {
          Ok(value) => name = Some(value)
          Err(error) => return Err(error)
        }
      Some("--version") =>
        match p.require_value("--version") {
          Ok(value) => version = Some(value)
          Err(error) => return Err(error)
        }
      Some("--extension") =>
        match p.require_value("--extension") {
          Ok(value) => extensions.push(value)
          Err(error) => return Err(error)
        }
      Some("--help") | Some("-h") => return Ok(Help(Some("pack")))
      Some(value) =>
        if value.has_prefix("-") {
          return Err("pack import-tree-sitter: unknown flag '" + value + "'")
        } else if source_dir is Some(_) {
          return Err(
            "pack import-tree-sitter: only one source directory is allowed",
          )
        } else {
          source_dir = Some(value)
        }
      None => ()
    }
  }
  match (source_dir, directory) {
    (Some(source_dir), Some(directory)) =>
      Ok(
        Pack(
          ImportTreeSitter({
            source_dir,
            directory,
            id,
            name,
            version,
            extensions,
            format,
          }),
        ),
      )
    (None, _) =>
      Err("pack import-tree-sitter: source directory required\n" + pack_usage())
    (_, None) =>
      Err("pack import-tree-sitter: --dir <pack-dir> required\n" + pack_usage())
  }
}

///|
fn parse_pack_init(
  p : ArgParser,
  format : PackOutputFormat,
) -> Result[Command, String] {
  let mut id : String? = None
  let mut name : String? = None
  let mut entry_rule : String? = None
  let extensions : Array[String] = []
  let mut maturity : String? = None
  let mut directory : String? = None
  while !p.at_end() {
    match p.peek() {
      Some("--name") => {
        ignore(p.next())
        match p.require_value("--name") {
          Ok(v) => name = Some(v)
          Err(e) => return Err(e)
        }
      }
      Some("--entry-rule") => {
        ignore(p.next())
        match p.require_value("--entry-rule") {
          Ok(v) => entry_rule = Some(v)
          Err(e) => return Err(e)
        }
      }
      Some("--extension") => {
        ignore(p.next())
        match p.require_value("--extension") {
          Ok(v) => extensions.push(v)
          Err(e) => return Err(e)
        }
      }
      Some("--maturity") => {
        ignore(p.next())
        match p.require_value("--maturity") {
          Ok(v) => maturity = Some(v)
          Err(e) => return Err(e)
        }
      }
      Some("--dir") => {
        ignore(p.next())
        match p.require_value("--dir") {
          Ok(v) => directory = Some(v)
          Err(e) => return Err(e)
        }
      }
      Some("--help") | Some("-h") => return Ok(Help(Some("pack")))
      Some(value) =>
        if value.has_prefix("-") {
          return Err("pack init: unknown flag '" + value + "'")
        } else if id is Some(_) {
          return Err("pack init: only one id is allowed")
        } else {
          ignore(p.next())
          id = Some(value)
        }
      None => break
    }
  }
  Ok(
    Pack(
      Init({ id, name, entry_rule, extensions, maturity, directory, format }),
    ),
  )
}

///|
fn parse_pack_check(
  p : ArgParser,
  format : PackOutputFormat,
) -> Result[Command, String] {
  let directory = match p.next() {
    Some(v) => v
    None => "."
  }
  if !p.at_end() {
    return Err("pack check: too many arguments")
  }
  Ok(Pack(Check({ directory, format })))
}

///|
fn parse_pack_test(
  p : ArgParser,
  format : PackOutputFormat,
) -> Result[Command, String] {
  let mut directory = "."
  let mut update = false
  while !p.at_end() {
    match p.next() {
      Some("--update") => update = true
      Some(v) =>
        if v.has_prefix("-") {
          return Err("pack test: unknown flag '" + v + "'")
        } else if directory != "." {
          return Err("pack test: too many arguments")
        } else {
          directory = v
        }
      None => ()
    }
  }
  Ok(Pack(Test({ directory, update, format })))
}

///|
fn parse_pack_build(
  p : ArgParser,
  format : PackOutputFormat,
) -> Result[Command, String] {
  let mut directory = "."
  let mut output : String? = None
  let targets : Array[PackBuildTarget] = []
  let mut out_dir : String? = None
  let mut package_name : String? = None
  while !p.at_end() {
    match p.next() {
      Some("--output") | Some("-o") =>
        match p.require_value("--output") {
          Ok(v) => output = Some(v)
          Err(e) => return Err(e)
        }
      Some("--target") =>
        match p.require_value("--target") {
          Ok("bundle") => targets.push(Bundle)
          Ok("moonbit") => targets.push(Moonbit)
          Ok("wasm") => targets.push(Wasm)
          Ok("npm") => targets.push(Npm)
          Ok("lsp") => targets.push(Lsp)
          Ok("vscode") => targets.push(Vscode)
          Ok("web") => targets.push(Web)
          Ok(v) => return Err("pack build: unknown target '" + v + "'")
          Err(e) => return Err(e)
        }
      Some("--out-dir") =>
        match p.require_value("--out-dir") {
          Ok(v) => out_dir = Some(v)
          Err(e) => return Err(e)
        }
      Some("--package-name") =>
        match p.require_value("--package-name") {
          Ok(v) => package_name = Some(v)
          Err(e) => return Err(e)
        }
      Some(v) =>
        if v.has_prefix("-") {
          return Err("pack build: unknown flag '" + v + "'")
        } else if directory != "." {
          return Err("pack build: too many arguments")
        } else {
          directory = v
        }
      None => ()
    }
  }
  if output is Some(_) &&
    !targets.is_empty() &&
    (targets.length() != 1 || targets[0] != Bundle) {
    return Err(
      "pack build: --output is only valid with the single bundle target",
    )
  }
  if out_dir is Some(_) && targets.is_empty() {
    return Err("pack build: --out-dir requires at least one --target")
  }
  if package_name is Some(_) && !targets.contains(Npm) {
    return Err("pack build: --package-name requires --target npm")
  }
  Ok(Pack(Build({ directory, output, targets, out_dir, package_name, format })))
}

///|
fn parse_generate(p : ArgParser) -> Result[Command, String] {
  let mut grammar_file : String? = None
  let mut output : String? = None
  let mut json = false
  let mut diagnostic = false
  let mut force = false
  while !p.at_end() {
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
  let mut bundle_file : String? = None
  let mut input_file : String? = None
  let mut format = Sexp
  let mut output : String? = None
  let mut outdir : String? = None
  let mut tokens = false
  let mut error_summary = false
  while !p.at_end() {
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
      Some("--bundle") | Some("-b") => {
        let _ = p.next()
        match p.require_value("--bundle") {
          Ok(v) => bundle_file = Some(v)
          Err(e) => return Err(e)
        }
      }
      Some("--format") => {
        let _ = p.next()
        match p.require_value("--format") {
          Ok("sexp") => format = Sexp
          Ok("json") => format = Json
          Ok("dot") => format = Dot
          Ok("tree") => format = Tree
          Ok(v) =>
            return Err(
              "unknown format '\{v}', expected 'sexp', 'json', 'dot', or 'tree'\n\{parse_usage()}",
            )
          Err(e) => return Err(e)
        }
      }
      Some("--output") | Some("-o") => {
        let _ = p.next()
        match p.require_value("--output") {
          Ok(v) => output = Some(v)
          Err(e) => return Err(e)
        }
      }
      Some("--outdir") => {
        let _ = p.next()
        match p.require_value("--outdir") {
          Ok(v) => outdir = Some(v)
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
          if grammar_file is None && table_file is None && bundle_file is None {
            grammar_file = Some(s)
          } else {
            input_file = Some(s)
          }
        }
      None => break
    }
  }
  let source_count = (if grammar_file is Some(_) { 1 } else { 0 }) +
    (if table_file is Some(_) { 1 } else { 0 }) +
    (if bundle_file is Some(_) { 1 } else { 0 })
  if source_count > 1 {
    return Err(
      "parse: --grammar, --table and --bundle are mutually exclusive\n\{parse_usage()}",
    )
  }
  if output is Some(_) && outdir is Some(_) {
    return Err(
      "parse: cannot use --output and --outdir together\n\{parse_usage()}",
    )
  }
  if source_count == 0 {
    return Err(
      "parse: grammar, table or bundle file required\n\{parse_usage()}",
    )
  }
  Ok(
    Parse({
      grammar_file,
      table_file,
      bundle_file,
      input_file,
      format,
      output,
      outdir,
      tokens,
      error_summary,
    }),
  )
}

///|
fn parse_check(p : ArgParser) -> Result[Command, String] {
  let mut grammar_file : String? = None
  let mut conflict_detail = false
  while !p.at_end() {
    match p.peek() {
      Some("--help") | Some("-h") => return Ok(Help(Some("check")))
      Some("--conflict-detail") | Some("--explain-conflicts") => {
        let _ = p.next()
        conflict_detail = true
      }
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
    Some(gf) => Ok(Check({ grammar_file: gf, conflict_detail }))
  }
}

///|
fn parse_fmt(p : ArgParser) -> Result[Command, String] {
  let mut grammar_file : String? = None
  let mut check = false
  let mut stdout = false
  while !p.at_end() {
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
  let mut bundle_file : String? = None
  let mut json = false
  let mut count = false
  while !p.at_end() {
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
      Some("--bundle") | Some("-b") => {
        let _ = p.next()
        match p.require_value("--bundle") {
          Ok(v) => bundle_file = Some(v)
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
          if pattern is None {
            pattern = Some(s)
          } else {
            input_file = Some(s)
          }
        }
      None => break
    }
  }
  let source_count = (if grammar_file is Some(_) { 1 } else { 0 }) +
    (if table_file is Some(_) { 1 } else { 0 }) +
    (if bundle_file is Some(_) { 1 } else { 0 })
  if source_count > 1 {
    return Err(
      "query: --grammar, --table and --bundle are mutually exclusive\n\{query_usage()}",
    )
  }
  match pattern {
    None => Err("query: pattern required\n\{query_usage()}")
    Some(pat) => {
      if source_count == 0 {
        return Err(
          "query: --grammar, --table or --bundle required\n\{query_usage()}",
        )
      }
      Ok(
        Query({
          pattern: pat,
          input_file,
          grammar_file,
          table_file,
          bundle_file,
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
  while !p.at_end() {
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
fn global_usage() -> String {
  (
    #|Usage: moonparse [global-options] <command> [options]
    #|
    #|Commands:
    #|  generate       <file.grammar>  Compile grammar to .parse_table
    #|  parse          <file.grammar>  Parse input and print CST
    #|  check          <file.grammar>  Validate grammar and report conflicts
    #|  fmt            <file.grammar>  Format a .grammar file
    #|  query          <pattern>       Run S-expression query on CST
    #|  test           [dir]           Run corpus test cases
    #|  build          <file>          Build distributable parser artifact
    #|  wasm           <file>          Build WASM distribution package
    #|  dump           <target> <file> Dump internal structures for debugging
    #|  clean                          Remove generated/, build/, dist/
    #|  pack           <command>       Create, check, test, or build a Language Pack
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
fn pack_usage() -> String {
  (
    #|Usage: moonparse pack [--format human|json] <command> [options]
    #|
    #|Commands:
    #|  init [<id>] [options]       Create a Language Pack (interactive without id)
    #|  check [<pack-dir>]          Validate a Language Pack
    #|  test [<pack-dir>] [--update] Run Corpus tests or update v2 snapshots
    #|  build [<pack-dir>] [options] Build Bundle and distribution targets
    #|  import-tree-sitter <tree-sitter-dir> --dir <pack-dir>
    #|                              Import Tree-sitter grammar.json as a Pack
    #|  export-tree-sitter <pack-dir> -o <grammar.json>
    #|                              Export a Pack as Tree-sitter grammar.json
    #|
    #|Init options:
    #|  --name <name> --entry-rule <rule> --extension <ext>
    #|  --maturity <value> --dir <path>
    #|
    #|Build options:
    #|  --target bundle|moonbit|wasm|npm|lsp|vscode|web
    #|                                  Repeatable; default is Bundle only
    #|  --out-dir <dir>                   Distribution root (default: dist/<id>)
    #|  --package-name <name>             Override NPM package name
    #|  -o, --output <file>               Single Bundle output only
    #|
    #|Import Tree-sitter options:
    #|  --dir <path>                      Target Pack directory
    #|  --id <id> --name <name> --version <semver>
    #|  --extension <ext>                 Repeatable extension override
    #|
    #|Export Tree-sitter options:
    #|  -o, --output <grammar.json>       Output grammar.json path
  )
}

///|
fn generate_usage() -> String {
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
fn parse_usage() -> String {
  (
    #|Usage: moonparse parse (-g <grammar> | -t <table> | -b <bundle>) [input-file] [options]
    #|
    #|Options:
    #|  -g, --grammar <file>  Grammar file (.grammar)
    #|  -t, --table   <file>  Parse table file (.parse_table)
    #|  -b, --bundle  <file>  LanguageBundle JSON (enables its Scanner)
    #|  --format <fmt>        Output format: sexp (default), json, dot (Graphviz), tree
    #|  -o, --output <file>   Write output to file instead of stdout
    #|  --outdir <dir>        Write output to auto-named file under directory
    #|  --tokens              Also print token stream
    #|  --error-summary       Only print ERROR node summary
    #|  --stdin               Read input from stdin
    #|  -h, --help            Show this help
  )
}

///|
fn test_usage() -> String {
  (
    #|Usage: moonparse test <spec>
    #|
    #|spec formats:
    #|  grammar.grammar:corpus.txt   Explicit grammar and corpus files
    #|  corpus.txt                   Auto-derives grammar from same basename
    #|
    #|Exit codes: 0 = all passed, 1 = test failures, 2 = load/compile error
    #|
    #|Options:
    #|  -h, --help  Show this help
  )
}

///|
fn check_usage() -> String {
  (
    #|Usage: moonparse check <file.grammar>
    #|
    #|Exit codes: 0 = ok, 1 = warnings, 2 = errors
    #|
    #|Options:
    #|  --conflict-detail     Explain each conflict with actions and Mermaid graph
    #|  --explain-conflicts   Alias for --conflict-detail
    #|  -h, --help            Show this help
  )
}

///|
fn fmt_usage() -> String {
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
fn query_usage() -> String {
  (
    #|Usage: moonparse query <pattern> [input-file] [options]
    #|
    #|Options:
    #|  -g, --grammar <file>  Grammar file (.grammar)
    #|  -t, --table   <file>  Parse table file (.parse_table)
    #|  -b, --bundle  <file>  LanguageBundle JSON; pattern may be highlights/locals/bindings/folding/modules
    #|  --json                Output JSON format
    #|  --count               Only print match count
    #|  -h, --help            Show this help
  )
}

///|
fn parse_build(p : ArgParser) -> Result[Command, String] {
  let mut input : String? = None
  let mut outdir : String? = None
  let mut wasm = false
  let mut conflict_detail = false
  while !p.at_end() {
    match p.peek() {
      Some("--help") | Some("-h") => return Ok(Help(Some("build")))
      Some("--output") | Some("-o") => {
        let _ = p.next()
        match p.require_value("--output") {
          Ok(v) => outdir = Some(v)
          Err(e) => return Err(e)
        }
      }
      Some("--wasm") => {
        let _ = p.next()
        wasm = true
      }
      Some("--conflict-detail") | Some("--explain-conflicts") => {
        let _ = p.next()
        conflict_detail = true
      }
      Some(s) =>
        if s[0].to_int() == '-'.to_int() {
          return Err("unknown flag '\{s}' for build\n\{build_usage()}")
        } else {
          let _ = p.next()
          input = Some(s)
        }
      None => break
    }
  }
  match input {
    None => Err("build: input file required\n\{build_usage()}")
    Some(f) => Ok(Build({ input: f, outdir, wasm, conflict_detail }))
  }
}

///|
fn parse_wasm(p : ArgParser) -> Result[Command, String] {
  let mut grammar_file : String? = None
  let mut table_file : String? = None
  let mut outdir : String? = None
  while !p.at_end() {
    match p.peek() {
      Some("--help") | Some("-h") => return Ok(Help(Some("wasm")))
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
      Some("--output") | Some("-o") => {
        let _ = p.next()
        match p.require_value("--output") {
          Ok(v) => outdir = Some(v)
          Err(e) => return Err(e)
        }
      }
      Some(s) =>
        if s[0].to_int() == '-'.to_int() {
          return Err("unknown flag '\{s}' for wasm\n\{wasm_usage()}")
        } else {
          let _ = p.next()
          if grammar_file is None && table_file is None {
            grammar_file = Some(s)
          } else {
            return Err(
              "wasm: unexpected positional argument '\{s}'\n\{wasm_usage()}",
            )
          }
        }
      None => break
    }
  }
  if grammar_file is Some(_) && table_file is Some(_) {
    return Err(
      "wasm: cannot use --grammar and --table together\n\{wasm_usage()}",
    )
  }
  if grammar_file is None && table_file is None {
    return Err("wasm: grammar or table file required\n\{wasm_usage()}")
  }
  Ok(Wasm({ grammar_file, table_file, outdir }))
}

///|
fn parse_dump(p : ArgParser) -> Result[Command, String] {
  // 子目标是第一个位置参数
  let target_str = match p.next() {
    Some("--help") | Some("-h") => return Ok(Help(Some("dump")))
    Some(s) => s
    None =>
      return Err(
        "dump: target required (ir | table | automaton)\n\{dump_usage()}",
      )
  }
  let target = match target_str {
    "ir" => DumpTarget::Ir
    "table" => DumpTarget::Table
    "automaton" => DumpTarget::Automaton
    other =>
      return Err(
        "dump: unknown target '\{other}' (expected: ir | table | automaton)\n\{dump_usage()}",
      )
  }
  let mut input : String? = None
  while !p.at_end() {
    match p.peek() {
      Some("--help") | Some("-h") => return Ok(Help(Some("dump")))
      Some(s) =>
        if s[0].to_int() == '-'.to_int() {
          return Err("unknown flag '\{s}' for dump\n\{dump_usage()}")
        } else {
          let _ = p.next()
          input = Some(s)
        }
      None => break
    }
  }
  match input {
    None => Err("dump: input file required\n\{dump_usage()}")
    Some(f) => Ok(Dump({ target, input: f }))
  }
}

///|
fn parse_clean(p : ArgParser) -> Result[Command, String] {
  let mut force = false
  while !p.at_end() {
    match p.peek() {
      Some("--help") | Some("-h") => return Ok(Help(Some("clean")))
      Some("--force") | Some("-f") => {
        let _ = p.next()
        force = true
      }
      Some(s) =>
        if s[0].to_int() == '-'.to_int() {
          return Err("unknown flag '\{s}' for clean\n\{clean_usage()}")
        } else {
          return Err("clean: unexpected argument '\{s}'\n\{clean_usage()}")
        }
      None => break
    }
  }
  Ok(Clean({ force, }))
}

///|
fn build_usage() -> String {
  (
    #|Usage: moonparse build <file> [options]
    #|
    #|Input: .grammar file (generates parse table first) or .parse_table file
    #|
    #|Output: build/
    #|  parser.parse_table   Binary parse table (native target)
    #|  parser.wasm          Same artifact with .wasm extension (with --wasm)
    #|
    #|Options:
    #|  -o, --output <dir>   Output directory (default: build/)
    #|  --wasm               Also write parser.wasm alongside parser.parse_table
    #|  --conflict-detail    Explain each grammar conflict with actions and graph
    #|  --explain-conflicts  Alias for --conflict-detail
    #|  -h, --help           Show this help
  )
}

///|
fn wasm_usage() -> String {
  (
    #|Usage: moonparse wasm (-g <file.grammar> | -t <file.parse_table>) [options]
    #|
    #|Build a WASM distribution package from a grammar or parse table.
    #|
    #|Output: dist/
    #|  parser.js            JavaScript module (embeds grammar DSL)
    #|  parser.parse_table   Binary parse table
    #|
    #|Options:
    #|  -g, --grammar <file>  Grammar file (.grammar)
    #|  -t, --table   <file>  Parse table file (.parse_table)
    #|  -o, --output <dir>    Output directory (default: dist/)
    #|  -h, --help            Show this help
  )
}

///|
fn dump_usage() -> String {
  (
    #|Usage: moonparse dump <target> <file> [options]
    #|
    #|Targets:
    #|  ir         Print the grammar IR (rules, terminals, precedences)
    #|  table      Print the LALR parse table as JSON
    #|  automaton  Print LR(0) item sets and GOTO transitions
    #|
    #|Input: .grammar file (or .parse_table for 'table' target)
    #|
    #|Options:
    #|  -h, --help  Show this help
    #|
    #|Examples:
    #|  moonparse dump ir      grammar.grammar
    #|  moonparse dump table   grammar.grammar
    #|  moonparse dump automaton grammar.grammar
  )
}

///|
fn clean_usage() -> String {
  (
    #|Usage: moonparse clean [options]
    #|
    #|Remove build artifacts: generated/, build/, dist/
    #|
    #|Options:
    #|  -f, --force  Skip confirmation (currently always skips, reserved for future use)
    #|  -h, --help   Show this help
  )
}
