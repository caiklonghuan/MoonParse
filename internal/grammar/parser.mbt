///|
priv struct GrammarParser {
  tokens : Array[SpannedToken]
  mut pos : Int
}

///|
fn GrammarParser::new(source : String) -> GrammarParser raise GrammarParseError {
  { tokens: lex_dsl(source), pos: 0 }
}

///|
fn GrammarParser::current(self : GrammarParser) -> SpannedToken {
  self.tokens[self.pos]
}

///|
fn GrammarParser::peek(self : GrammarParser, delta? : Int = 0) -> DslToken {
  self.tokens[self.pos + delta].token
}

///|
fn GrammarParser::advance(self : GrammarParser) -> Unit {
  if self.pos + 1 < self.tokens.length() {
    self.pos += 1
  }
}

///|
fn GrammarParser::fail(
  self : GrammarParser,
  code : String,
  reason : String,
) -> Unit raise GrammarParseError {
  raise InvalidGrammar(byte_offset=self.current().start_byte, code~, reason~)
}

///|
fn GrammarParser::skip_separators(self : GrammarParser) -> Unit {
  while self.peek() is (Newline | Punct(';')) {
    self.advance()
  }
}

///|
fn GrammarParser::expect_name(
  self : GrammarParser,
  context : String,
) -> String raise GrammarParseError {
  match self.peek() {
    Name(name) => {
      self.advance()
      name
    }
    _ => {
      self.fail("G010", "expected name \{context}")
      ""
    }
  }
}

///|
fn GrammarParser::expect_punct(
  self : GrammarParser,
  expected : Char,
) -> Unit raise GrammarParseError {
  if self.peek() == Punct(expected) {
    self.advance()
  } else {
    self.fail("G011", "expected '\{expected}'")
  }
}

///|
fn GrammarParser::signed_integer(
  self : GrammarParser,
) -> Int raise GrammarParseError {
  let sign = if self.peek() == Punct('-') {
    self.advance()
    -1
  } else {
    1
  }
  match self.peek() {
    Number(value) => {
      self.advance()
      sign * value
    }
    _ => {
      self.fail("G012", "expected integer")
      0
    }
  }
}

///|
fn GrammarParser::at_pattern_end(self : GrammarParser) -> Bool {
  match self.peek() {
    End | Newline | Punct(';') | Punct(')') | Punct(']') | Punct(',') => true
    _ => false
  }
}

///|
fn GrammarParser::starts_primary(self : GrammarParser) -> Bool {
  match self.peek() {
    Name(_)
    | Text(_)
    | RegexText(_)
    | Punct('(')
    | Punct('.')
    | Punct('@')
    | Punct('!')
    | Punct('&') => true
    _ => false
  }
}

///|
fn parse_regex_pattern(
  source : String,
  token_start : Int,
) -> GrammarPattern raise GrammarParseError {
  try @regex.parse(source) catch {
    InvalidRegex(byte_offset~, reason~) =>
      raise InvalidGrammar(
        byte_offset=token_start + 1 + byte_offset,
        code="G020",
        reason="invalid regex: \{reason}",
      )
  } noraise {
    ir => Regex(source, ir)
  }
}

///|
fn GrammarParser::parse_function(
  self : GrammarParser,
  name : String,
) -> GrammarPattern raise GrammarParseError {
  let mut function_name = name
  if self.peek() == Punct('.') {
    self.advance()
    function_name = function_name + "." + self.expect_name("after '.'")
  }
  self.expect_punct('(')
  match function_name {
    "prec" | "prec.left" | "prec.right" | "prec.dynamic" => {
      let level = self.signed_integer()
      self.expect_punct(',')
      let inner = self.parse_choice()
      self.expect_punct(')')
      let associativity = match function_name {
        "prec.left" => Left
        "prec.right" => Right
        "prec.dynamic" => Dynamic
        _ => None
      }
      Precedence(level, associativity, inner)
    }
    "lex.prec" => {
      let level = self.signed_integer()
      self.expect_punct(',')
      let inner = self.parse_choice()
      self.expect_punct(')')
      LexicalPrecedence(level, inner)
    }
    "alias" | "alias.anonymous" => {
      let alias_name = match self.peek() {
        Text(value) => {
          self.advance()
          value
        }
        _ => {
          self.fail("G021", "alias name must be a string")
          ""
        }
      }
      self.expect_punct(',')
      let inner = self.parse_choice()
      self.expect_punct(')')
      Alias(alias_name, function_name == "alias", inner)
    }
    "reserved" => {
      let set_name = match self.peek() {
        Text(value) | Name(value) => {
          self.advance()
          value
        }
        _ => {
          self.fail("G022", "reserved set name must be a name or string")
          ""
        }
      }
      self.expect_punct(',')
      let inner = self.parse_choice()
      self.expect_punct(')')
      Reserved(set_name, inner)
    }
    _ => {
      self.fail("G023", "unknown pattern function '\{function_name}'")
      Ref(function_name)
    }
  }
}

