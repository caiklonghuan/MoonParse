///|
priv enum DslToken {
  Name(String)
  Text(String)
  RegexText(String)
  Number(Int)
  Punct(Char)
  Newline
  End
} derive(Eq)

///|
priv struct SpannedToken {
  token : DslToken
  start_byte : Int
}

///|
priv struct DslLexer {
  chars : Array[Char]
  offsets : Array[Int]
  mut pos : Int
}

///|
fn scalar_width(ch : Char) -> Int {
  let value = ch.to_int()
  if value <= 0x7f {
    1
  } else if value <= 0x7ff {
    2
  } else if value <= 0xffff {
    3
  } else {
    4
  }
}

///|
fn DslLexer::new(source : String) -> DslLexer {
  let chars : Array[Char] = []
  let offsets : Array[Int] = [0]
  let mut offset = 0
  for ch in source {
    chars.push(ch)
    offset += scalar_width(ch)
    offsets.push(offset)
  }
  { chars, offsets, pos: 0 }
}

///|
fn DslLexer::peek(self : DslLexer, delta? : Int = 0) -> Char? {
  self.chars.get(self.pos + delta)
}

///|
fn DslLexer::take(self : DslLexer) -> Char? {
  match self.peek() {
    Some(ch) => {
      self.pos += 1
      Some(ch)
    }
    None => None
  }
}

///|
fn DslLexer::offset(self : DslLexer) -> Int {
  self.offsets[self.pos]
}

///|
fn lex_fail(
  byte_offset : Int,
  code : String,
  reason : String,
) -> Unit raise GrammarParseError {
  raise InvalidGrammar(byte_offset~, code~, reason~)
}

///|
fn is_punctuation(ch : Char) -> Bool {
  match ch {
    ':'
    | '|'
    | '*'
    | '+'
    | '?'
    | '('
    | ')'
    | ','
    | '['
    | ']'
    | '{'
    | '}'
    | '.'
    | '@'
    | '!'
    | '&'
    | ';'
    | '-' => true
    _ => false
  }
}

///|
fn decoded_escape(ch : Char) -> Char {
  match ch {
    'n' => '\n'
    'r' => '\r'
    't' => '\t'
    'f' => '\f'
    '0' => '\u{0}'
    _ => ch
  }
}

///|
fn DslLexer::lex_string(
  self : DslLexer,
  start : Int,
) -> SpannedToken raise GrammarParseError {
  ignore(self.take())
  let mut value = ""
  while self.peek() != Some('"') {
    match self.take() {
      None => lex_fail(start, "G001", "unterminated string literal")
      Some('\n' | '\r') =>
        lex_fail(self.offset(), "G001", "newline in string literal")
      Some('\\') =>
        match self.take() {
          Some(ch) => value = value + decoded_escape(ch).to_string()
          None => lex_fail(self.offset(), "G001", "dangling string escape")
        }
      Some(ch) => value = value + ch.to_string()
    }
  }
  ignore(self.take())
  { token: Text(value), start_byte: start }
}

///|
fn DslLexer::lex_regex(
  self : DslLexer,
  start : Int,
) -> SpannedToken raise GrammarParseError {
  ignore(self.take())
  let mut value = ""
  while self.peek() != Some('/') {
    match self.take() {
      None => lex_fail(start, "G002", "unterminated regex literal")
      Some('\n' | '\r') =>
        lex_fail(self.offset(), "G002", "newline in regex literal")
      Some('\\') =>
        match self.take() {
          Some(ch) => value = value + "\\" + ch.to_string()
          None => lex_fail(self.offset(), "G002", "dangling regex escape")
        }
      Some(ch) => value = value + ch.to_string()
    }
  }
  ignore(self.take())
  { token: RegexText(value), start_byte: start }
}

///|
fn DslLexer::skip_block_comment(
  self : DslLexer,
  start : Int,
) -> Unit raise GrammarParseError {
  ignore(self.take())
  ignore(self.take())
  while self.peek() != Some('*') || self.peek(delta=1) != Some('/') {
    if self.take() is None {
      lex_fail(start, "G003", "unterminated block comment")
    }
  }
  ignore(self.take())
  ignore(self.take())
}

///|
fn is_name_delimiter(ch : Char) -> Bool {
  ch == ' ' ||
  ch == '\t' ||
  ch == '\r' ||
  ch == '\n' ||
  ch == '"' ||
  ch == '/' ||
  is_punctuation(ch)
}

///|
fn decimal_value(text : String) -> Int? {
  if text is "" {
    return None
  }
  let mut value = 0
  for ch in text {
    if ch < '0' || ch > '9' {
      return None
    }
    let digit = ch.to_int() - '0'.to_int()
    if value > (0x7fffffff - digit) / 10 {
      return None
    }
    value = value * 10 + digit
  }
  Some(value)
}

///|
fn lex_dsl(source : String) -> Array[SpannedToken] raise GrammarParseError {
  let lexer = DslLexer::new(source)
  let tokens : Array[SpannedToken] = []
  while lexer.peek() is Some(ch) {
    let start = lexer.offset()
    match ch {
      ' ' | '\t' => ignore(lexer.take())
      '\r' => {
        ignore(lexer.take())
        if lexer.peek() == Some('\n') {
          ignore(lexer.take())
        }
        tokens.push({ token: Newline, start_byte: start })
      }
      '\n' => {
        ignore(lexer.take())
        tokens.push({ token: Newline, start_byte: start })
      }
      '"' => tokens.push(lexer.lex_string(start))
      '/' =>
        if lexer.peek(delta=1) == Some('/') {
          while lexer.peek() is Some(c) && c != '\n' {
            ignore(lexer.take())
          }
        } else if lexer.peek(delta=1) == Some('*') {
          lexer.skip_block_comment(start)
        } else {
          tokens.push(lexer.lex_regex(start))
        }
      _ =>
        if is_punctuation(ch) {
          ignore(lexer.take())
          tokens.push({ token: Punct(ch), start_byte: start })
        } else {
          let mut word = ""
          while lexer.peek() is Some(c) && !is_name_delimiter(c) {
            ignore(lexer.take())
            word = word + c.to_string()
          }
          if word is "" {
            lex_fail(start, "G004", "invalid grammar character")
          }
          let token = match decimal_value(word) {
            Some(value) => Number(value)
            None => Name(word)
          }
          tokens.push({ token, start_byte: start })
        }
    }
  }
  let end = lexer.offset()
  tokens.push({ token: End, start_byte: end })
  tokens
}
