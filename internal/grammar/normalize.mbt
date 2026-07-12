///|
priv struct NormalizeContext {
  symbols : Array[NormalizedSymbol]
  productions : Array[NormalizedProduction]
  tokens : Array[NormalizedToken]
  reserved_sets : Array[NormalizedReservedSet]
  mut next_synthetic : Int
}

///|
fn normalize_fail(
  code : String,
  reason : String,
) -> Unit raise GrammarParseError {
  raise InvalidGrammar(byte_offset=0, code~, reason~)
}

///|
fn find_symbol(symbols : Array[NormalizedSymbol], name : String) -> Int? {
  for symbol in symbols {
    if symbol.name == name {
      return Some(symbol.id)
    }
  }
  None
}

///|
fn find_reference_symbol(
  symbols : Array[NormalizedSymbol],
  name : String,
) -> Int? {
  for symbol in symbols {
    if symbol.name == name &&
      (
        symbol.kind == NamedNonterminal ||
        symbol.kind == AnonymousNonterminal ||
        symbol.kind == NamedTerminal ||
        symbol.kind == ExternalTerminal
      ) {
      return Some(symbol.id)
    }
  }
  None
}

///|
fn find_symbol_kind(
  symbols : Array[NormalizedSymbol],
  name : String,
  kind : NormalizedSymbolKind,
) -> Int? {
  for symbol in symbols {
    if symbol.name == name && symbol.kind == kind {
      return Some(symbol.id)
    }
  }
  None
}

///|
fn NormalizeContext::add_symbol(
  self : NormalizeContext,
  name : String,
  kind : NormalizedSymbolKind,
  declaration_order : Int,
) -> Int {
  let id = self.symbols.length()
  self.symbols.push({ id, name, kind, declaration_order })
  id
}

///|
fn NormalizeContext::named_symbol(
  self : NormalizeContext,
  name : String,
) -> Int raise GrammarParseError {
  match find_reference_symbol(self.symbols, name) {
    Some(id) => id
    None => {
      normalize_fail("G101", "undefined rule or external '\{name}'")
      -1
    }
  }
}

///|
fn NormalizeContext::terminal(
  self : NormalizeContext,
  name : String,
  kind : NormalizedSymbolKind,
) -> Int {
  match find_symbol_kind(self.symbols, name, kind) {
    Some(id) => id
    None => self.add_symbol(name, kind, self.symbols.length())
  }
}

///|
fn NormalizeContext::synthetic(self : NormalizeContext, owner : String) -> Int {
  let serial = self.next_synthetic
  self.next_synthetic += 1
  self.add_symbol(
    "_mp_\{owner}_\{serial}",
    AnonymousNonterminal,
    self.symbols.length(),
  )
}

///|
fn plain_element(symbol_id : Int) -> NormalizedElement {
  {
    symbol_id,
    field: None,
    alias_name: None,
    alias_is_named: false,
    lookahead: None,
    reserved_set: None,
  }
}

///|
fn NormalizeContext::push_production(
  self : NormalizeContext,
  lhs : Int,
  rhs : Array[NormalizedElement],
  precedence : Int,
  associativity : Associativity,
) -> Unit raise GrammarParseError {
  if self.productions.length() >= 1000000 {
    normalize_fail("G102", "production resource limit exceeded")
  }
  let dynamic_precedence = if associativity == Dynamic { precedence } else { 0 }
  let static_precedence = if associativity == Dynamic { 0 } else { precedence }
  self.productions.push({
    id: self.productions.length(),
    lhs,
    rhs,
    precedence: static_precedence,
    associativity,
    dynamic_precedence,
  })
}

