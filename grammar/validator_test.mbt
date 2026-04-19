// validator_test.mbt
// 将 Grammar 语义校验测试收拢为单文件、按功能模块组织的表驱动套件。

///|
priv struct ValidationCase {
  name : String
  dsl : String
  expected_kinds : Array[String]
  absent_kinds : Array[String]
  expected_count : Int?
}

///|
priv struct HintCase {
  name : String
  dsl : String
  kind : String
  expected_hint_substring : String
}

///|
priv struct LenientValidationCase {
  name : String
  dsl : String
  expected_kinds : Array[String]
  absent_kinds : Array[String]
  expected_count : Int?
}

///|
priv struct RenderCase {
  name : String
  error : ValidationError
  expected_substrings : Array[String]
}

///|
fn parse_ok(name : String, dsl : String) -> Grammar raise {
  match parse_grammar(dsl) {
    Success(g) => g
    Error(err) =>
      fail(
        "parse failed [\{name}]: \{err.message} at \{err.location.line}:\{err.location.column}",
      )
  }
}

///|
fn parse_lenient(_name : String, dsl : String) -> Grammar {
  let (grammar, _errors) = parse_grammar_lenient(dsl)
  grammar
}

///|
fn kind_of(error : ValidationError) -> String {
  match error.kind {
    ValidationErrorKind::UndefinedRule(r) => "UndefinedRule:\{r}"
    ValidationErrorKind::UndefinedStartRule(r) => "UndefinedStartRule:\{r}"
    ValidationErrorKind::DirectLeftRecursion(r) => "DirectLeft:\{r}"
    ValidationErrorKind::IndirectLeftRecursion(_) => "IndirectLeft"
    ValidationErrorKind::UnreachableRule(r) => "Unreachable:\{r}"
    ValidationErrorKind::InvalidRegex(re, _) => "InvalidRegex:\{re}"
    ValidationErrorKind::DuplicateRule(r) => "DuplicateRule:\{r}"
    ValidationErrorKind::MixedPrecSystems => "MixedPrecSystems"
    ValidationErrorKind::ExtrasNonTerminal(d) => "ExtrasNonTerminal:\{d}"
    ValidationErrorKind::UndefinedTemplateRule(r) =>
      "UndefinedTemplateRule:\{r}"
    ValidationErrorKind::RuleAppArityMismatch(r, e, g) =>
      "ArityMismatch:\{r}:\{e}:\{g}"
    ValidationErrorKind::TemplateRuleUsedAsRef(r) =>
      "TemplateRuleUsedAsRef:\{r}"
    ValidationErrorKind::UndefinedWordRule(r) => "UndefinedWordRule:\{r}"
    ValidationErrorKind::TokenRuleContainsRef(r) => "TokenRuleContainsRef:\{r}"
    ValidationErrorKind::ConflictUndeclaredRule(r) =>
      "ConflictUndeclaredRule:\{r}"
    ValidationErrorKind::SupertypeUndeclaredRule(r) =>
      "SupertypeUndeclaredRule:\{r}"
    ValidationErrorKind::DeprecatedRuleUsed(r) => "DeprecatedRuleUsed:\{r}"
    ValidationErrorKind::LookaheadNonTailAssertion =>
      "LookaheadNonTailAssertion"
    ValidationErrorKind::LookaheadMixedAssertions => "LookaheadMixedAssertions"
  }
}

///|
fn kinds(errors : Array[ValidationError]) -> Array[String] {
  errors.map(kind_of)
}

///|
fn arr_string_contains(arr : Array[String], s : String) -> Bool {
  for item in arr {
    if item == s {
      return true
    }
  }
  false
}

///|
fn find_error_by_kind(
  errors : Array[ValidationError],
  target_kind : String,
) -> ValidationError? {
  for error in errors {
    if kind_of(error) == target_kind {
      return Some(error)
    }
  }
  None
}