///|
fn GrammarParser::parse_primary(
  self : GrammarParser,
) -> GrammarPattern raise GrammarParseError {
  let token = self.current()
  match token.token {
    Name(name) => {
      self.advance()
      if (
          name == "prec" ||
          name == "alias" ||
          name == "lex" ||
          name == "reserved"
        ) &&
        (self.peek() == Punct('(') || self.peek() == Punct('.')) {
        self.parse_function(name)
      } else if self.peek() == Punct(':') {
        self.advance()
        Field(name, self.parse_primary())
      } else {
        Ref(name)
      }
    }
    Text(value) => {
      self.advance()
      Literal(value)
    }
    RegexText(source) => {
      self.advance()
      parse_regex_pattern(source, token.start_byte)
    }
    Punct('.') => {
      self.advance()
      AnyScalar
    }
    Punct('(') => {
      self.advance()
      let inner = self.parse_choice()
      self.expect_punct(')')
      inner
    }
    Punct('@') => {
      self.advance()
      let label = self.expect_name("after '@'")
      Tagged(label, self.parse_primary())
    }
    Punct('!') => {
      self.advance()
      Lookahead(self.parse_primary(), false)
    }
    Punct('&') => {
      self.advance()
      Lookahead(self.parse_primary(), true)
    }
    _ => {
      self.fail("G024", "expected grammar pattern")
      Ref("")
    }
  }
}

///|
fn GrammarParser::parse_postfix(
  self : GrammarParser,
) -> GrammarPattern raise GrammarParseError {
  let atom = self.parse_primary()
  match self.peek() {
    Punct('*') => {
      self.advance()
      ZeroOrMore(atom)
    }
    Punct('+') => {
      self.advance()
      OneOrMore(atom)
    }
    Punct('?') => {
      self.advance()
      Optional(atom)
    }
    Punct('{') => {
      self.advance()
      let minimum = self.signed_integer()
      if minimum < 0 {
        self.fail("G025", "repeat minimum cannot be negative")
      }
      let maximum = if self.peek() == Punct(',') {
        self.advance()
        self.signed_integer()
      } else {
        minimum
      }
      self.expect_punct('}')
      if maximum < minimum {
        self.fail("G025", "repeat maximum is smaller than minimum")
      }
      RepeatRange(atom, minimum, maximum)
    }
    _ => atom
  }
}

///|
fn GrammarParser::parse_sequence(
  self : GrammarParser,
) -> GrammarPattern raise GrammarParseError {
  let parts : Array[GrammarPattern] = []
  while !self.at_pattern_end() &&
        self.peek() != Punct('|') &&
        self.starts_primary() {
    parts.push(self.parse_postfix())
  }
  match parts {
    [] => {
      self.fail("G026", "expected non-empty pattern")
      Sequence([])
    }
    [only] => only
    _ => Sequence(parts)
  }
}

///|
fn GrammarParser::parse_choice(
  self : GrammarParser,
) -> GrammarPattern raise GrammarParseError {
  let branches : Array[GrammarPattern] = [self.parse_sequence()]
  while self.peek() == Punct('|') {
    self.advance()
    branches.push(self.parse_sequence())
  }
  match branches {
    [only] => only
    _ => Choice(branches)
  }
}

///|
fn GrammarParser::parse_name_list(
  self : GrammarParser,
) -> Array[String] raise GrammarParseError {
  self.expect_punct('[')
  let values : Array[String] = []
  while self.peek() != Punct(']') {
    self.skip_separators()
    if self.peek() == Punct(']') {
      break
    }
    values.push(self.expect_name("in list"))
    if self.peek() == Punct(',') {
      self.advance()
    } else if self.peek() != Punct(']') {
      self.fail("G030", "expected ',' or ']' in name list")
    }
  }
  self.expect_punct(']')
  values
}

///|
fn GrammarParser::parse_text_list(
  self : GrammarParser,
) -> Array[String] raise GrammarParseError {
  self.expect_punct('[')
  let values : Array[String] = []
  while self.peek() != Punct(']') {
    self.skip_separators()
    if self.peek() == Punct(']') {
      break
    }
    match self.peek() {
      Text(value) => {
        self.advance()
        values.push(value)
      }
      _ => self.fail("G031", "expected string in reserved set")
    }
    if self.peek() == Punct(',') {
      self.advance()
    } else if self.peek() != Punct(']') {
      self.fail("G031", "expected ',' or ']' in string list")
    }
  }
  self.expect_punct(']')
  values
}

