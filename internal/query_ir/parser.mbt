///|
priv suberror QueryParseFailure {
  Syntax(Int, String)
  Unsupported(String)
  UnknownNodeName(String)
  UnknownFieldName(String)
  UnknownCaptureName(String)
}

///|
priv struct QueryParser {
  source : String
  schema : QuerySchema
  mut offset : Int
  mut captures : Array[String]
}

///|
fn QueryParser::new(source : String, schema : QuerySchema) -> QueryParser {
  { source, schema, offset: 0, captures: [] }
}

///|
fn QueryParser::at_end(self : QueryParser) -> Bool {
  self.offset >= self.source.length()
}

///|
fn QueryParser::current(self : QueryParser) -> UInt16 {
  if self.at_end() {
    0
  } else {
    self.source[self.offset]
  }
}

///|
fn ascii(c : Char) -> UInt16 {
  c.to_int().to_uint16()
}

///|
fn QueryParser::byte_offset(self : QueryParser) -> Int {
  let mut i = 0
  let mut result = 0
  while i < self.offset {
    let unit = self.source[i].to_int()
    if unit <= 0x7f {
      result += 1
      i += 1
    } else if unit <= 0x7ff {
      result += 2
      i += 1
    } else if unit >= 0xd800 &&
      unit <= 0xdbff &&
      i + 1 < self.offset &&
      self.source[i + 1].to_int() >= 0xdc00 &&
      self.source[i + 1].to_int() <= 0xdfff {
      result += 4
      i += 2
    } else {
      result += 3
      i += 1
    }
  }
  result
}

///|
fn QueryParser::advance(self : QueryParser) -> UInt16 {
  let c = self.current()
  self.offset += 1
  c
}

///|
fn QueryParser::skip_trivia(self : QueryParser) -> Unit {
  while !self.at_end() {
    let c = self.current()
    if c == ascii(' ') ||
      c == ascii('\t') ||
      c == ascii('\r') ||
      c == ascii('\n') {
      self.offset += 1
    } else if c == ascii(';') {
      while !self.at_end() && self.current() != ascii('\n') {
        self.offset += 1
      }
    } else {
      break
    }
  }
}

///|
fn QueryParser::expect(
  self : QueryParser,
  wanted : Char,
) -> Unit raise QueryParseFailure {
  if self.at_end() || self.current() != ascii(wanted) {
    raise Syntax(self.byte_offset(), "expected '\{wanted}'")
  }
  self.offset += 1
}

///|
fn is_ident_char(c : UInt16) -> Bool {
  (c >= ascii('a') && c <= ascii('z')) ||
  (c >= ascii('A') && c <= ascii('Z')) ||
  (c >= ascii('0') && c <= ascii('9')) ||
  c == ascii('_') ||
  c == ascii('-')
}

///|
fn is_capture_char(c : UInt16) -> Bool {
  is_ident_char(c) || c == ascii('.')
}

///|
fn QueryParser::read_ascii_name(
  self : QueryParser,
  capture? : Bool = false,
) -> String raise QueryParseFailure {
  let start = self.offset
  while !self.at_end() &&
        (if capture {
          is_capture_char(self.current())
        } else {
          is_ident_char(self.current())
        }) {
    self.offset += 1
  }
  if self.offset == start {
    raise Syntax(self.byte_offset(), "expected name")
  }
  self.source[start:self.offset].to_owned()
}

