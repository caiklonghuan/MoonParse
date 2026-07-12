///|
fn lint_engine_rule(
  id : String,
  query : String,
  enabled? : Bool = true,
  severity? : String = "warning",
  diagnostic_capture? : String = "value",
  fix? : String = "",
) -> String {
  "{" +
  "\"id\":\"" +
  id +
  "\"," +
  "\"query\":\"" +
  query +
  "\"," +
  "\"enabledByDefault\":" +
  enabled.to_string() +
  "," +
  "\"severity\":\"" +
  severity +
  "\"," +
  "\"message\":\"message " +
  id +
  "\"," +
  "\"diagnosticCapture\":\"" +
  diagnostic_capture +
  "\"" +
  fix +
  "}"
}

///|
fn lint_engine_fix(
  operation : String,
  target? : String = "value",
  template? : String = "",
) -> String {
  ",\"fix\":{" +
  "\"title\":\"Fix value\"," +
  "\"operation\":\"" +
  operation +
  "\"," +
  "\"targetCapture\":\"" +
  target +
  "\"," +
  "\"template\":\"" +
  template +
  "\"}"
}

///|
fn lint_engine_source(
  rules : Array[String],
  queries : Array[(String, String)],
  rule_set_enabled? : Bool = true,
) -> LanguagePackSource {
  let manifest =
    #|{
    #|  "schemaVersion": 1,
    #|  "id": "lint-test",
    #|  "name": "Lint Test",
    #|  "version": "0.1.0",
    #|  "maturity": "experimental",
    #|  "entryRule": "document",
    #|  "extensions": [".lint"],
    #|  "compatibility": {
    #|    "minimumMoonParseVersion": "0.1.0",
    #|    "maximumMoonParseVersionExclusive": "0.2.0"
    #|  },
    #|  "grammar": { "path": "grammar/main.grammar", "format": "dsl" },
    #|  "lint": { "ruleSets": ["lint/recommended.json"] },
    #|  "corpus": { "directory": "corpus", "format": "moonparse-corpus-v1" }
    #|}
  let ruleset = "{" +
    "\"schemaVersion\":1," +
    "\"id\":\"recommended\"," +
    "\"enabledByDefault\":" +
    rule_set_enabled.to_string() +
    "," +
    "\"rules\":[" +
    rules.join(",") +
    "]}"
  let files : Map[String, Bytes] = {}
  files["grammar/main.grammar"] = @utf8.encode(
    "start document\nrule document: value | pair\nrule pair: value \",\" value\nrule value: /[A-Za-z0-9]+/",
  )
  files["lint/recommended.json"] = @utf8.encode(ruleset)
  files["corpus/basic.txt"] = @utf8.encode(
    "====\nvalue\n====\n42\n----\nerror: ok\nsexp-contains:\n  value\n",
  )
  for item in queries {
    files[item.0] = @utf8.encode(item.1)
  }
  LanguagePackSource::new(manifest, files)
}

///|
fn lint_engine_bundle(
  rules : Array[String],
  queries : Array[(String, String)],
  rule_set_enabled? : Bool = true,
) -> LanguageBundle {
  build_bundle(
    lint_engine_source(rules, queries, rule_set_enabled~),
    PackBuildOptions::default(),
  ).unwrap()
}

///|
test "lint engine/config precedence and severity override" {
  let query_path = "queries/lint/value.scm"
  let bundle = lint_engine_bundle(
    [lint_engine_rule("value-rule", query_path)],
    [(query_path, "(value) @value")],
  )
  let root = parse_bundle(bundle, "42").unwrap()
  let diagnostics = lint_bundle(bundle, root, "42")
  assert_eq(diagnostics.length(), 1)
  assert_true(diagnostics[0].severity == LintWarning)
  assert_eq(diagnostics[0].rule_id, "lint-test/recommended/value-rule")
  assert_eq(diagnostics[0].start_byte, 0)
  assert_eq(diagnostics[0].end_byte, 2)
  let disabled = { ..LintOptions::default(), enabled: false }
  assert_true(lint_bundle(bundle, root, "42", options=disabled).is_empty())
  let rule_sets : Map[String, Bool] = { "lint-test/recommended": false }
  let set_disabled = { ..LintOptions::default(), rule_sets, }
  assert_true(lint_bundle(bundle, root, "42", options=set_disabled).is_empty())
  set_disabled.rules["lint-test/recommended/value-rule"] = LintLevel(LintError)
  let enabled_by_rule = lint_bundle(bundle, root, "42", options=set_disabled)
  assert_eq(enabled_by_rule.length(), 1)
  assert_true(enabled_by_rule[0].severity == LintError)
  set_disabled.rules["lint-test/recommended/value-rule"] = LintOff
  assert_true(lint_bundle(bundle, root, "42", options=set_disabled).is_empty())
}

///|
test "lint engine/explicit severity enables default-off rule" {
  let query_path = "queries/lint/value.scm"
  let bundle = lint_engine_bundle(
    [lint_engine_rule("value-rule", query_path, enabled=false)],
    [(query_path, "(value) @value")],
  )
  let root = parse_bundle(bundle, "42").unwrap()
  assert_true(lint_bundle(bundle, root, "42").is_empty())
  let options = LintOptions::default()
  options.rules["lint-test/recommended/value-rule"] = LintLevel(LintHint)
  let diagnostics = lint_bundle(bundle, root, "42", options~)
  assert_eq(diagnostics.length(), 1)
  assert_true(diagnostics[0].severity == LintHint)
}