///|
fn GrammarParser::parse_extras(
  self : GrammarParser,
) -> Array[GrammarPattern] raise GrammarParseError {
  self.expect_punct('[')
  let values : Array[GrammarPattern] = []
  while self.peek() != Punct(']') {
    self.skip_separators()
    if self.peek() == Punct(']') {
      break
    }
    values.push(self.parse_choice())
    if self.peek() == Punct(',') {
      self.advance()
    } else if self.peek() != Punct(']') {
      self.fail("G032", "expected ',' or ']' in extras")
    }
  }
  self.expect_punct(']')
  values
}

///|
fn GrammarParser::parse_conflicts(
  self : GrammarParser,
) -> Array[Array[String]] raise GrammarParseError {
  self.expect_punct('[')
  let groups : Array[Array[String]] = []
  while self.peek() != Punct(']') {
    self.skip_separators()
    if self.peek() == Punct(']') {
      break
    }
    groups.push(self.parse_name_list())
    if self.peek() == Punct(',') {
      self.advance()
    } else if self.peek() != Punct(']') {
      self.fail("G033", "expected ',' or ']' in conflicts")
    }
  }
  self.expect_punct(']')
  groups
}

///|
/// Parse the canonical MoonParse grammar DSL without filesystem or host state.
pub fn parse_grammar(source : String) -> GrammarAst raise GrammarParseError {
  let parser = GrammarParser::new(source)
  let mut start : String? = None
  let rules : Array[RuleDecl] = []
  let extras : Array[GrammarPattern] = []
  let externals : Array[String] = []
  let mut word : String? = None
  let conflicts : Array[Array[String]] = []
  let supertypes : Array[String] = []
  let precedences : Array[PrecedenceDecl] = []
  let reserved_sets : Array[ReservedSet] = []
  let mut declaration_order = 0
  parser.skip_separators()
  while parser.peek() != End {
    let attributes : Array[RuleAttribute] = []
    while parser.peek() == Punct('@') {
      parser.advance()
      match parser.expect_name("as rule attribute") {
        "inline" => attributes.push(Inline)
        "hide" => attributes.push(Hidden)
        other => parser.fail("G040", "unknown rule attribute '\{other}'")
      }
    }
    match parser.peek() {
      Name("start") => {
        parser.advance()
        if start is Some(_) {
          parser.fail("G041", "duplicate start declaration")
        }
        start = Some(parser.expect_name("after start"))
      }
      Name("rule") => {
        parser.advance()
        let name = parser.expect_name("after rule")
        parser.expect_punct(':')
        let pattern = parser.parse_choice()
        rules.push({
          name,
          pattern,
          is_token: false,
          immediate: false,
          declaration_order,
          attributes,
        })
      }
      Name("token") => {
        parser.advance()
        let immediate = if parser.peek() == Punct('.') {
          parser.advance()
          let suffix = parser.expect_name("after token.")
          if suffix != "immediate" {
            parser.fail("G042", "expected token.immediate")
          }
          true
        } else {
          false
        }
        if parser.expect_name("after token") != "rule" {
          parser.fail("G042", "expected rule after token")
        }
        let name = parser.expect_name("after token rule")
        parser.expect_punct(':')
        let pattern = parser.parse_choice()
        rules.push({
          name,
          pattern,
          is_token: true,
          immediate,
          declaration_order,
          attributes,
        })
      }
      Name("extras") => {
        parser.advance()
        for pattern in parser.parse_extras() {
          extras.push(pattern)
        }
      }
      Name("externals") => {
        parser.advance()
        for name in parser.parse_name_list() {
          externals.push(name)
        }
      }
      Name("word") => {
        parser.advance()
        if word is Some(_) {
          parser.fail("G046", "duplicate word declaration")
        }
        word = Some(parser.expect_name("after word"))
      }
      Name("conflicts") => {
        parser.advance()
        for group in parser.parse_conflicts() {
          conflicts.push(group)
        }
      }
      Name("supertypes") => {
        parser.advance()
        for name in parser.parse_name_list() {
          supertypes.push(name)
        }
      }
      Name("reserved") => {
        parser.advance()
        let name = parser.expect_name("after reserved")
        let words = parser.parse_text_list()
        reserved_sets.push({ name, words, declaration_order })
      }
      Name("precedence") => {
        parser.advance()
        let associativity = match parser.expect_name("after precedence") {
          "left" => Left
          "right" => Right
          "nonassoc" => NonAssoc
          "dynamic" => Dynamic
          other => {
            parser.fail("G043", "unknown associativity '\{other}'")
            None
          }
        }
        let names = parser.parse_name_list()
        precedences.push({ associativity, rules: names, declaration_order })
      }
      _ => parser.fail("G044", "unknown top-level grammar declaration")
    }
    declaration_order += 1
    match parser.peek() {
      End => ()
      Newline | Punct(';') => parser.skip_separators()
      _ =>
        parser.fail("G045", "declarations must be separated by newline or ';'")
    }
  }
  {
    start,
    rules,
    extras,
    externals,
    word,
    conflicts,
    supertypes,
    precedences,
    reserved_sets,
  }
}