///|
fn QueryParser::read_string(
  self : QueryParser,
) -> String raise QueryParseFailure {
  self.expect('"')
  let out = StringBuilder::new()
  while !self.at_end() && self.current() != ascii('"') {
    let c = self.advance()
    if c == ascii('\\') {
      if self.at_end() {
        raise Syntax(self.byte_offset(), "unterminated escape")
      }
      match self.advance() {
        c if c == ascii('"') => out.write_char('"')
        c if c == ascii('\\') => out.write_char('\\')
        c if c == ascii('n') => out.write_char('\n')
        c if c == ascii('r') => out.write_char('\r')
        c if c == ascii('t') => out.write_char('\t')
        _ => raise Unsupported("string escape")
      }
    } else {
      let unit = c.to_int()
      if unit >= 0xd800 && unit <= 0xdbff {
        if self.at_end() {
          raise Syntax(self.byte_offset(), "unterminated UTF-16 surrogate")
        }
        let low = self.advance().to_int()
        if low < 0xdc00 || low > 0xdfff {
          raise Syntax(self.byte_offset(), "invalid UTF-16 surrogate")
        }
        let scalar = 0x10000 + ((unit - 0xd800) << 10) + (low - 0xdc00)
        out.write_char(scalar.unsafe_to_char())
      } else {
        out.write_char(unit.unsafe_to_char())
      }
    }
  }
  if self.at_end() {
    raise Syntax(self.byte_offset(), "unterminated string")
  }
  self.offset += 1
  out.to_string()
}

///|
fn QueryParser::declare_capture(
  self : QueryParser,
) -> Int raise QueryParseFailure {
  self.expect('@')
  let name = self.read_ascii_name(capture=true)
  let index = self.captures.length()
  self.captures.push(name)
  index
}

///|
fn QueryParser::try_field(
  self : QueryParser,
) -> (Int?, String?) raise QueryParseFailure {
  let saved = self.offset
  if self.at_end() || !is_ident_char(self.current()) {
    return (None, None)
  }
  let name = self.read_ascii_name()
  self.skip_trivia()
  if !self.at_end() && self.current() == ascii(':') {
    self.offset += 1
    match self.schema.field_id(name) {
      Some(id) => (Some(id), Some(name))
      None => raise UnknownFieldName(name)
    }
  } else {
    self.offset = saved
    (None, None)
  }
}

///|
fn QueryParser::parse_expr(
  self : QueryParser,
) -> QueryExpr raise QueryParseFailure {
  self.skip_trivia()
  if self.at_end() {
    raise Syntax(self.byte_offset(), "expected query pattern")
  }
  match self.current() {
    c if c == ascii('(') => self.parse_named()
    c if c == ascii('"') => {
      let token = self.read_string()
      if !self.schema.has_anonymous_token(token) {
        raise UnknownNodeName(token)
      }
      Anonymous(token)
    }
    c if c == ascii('_') => {
      self.offset += 1
      Wildcard
    }
    c if c == ascii('[') => self.parse_alternation()
    c if c == ascii('!') => raise Unsupported("negated fields")
    _ => raise Syntax(self.byte_offset(), "expected pattern")
  }
}

///|
fn QueryParser::parse_alternation(
  self : QueryParser,
) -> QueryExpr raise QueryParseFailure {
  self.expect('[')
  self.skip_trivia()
  let items : Array[QueryExpr] = []
  while !self.at_end() && self.current() != ascii(']') {
    items.push(self.parse_expr())
    self.skip_trivia()
  }
  if self.at_end() {
    raise Syntax(self.byte_offset(), "unterminated alternation")
  }
  self.offset += 1
  if items.is_empty() {
    raise Syntax(self.byte_offset(), "empty alternation")
  }
  Alternation(items)
}

///|
fn QueryParser::parse_named(
  self : QueryParser,
) -> QueryExpr raise QueryParseFailure {
  self.expect('(')
  self.skip_trivia()
  if self.current() == ascii('_') {
    self.offset += 1
    self.skip_trivia()
    self.expect(')')
    return Wildcard
  }
  let name = self.read_ascii_name()
  let node_id = match self.schema.node_id(name) {
    Some(id) => id
    None => raise UnknownNodeName(name)
  }
  let children : Array[QueryChild] = []
  let mut pending_anchor = false
  self.skip_trivia()
  while !self.at_end() && self.current() != ascii(')') {
    if self.current() == ascii('.') {
      if pending_anchor {
        raise Syntax(self.byte_offset(), "duplicate sibling anchor")
      }
      self.offset += 1
      pending_anchor = true
      self.skip_trivia()
      continue
    }
    let (field_id, field_name) = self.try_field()
    self.skip_trivia()
    let expr = self.parse_expr()
    self.skip_trivia()
    let quantifier = if !self.at_end() {
      match self.current() {
        c if c == ascii('?') => {
          self.offset += 1
          ZeroOrOne
        }
        c if c == ascii('*') => {
          self.offset += 1
          ZeroOrMore
        }
        c if c == ascii('+') => {
          self.offset += 1
          OneOrMore
        }
        _ => One
      }
    } else {
      One
    }
    self.skip_trivia()
    let capture_index = if !self.at_end() && self.current() == ascii('@') {
      Some(self.declare_capture())
    } else {
      None
    }
    children.push({
      field_id,
      field_name,
      expr,
      quantifier,
      capture_index,
      anchor_before: pending_anchor,
      anchor_after: false,
    })
    pending_anchor = false
    self.skip_trivia()
  }
  if pending_anchor {
    if children.is_empty() {
      raise Syntax(self.byte_offset(), "sibling anchor requires a child")
    }
    let last = children.pop().unwrap()
    children.push({ ..last, anchor_after: true })
  }
  self.expect(')')
  Named(node_id, name, children)
}