///|
fn NormalizeContext::element(
  self : NormalizeContext,
  pattern : GrammarPattern,
  owner : String,
) -> NormalizedElement raise GrammarParseError {
  match pattern {
    Field(name, inner) => {
      let element = self.element(inner, owner)
      {
        symbol_id: element.symbol_id,
        field: Some(name),
        alias_name: element.alias_name,
        alias_is_named: element.alias_is_named,
        lookahead: element.lookahead,
        reserved_set: element.reserved_set,
      }
    }
    Alias(name, named, inner) => {
      let element = self.element(inner, owner)
      {
        symbol_id: element.symbol_id,
        field: element.field,
        alias_name: Some(name),
        alias_is_named: named,
        lookahead: element.lookahead,
        reserved_set: element.reserved_set,
      }
    }
    Tagged(name, inner) => {
      let element = self.element(inner, owner)
      {
        symbol_id: element.symbol_id,
        field: if element.field is None {
          Some(name)
        } else {
          element.field
        },
        alias_name: element.alias_name,
        alias_is_named: element.alias_is_named,
        lookahead: element.lookahead,
        reserved_set: element.reserved_set,
      }
    }
    Lookahead(inner, positive) => {
      let element = self.element(inner, owner)
      {
        symbol_id: element.symbol_id,
        field: element.field,
        alias_name: element.alias_name,
        alias_is_named: element.alias_is_named,
        lookahead: Some(if positive { Positive } else { Negative }),
        reserved_set: element.reserved_set,
      }
    }
    Reserved(name, inner) => {
      if !self.reserved_sets.any(fn(set) { set.name == name }) {
        normalize_fail("G114", "unknown reserved set '\{name}'")
      }
      let element = self.element(inner, owner)
      {
        symbol_id: element.symbol_id,
        field: element.field,
        alias_name: element.alias_name,
        alias_is_named: element.alias_is_named,
        lookahead: element.lookahead,
        reserved_set: Some(name),
      }
    }
    LexicalPrecedence(_, inner) => self.element(inner, owner)
    _ => plain_element(self.symbol(pattern, owner))
  }
}

///|
fn NormalizeContext::symbol(
  self : NormalizeContext,
  pattern : GrammarPattern,
  owner : String,
) -> Int raise GrammarParseError {
  match pattern {
    Ref(name) => self.named_symbol(name)
    Literal(value) => self.terminal(value, LiteralTerminal)
    Regex(source, _) => self.terminal(source, RegexTerminal)
    AnyScalar => self.terminal(".", AnyTerminal)
    Field(_, inner)
    | Tagged(_, inner)
    | Lookahead(inner, _)
    | Alias(_, _, inner)
    | LexicalPrecedence(_, inner)
    | Reserved(_, inner) => self.symbol(inner, owner)
    ZeroOrMore(inner) => {
      let synthetic = self.synthetic(owner)
      let child = self.element(inner, owner)
      self.push_production(synthetic, [], 0, None)
      self.push_production(
        synthetic,
        [plain_element(synthetic), child],
        0,
        None,
      )
      synthetic
    }
    OneOrMore(inner) => {
      let synthetic = self.synthetic(owner)
      let child = self.element(inner, owner)
      self.push_production(synthetic, [child], 0, None)
      self.push_production(
        synthetic,
        [plain_element(synthetic), child],
        0,
        None,
      )
      synthetic
    }
    Optional(inner) => {
      let synthetic = self.synthetic(owner)
      self.push_production(synthetic, [], 0, None)
      self.push_production(synthetic, [self.element(inner, owner)], 0, None)
      synthetic
    }
    RepeatRange(inner, minimum, maximum) => {
      if minimum < 0 || maximum < minimum {
        normalize_fail("G103", "invalid bounded repetition range")
      }
      if maximum > 256 {
        normalize_fail("G103", "bounded repetition maximum exceeds 256")
      }
      let synthetic = self.synthetic(owner)
      for count in minimum..<=maximum {
        let rhs : Array[NormalizedElement] = []
        for _ in 0..<count {
          rhs.push(self.element(inner, owner))
        }
        self.push_production(synthetic, rhs, 0, None)
      }
      synthetic
    }
    Choice(_) | Sequence(_) | Precedence(_, _, _) => {
      let synthetic = self.synthetic(owner)
      self.emit_body(synthetic, pattern, owner, 0, None)
      synthetic
    }
  }
}

