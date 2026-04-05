///|
// Query 模式编译器
// 公开 API：
//   compile(src) -> Result[CompiledQuery, QueryError]
//
// 支持的 S-表达式语法：
//   query        = ws top_item*
//   top_item     = pattern | predicate
//   pattern      = node_pattern | anon_pattern | wildcard
//   node_pattern = '(' ident child* ')'
//   anon_pattern = '"' chars '"'
//   wildcard     = '_'
//   child        = [ident ':'] pattern ['@' capture_name]
//   predicate    = '#eq?' '@' capture_name '"' literal '"'
//
// 行注释以 ';' 开头

///|
/// 内部解析错误（仅在 compile 内部传播）
priv suberror ParseErr {
  PE(Int, String)
}

///|
/// 手写递归下降 parser（包内私有）
priv struct Parser {
  src : String
  mut pos : Int
}

///|
fn Parser::new(src : String) -> Parser {
  { src, pos: 0 }
}

///|
fn Parser::at_end(self : Parser) -> Bool {
  self.pos >= self.src.length()
}

///|
fn Parser::cur(self : Parser) -> Char {
  if self.at_end() {
    '\u{00}'
  } else {
    self.src[self.pos].to_int().unsafe_to_char()
  }
}

///|
fn Parser::advance(self : Parser) -> Char {
  let c = self.cur()
  self.pos = self.pos + 1
  c
}

///|
/// 跳过空白和行注释（`;` 到行尾）
fn Parser::skip_ws(self : Parser) -> Unit {
  while not(self.at_end()) {
    let c = self.cur()
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      self.pos = self.pos + 1
    } else if c == ';' {
      while not(self.at_end()) && self.cur() != '\n' {
        self.pos = self.pos + 1
      }
    } else {
      break
    }
  }
}

///|
fn Parser::expect(self : Parser, c : Char) -> Unit raise ParseErr {
  if self.at_end() || self.cur() != c {
    raise PE(self.pos, "expected '\{c}' but got '\{self.cur()}'")
  }
  self.pos = self.pos + 1
}

///|
/// 标识符字符：字母、数字、`_`、`-`（Tree-Sitter 节点类型名常用 `-`）
fn is_ident_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c == '-'
}

///|
/// 捕获名字符：在标识符基础上还允许 `.`（如 `func.name`）
fn is_capture_char(c : Char) -> Bool {
  is_ident_char(c) || c == '.'
}

///|
/// 谓词名字符：在标识符基础上还允许 `?`（如 `eq?`）
fn is_pred_char(c : Char) -> Bool {
  is_ident_char(c) || c == '?'
}

///|
fn Parser::read_ident(self : Parser) -> String raise ParseErr {
  if self.at_end() || not(is_ident_char(self.cur())) {
    raise PE(self.pos, "expected identifier, got '\{self.cur()}'")
  }
  let buf = StringBuilder::new()
  while not(self.at_end()) && is_ident_char(self.cur()) {
    buf.write_char(self.advance())
  }
  buf.to_string()
}

///|
fn Parser::read_capture_name(self : Parser) -> String raise ParseErr {
  if self.at_end() || not(is_capture_char(self.cur())) {
    raise PE(self.pos, "expected capture name, got '\{self.cur()}'")
  }
  let buf = StringBuilder::new()
  while not(self.at_end()) && is_capture_char(self.cur()) {
    buf.write_char(self.advance())
  }
  buf.to_string()
}

///|
/// 读取双引号字符串（含简单转义：`\\`、`\"`、`\n`、`\t`）
fn Parser::read_string(self : Parser) -> String raise ParseErr {
  self.expect('"')
  let buf = StringBuilder::new()
  while not(self.at_end()) && self.cur() != '"' {
    let c = self.advance()
    if c == '\\' {
      if self.at_end() {
        raise PE(self.pos, "unterminated escape sequence")
      }
      let esc = self.advance()
      match esc {
        '"' => buf.write_char('"')
        '\\' => buf.write_char('\\')
        'n' => buf.write_char('\n')
        't' => buf.write_char('\t')
        _ => {
          buf.write_char('\\')
          buf.write_char(esc)
        }
      }
    } else {
      buf.write_char(c)
    }
  }
  if self.at_end() {
    raise PE(self.pos, "unterminated string literal")
  }
  self.expect('"')
  buf.to_string()
}

