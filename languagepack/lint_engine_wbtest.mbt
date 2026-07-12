///|
fn lint_wb_leaf(start_byte : Int, end_byte : Int) -> @runtime.CstNode {
  @runtime.CstNode::leaf(
    0,
    true,
    start_byte,
    end_byte,
    { row: 0, column: start_byte },
    { row: 0, column: end_byte },
    0,
    end_byte,
    false,
    false,
  )
}

///|
fn lint_wb_capture(
  name : String,
  start_byte : Int,
  end_byte : Int,
) -> @query.CaptureResult {
  { match_id: 0, capture_name: name, node: lint_wb_leaf(start_byte, end_byte) }
}

///|
test "lint engine/template expansion rejects missing duplicate and invalid captures" {
  let source = "alpha"
  let missing : Map[String, Array[@query.CaptureResult]] = {}
  assert_true(lint_expand_template("${value}", missing, source) == None)
  let duplicate : Map[String, Array[@query.CaptureResult]] = {
    "value": [lint_wb_capture("value", 0, 1), lint_wb_capture("value", 1, 2)],
  }
  assert_true(lint_expand_template("${value}", duplicate, source) == None)
  let invalid : Map[String, Array[@query.CaptureResult]] = {
    "value": [lint_wb_capture("value", 0, 99)],
  }
  assert_true(lint_expand_template("${value}", invalid, source) == None)
}

///|
test "lint engine/template expansion preserves raw text and dollar escapes" {
  let source = "alpha"
  let captures : Map[String, Array[@query.CaptureResult]] = {
    "value": [lint_wb_capture("value", 0, 5)],
  }
  assert_true(
    lint_expand_template("before-${value}-$$-after", captures, source) ==
    Some("before-alpha-$-after"),
  )
  let unicode_source = "\u{4F60}\u{597D}"
  let unicode_captures : Map[String, Array[@query.CaptureResult]] = {
    "value": [lint_wb_capture("value", 0, unicode_source.length())],
  }
  assert_true(
    lint_expand_template("${value}", unicode_captures, unicode_source) ==
    Some("\u{4F60}\u{597D}"),
  )
}

///|
test "lint engine/dedup removes conflicting fixes" {
  let left : LintDiagnostic = {
    rule_id: "pack/set/rule",
    message: "message",
    severity: LintWarning,
    start_byte: 0,
    end_byte: 1,
    fix: Some({
      title: "fix",
      edit: { start_byte: 0, end_byte: 1, replacement: "a" },
    }),
  }
  let right = {
    ..left,
    fix: Some({
      title: "fix",
      edit: { start_byte: 0, end_byte: 1, replacement: "b" },
    }),
  }
  let diagnostics = lint_sort_and_deduplicate([right, left])
  assert_eq(diagnostics.length(), 1)
  assert_true(diagnostics[0].fix is None)
}

///|
test "lint engine/no-op edits are suppressed" {
  let source = "alpha"
  let captures : Map[String, Array[@query.CaptureResult]] = {
    "value": [lint_wb_capture("value", 0, 5)],
  }
  assert_true(
    lint_build_fix(
      {
        title: "same",
        operation: Replace,
        target_capture: "value",
        template: "${value}",
      },
      captures,
      source,
    )
    is None,
  )
  assert_true(
    lint_build_fix(
      {
        title: "empty",
        operation: InsertBefore,
        target_capture: "value",
        template: "",
      },
      captures,
      source,
    )
    is None,
  )
}