///|
fn NormalizeContext::emit_body(
  self : NormalizeContext,
  lhs : Int,
  pattern : GrammarPattern,
  owner : String,
  fallback_precedence : Int,
  fallback_associativity : Associativity,
) -> Unit raise GrammarParseError {
  match pattern {
    Choice(branches) =>
      for branch in branches {
        self.emit_body(
          lhs, branch, owner, fallback_precedence, fallback_associativity,
        )
      }
    Precedence(level, associativity, inner) =>
      self.emit_body(lhs, inner, owner, level, associativity)
    Sequence(parts) => {
      let rhs : Array[NormalizedElement] = []
      for part in parts {
        rhs.push(self.element(part, owner))
      }
      self.push_production(
        lhs, rhs, fallback_precedence, fallback_associativity,
      )
    }
    _ =>
      self.push_production(
        lhs,
        [self.element(pattern, owner)],
        fallback_precedence,
        fallback_associativity,
      )
  }
}

///|
fn rule_precedence(grammar : GrammarAst, name : String) -> (Int, Associativity) {
  for index, declaration in grammar.precedences {
    if declaration.rules.contains(name) {
      return (index + 1, declaration.associativity)
    }
  }
  (0, None)
}

///|
fn lexical_precedence(pattern : GrammarPattern) -> Int {
  match pattern {
    LexicalPrecedence(level, _) => level
    Reserved(_, inner)
    | Alias(_, _, inner)
    | Field(_, inner)
    | Tagged(_, inner) => lexical_precedence(inner)
    _ => 0
  }
}

///|
fn validate_token_pattern(
  ctx : NormalizeContext,
  pattern : GrammarPattern,
) -> Unit raise GrammarParseError {
  match pattern {
    Literal(_) | Regex(_, _) | AnyScalar => ()
    Ref(name) =>
      match find_reference_symbol(ctx.symbols, name) {
        Some(id) =>
          if ctx.symbols[id].kind != NamedTerminal {
            normalize_fail(
              "G111", "token rule may only reference another token rule",
            )
          }
        None => normalize_fail("G101", "undefined token rule '\{name}'")
      }
    Choice(parts) | Sequence(parts) =>
      for part in parts {
        validate_token_pattern(ctx, part)
      }
    ZeroOrMore(inner)
    | OneOrMore(inner)
    | Optional(inner)
    | RepeatRange(inner, _, _)
    | Alias(_, _, inner)
    | LexicalPrecedence(_, inner)
    | Reserved(_, inner) => validate_token_pattern(ctx, inner)
    Field(_, _) | Tagged(_, _) | Lookahead(_, _) | Precedence(_, _, _) =>
      normalize_fail("G111", "parser-only operator in token rule")
  }
}

///|
fn symbol_ids(
  ctx : NormalizeContext,
  names : Array[String],
  code : String,
) -> Array[Int] raise GrammarParseError {
  let ids : Array[Int] = []
  for name in names {
    match find_reference_symbol(ctx.symbols, name) {
      Some(id) => if !ids.contains(id) { ids.push(id) }
      None => normalize_fail(code, "unknown symbol '\{name}'")
    }
  }
  ids
}

