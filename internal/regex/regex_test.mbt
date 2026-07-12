///|
fn assert_match(
  pattern : String,
  accepted : String,
  rejected : String,
) -> Unit raise {
  let nfa = compile_source(pattern)
  assert_true(nfa.matches(accepted), msg="pattern \{pattern} must accept")
  assert_true(!nfa.matches(rejected), msg="pattern \{pattern} must reject")
}

///|
fn assert_invalid(pattern : String) -> Unit raise {
  try parse(pattern) catch {
    InvalidRegex(..) => ()
  } noraise {
    _ => fail("pattern must be rejected: \{pattern}")
  }
}

///|
test "regex parser normalizes precedence without retaining groups" {
  let ir = parse("a(b|c)*d?")
  assert_true(
    ir
    is Concat(
      [
        Literal('a'),
        Repeat(Alternate([Literal('b'), Literal('c')]), ZeroOrMore),
        Repeat(Literal('d'), ZeroOrOne),
      ]
    ),
  )
}

///|
test "Thompson NFA matches literal concat alternation and repetition oracle" {
  assert_match("abc", "abc", "ab")
  assert_match("(ab|cd)+e?", "abcdabe", "abce")
  assert_match("a*", "", "b")
  assert_match("colou?r", "color", "colouur")
}

///|
test "character classes shorthands and Unicode ranges are portable" {
  assert_match("[a-c]+\\d?", "abcc7", "abcd")
  assert_match("[α-ω]+", "αλω", "alpha")
  assert_match("[中-龥]+", "中文", "Moon")
  assert_match("[^0-9]+", "Moon_解析", "Moon2")
  assert_match("\\w+", "Moon_2026", "Moon-2026")
  assert_match("\\s+", " \t\r\n", "x")
}

///|
test "dot and escaped metacharacters have scalar semantics" {
  assert_match("a.c", "a你c", "ac")
  assert_match("\\[a\\]", "[a]", "a")
  assert_match("\\f", "\f", "f")
}

///|
test "longest prefix reports UTF-8 byte coordinates" {
  let nfa = compile_source("[你a]+")
  assert_true(nfa.longest_prefix("你a!") == Some(4))
  assert_true(nfa.longest_prefix("!你") == None)
  assert_true(compile_source("a*").longest_prefix("bbb") == Some(0))
}

///|
test "canonical Thompson construction is deterministic" {
  let first = compile_source("(ab|[c-e])+\\d?").canonical_key()
  for _ in 0..<100 {
    assert_eq(compile_source("(ab|[c-e])+\\d?").canonical_key(), first)
  }
  assert_true(first.length() > 20)
}

///|
test "invalid regexes fail deterministically" {
  for pattern in ["(", "[a-", "[z-a]", "\\", "*a", "a**", "a)", "[]", "[\\D]"] {
    assert_invalid(pattern)
  }
}

///|
test "parse errors expose UTF-8 byte offsets" {
  try parse("你(") catch {
    InvalidRegex(byte_offset~, reason=_) => assert_eq(byte_offset, 4)
  } noraise {
    _ => fail("expected unterminated group")
  }
}
