///|
test "language packs/sample manifests load" {
  assert_eq(builtin_json_pack.manifest.id, "json")
  assert_eq(builtin_python_pack.manifest.id, "python")
  assert_eq(builtin_moonbit_pack.manifest.id, "moonbit")
  assert_true(builtin_json_pack.corpus.length() > 0)
  assert_true(builtin_python_pack.corpus.length() > 0)
  assert_true(builtin_moonbit_pack.corpus.length() > 0)
}

///|
test "language packs/MoonBit ambiguity is explicit warning" {
  let diagnostics = @languagepack.check_pack(
    embedded_moonbit_pack_source(),
    builtin_pack_options(),
  )
  assert_true(
    diagnostics.any(fn(diagnostic) {
      diagnostic.code == "PACK307" &&
      diagnostic.severity == @languagepack.PackSeverity::Warning
    }),
  )
}

///|
test "language packs/JSON bundle parses and exposes compiled query" {
  let input = "{\"nested\": [1, 2]}"
  let root = @languagepack.parse_bundle(builtin_json_bundle, input).unwrap()
  assert_true(builtin_json_bundle.highlights_query is Some(_))
  let captures = @languagepack.exec_bundle_query(
    builtin_json_bundle,
    @languagepack.BundleQueryKind::Highlights,
    root,
    input,
  ).unwrap()
  assert_true(captures.length() > 0)
}

///|
test "language packs/Python bundle resolves indent scanner" {
  let provider : @languagepack.PackScannerProvider = {
    id: "python-indent",
    api_version: 1,
    create: python_indent_scanner,
  }
  let input = "def answer():\n    return 42\n"
  let root = @languagepack.parse_bundle(
    builtin_python_bundle,
    input,
    scanner_provider=provider,
  ).unwrap()
  assert_true(root.children.length() > 0)
  let captures = @languagepack.exec_bundle_query(
    builtin_python_bundle,
    @languagepack.BundleQueryKind::Highlights,
    root,
    input,
  ).unwrap()
  assert_true(captures.length() > 0)
}

///|
test "language packs/MoonBit bundle parses and queries source" {
  let input = "pub fn answer() -> Int { 42 }\n"
  let root = @languagepack.parse_bundle(builtin_moonbit_bundle, input).unwrap()
  assert_true(root.children.length() > 0)
  let captures = @languagepack.exec_bundle_query(
    builtin_moonbit_bundle,
    @languagepack.BundleQueryKind::Highlights,
    root,
    input,
  ).unwrap()
  assert_true(captures.length() > 0)
  assert_true(builtin_moonbit_bundle.capabilities.modules)
  let module_captures = @languagepack.exec_bundle_query(
    builtin_moonbit_bundle,
    @languagepack.BundleQueryKind::Modules,
    root,
    input,
  ).unwrap()
  assert_true(
    module_captures.any(fn(capture) {
      capture.capture_name == "module.export.candidate" &&
      capture.node.start_byte == 7 &&
      capture.node.end_byte == 13
    }),
  )
}

///|
fn moonbit_has_error_or_missing(node : @runtime.CstNode) -> Bool {
  if node.is_error || node.is_missing {
    return true
  }
  node.children.any(moonbit_has_error_or_missing)
}

///|
test "language packs/MoonBit function visibility parses without recovery" {
  for
    input in [
      "fn run() {}\n", "pub fn run() {}\n", "priv fn run() {}\n", "pub(all) fn run() {}\n",
      "pub(readonly) fn run() {}\n", "pub(open) fn run() {}\n",
    ] {
    let root = @languagepack.parse_bundle(builtin_moonbit_bundle, input).unwrap()
    assert_false(moonbit_has_error_or_missing(root))
  }
  let public_sexp = moonbit_sexp("pub fn run() {}\n")
  assert_true(public_sexp.contains("(visibility)"))
  assert_false(public_sexp.contains("(ERROR)"))
}

///|
test "language packs/JSON recommended lint rules and fix" {
  let input = "{\"\": -0, \"ok\": 1}"
  let root = @languagepack.parse_bundle(builtin_json_bundle, input).unwrap()
  let diagnostics = @languagepack.lint_bundle(builtin_json_bundle, root, input)
  assert_eq(diagnostics.length(), 2)
  assert_eq(diagnostics[0].rule_id, "json/recommended/empty-object-key")
  assert_true(diagnostics[0].fix is None)
  assert_eq(diagnostics[1].rule_id, "json/recommended/negative-zero")
  let fix = diagnostics[1].fix.unwrap()
  assert_eq(fix.title, "Replace -0 with 0")
  assert_true(fix.edit == { start_byte: 5, end_byte: 7, replacement: "0" })
  let fixed = input[:fix.edit.start_byte].to_owned() +
    fix.edit.replacement +
    input[fix.edit.end_byte:].to_owned()
  let fixed_root = @languagepack.parse_bundle(builtin_json_bundle, fixed).unwrap()
  assert_eq(
    @languagepack.lint_bundle(builtin_json_bundle, fixed_root, fixed).length(),
    1,
  )
}

///|
test "language packs/MoonBit recommended lint configuration" {
  let input = "let value = -0\n// TODO: demo\n"
  let root = @languagepack.parse_bundle(builtin_moonbit_bundle, input).unwrap()
  let diagnostics = @languagepack.lint_bundle(
    builtin_moonbit_bundle, root, input,
  )
  assert_eq(diagnostics.length(), 2)
  assert_eq(diagnostics[0].rule_id, "moonbit/recommended/negative-zero")
  assert_eq(diagnostics[1].rule_id, "moonbit/recommended/todo-comment")
  assert_true(
    diagnostics[1].severity == @languagepack.LintSeverity::LintInformation,
  )
  let options = @languagepack.LintOptions::default()
  options.rules["moonbit/recommended/negative-zero"] = @languagepack.LintRuleSetting::LintOff
  options.rules["moonbit/recommended/todo-comment"] = @languagepack.LintRuleSetting::LintLevel(
    @languagepack.LintSeverity::LintError,
  )
  let overridden = @languagepack.lint_bundle(
    builtin_moonbit_bundle,
    root,
    input,
    options~,
  )
  assert_eq(overridden.length(), 1)
  assert_true(overridden[0].severity == @languagepack.LintSeverity::LintError)
}

///|
test "language packs/all sample bundles dual-format round trip" {
  for
    bundle in [
      builtin_json_bundle, builtin_python_bundle, builtin_moonbit_bundle,
    ] {
    let restored = match
      @languagepack.bundle_from_json(@languagepack.bundle_to_json(bundle)) {
      Ok(value) => value
      Err(errors) =>
        fail(
          "bundle round trip failed for \{bundle.pack_id}: \{to_repr(errors)}",
        )
    }
    assert_eq(restored.pack_id, bundle.pack_id)
    assert_true(
      @tablegen.serialize_table(restored.table) ==
      @tablegen.serialize_table(bundle.table),
    )
  }
}

///|
test "language packs/legacy parser facades use bundle tables" {
  assert_true(parse_json("{\"ok\": true}") is Ok(_))
  assert_true(parse_python("x = 1\n") is Ok(_))
  assert_true(parse_moonbit("let x = 1\n") is Ok(_))
  assert_eq(json_grammar, builtin_json_pack.grammar_source)
  assert_eq(python_grammar, builtin_python_pack.grammar_source)
  assert_eq(moonbit_grammar, builtin_moonbit_pack.grammar_source)
}
