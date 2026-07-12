///|
priv struct RegexParser {
  chars : Array[Char]
  byte_offsets : Array[Int]
  mut pos : Int
}

///|
fn RegexParser::new(source : String) -> RegexParser {
  let chars : Array[Char] = []
  let byte_offsets : Array[Int] = [0]
  let mut offset = 0
  for ch in source {
    chars.push(ch)
    offset += unicode_scalar_utf8_width(ch)
    byte_offsets.push(offset)
  }
  { chars, byte_offsets, pos: 0 }
}

///|
fn RegexParser::peek(self : RegexParser) -> Char? {
  self.chars.get(self.pos)
}

///|
fn RegexParser::peek_at(self : RegexParser, delta : Int) -> Char? {
  self.chars.get(self.pos + delta)
}

///|
fn RegexParser::take(self : RegexParser) -> Char? {
  match self.peek() {
    Some(ch) => {
      self.pos += 1
      Some(ch)
    }
    None => None
  }
}

///|
fn RegexParser::offset(self : RegexParser) -> Int {
  self.byte_offsets[self.pos]
}

///|
fn RegexParser::fail(
  self : RegexParser,
  reason : String,
) -> Unit raise RegexParseError {
  raise InvalidRegex(byte_offset=self.offset(), reason~)
}

///|
fn shorthand_class(ch : Char) -> RegexIr? {
  match ch {
    'd' => Some(CharClass([{ lo: '0', hi: '9' }], false))
    'D' => Some(CharClass([{ lo: '0', hi: '9' }], true))
    'w' =>
      Some(
        CharClass(
          [
            { lo: '0', hi: '9' },
            { lo: 'A', hi: 'Z' },
            { lo: '_', hi: '_' },
            { lo: 'a', hi: 'z' },
          ],
          false,
        ),
      )
    'W' =>
      Some(
        CharClass(
          [
            { lo: '0', hi: '9' },
            { lo: 'A', hi: 'Z' },
            { lo: '_', hi: '_' },
            { lo: 'a', hi: 'z' },
          ],
          true,
        ),
      )
    's' =>
      Some(
        CharClass(
          [
            { lo: '\t', hi: '\t' },
            { lo: '\n', hi: '\n' },
            { lo: '\r', hi: '\r' },
            { lo: ' ', hi: ' ' },
          ],
          false,
        ),
      )
    'S' =>
      Some(
        CharClass(
          [
            { lo: '\t', hi: '\t' },
            { lo: '\n', hi: '\n' },
            { lo: '\r', hi: '\r' },
            { lo: ' ', hi: ' ' },
          ],
          true,
        ),
      )
    _ => None
  }
}

///|
fn escaped_literal(ch : Char) -> Char {
  match ch {
    'n' => '\n'
    't' => '\t'
    'r' => '\r'
    'f' => '\f'
    'v' => (0x0b).unsafe_to_char()
    '0' => '\u{0}'
    _ => ch
  }
}

///|
fn RegexParser::parse_escape(
  self : RegexParser,
) -> RegexIr raise RegexParseError {
  match self.take() {
    None => {
      self.fail("dangling escape")
      Empty
    }
    Some(ch) =>
      match shorthand_class(ch) {
        Some(ir) => ir
        None => Literal(escaped_literal(ch))
      }
  }
}

///|
fn class_escape_ranges(
  parser : RegexParser,
  ch : Char,
) -> Array[CharRange] raise RegexParseError {
  match ch {
    'd' => [{ lo: '0', hi: '9' }]
    'w' =>
      [
        { lo: '0', hi: '9' },
        { lo: 'A', hi: 'Z' },
        { lo: '_', hi: '_' },
        { lo: 'a', hi: 'z' },
      ]
    's' =>
      [
        { lo: '\t', hi: '\t' },
        { lo: '\n', hi: '\n' },
        { lo: '\r', hi: '\r' },
        { lo: ' ', hi: ' ' },
      ]
    'D' | 'W' | 'S' => {
      parser.fail(
        "negated shorthand is not composable inside a character class",
      )
      []
    }
    _ => {
      let literal = escaped_literal(ch)
      [{ lo: literal, hi: literal }]
    }
  }
}