///|
test "lint engine/ruleset override enables default-off ruleset" {
  let query_path = "queries/lint/value.scm"
  let bundle = lint_engine_bundle(
    [lint_engine_rule("value-rule", query_path)],
    [(query_path, "(value) @value")],
    rule_set_enabled=false,
  )
  let root = parse_bundle(bundle, "42").unwrap()
  assert_true(lint_bundle(bundle, root, "42").is_empty())
  let options = LintOptions::default()
  options.rule_sets["lint-test/recommended"] = true
  assert_eq(lint_bundle(bundle, root, "42", options~).length(), 1)
}

///|
test "lint engine/four rewrite operations and deterministic sorting" {
  let query_path = "queries/lint/value.scm"
  let rules = [
    lint_engine_rule(
      "after",
      query_path,
      fix=lint_engine_fix("insertAfter", template="z"),
    ),
    lint_engine_rule(
      "before",
      query_path,
      fix=lint_engine_fix("insertBefore", template="a"),
    ),
    lint_engine_rule("delete", query_path, fix=lint_engine_fix("delete")),
    lint_engine_rule(
      "replace",
      query_path,
      fix=lint_engine_fix("replace", template="${value}$$"),
    ),
  ]
  let bundle = lint_engine_bundle(rules, [(query_path, "(value) @value")])
  let root = parse_bundle(bundle, "42").unwrap()
  let diagnostics = lint_bundle(bundle, root, "42")
  assert_eq(diagnostics.length(), 4)
  assert_true(
    diagnostics.map(fn(item) { item.rule_id }) ==
    [
      "lint-test/recommended/after", "lint-test/recommended/before", "lint-test/recommended/delete",
      "lint-test/recommended/replace",
    ],
  )
  assert_true(
    diagnostics[0].fix.unwrap().edit ==
    { start_byte: 2, end_byte: 2, replacement: "z" },
  )
  assert_true(
    diagnostics[1].fix.unwrap().edit ==
    { start_byte: 0, end_byte: 0, replacement: "a" },
  )
  assert_true(
    diagnostics[2].fix.unwrap().edit ==
    { start_byte: 0, end_byte: 2, replacement: "" },
  )
  assert_true(
    diagnostics[3].fix.unwrap().edit ==
    { start_byte: 0, end_byte: 2, replacement: "42$" },
  )
}

///|
test "lint engine/groups matches and deduplicates identical diagnostics" {
  let query_path = "queries/lint/value.scm"
  let bundle = lint_engine_bundle(
    [lint_engine_rule("value-rule", query_path)],
    [(query_path, "(value) @value\n(value) @value")],
  )
  let root = parse_bundle(bundle, "2,1").unwrap()
  let diagnostics = lint_bundle(bundle, root, "2,1")
  assert_eq(diagnostics.length(), 2)
  assert_eq(diagnostics[0].start_byte, 0)
  assert_eq(diagnostics[1].start_byte, 2)
}

///|
test "lint engine/duplicate diagnostic capture ignores match" {
  let query_path = "queries/lint/value.scm"
  let bundle = lint_engine_bundle(
    [lint_engine_rule("value-rule", query_path, diagnostic_capture="diag")],
    [(query_path, "(document (value) @diag) @diag")],
  )
  let root = parse_bundle(bundle, "42").unwrap()
  assert_true(lint_bundle(bundle, root, "42").is_empty())
}

///|
test "lint engine/duplicate fix target keeps diagnostic without fix" {
  let query_path = "queries/lint/value.scm"
  let bundle = lint_engine_bundle(
    [
      lint_engine_rule(
        "value-rule",
        query_path,
        diagnostic_capture="diag",
        fix=lint_engine_fix("replace", target="target", template="x"),
      ),
    ],
    [(query_path, "(pair (value) @target (value) @target) @diag")],
  )
  let root = parse_bundle(bundle, "2,1").unwrap()
  let diagnostics = lint_bundle(bundle, root, "2,1")
  assert_eq(diagnostics.length(), 1)
  assert_true(diagnostics[0].fix is None)
}

///|
test "lint engine/fix target may differ from diagnostic capture" {
  let query_path = "queries/lint/value.scm"
  let bundle = lint_engine_bundle(
    [
      lint_engine_rule(
        "pair-rule",
        query_path,
        diagnostic_capture="diag",
        fix=lint_engine_fix("replace", target="target", template="x"),
      ),
    ],
    [(query_path, "(pair (value) @target (value) @other) @diag")],
  )
  let root = parse_bundle(bundle, "2,1").unwrap()
  let diagnostics = lint_bundle(bundle, root, "2,1")
  assert_eq(diagnostics.length(), 1)
  assert_eq(diagnostics[0].start_byte, 0)
  assert_eq(diagnostics[0].end_byte, 3)
  assert_true(
    diagnostics[0].fix.unwrap().edit ==
    { start_byte: 0, end_byte: 1, replacement: "x" },
  )
}

///|
test "lint engine/old bundle without lint returns empty" {
  let bundle = build_bundle(test_source(), PackBuildOptions::default()).unwrap()
  let root = parse_bundle(bundle, "42").unwrap()
  assert_true(lint_bundle(bundle, root, "42").is_empty())
}

///|
test "lint contract/delete requires empty template" {
  let query_path = "queries/lint/value.scm"
  let errors = build_bundle(
    lint_engine_source(
      [
        lint_engine_rule(
          "delete",
          query_path,
          fix=lint_engine_fix("delete", template="not-empty"),
        ),
      ],
      [(query_path, "(value) @value")],
    ),
    PackBuildOptions::default(),
  ).unwrap_err()
  assert_true(errors.any(fn(error) { error.code == "PACK108" }))
}
