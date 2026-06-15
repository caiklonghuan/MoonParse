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
        fail("bundle round trip failed for \{bundle.pack_id}: \{errors}")
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
