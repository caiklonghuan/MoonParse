///|
fn symbol_id(grammar : NormalizedGrammar, name : String) -> Int raise {
  for symbol in grammar.symbols {
    if symbol.name == name {
      return symbol.id
    }
  }
  fail("missing symbol \{name}")
}

///|
fn assert_invalid(source : String, expected_code : String) -> Unit raise {
  try ignore(normalize(parse_grammar(source))) catch {
    InvalidGrammar(code~, ..) => assert_eq(code, expected_code)
  } noraise {
    _ => fail("grammar must be rejected")
  }
}

///|
fn representative_grammar() -> String {
  let source =
    #|// canonical grammar fixture
    #|start document
    #|@inline rule document: statement*
    #|rule statement: lhs: identifier "=" rhs: value
    #|rule value: identifier | number
    #|token rule identifier: /[a-zA-Z_]\w*/
    #|token.immediate rule number: lex.prec(2, /\d+/)
    #|extras [/\s+/]
    #|externals [comment]
    #|word identifier
    #|conflicts [[statement, value]]
    #|supertypes [value]
    #|precedence left [statement]
    #|reserved global ["if", "else"]
  source
}

///|
fn production_for(
  grammar : NormalizedGrammar,
  lhs : Int,
) -> NormalizedProduction? {
  for production in grammar.productions {
    if production.lhs == lhs {
      return Some(production)
    }
  }
  None
}

///|
test "grammar DSL parses representative declarations and regex IR" {
  let grammar = parse_grammar(representative_grammar())
  assert_true(grammar.start == Some("document"))
  assert_eq(grammar.rules.length(), 5)
  assert_true(grammar.rules[0].attributes.contains(Inline))
  assert_true(grammar.rules[4].immediate)
  assert_eq(grammar.extras.length(), 1)
  assert_true(grammar.externals == ["comment"])
  assert_true(grammar.word == Some("identifier"))
  assert_eq(grammar.conflicts.length(), 1)
  assert_eq(grammar.reserved_sets.length(), 1)
  assert_true(
    grammar.rules[3].pattern
    is Regex("[a-zA-Z_]\\w*", Concat([CharClass(_, _), Repeat(_, _)])),
  )
}

///|
test "normalization assigns stable source-order rule IDs and lowers EBNF" {
  let normalized = normalize(parse_grammar(representative_grammar()))
  assert_eq(normalized.start_symbol, 0)
  assert_eq(symbol_id(normalized, "document"), 0)
  assert_eq(symbol_id(normalized, "statement"), 1)
  assert_eq(symbol_id(normalized, "value"), 2)
  assert_eq(symbol_id(normalized, "identifier"), 3)
  assert_eq(symbol_id(normalized, "number"), 4)
  assert_eq(symbol_id(normalized, "comment"), 5)
  assert_true(normalized.productions.length() >= 6)
  assert_true(
    normalized.productions.any(fn(production) { production.rhs.length() == 0 }),
  )
  assert_true(normalized.extras.length() == 1)
  assert_true(normalized.word_symbol == Some(3))
  assert_eq(normalized.tokens.length(), 2)
  assert_true(normalized.tokens[1].immediate)
  assert_eq(normalized.tokens[1].lexical_precedence, 2)
  assert_true(normalized.conflicts == [[1, 2]])
  assert_true(normalized.supertypes == [2])
  assert_true(normalized.inline_symbols == [0])
}

///|
test "field alias lookahead and precedence metadata survive normalization" {
  let source =
    #|start expr
    #|rule expr: prec.left(7, left: atom alias("operator", "+") &atom)
    #|rule atom: /[a-z]+/
  let normalized = normalize(parse_grammar(source))
  let expr = symbol_id(normalized, "expr")
  let production = production_for(normalized, expr)
  match production {
    Some(actual) => {
      assert_eq(actual.precedence, 7)
      assert_true(actual.associativity == Left)
      assert_true(actual.rhs[0].field == Some("left"))
      assert_true(actual.rhs[1].alias_name == Some("operator"))
      assert_true(actual.rhs[1].alias_is_named)
      assert_true(actual.rhs[2].lookahead == Some(Positive))
    }
    None => fail("missing expr production")
  }
}

///|
test "reserved annotations and CR line endings survive normalization" {
  let source = "reserved global [\"if\"]\rrule source: reserved(global, word)\rtoken rule word: /[a-z]+/"
  let normalized = normalize(parse_grammar(source))
  let production = production_for(normalized, symbol_id(normalized, "source"))
  assert_true(production.unwrap().rhs[0].reserved_set == Some("global"))
  assert_true(normalized.reserved_sets[0].words == ["if"])
}

///|
test "normalization rejects silently lossy metadata" {
  assert_invalid("rule source: reserved(missing, \"x\")", "G114")
  assert_invalid("@inline token rule word: /x/", "G115")
  assert_invalid("reserved global [\"if\", \"if\"]\nrule source: \"x\"", "G110")
  assert_invalid("word item\nword item\ntoken rule item: /x/", "G046")
}

///|
test "grammar canonical key is deterministic across repeated compilation" {
  let first = normalize(parse_grammar(representative_grammar())).canonical_key()
  for _ in 0..<100 {
    let next = normalize(parse_grammar(representative_grammar())).canonical_key()
    assert_eq(next, first)
  }
}

///|
test "grammar canonical key covers semantic metadata" {
  let base = normalize(
    parse_grammar("rule source: item\ntoken rule item: /[a-z]+/"),
  ).canonical_key()
  let with_extra = normalize(
    parse_grammar(
      "rule source: item\ntoken rule item: /[a-z]+/\nextras [/\\s+/]",
    ),
  ).canonical_key()
  let with_inline = normalize(
    parse_grammar("@inline rule source: item\ntoken rule item: /[a-z]+/"),
  ).canonical_key()
  assert_true(base != with_extra)
  assert_true(base != with_inline)
}

///|
test "grammar rejects invalid regex duplicate and undefined rule" {
  assert_invalid("rule value: /[z-a]/", "G020")
  assert_invalid("rule value: \"a\"\nrule value: \"b\"", "G104")
  assert_invalid("rule value: missing", "G101")
  assert_invalid("rule value: \"x\"{0,257}", "G103")
}

///|
test "grammar errors use UTF-8 byte offsets" {
  try parse_grammar("rule 你: /(/\n") catch {
    InvalidGrammar(byte_offset~, code="G020", ..) => assert_eq(byte_offset, 12)
    error => fail("unexpected error \{to_repr(error)}")
  } noraise {
    _ => fail("invalid regex must fail")
  }
}