///|
fn assert_has_kind(
  actual_kinds : Array[String],
  expected_kind : String,
  case_name : String,
) -> Unit raise {
  if !arr_string_contains(actual_kinds, expected_kind) {
    fail(
      "missing validation kind [\{case_name}]: \{expected_kind}, actual=\{actual_kinds}",
    )
  }
}

///|
fn assert_lacks_kind(
  actual_kinds : Array[String],
  unexpected_kind : String,
  case_name : String,
) -> Unit raise {
  if arr_string_contains(actual_kinds, unexpected_kind) {
    fail(
      "unexpected validation kind [\{case_name}]: \{unexpected_kind}, actual=\{actual_kinds}",
    )
  }
}

///|
fn run_validation_cases(cases : Array[ValidationCase]) -> Unit raise {
  for tc in cases {
    let grammar = parse_ok(tc.name, tc.dsl)
    let errors = validate_grammar(grammar)
    let actual_kinds = kinds(errors)
    match tc.expected_count {
      Some(count) =>
        if errors.length() != count {
          fail(
            "unexpected validation count [\{tc.name}]: expected \{count}, got \{errors.length()} kinds=\{actual_kinds}",
          )
        }
      None => ()
    }
    for expected_kind in tc.expected_kinds {
      assert_has_kind(actual_kinds, expected_kind, tc.name)
    }
    for unexpected_kind in tc.absent_kinds {
      assert_lacks_kind(actual_kinds, unexpected_kind, tc.name)
    }
  }
}

///|
fn run_hint_cases(cases : Array[HintCase]) -> Unit raise {
  for tc in cases {
    let grammar = parse_ok(tc.name, tc.dsl)
    let errors = validate_grammar(grammar)
    match find_error_by_kind(errors, tc.kind) {
      None => fail("missing error for hint case [\{tc.name}]: \{tc.kind}")
      Some(error) =>
        match error.hint {
          None => fail("missing hint [\{tc.name}] for \{tc.kind}")
          Some(hint) => assert_true(hint.contains(tc.expected_hint_substring))
        }
    }
  }
}

///|
fn run_lenient_validation_cases(
  cases : Array[LenientValidationCase],
) -> Unit raise {
  for tc in cases {
    let grammar = parse_lenient(tc.name, tc.dsl)
    let errors = validate_grammar(grammar)
    let actual_kinds = kinds(errors)
    match tc.expected_count {
      Some(count) =>
        if errors.length() != count {
          fail(
            "unexpected lenient validation count [\{tc.name}]: expected \{count}, got \{errors.length()} kinds=\{actual_kinds}",
          )
        }
      None => ()
    }
    for expected_kind in tc.expected_kinds {
      assert_has_kind(actual_kinds, expected_kind, tc.name)
    }
    for unexpected_kind in tc.absent_kinds {
      assert_lacks_kind(actual_kinds, unexpected_kind, tc.name)
    }
  }
}

///|
fn run_render_cases(cases : Array[RenderCase]) -> Unit raise {
  for tc in cases {
    let rendered = tc.error.to_string()
    for expected in tc.expected_substrings {
      if !rendered.contains(expected) {
        fail("render case failed [\{tc.name}]: missing substring \{expected}")
      }
    }
  }
}