///|
/// Normalize EBNF into stable-ID BNF. IDs derive from rule declaration order,
/// then external declaration order, terminal first occurrence, and deterministic
/// synthetic traversal in that order.
pub fn normalize(
  grammar : GrammarAst,
) -> NormalizedGrammar raise GrammarParseError {
  let ctx : NormalizeContext = {
    symbols: [],
    productions: [],
    tokens: [],
    reserved_sets: [],
    next_synthetic: 0,
  }
  if grammar.rules.length() == 0 {
    normalize_fail("G100", "grammar has no rules")
  }
  for rule in grammar.rules {
    if find_symbol(ctx.symbols, rule.name) is Some(_) {
      normalize_fail("G104", "duplicate rule '\{rule.name}'")
    }
    let kind = if rule.is_token {
      NamedTerminal
    } else if rule.name.has_prefix("_") || rule.attributes.contains(Hidden) {
      AnonymousNonterminal
    } else {
      NamedNonterminal
    }
    ignore(ctx.add_symbol(rule.name, kind, rule.declaration_order))
  }
  for rule in grammar.rules {
    if rule.is_token && rule.attributes.contains(Inline) {
      normalize_fail("G115", "token rule '\{rule.name}' cannot be inline")
    }
  }
  for declaration in grammar.precedences {
    for name in declaration.rules {
      match find_reference_symbol(ctx.symbols, name) {
        Some(id) =>
          if ctx.symbols[id].kind == NamedTerminal ||
            ctx.symbols[id].kind == ExternalTerminal {
            normalize_fail(
              "G109",
              "parser precedence cannot target terminal '\{name}'",
            )
          }
        None =>
          normalize_fail("G109", "precedence references unknown rule '\{name}'")
      }
    }
  }
  for name in grammar.externals {
    if find_symbol(ctx.symbols, name) is Some(_) {
      normalize_fail("G105", "duplicate external or rule '\{name}'")
    }
    ignore(ctx.add_symbol(name, ExternalTerminal, ctx.symbols.length()))
  }
  for set in grammar.reserved_sets {
    if ctx.reserved_sets.any(fn(existing) { existing.name == set.name }) {
      normalize_fail("G110", "duplicate reserved set '\{set.name}'")
    }
    let words : Array[String] = []
    for word in set.words {
      if words.contains(word) {
        normalize_fail(
          "G110",
          "duplicate word '\{word}' in reserved set '\{set.name}'",
        )
      }
      words.push(word)
    }
    ctx.reserved_sets.push({ name: set.name, words })
  }
  for rule in grammar.rules {
    let lhs = ctx.named_symbol(rule.name)
    if rule.is_token {
      validate_token_pattern(ctx, rule.pattern)
      ctx.tokens.push({
        symbol_id: lhs,
        pattern: rule.pattern,
        immediate: rule.immediate,
        lexical_precedence: lexical_precedence(rule.pattern),
        declaration_order: rule.declaration_order,
      })
    } else {
      let (precedence, associativity) = rule_precedence(grammar, rule.name)
      ctx.emit_body(lhs, rule.pattern, rule.name, precedence, associativity)
    }
  }
  let start_name = match grammar.start {
    Some(name) => name
    None => grammar.rules[0].name
  }
  let start_symbol = ctx.named_symbol(start_name)
  if ctx.symbols[start_symbol].kind != NamedNonterminal &&
    ctx.symbols[start_symbol].kind != AnonymousNonterminal {
    normalize_fail("G112", "start symbol must be a parser rule")
  }
  let extras : Array[Int] = []
  for pattern in grammar.extras {
    let id = ctx.symbol(pattern, "extra")
    match ctx.symbols[id].kind {
      NamedTerminal
      | LiteralTerminal
      | RegexTerminal
      | AnyTerminal
      | ExternalTerminal => if !extras.contains(id) { extras.push(id) }
      _ => normalize_fail("G106", "extra must normalize to a terminal")
    }
  }
  let word_symbol = match grammar.word {
    Some(name) => {
      let id = ctx.named_symbol(name)
      if ctx.symbols[id].kind != NamedTerminal {
        normalize_fail("G113", "word symbol must be a token rule")
      }
      Some(id)
    }
    None => None
  }
  let conflicts : Array[Array[Int]] = []
  for group in grammar.conflicts {
    conflicts.push(symbol_ids(ctx, group, "G107"))
  }
  let supertypes = symbol_ids(ctx, grammar.supertypes, "G108")
  for id in supertypes {
    if ctx.symbols[id].kind != NamedNonterminal &&
      ctx.symbols[id].kind != AnonymousNonterminal {
      normalize_fail("G108", "supertype must be a parser rule")
    }
  }
  let inline_symbols : Array[Int] = []
  for rule in grammar.rules {
    if rule.attributes.contains(Inline) {
      let id = ctx.named_symbol(rule.name)
      inline_symbols.push(id)
    }
  }
  {
    start_symbol,
    symbols: ctx.symbols,
    productions: ctx.productions,
    tokens: ctx.tokens,
    extras,
    word_symbol,
    conflicts,
    supertypes,
    inline_symbols,
    reserved_sets: ctx.reserved_sets,
  }
}

///|
fn symbol_kind_key(kind : NormalizedSymbolKind) -> String {
  match kind {
    NamedNonterminal => "n"
    AnonymousNonterminal => "h"
    NamedTerminal => "t"
    LiteralTerminal => "l"
    RegexTerminal => "r"
    AnyTerminal => "a"
    ExternalTerminal => "x"
  }
}

///|
fn association_key(value : Associativity) -> String {
  match value {
    None => "n"
    Left => "l"
    Right => "r"
    NonAssoc => "x"
    Dynamic => "d"
  }
}

///|
fn text_key(value : String) -> String {
  "\{value.length()}:\{value}"
}

