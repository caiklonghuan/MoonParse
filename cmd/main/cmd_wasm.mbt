///|
// wasm 命令处理器
// grammar / parse_table → dist/parser.js + dist/parser.parse_table

///|
/// wasm 命令主体。
/// 输出：
///   <outdir>/parser.parse_table   — 二进制解析表
///   <outdir>/parser.js            — JavaScript 加载模块
/// 返回退出码：0=成功，1=有警告，2=致命错误。
pub fn cmd_wasm(args : WasmArgs) -> Int {
  let outdir = match args.outdir {
    Some(d) => d
    None => "dist"
  }

  // 创建输出目录
  match make_dir(outdir) {
    Ok(_) => ()
    Err(msg) => {
      print_err("error: " + msg)
      return 2
    }
  }

  // 确定输入来源
  let (table_bytes, grammar_dsl, table_json, exit_code) = match
    args.grammar_file {
    Some(gf) =>
      match wasm_from_grammar(gf) {
        Err(code) => return code
        Ok(triple) => triple
      }
    None =>
      match args.table_file {
        Some(tf) =>
          match wasm_from_table(tf) {
            Ok(result) => result
            Err(msg) => {
              print_err("error: " + msg)
              return 2
            }
          }
        None => {
          print_err("error: grammar or table file required")
          return 2
        }
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

  // 生成 JavaScript 胶水模块
  let js_content = generate_js_glue(grammar_dsl, table_json)
  let js_path = outdir + "/parser.js"
  match write_file(js_path, js_content) {
    Ok(_) => ()
    Err(msg) => {
      print_err("error: " + msg)
      return 2
    }
  }
  print_info("written: " + js_path)

  exit_code
}

///|
/// 从 .grammar 文件生成 parse table 及 DSL 字符串
fn wasm_from_grammar(
  grammar_file : String,
) -> Result[(Bytes, String?, String?, Int), Int] {
  let src = match read_file(grammar_file) {
    Ok(s) => s
    Err(msg) => {
      print_err("error: " + msg)
      return Err(2)
    }
  }

  let grammar = match @grammar.parse_grammar(src) {
    Success(g) => g
    Error(err) => {
      report_grammar_parse_error(err, Some(grammar_file), Some(src))
      return Err(2)
    }
  }

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
  Ok((bytes, Some(src), None, exit_code))
}

///|
/// 从二进制 .parse_table 文件读取，直接 base64 编码以供 JS 加载。
fn wasm_from_table(
  table_file : String,
) -> Result[(Bytes, String?, String?, Int), String] {
  let bytes = match read_bytes(table_file) {
    Ok(b) => b
    Err(msg) => return Err(msg)
  }
  // 校验二进制表格式是否合法
  match @tablegen.deserialize_table(bytes) {
    Ok(_) => ()
    Err(msg) => return Err("failed to deserialize parse table: " + msg)
  }
  Ok((bytes, None, Some(bytes_to_base64(bytes)), 0))
}

///|
// Base64 编码（用于在生成的 JS 中嵌入二进制解析表）

///|
fn base64_encode_char(idx : Int) -> Char {
  if idx < 26 {
    (65 + idx).unsafe_to_char()
  } else if idx < 52 {
    (97 + idx - 26).unsafe_to_char()
  } else if idx < 62 {
    (48 + idx - 52).unsafe_to_char()
  } else if idx == 62 {
    '+'
  } else {
    '/'
  }
}

///|
fn bytes_to_base64(data : Bytes) -> String {
  let buf = StringBuilder::new()
  let len = data.length()
  let mut i = 0
  while i + 2 < len {
    let b0 = data[i].to_int()
    let b1 = data[i + 1].to_int()
    let b2 = data[i + 2].to_int()
    buf.write_char(base64_encode_char((b0 >> 2) & 0x3F))
    buf.write_char(base64_encode_char(((b0 << 4) | (b1 >> 4)) & 0x3F))
    buf.write_char(base64_encode_char(((b1 << 2) | (b2 >> 6)) & 0x3F))
    buf.write_char(base64_encode_char(b2 & 0x3F))
    i = i + 3
  }
  let remaining = len - i
  if remaining == 1 {
    let b0 = data[i].to_int()
    buf.write_char(base64_encode_char((b0 >> 2) & 0x3F))
    buf.write_char(base64_encode_char((b0 << 4) & 0x3F))
    buf.write_char('=')
    buf.write_char('=')
  } else if remaining == 2 {
    let b0 = data[i].to_int()
    let b1 = data[i + 1].to_int()
    buf.write_char(base64_encode_char((b0 >> 2) & 0x3F))
    buf.write_char(base64_encode_char(((b0 << 4) | (b1 >> 4)) & 0x3F))
    buf.write_char(base64_encode_char((b1 << 2) & 0x3F))
    buf.write_char('=')
  }
  buf.to_string()
}

///|
fn write_js_template_literal(buf : StringBuilder, content : String) -> Unit {
  buf.write_char('`')
  for ch in content {
    match ch {
      '`' => buf.write_string("\\`")
      '\\' => buf.write_string("\\\\")
      '$' => buf.write_string("\\$")
      c => buf.write_char(c)
    }
  }
  buf.write_char('`')
}

///|
/// 生成 JavaScript ES Module 胶水文件内容。
/// 若有 grammar_dsl，嵌入 DSL 字符串以便通过 createParser() 直接使用；
/// 若有 table_base64，则嵌入 Base64 编码的二进制表供 createParserFromBytes() 加载。
fn generate_js_glue(grammar_dsl : String?, table_base64 : String?) -> String {
  let buf = StringBuilder::new()
  buf.write_string(
    (
      #|// Generated by moonparse wasm — do not edit manually.
      #|// Requires: moonparse  (https://www.npmjs.com/package/moonparse)
      #|//
      #|// Usage (Node.js / ESM):
      #|//   import { loadParser } from "./parser.js";
      #|//   const parser = await loadParser();
      #|//   const tree = parser.parse("your source code here");
      #|//
      #|async function _loadMoonParseInstance(moonparseModule) {
      #|  if (moonparseModule != null) return moonparseModule;
      #|  const { loadMoonParse } = await import("moonparse");
      #|  return loadMoonParse();
      #|}
      #|
    ),
  )
  match grammar_dsl {
    Some(dsl) => {
      buf.write_string("const _grammarDsl = ")
      write_js_template_literal(buf, dsl)
      buf.write_string(";\n\nexport const grammarDsl = _grammarDsl;\n\n")
      buf.write_string(
        (
          #|export async function loadParser(moonparseModule) {
          #|  const mp = await _loadMoonParseInstance(moonparseModule);
          #|  return mp.createParser(_grammarDsl);
          #|}
          #|
        ),
      )
    }
    None =>
      match table_base64 {
        Some(b64) => {
          buf.write_string("const _tableBase64 = \"")
          buf.write_string(b64)
          buf.write_string("\";\n\n")
          buf.write_string(
            (
              #|function _base64ToUint8Array(b64) {
              #|  if (typeof Buffer !== 'undefined') return new Uint8Array(Buffer.from(b64, 'base64'));
              #|  const bin = atob(b64);
              #|  const a = new Uint8Array(bin.length);
              #|  for (let i = 0; i < bin.length; i++) a[i] = bin.charCodeAt(i);
              #|  return a;
              #|}
              #|
              #|export async function loadParser(moonparseModule) {
              #|  const mp = await _loadMoonParseInstance(moonparseModule);
              #|  return mp.createParserFromBytes(_base64ToUint8Array(_tableBase64));
              #|}
              #|
              #|export const tableBytes = _base64ToUint8Array(_tableBase64);
              #|
            ),
          )
        }
        None => ()
      }
  }
  buf.to_string()
}