///|
fn get_validator_core_cases() -> Array[ValidationCase] {
  [
    {
      name: "合法文法无错",
      dsl: "start expr\nrule expr: term (\"+\" term)*\nrule term: /\\d+/",
      expected_kinds: [],
      absent_kinds: [],
      expected_count: Some(0),
    },
    {
      name: "start 规则不存在",
      dsl: "start missing\nrule expr: /\\d+/",
      expected_kinds: ["UndefinedStartRule:missing"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "引用未定义规则",
      dsl: "rule expr: ghost",
      expected_kinds: ["UndefinedRule:ghost"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "多个未定义引用",
      dsl: "rule expr: a b c",
      expected_kinds: ["UndefinedRule:a", "UndefinedRule:b", "UndefinedRule:c"],
      absent_kinds: [],
      expected_count: Some(3),
    },
    {
      name: "直接左递归",
      dsl: "rule expr: expr \"+\" /\\d+/",
      expected_kinds: ["DirectLeft:expr"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "选择中的直接左递归",
      dsl: "rule expr: expr | /\\d+/",
      expected_kinds: ["DirectLeft:expr"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "间接左递归",
      dsl: "rule a: b\nrule b: a",
      expected_kinds: ["IndirectLeft"],
      absent_kinds: [],
      expected_count: None,
    },
    {
      name: "不可达规则",
      dsl: "start expr\nrule expr: /\\d+/\nrule orphan: /[a-z]/",
      expected_kinds: ["Unreachable:orphan"],
      absent_kinds: ["Unreachable:expr"],
      expected_count: Some(1),
    },
    {
      name: "没有 start 时不做可达性检查",
      dsl: "rule orphan: /[a-z]/\nrule other: /\\d+/",
      expected_kinds: [],
      absent_kinds: ["Unreachable:orphan", "Unreachable:other"],
      expected_count: Some(0),
    },
    {
      name: "传递可达性",
      dsl: "start a\nrule a: b\nrule b: c\nrule c: /\\d+/\nrule d: /[a-z]/",
      expected_kinds: ["Unreachable:d"],
      absent_kinds: ["Unreachable:a", "Unreachable:b", "Unreachable:c"],
      expected_count: Some(1),
    },
    {
      name: "重复规则定义",
      dsl: "rule expr: /\\d+/\nrule expr: /[a-z]/",
      expected_kinds: ["DuplicateRule:expr"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "混用顶层 precedence 与内联 prec",
      dsl: "precedence left plus\nrule plus: \"+\"\nrule num: /\\d+/\nrule expr: prec(1, num)",
      expected_kinds: ["MixedPrecSystems"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "extras 中出现非终结符",
      dsl: "rule expr: /\\d+/\nextras [expr]",
      expected_kinds: ["ExtrasNonTerminal:expr"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "supertypes 中未声明规则",
      dsl: "supertypes [expr, stmt]\nrule expr: /\\d+/",
      expected_kinds: ["SupertypeUndeclaredRule:stmt"],
      absent_kinds: ["SupertypeUndeclaredRule:expr"],
      expected_count: Some(1),
    },
    {
      name: "supertypes 中全部已声明",
      dsl: "supertypes [expr, stmt]\nrule expr: /\\d+/\nrule stmt: expr",
      expected_kinds: [],
      absent_kinds: [
        "SupertypeUndeclaredRule:expr", "SupertypeUndeclaredRule:stmt",
      ],
      expected_count: Some(0),
    },
    {
      name: "普通规则引用 deprecated 规则",
      dsl: "@deprecated rule old_expr: /\\d+/\nrule new_expr: old_expr",
      expected_kinds: ["DeprecatedRuleUsed:old_expr"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "conflicts 中未声明规则",
      dsl: "conflicts [[expr, stmt]]\nrule expr: /\\d+/",
      expected_kinds: ["ConflictUndeclaredRule:stmt"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "conflicts 中规则都已声明",
      dsl: "conflicts [[expr, stmt]]\nrule expr: /\\d+/\nrule stmt: expr",
      expected_kinds: [],
      absent_kinds: [
        "ConflictUndeclaredRule:expr", "ConflictUndeclaredRule:stmt",
      ],
      expected_count: Some(0),
    },
  ]
}

///|
fn get_validator_lenient_cases() -> Array[LenientValidationCase] {
  [
    {
      name: "deprecated 规则之间互引不报警",
      dsl: "@deprecated rule old_a: /\\d+/\n@deprecated rule old_b: old_a",
      expected_kinds: [],
      absent_kinds: ["DeprecatedRuleUsed:old_a"],
      expected_count: None,
    },
  ]
}

///|
fn get_validator_template_cases() -> Array[ValidationCase] {
  [
    {
      name: "对非模板规则做实例化",
      dsl: "rule list: \",\"\nrule num: /\\d+/\nrule use: list[num]",
      expected_kinds: ["UndefinedTemplateRule:list"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "模板实参个数不匹配",
      dsl: "rule pair[A, B]: \",\"\nrule num: /\\d+/\nrule use: pair[num]",
      expected_kinds: ["ArityMismatch:pair:2:1"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "模板规则被当作普通引用",
      dsl: "rule list[T]: \",\"\nrule use: list",
      expected_kinds: ["TemplateRuleUsedAsRef:list"],
      absent_kinds: [],
      expected_count: Some(1),
    },
  ]
}

///|
fn get_validator_word_and_token_cases() -> Array[ValidationCase] {
  [
    {
      name: "word 指向未定义规则",
      dsl: "word identifier\nrule num: /\\d+/",
      expected_kinds: ["UndefinedWordRule:identifier"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "word 指向的规则必须是 token rule",
      dsl: "word identifier\nrule identifier: /[a-z]+/",
      expected_kinds: ["UndefinedWordRule:identifier"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "token rule 引用了非 token 规则",
      dsl: "token rule trivia: ws\nrule ws: /\\s+/",
      expected_kinds: ["TokenRuleContainsRef:ws"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "独立 token rule 合法",
      dsl: "token rule digit: /\\d+/",
      expected_kinds: [],
      absent_kinds: ["TokenRuleContainsRef:digit"],
      expected_count: Some(0),
    },
  ]
}

///|
fn get_validator_regex_cases() -> Array[ValidationCase] {
  [
    {
      name: "量词前没有原子",
      dsl: "rule expr: /+\\d+/",
      expected_kinds: ["InvalidRegex:+\\d+"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "嵌套量词非法",
      dsl: "rule expr: /a++/",
      expected_kinds: ["InvalidRegex:a++"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "lazy quantifier 合法",
      dsl: "rule expr: /a*?/",
      expected_kinds: [],
      absent_kinds: ["InvalidRegex:a*?"],
      expected_count: Some(0),
    },
    {
      name: "非法重复区间",
      dsl: "rule expr: /a{5,2}/",
      expected_kinds: ["InvalidRegex:a{5,2}"],
      absent_kinds: [],
      expected_count: Some(1),
    },
    {
      name: "合法重复区间",
      dsl: "rule expr: /a{2,5}/",
      expected_kinds: [],
      absent_kinds: ["InvalidRegex:a{2,5}"],
      expected_count: Some(0),
    },
  ]
}

///|
fn get_validator_hint_cases() -> Array[HintCase] {
  [
    {
      name: "start 规则不存在时给出修复提示",
      dsl: "start missing\nrule expr: /\\d+/",
      kind: "UndefinedStartRule:missing",
      expected_hint_substring: "change the 'start' declaration to an existing rule",
    },
    {
      name: "引用未定义规则时给出修复提示",
      dsl: "rule expr: ghost",
      kind: "UndefinedRule:ghost",
      expected_hint_substring: "replace the reference with an existing rule",
    },
    {
      name: "混用 precedence 机制时给出修复提示",
      dsl: "precedence left plus\nrule plus: \"+\"\nrule num: /\\d+/\nrule expr: prec(1, num)",
      kind: "MixedPrecSystems",
      expected_hint_substring: "remove inline 'prec(...)'",
    },
    {
      name: "模板实参个数不匹配时给出修复提示",
      dsl: "rule pair[A, B]: \",\"\nrule num: /\\d+/\nrule use: pair[num]",
      kind: "ArityMismatch:pair:2:1",
      expected_hint_substring: "supply 2 argument(s)",
    },
    {
      name: "模板规则作为普通引用时给出实例化提示",
      dsl: "rule list[T]: \",\"\nrule use: list",
      kind: "TemplateRuleUsedAsRef:list",
      expected_hint_substring: "use 'list[...]' to instantiate the template",
    },
    {
      name: "word 指向非 token 规则时给出修复提示",
      dsl: "word identifier\nrule identifier: /[a-z]+/",
      kind: "UndefinedWordRule:identifier",
      expected_hint_substring: "declare the rule with 'token rule'",
    },
    {
      name: "token rule purity 报错时给出修复提示",
      dsl: "token rule trivia: ws\nrule ws: /\\s+/",
      kind: "TokenRuleContainsRef:ws",
      expected_hint_substring: "declare 'ws' as 'token rule' or inline its pattern",
    },
    {
      name: "conflicts 引用未声明规则时给出修复提示",
      dsl: "conflicts [[expr, stmt]]\nrule expr: /\\d+/",
      kind: "ConflictUndeclaredRule:stmt",
      expected_hint_substring: "remove it from the conflict group",
    },
    {
      name: "supertypes 引用未声明规则时给出修复提示",
      dsl: "supertypes [expr, stmt]\nrule expr: /\\d+/",
      kind: "SupertypeUndeclaredRule:stmt",
      expected_hint_substring: "remove it from the supertype list",
    },
  ]
}

///|
fn get_validator_render_cases() -> Array[RenderCase] {
  [
    {
      name: "UndefinedRule to_string",
      error: {
        rule: "expr",
        kind: ValidationErrorKind::UndefinedRule("ghost"),
        location: None,
        hint: None,
      },
      expected_substrings: ["expr", "ghost"],
    },
    {
      name: "DirectLeftRecursion to_string",
      error: {
        rule: "a",
        kind: ValidationErrorKind::DirectLeftRecursion("a"),
        location: None,
        hint: None,
      },
      expected_substrings: ["direct left recursion", "a"],
    },
    {
      name: "IndirectLeftRecursion to_string",
      error: {
        rule: "b",
        kind: ValidationErrorKind::IndirectLeftRecursion(["a", "b", "a"]),
        location: None,
        hint: None,
      },
      expected_substrings: ["a -> b -> a"],
    },
    {
      name: "DuplicateRule to_string",
      error: {
        rule: "expr",
        kind: ValidationErrorKind::DuplicateRule("expr"),
        location: None,
        hint: None,
      },
      expected_substrings: ["defined more than once", "expr"],
    },
    {
      name: "SupertypeUndeclaredRule to_string",
      error: {
        rule: "<supertypes>",
        kind: ValidationErrorKind::SupertypeUndeclaredRule("stmt"),
        location: None,
        hint: None,
      },
      expected_substrings: ["supertypes", "stmt"],
    },
    {
      name: "DeprecatedRuleUsed to_string",
      error: {
        rule: "new_expr",
        kind: ValidationErrorKind::DeprecatedRuleUsed("old_expr"),
        location: None,
        hint: None,
      },
      expected_substrings: ["deprecated", "old_expr"],
    },
    {
      name: "MixedPrecSystems to_string",
      error: {
        rule: "<grammar>",
        kind: ValidationErrorKind::MixedPrecSystems,
        location: None,
        hint: None,
      },
      expected_substrings: ["precedence", "prec(n,p)"],
    },
    {
      name: "RuleAppArityMismatch to_string 附带 hint",
      error: {
        rule: "use",
        kind: ValidationErrorKind::RuleAppArityMismatch("pair", 2, 1),
        location: None,
        hint: Some(
          "supply 2 argument(s) to 'pair[...]' or update the template parameter list",
        ),
      },
      expected_substrings: [
        "expects 2 argument(s) but got 1", "hint:", "pair[...]",
      ],
    },
    {
      name: "TokenRuleContainsRef to_string 附带 hint",
      error: {
        rule: "trivia",
        kind: ValidationErrorKind::TokenRuleContainsRef("ws"),
        location: None,
        hint: Some("declare 'ws' as 'token rule' or inline its pattern"),
      },
      expected_substrings: ["token rule", "ws", "hint:"],
    },
  ]
}

///|
fn validator_core_test() -> Unit raise {
  run_validation_cases(get_validator_core_cases())
  run_lenient_validation_cases(get_validator_lenient_cases())
}

///|
fn validator_template_test() -> Unit raise {
  run_validation_cases(get_validator_template_cases())
}

///|
fn validator_word_and_token_test() -> Unit raise {
  run_validation_cases(get_validator_word_and_token_cases())
  run_hint_cases(get_validator_hint_cases())
}

///|
fn validator_regex_test() -> Unit raise {
  run_validation_cases(get_validator_regex_cases())
}

///|
fn validator_message_test() -> Unit raise {
  run_render_cases(get_validator_render_cases())
}

///|
fn get_validator_lookahead_cases() -> Array[ValidationCase] {
  [
    {
      name: "末尾 Not 断言合法",
      dsl: "start s\nrule s: \"a\" !\"b\"",
      expected_kinds: [],
      absent_kinds: ["LookaheadNonTailAssertion", "LookaheadMixedAssertions"],
      expected_count: Some(0),
    },
    {
      name: "末尾 And 断言合法",
      dsl: "start s\nrule s: \"a\" &\"b\"",
      expected_kinds: [],
      absent_kinds: ["LookaheadNonTailAssertion", "LookaheadMixedAssertions"],
      expected_count: Some(0),
    },
    {
      name: "末尾多个同类断言合法",
      dsl: "start s\nrule s: \"a\" !\"b\" !\"c\"",
      expected_kinds: [],
      absent_kinds: ["LookaheadNonTailAssertion", "LookaheadMixedAssertions"],
      expected_count: Some(0),
    },
    {
      name: "非末尾 Not 断言报错",
      dsl: "start s\nrule s: \"a\" !\"b\" \"c\"",
      expected_kinds: ["LookaheadNonTailAssertion"],
      absent_kinds: ["LookaheadMixedAssertions"],
      expected_count: Some(1),
    },
    {
      name: "非末尾 And 断言报错",
      dsl: "start s\nrule s: &\"a\" \"b\"",
      expected_kinds: ["LookaheadNonTailAssertion"],
      absent_kinds: ["LookaheadMixedAssertions"],
      expected_count: Some(1),
    },
    {
      name: "混用 & 和 ! 断言报错",
      dsl: "start s\nrule s: \"a\" &\"b\" !\"c\"",
      expected_kinds: ["LookaheadMixedAssertions"],
      absent_kinds: ["LookaheadNonTailAssertion"],
      expected_count: Some(1),
    },
  ]
}

///|
fn get_validator_lookahead_hint_cases() -> Array[HintCase] {
  [
    {
      name: "非末尾断言给出位置提示",
      dsl: "start s\nrule s: \"a\" !\"b\" \"c\"",
      kind: "LookaheadNonTailAssertion",
      expected_hint_substring: "reduce point",
    },
    {
      name: "混用断言给出优先级提示",
      dsl: "start s\nrule s: \"a\" &\"b\" !\"c\"",
      kind: "LookaheadMixedAssertions",
      expected_hint_substring: "'&' constraint takes effect",
    },
  ]
}

///|
fn get_validator_lookahead_render_cases() -> Array[RenderCase] {
  [
    {
      name: "LookaheadNonTailAssertion to_string",
      error: {
        rule: "s",
        kind: ValidationErrorKind::LookaheadNonTailAssertion,
        location: None,
        hint: None,
      },
      expected_substrings: ["assertion", "tail position", "s"],
    },
    {
      name: "LookaheadMixedAssertions to_string",
      error: {
        rule: "s",
        kind: ValidationErrorKind::LookaheadMixedAssertions,
        location: None,
        hint: None,
      },
      expected_substrings: ["&", "!", "s"],
    },
  ]
}

///|
fn validator_lookahead_test() -> Unit raise {
  run_validation_cases(get_validator_lookahead_cases())
  run_hint_cases(get_validator_lookahead_hint_cases())
  run_render_cases(get_validator_lookahead_render_cases())
}

///|
test "grammar_validation_suite" {
  validator_core_test()
  validator_template_test()
  validator_word_and_token_test()
  validator_regex_test()
  validator_message_test()
  validator_lookahead_test()
}