///|
fn optional_text_key(value : String?) -> String {
  match value {
    None => "0"
    Some(text) => "1\{text_key(text)}"
  }
}

///|
fn pattern_key(pattern : GrammarPattern) -> String {
  match pattern {
    Ref(name) => "R\{text_key(name)}"
    Literal(value) => "L\{text_key(value)}"
    Regex(source, _) => "X\{text_key(source)}"
    AnyScalar => "."
    Choice(items) => "C\{items.length()}[\{items.map(pattern_key).join("")}]"
    Sequence(items) => "S\{items.length()}[\{items.map(pattern_key).join("")}]"
    ZeroOrMore(inner) => "*\{pattern_key(inner)}"
    OneOrMore(inner) => "+\{pattern_key(inner)}"
    Optional(inner) => "?\{pattern_key(inner)}"
    RepeatRange(inner, minimum, maximum) =>
      "B\{minimum}:\{maximum}:\{pattern_key(inner)}"
    Field(name, inner) => "F\{text_key(name)}\{pattern_key(inner)}"
    Tagged(name, inner) => "T\{text_key(name)}\{pattern_key(inner)}"
    Lookahead(inner, positive) =>
      "K\{if positive { 1 } else { 0 }}\{pattern_key(inner)}"
    Precedence(level, associativity, inner) =>
      "P\{level}:\{association_key(associativity)}\{pattern_key(inner)}"
    Alias(name, named, inner) =>
      "A\{if named { 1 } else { 0 }}\{text_key(name)}\{pattern_key(inner)}"
    LexicalPrecedence(level, inner) => "Q\{level}:\{pattern_key(inner)}"
    Reserved(name, inner) => "V\{text_key(name)}\{pattern_key(inner)}"
  }
}

///|
fn integer_array_key(values : Array[Int]) -> String {
  "\{values.length()}[\{values.map(fn(value) { "\{value}," }).join("")}]"
}

///|
/// Stable review/oracle representation. It deliberately excludes object
/// identity and mutable collection iteration order.
pub fn NormalizedGrammar::canonical_key(self : NormalizedGrammar) -> String {
  let symbols : Array[String] = []
  for symbol in self.symbols {
    symbols.push(
      "\{symbol.id}:\{symbol_kind_key(symbol.kind)}:\{symbol.name}:\{symbol.declaration_order}",
    )
  }
  let productions : Array[String] = []
  for production in self.productions {
    let rhs : Array[String] = []
    for element in production.rhs {
      let lookahead = match element.lookahead {
        None => "n"
        Some(Positive) => "p"
        Some(Negative) => "m"
      }
      rhs.push(
        "\{element.symbol_id}:\{optional_text_key(element.field)}:\{optional_text_key(element.alias_name)}:\{if element.alias_is_named { 1 } else { 0 }}:\{lookahead}:\{optional_text_key(element.reserved_set)}",
      )
    }
    let joined_rhs = rhs.join(",")
    productions.push(
      "\{production.id}:\{production.lhs}>\{joined_rhs}:\{production.precedence}:\{association_key(production.associativity)}:\{production.dynamic_precedence}",
    )
  }
  let tokens : Array[String] = []
  for token in self.tokens {
    tokens.push(
      "\{token.symbol_id}:\{if token.immediate { 1 } else { 0 }}:\{token.lexical_precedence}:\{token.declaration_order}:\{pattern_key(token.pattern)}",
    )
  }
  let conflicts = self.conflicts.map(integer_array_key).join("")
  let reserved : Array[String] = []
  for set in self.reserved_sets {
    reserved.push(
      "\{text_key(set.name)}\{set.words.length()}[\{set.words.map(text_key).join("")}]",
    )
  }
  let joined_symbols = symbols.join("|")
  let joined_productions = productions.join("|")
  "start=\{self.start_symbol};word=\{self.word_symbol.unwrap_or(-1)};symbols=\{joined_symbols};productions=\{joined_productions};tokens=\{tokens.join("|")};extras=\{integer_array_key(self.extras)};conflicts=\{conflicts};supertypes=\{integer_array_key(self.supertypes)};inline=\{integer_array_key(self.inline_symbols)};reserved=\{reserved.join("")}"
}
