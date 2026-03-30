// 测试 validator.mbt 中的 validate_grammar 函数

// ─── 辅助 ──────────────────────────────────────────────────────────────────────

///|
fn parse_ok(dsl : String) -> Grammar {
  match parse_grammar(dsl) {
    Success(g) => g
    Error(err) => abort("parse failed: \{err.message}")
  }
}

///|
fn kinds(errors : Array[ValidationError]) -> Array[String] {
  errors.map(fn(e) {
    match e.kind {
      ValidationErrorKind::UndefinedRule(r) => "UndefinedRule:\{r}"
      ValidationErrorKind::UndefinedStartRule(r) => "UndefinedStartRule:\{r}"
      ValidationErrorKind::DirectLeftRecursion(r) => "DirectLeft:\{r}"
      ValidationErrorKind::IndirectLeftRecursion(_) => "IndirectLeft"
      ValidationErrorKind::UnreachableRule(r) => "Unreachable:\{r}"
    }
  })
}

// ─── 正常语法：无错 ────────────────────────────────────────────────────────────

///|
test "validate_valid_grammar" {
  let dsl = "start expr\nrule expr: term (\"+\" term)*\nrule term: /\\d+/"
  let g = parse_ok(dsl)
  let errs = validate_grammar(g)
  assert_eq(errs.length(), 0)
}

// ─── start 规则不存在 ──────────────────────────────────────────────────────────

///|
test "validate_undefined_start" {
  let g = parse_ok("start missing\nrule expr: /\\d+/")
  let errs = validate_grammar(g)
  assert_eq(errs.length(), 1)
  let k = kinds(errs)
  assert_true(k.contains("UndefinedStartRule:missing"))
}

// ─── 引用未定义规则 ─────────────────────────────────────────────────────────────

///|
test "validate_undefined_rule_ref" {
  let g = parse_ok("rule expr: ghost")
  let errs = validate_grammar(g)
  // 应报告 UndefinedRule:ghost
  let k = kinds(errs)
  assert_true(arr_string_contains(k, "UndefinedRule:ghost"))
}

///|
test "validate_multiple_undefined_refs" {
  let g = parse_ok("rule expr: a b c")
  let errs = validate_grammar(g)
  let k = kinds(errs)
  assert_true(arr_string_contains(k, "UndefinedRule:a"))
  assert_true(arr_string_contains(k, "UndefinedRule:b"))
  assert_true(arr_string_contains(k, "UndefinedRule:c"))
}

// ─── 直接左递归 ─────────────────────────────────────────────────────────────────

///|
test "validate_direct_left_recursion" {
  // A -> A "+" B
  let g = parse_ok("rule expr: expr \"+\" /\\d+/")
  let errs = validate_grammar(g)
  let k = kinds(errs)
  assert_true(arr_string_contains(k, "DirectLeft:expr"))
}

///|
test "validate_direct_left_recursion_in_choice" {
  // A -> A | B
  let g = parse_ok("rule expr: expr | /\\d+/")
  let errs = validate_grammar(g)
  let k = kinds(errs)
  assert_true(arr_string_contains(k, "DirectLeft:expr"))
}

// ─── 间接左递归 ─────────────────────────────────────────────────────────────────

///|
test "validate_indirect_left_recursion" {
  // A -> B, B -> A
  let g = parse_ok("rule a: b\nrule b: a")
  let errs = validate_grammar(g)
  let k = kinds(errs)
  // 应报告 IndirectLeft
  let mut has_indirect = false
  for s in k {
    if s == "IndirectLeft" {
      has_indirect = true
    }
  }
  assert_true(has_indirect)
}

// ─── 可达性分析 ─────────────────────────────────────────────────────────────────

///|
test "validate_unreachable_rule" {
  let g = parse_ok("start expr\nrule expr: /\\d+/\nrule orphan: /[a-z]/")
  let errs = validate_grammar(g)
  let k = kinds(errs)
  assert_true(arr_string_contains(k, "Unreachable:orphan"))
  // expr 本身可达，不应出现在错误中
  let mut expr_unreachable = false
  for s in k {
    if s == "Unreachable:expr" {
      expr_unreachable = true
    }
  }
  assert_true(expr_unreachable == false)
}

///|
test "validate_no_unreachable_without_start" {
  // 没有 start 声明时不做可达性检查
  let g = parse_ok("rule orphan: /[a-z]/\nrule other: /\\d+/")
  let errs = validate_grammar(g)
  let k = kinds(errs)
  let mut has_unreachable = false
  for s in k {
    if s.length() >= 11 && s[0:11].to_string() == "Unreachable" {
      has_unreachable = true
    }
  }
  assert_true(has_unreachable == false)
}

///|
test "validate_transitive_reachability" {
  // start -> a -> b -> c，d 不可达
  let g = parse_ok(
    "start a\nrule a: b\nrule b: c\nrule c: /\\d+/\nrule d: /[a-z]/",
  )
  let errs = validate_grammar(g)
  let k = kinds(errs)
  assert_true(arr_string_contains(k, "Unreachable:d"))
  assert_true(not(arr_string_contains(k, "Unreachable:a")))
  assert_true(not(arr_string_contains(k, "Unreachable:b")))
  assert_true(not(arr_string_contains(k, "Unreachable:c")))
}

// ─── to_string ─────────────────────────────────────────────────────────────────

///|
test "validate_error_to_string" {
  let e1 : ValidationError = {
    rule: "expr",
    kind: ValidationErrorKind::UndefinedRule("ghost"),
  }
  assert_true(e1.to_string().length() > 0)

  let e2 : ValidationError = {
    rule: "a",
    kind: ValidationErrorKind::DirectLeftRecursion("a"),
  }
  assert_true(e2.to_string().length() > 0)

  let e3 : ValidationError = {
    rule: "b",
    kind: ValidationErrorKind::IndirectLeftRecursion(["a", "b", "a"]),
  }
  assert_true(e3.to_string().length() > 0)
}

// ─── 辅助（测试内部用） ───────────────────────────────────────────────────────

///|
fn arr_string_contains(arr : Array[String], s : String) -> Bool {
  for item in arr {
    if item == s {
      return true
    }
  }
  false
}
