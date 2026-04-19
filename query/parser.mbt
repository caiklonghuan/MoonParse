///|
// Query 模式编译器
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
  while !self.at_end() {
    let c = self.cur()
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      self.pos = self.pos + 1
    } else if c == ';' {
      while !self.at_end() && self.cur() != '\n' {
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
  if self.at_end() || !is_ident_char(self.cur()) {
    raise PE(self.pos, "expected identifier, got '\{self.cur()}'")
  }
  let buf = StringBuilder::new()
  while !self.at_end() && is_ident_char(self.cur()) {
    buf.write_char(self.advance())
  }
  buf.to_string()
}

///|
fn Parser::read_capture_name(self : Parser) -> String raise ParseErr {
  if self.at_end() || !is_capture_char(self.cur()) {
    raise PE(self.pos, "expected capture name, got '\{self.cur()}'")
  }
  let buf = StringBuilder::new()
  while !self.at_end() && is_capture_char(self.cur()) {
    buf.write_char(self.advance())
  }
  buf.to_string()
}

///|
/// 读取双引号字符串（含简单转义：`\\`、`\"`、`\n`、`\t`）
fn Parser::read_string(self : Parser) -> String raise ParseErr {
  self.expect('"')
  let buf = StringBuilder::new()
  while !self.at_end() && self.cur() != '"' {
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
  if self.at_end() || !is_ident_char(self.cur()) {
    return None
  }
  let ident = self.read_ident()
  self.skip_ws()
  if !self.at_end() && self.cur() == ':' {
    self.pos = self.pos + 1
    return Some(ident)
  }
  // 回退：不是字段约束
  self.pos = save
  None
}

///|
/// 解析单个模式（node_pattern | anon_pattern | wildcard | alternation）
fn Parser::parse_pattern(self : Parser) -> QueryPattern raise ParseErr {
  self.skip_ws()
  match self.cur() {
    '(' => self.parse_node_pattern()
    '"' => AnonPattern(self.read_string())
    '_' => {
      self.pos = self.pos + 1
      Wildcard
    }
    '[' => self.parse_alternation()
    c =>
      raise PE(
        self.pos,
        "expected pattern ('(', '\"', '_', or '['), got '\{c}'",
      )
  }
}

///|
/// 解析交替模式：`[ pattern+ ]`
fn Parser::parse_alternation(self : Parser) -> QueryPattern raise ParseErr {
  self.expect('[')
  self.skip_ws()
  let alternatives : Array[QueryPattern] = []
  while !self.at_end() && self.cur() != ']' {
    alternatives.push(self.parse_pattern())
    self.skip_ws()
  }
  if self.at_end() {
    raise PE(self.pos, "unterminated alternation '['")
  }
  self.expect(']')
  if alternatives.is_empty() {
    raise PE(self.pos - 1, "empty alternation '[]'")
  }
  Alternation(alternatives)
}

///|
/// 解析 `( ident ('.' | child)* '.'? ')'`
/// 支持 `.` 锚点标记：
///   - `(node . child)` — child 前的 `.` 设置 `anchor_before`
///   - `(node child .)` — child 后的 `.` 设置 `anchor_after`
fn Parser::parse_node_pattern(self : Parser) -> QueryPattern raise ParseErr {
  self.expect('(')
  self.skip_ws()
  let type_name = self.read_ident()
  let children : Array[PatternChild] = []
  let mut pending_anchor = false
  self.skip_ws()
  while !self.at_end() && self.cur() != ')' {
    if self.cur() == '.' {
      self.pos = self.pos + 1
      pending_anchor = true
      self.skip_ws()
      continue
    }
    let child = self.parse_child(pending_anchor)
    children.push(child)
    pending_anchor = false
    self.skip_ws()
  }
  // 尾锚点：循环结束时 pending_anchor 仍为 true，说明最后是尾锚点
  if pending_anchor && !children.is_empty() {
    let last = children.pop().unwrap()
    children.push({
      field: last.field,
      pattern: last.pattern,
      capture: last.capture,
      quantifier: last.quantifier,
      anchor_before: last.anchor_before,
      anchor_after: true,
    })
  }
  self.expect(')')
  NodePattern(type_name, children)
}

///|
/// 解析子节点：`[field ':'] pattern ['*'|'+'|'?'] ['@' capture_name]`
fn Parser::parse_child(
  self : Parser,
  anchor_before : Bool,
) -> PatternChild raise ParseErr {
  self.skip_ws()
  let field = self.try_parse_field()
  self.skip_ws()
  let pattern = self.parse_pattern()
  self.skip_ws()
  // 量词（可选，紧跟在模式之后）
  let quantifier : Quantifier = if !self.at_end() {
    match self.cur() {
      '*' => {
        self.pos = self.pos + 1
        ZeroOrMore
      }
      '+' => {
        self.pos = self.pos + 1
        OneOrMore
      }
      '?' => {
        self.pos = self.pos + 1
        ZeroOrOne
      }
      _ => One
    }
  } else {
    One
  }
  self.skip_ws()
  let capture : String? = if !self.at_end() && self.cur() == '@' {
    self.pos = self.pos + 1
    Some(self.read_capture_name())
  } else {
    None
  }
  { field, pattern, capture, quantifier, anchor_before, anchor_after: false }
}

///|
/// 解析谓词：`#eq? '@' capture_name '"' literal '"'`
fn Parser::parse_predicate(self : Parser) -> Predicate raise ParseErr {
  self.expect('#')
  let buf = StringBuilder::new()
  while !self.at_end() && is_pred_char(self.cur()) {
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
      Eq(capture_name, literal)
    }
    "match?" => {
      self.expect('@')
      let capture_name = self.read_capture_name()
      self.skip_ws()
      let pattern_str = self.read_string()
      Match(capture_name, pattern_str)
    }
    "not-eq?" => {
      self.expect('@')
      let capture_name = self.read_capture_name()
      self.skip_ws()
      let literal = self.read_string()
      NotEq(capture_name, literal)
    }
    "not-match?" => {
      self.expect('@')
      let capture_name = self.read_capture_name()
      self.skip_ws()
      let pattern_str = self.read_string()
      NotMatch(capture_name, pattern_str)
    }
    "any-of?" => {
      self.expect('@')
      let capture_name = self.read_capture_name()
      self.skip_ws()
      let values : Array[String] = []
      while !self.at_end() && self.cur() == '"' {
        values.push(self.read_string())
        self.skip_ws()
      }
      if values.is_empty() {
        raise PE(self.pos, "#any-of? requires at least one string value")
      }
      AnyOf(capture_name, values)
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
  let predicates : Array[Array[Predicate]] = []
  try {
    p.skip_ws()
    while !p.at_end() {
      match p.cur() {
        '(' | '"' | '_' | '[' => {
          let pat = p.parse_pattern()
          // 可选顶层捕获标注：pattern @capture_name
          p.skip_ws()
          let top_capture : String? = if !p.at_end() && p.cur() == '@' {
            p.pos = p.pos + 1
            Some(p.read_capture_name())
          } else {
            None
          }
          patterns.push((pat, top_capture))
          predicates.push([]) // 为该模式初始化空谓词列表
        }
        '#' => {
          if patterns.is_empty() {
            raise PE(p.pos, "predicate must follow a pattern")
          }
          let pred = p.parse_predicate()
          predicates[patterns.length() - 1].push(pred)
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