///|
fn QueryParser::capture_reference(
  self : QueryParser,
) -> String raise QueryParseFailure {
  self.expect('@')
  let name = self.read_ascii_name(capture=true)
  match find_name(self.captures, name) {
    Some(_) => name
    None => raise UnknownCaptureName(name)
  }
}

///|
fn QueryParser::parse_predicate(
  self : QueryParser,
) -> QueryPredicate raise QueryParseFailure {
  self.expect('#')
  let name = self.read_ascii_name()
  if self.at_end() || self.current() != ascii('?') {
    raise Unsupported("predicate #\{name}")
  }
  self.offset += 1
  self.skip_trivia()
  let capture = self.capture_reference()
  self.skip_trivia()
  match name {
    "eq" | "not-eq" | "match" | "not-match" => {
      let value = self.read_string()
      match name {
        "eq" => Eq(capture, value)
        "not-eq" => NotEq(capture, value)
        "match" => Match(capture, value)
        _ => NotMatch(capture, value)
      }
    }
    "any-of" => {
      let values : Array[String] = []
      while !self.at_end() && self.current() == ascii('"') {
        values.push(self.read_string())
        self.skip_trivia()
      }
      if values.is_empty() {
        raise Syntax(self.byte_offset(), "#any-of? requires a value")
      }
      AnyOf(capture, values)
    }
    _ => raise Unsupported("predicate #\{name}")
  }
}

///|
fn QueryParser::parse(
  self : QueryParser,
) -> Array[QueryPattern] raise QueryParseFailure {
  let patterns : Array[QueryPattern] = []
  self.skip_trivia()
  while !self.at_end() {
    if self.current() == ascii('#') {
      if patterns.is_empty() {
        raise Syntax(self.byte_offset(), "predicate must follow a pattern")
      }
      let predicate = self.parse_predicate()
      let previous = patterns.pop().unwrap()
      previous.predicates.push(predicate)
      patterns.push(previous)
    } else {
      self.captures = []
      let root = self.parse_expr()
      self.skip_trivia()
      let root_capture_index = if !self.at_end() && self.current() == ascii('@') {
        Some(self.declare_capture())
      } else {
        None
      }
      patterns.push({
        index: patterns.length(),
        root,
        root_capture_index,
        capture_names: self.captures.copy(),
        predicates: [],
      })
    }
    self.skip_trivia()
  }
  if patterns.is_empty() {
    raise Syntax(0, "query contains no patterns")
  }
  patterns
}

///|
pub fn compile_query(
  source : String,
  schema : QuerySchema,
) -> CompiledQueryIr raise QueryCompileError {
  try {
    let patterns = QueryParser::new(source, schema).parse()
    { bytecode: encode_query_bytecode(patterns), patterns }
  } catch {
    Syntax(offset, message) => raise ParseError(offset, message)
    Unsupported(feature) => raise UnsupportedFeature(feature)
    UnknownNodeName(name) => raise UnknownNode(name)
    UnknownFieldName(name) => raise UnknownField(name)
    UnknownCaptureName(name) => raise UnknownCapture(name)
  }
}