///|
/// 尝试读取 `ident:` 字段约束前缀。
/// 成功返回 Some(field_name)，无字段时恢复 pos 并返回 None。
fn Parser::try_parse_field(self : Parser) -> String? raise ParseErr {
  let save = self.pos
  // _ 后面不跟 : 时是通配符 pattern，这里先尝试
  if self.at_end() || not(is_ident_char(self.cur())) {
    return None
  }
  let ident = self.read_ident()
  self.skip_ws()
  if not(self.at_end()) && self.cur() == ':' {
    self.pos = self.pos + 1
    return Some(ident)
  }
  // 回退：不是字段约束
  self.pos = save
  None
}

///|
/// 解析单个模式（node_pattern | anon_pattern | wildcard）
fn Parser::parse_pattern(self : Parser) -> QueryPattern raise ParseErr {
  self.skip_ws()
  match self.cur() {
    '(' => self.parse_node_pattern()
    '"' => AnonPattern(self.read_string())
    '_' => {
      self.pos = self.pos + 1
      Wildcard
    }
    c => raise PE(self.pos, "expected pattern ('(', '\"', or '_'), got '\{c}'")
  }
}

///|
/// 解析 `( ident child* )`
fn Parser::parse_node_pattern(self : Parser) -> QueryPattern raise ParseErr {
  self.expect('(')
  self.skip_ws()
  let type_name = self.read_ident()
  let children : Array[PatternChild] = []
  self.skip_ws()
  while not(self.at_end()) && self.cur() != ')' {
    children.push(self.parse_child())
    self.skip_ws()
  }
  self.expect(')')
  NodePattern(type_name, children)
}

///|
/// 解析子节点：`[field ':'] pattern ['@' capture_name]`
fn Parser::parse_child(self : Parser) -> PatternChild raise ParseErr {
  self.skip_ws()
  let field = self.try_parse_field()
  self.skip_ws()
  let pattern = self.parse_pattern()
  self.skip_ws()
  let capture : String? = if not(self.at_end()) && self.cur() == '@' {
    self.pos = self.pos + 1
    Some(self.read_capture_name())
  } else {
    None
  }
  { field, pattern, capture }
}

///|
/// 解析谓词：`#eq? '@' capture_name '"' literal '"'`
/// pattern_index 为谓词关联的顶层模式编号（最近一条模式）
fn Parser::parse_predicate(
  self : Parser,
  pattern_index : Int,
) -> (Int, Predicate) raise ParseErr {
  self.expect('#')
  let buf = StringBuilder::new()
  while not(self.at_end()) && is_pred_char(self.cur()) {
    buf.write_char(self.advance())
  }
  let pred_name = buf.to_string()
  self.skip_ws()
  match pred_name {
    "eq?" => {
      self.expect('@')
      let capture_name = self.read_capture_name()
      self.skip_ws()
      let literal = self.read_string()
      (pattern_index, Eq(capture_name, literal))
    }
    _ => raise PE(self.pos, "unknown predicate '#\{pred_name}'")
  }
}

///|
/// 将 S-表达式查询字符串编译为 `CompiledQuery`。
///
/// 一个查询字符串可包含多条顶层模式，每条独立匹配。
/// 谓词（`#eq?` 等）关联到它**之前**最近一条顶层模式。
///
/// ```moonbit nocheck
/// compile("(identifier) @name") // → Ok(...)
/// compile("(bad")               // → Err(ParseError(5, "expected ')'..."))
/// ```
pub fn compile(src : String) -> Result[CompiledQuery, QueryError] {
  let p = Parser::new(src)
  let patterns : Array[(QueryPattern, String?)] = []
  let predicates : Array[(Int, Predicate)] = []
  try {
    p.skip_ws()
    while not(p.at_end()) {
      match p.cur() {
        '(' | '"' | '_' => {
          let pat = p.parse_pattern()
          // 可选顶层捕获标注：pattern @capture_name
          p.skip_ws()
          let top_capture : String? = if not(p.at_end()) && p.cur() == '@' {
            p.pos = p.pos + 1
            Some(p.read_capture_name())
          } else {
            None
          }
          patterns.push((pat, top_capture))
        }
        '#' => {
          if patterns.is_empty() {
            raise PE(p.pos, "predicate must follow a pattern")
          }
          let pred = p.parse_predicate(patterns.length() - 1)
          predicates.push(pred)
        }
        c => raise PE(p.pos, "unexpected character '\{c}'")
      }
      p.skip_ws()
    }
    Ok({ patterns, predicates })
  } catch {
    PE(offset, msg) => Err(ParseError(offset, msg))
  }
}