///|
fn RegexParser::parse_class_atom(
  self : RegexParser,
) -> Array[CharRange] raise RegexParseError {
  match self.take() {
    None => {
      self.fail("unterminated character class")
      []
    }
    Some('\\') =>
      match self.take() {
        Some(ch) => class_escape_ranges(self, ch)
        None => {
          self.fail("dangling escape in character class")
          []
        }
      }
    Some(ch) => [{ lo: ch, hi: ch }]
  }
}

///|
fn RegexParser::parse_class(
  self : RegexParser,
) -> RegexIr raise RegexParseError {
  let negated = match self.peek() {
    Some('^') => {
      ignore(self.take())
      true
    }
    _ => false
  }
  let ranges : Array[CharRange] = []
  let mut first = true
  while self.peek() != Some(']') || first {
    if self.peek() is None {
      self.fail("unterminated character class")
    }
    let atom = self.parse_class_atom()
    if atom.length() == 1 &&
      self.peek() == Some('-') &&
      self.peek_at(1) != Some(']') {
      ignore(self.take())
      let end = self.parse_class_atom()
      if end.length() != 1 {
        self.fail("character-class range endpoint must be one scalar")
      }
      let lo = atom[0].lo
      let hi = end[0].lo
      if lo > hi {
        self.fail("descending character-class range")
      }
      ranges.push({ lo, hi })
    } else {
      for range in atom {
        ranges.push(range)
      }
    }
    first = false
  }
  ignore(self.take())
  if ranges.length() == 0 {
    self.fail("empty character class")
  }
  CharClass(canonical_ranges(ranges), negated)
}

///|
fn RegexParser::parse_atom(self : RegexParser) -> RegexIr raise RegexParseError {
  match self.take() {
    Some('(') => {
      let result = self.parse_alternate()
      match self.take() {
        Some(')') => result
        _ => {
          self.fail("unterminated group")
          Empty
        }
      }
    }
    Some('[') => self.parse_class()
    Some('.') => AnyScalar
    Some('\\') => self.parse_escape()
    Some(')') => {
      self.fail("unmatched closing parenthesis")
      Empty
    }
    Some('*' | '+' | '?') => {
      self.fail("quantifier has no preceding atom")
      Empty
    }
    Some('|') | None => {
      self.fail("expected regular-expression atom")
      Empty
    }
    Some(ch) => Literal(ch)
  }
}

///|
fn RegexParser::parse_repeat(
  self : RegexParser,
) -> RegexIr raise RegexParseError {
  let atom = self.parse_atom()
  let result = match self.peek() {
    Some('*') => {
      ignore(self.take())
      Repeat(atom, ZeroOrMore)
    }
    Some('+') => {
      ignore(self.take())
      Repeat(atom, OneOrMore)
    }
    Some('?') => {
      ignore(self.take())
      Repeat(atom, ZeroOrOne)
    }
    _ => atom
  }
  match self.peek() {
    Some('*' | '+' | '?') => {
      self.fail("stacked quantifiers are not supported")
      result
    }
    _ => result
  }
}

///|
fn RegexParser::parse_concat(
  self : RegexParser,
) -> RegexIr raise RegexParseError {
  let parts : Array[RegexIr] = []
  while self.peek() is Some(ch) && ch != '|' && ch != ')' {
    parts.push(self.parse_repeat())
  }
  make_concat(parts)
}

///|
fn RegexParser::parse_alternate(
  self : RegexParser,
) -> RegexIr raise RegexParseError {
  let branches : Array[RegexIr] = [self.parse_concat()]
  while self.peek() == Some('|') {
    ignore(self.take())
    branches.push(self.parse_concat())
  }
  make_alternate(branches)
}

///|
/// Parse the portable v1 regex subset into normalized IR.
pub fn parse(source : String) -> RegexIr raise RegexParseError {
  if source is "" {
    Empty
  } else {
    let parser = RegexParser::new(source)
    let result = parser.parse_alternate()
    if parser.peek() is Some(_) {
      parser.fail("unexpected trailing input")
    }
    result
  }
}
