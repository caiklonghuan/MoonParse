///|
fn test_manifest(
  id? : String = "test-lang",
  entry? : String = "document",
  version? : String = "0.1.0",
  grammar_path? : String = "grammar/main.grammar",
  scanner? : String = "",
  allow_ambiguous? : Bool = false,
) -> String {
  let scanner_json = if scanner.is_empty() {
    ""
  } else {
    ",\"scanner\":{\"id\":\"" + scanner + "\",\"apiVersion\":1}"
  }
  "{" +
  "\"schemaVersion\":1," +
  "\"id\":\"" +
  id +
  "\"," +
  "\"name\":\"Test Language\"," +
  "\"version\":\"" +
  version +
  "\"," +
  "\"maturity\":\"experimental\"," +
  "\"entryRule\":\"" +
  entry +
  "\"," +
  "\"extensions\":[\".test\"]," +
  "\"grammar\":{\"path\":\"" +
  grammar_path +
  "\",\"format\":\"dsl\"}," +
  "\"compatibility\":{\"minimumMoonParseVersion\":\"0.1.0\",\"maximumMoonParseVersionExclusive\":\"0.2.0\"}," +
  "\"queries\":{\"highlights\":\"queries/highlights.scm\"}," +
  "\"build\":{\"allowAmbiguousConflicts\":" +
  allow_ambiguous.to_string() +
  "}" +
  scanner_json +
  "}"
}

///|
fn test_source(
  manifest? : String = test_manifest(),
  grammar? : String = "start document\nrule document: number\nrule number: /[0-9]+/",
  query? : String = "(number) @number",
  corpus? : String = "====\nnumber\n====\n42\n----\nerror: ok\nsexp-contains:\n  number\n",
) -> LanguagePackSource {
  let files : Map[String, Bytes] = Map::new()
  files["grammar/main.grammar"] = @utf8.encode(grammar)
  files["queries/highlights.scm"] = @utf8.encode(query)
  files["corpus/basic.txt"] = @utf8.encode(corpus)
  LanguagePackSource::new(manifest, files)
}

///|
fn test_lint_ruleset(
  id? : String = "recommended",
  rule_id? : String = "normalize-negative-zero",
  severity? : String = "warning",
  diagnostic_capture? : String = "value",
  query_path? : String = "queries/lint/normalize.scm",
  duplicate_rule? : Bool = false,
  fix? : String = ",\"fix\":{\"title\":\"Replace with 0\",\"operation\":\"replace\",\"targetCapture\":\"value\",\"template\":\"0\"}",
) -> String {
  let rule = "{" +
    "\"id\":\"" +
    rule_id +
    "\"," +
    "\"query\":\"" +
    query_path +
    "\"," +
    "\"enabledByDefault\":true," +
    "\"severity\":\"" +
    severity +
    "\"," +
    "\"message\":\"Use 0 instead of -0\"," +
    "\"diagnosticCapture\":\"" +
    diagnostic_capture +
    "\"" +
    fix +
    "}"
  let duplicate = if duplicate_rule { "," + rule } else { "" }
  "{" +
  "\"schemaVersion\":1," +
  "\"id\":\"" +
  id +
  "\"," +
  "\"enabledByDefault\":true," +
  "\"rules\":[" +
  rule +
  duplicate +
  "]}"
}

///|
fn test_lint_source(
  ruleset? : String = test_lint_ruleset(),
  lint_query? : String = "(number) @value",
) -> LanguagePackSource {
  let manifest = test_manifest().replace(
    old="\"build\":{",
    new="\"lint\":{\"ruleSets\":[\"lint/recommended.json\"]},\"build\":{",
  )
  let source = test_source(manifest~)
  source.files["lint/recommended.json"] = @utf8.encode(ruleset)
  source.files["queries/lint/normalize.scm"] = @utf8.encode(lint_query)
  source
}

///|
test "manifest/default resources and schema" {
  let manifest = load_manifest(test_manifest()).unwrap()
  assert_eq(manifest.schema_version, 1)
  assert_eq(manifest.grammar.path, "grammar/main.grammar")
  assert_eq(manifest.corpus.format, "moonparse-corpus-v1")
  assert_true(manifest.lint.rule_sets.is_empty())
}

///|
test "manifest/lint ruleset resources" {
  let manifest = load_manifest(test_lint_source().manifest).unwrap()
  assert_eq(manifest.lint.rule_sets, ["lint/recommended.json"])
}

///|
test "manifest/rejects invalid id semver and path" {
  let bad = test_manifest(
    id="Bad_ID",
    version="bad",
    grammar_path="../escape.grammar",
  )
  let errors = load_manifest(bad).unwrap_err()
  assert_true(errors.length() >= 2)
  assert_true(has_pack_errors(errors))
}

///|
test "manifest/rejects unknown schema and duplicate extension" {
  let bad = test_manifest()
    .replace(old="\"schemaVersion\":1", new="\"schemaVersion\":2")
    .replace(old="[\".test\"]", new="[\".test\",\".test\"]")
  let errors = load_manifest(bad).unwrap_err()
  assert_true(errors.any(fn(error) { error.code == "PACK101" }))
  assert_true(errors.any(fn(error) { error.code == "PACK107" }))
}

///|
test "load_pack/default query and corpus" {
  let pack = load_pack(test_source()).unwrap()
  assert_eq(pack.manifest.id, "test-lang")
  assert_true(pack.highlights_query is Some(_))
  assert_eq(pack.corpus.length(), 1)
  assert_eq(pack.corpus[0].source, "42")
}

///|
test "load_pack/rejects missing declared query" {
  let source = test_source()
  source.files.remove("queries/highlights.scm")
  let errors = load_pack(source).unwrap_err()
  assert_true(errors.any(fn(error) { error.code == "PACK203" }))
}

///|
test "load_pack/loads lint ruleset and query source" {
  let pack = load_pack(test_lint_source()).unwrap()
  assert_eq(pack.lint_rule_sets.length(), 1)
  assert_eq(pack.lint_rule_sets[0].id, "recommended")
  assert_eq(
    pack.lint_rule_sets[0].rules[0].global_id,
    "test-lang/recommended/normalize-negative-zero",
  )
  assert_eq(pack.lint_rule_sets[0].rules[0].query_source, "(number) @value")
  assert_true(pack.lint_rule_sets[0].rules[0].compiled_query is None)
}

///|
test "load_pack/rejects missing lint ruleset and query" {
  let missing_ruleset = test_lint_source()
  missing_ruleset.files.remove("lint/recommended.json")
  let ruleset_errors = load_pack(missing_ruleset).unwrap_err()
  assert_true(ruleset_errors.any(fn(error) { error.code == "PACK205" }))
  let missing_query = test_lint_source()
  missing_query.files.remove("queries/lint/normalize.scm")
  let query_errors = load_pack(missing_query).unwrap_err()
  assert_true(
    query_errors.any(fn(error) {
      error.code == "PACK203" && error.path == "queries/lint/normalize.scm"
    }),
  )
}

///|
test "load_pack/rejects invalid lint metadata" {
  let errors = load_pack(
    test_lint_source(
      ruleset=test_lint_ruleset(severity="fatal", diagnostic_capture="@bad"),
    ),
  ).unwrap_err()
  assert_true(errors.any(fn(error) { error.code == "PACK108" }))
  let id_errors = load_pack(
    test_lint_source(ruleset=test_lint_ruleset(rule_id="bad--id")),
  ).unwrap_err()
  assert_true(id_errors.any(fn(error) { error.code == "PACK108" }))
  let duplicate_rule_errors = load_pack(
    test_lint_source(ruleset=test_lint_ruleset(duplicate_rule=true)),
  ).unwrap_err()
  assert_true(duplicate_rule_errors.any(fn(error) { error.code == "PACK108" }))
}

///|
test "load_pack/rejects duplicate lint ruleset ids" {
  let base = test_lint_source()
  let manifest = base.manifest.replace(
    old="[\"lint/recommended.json\"]",
    new="[\"lint/recommended.json\",\"lint/duplicate.json\"]",
  )
  base.files["lint/duplicate.json"] = @utf8.encode(test_lint_ruleset())
  let source = LanguagePackSource::new(manifest, base.files)
  let errors = load_pack(source).unwrap_err()
  assert_true(errors.any(fn(error) { error.code == "PACK109" }))
}

///|
test "build_bundle/parse and queries" {
  let bundle = build_bundle(test_source(), PackBuildOptions::default()).unwrap()
  assert_true(bundle.capabilities.highlights)
  let root = parse_bundle(bundle, "42").unwrap()
  let query = bundle.highlights_query.unwrap()
  let captures = @query.exec(query, root, "42", bundle.table)
  assert_eq(captures.length(), 1)
}

///|
test "build_bundle/folding query executes and round trips" {
  let manifest = test_manifest().replace(
    old="\"queries\":{\"highlights\":\"queries/highlights.scm\"}",
    new="\"queries\":{\"highlights\":\"queries/highlights.scm\",\"folding\":\"queries/folding.scm\"}",
  )
  let source = test_source(manifest~)
  source.files["queries/folding.scm"] = @utf8.encode("(document) @fold")
  let bundle = build_bundle(source, PackBuildOptions::default()).unwrap()
  assert_true(bundle.capabilities.folding)
  let restored = bundle_from_json(bundle_to_json(bundle)).unwrap()
  assert_true(restored.capabilities.folding)
  let root = parse_bundle(restored, "42").unwrap()
  let captures = exec_bundle_query(restored, Folding, root, "42").unwrap()
  assert_eq(captures.length(), 1)
  assert_eq(captures[0].capture_name, "fold")
}

///|
test "build_bundle/modules query executes and round trips" {
  let manifest = test_manifest().replace(
    old="\"queries\":{\"highlights\":\"queries/highlights.scm\"}",
    new="\"queries\":{\"highlights\":\"queries/highlights.scm\",\"modules\":\"queries/modules.scm\"}",
  )
  let source = test_source(manifest~)
  source.files["queries/modules.scm"] = @utf8.encode("(document) @module.name")
  let bundle = build_bundle(source, PackBuildOptions::default()).unwrap()
  assert_true(bundle.capabilities.modules)
  let restored = bundle_from_json(bundle_to_json(bundle)).unwrap()
  assert_true(restored.capabilities.modules)
  let root = parse_bundle(restored, "42").unwrap()
  let captures = exec_bundle_query(restored, Modules, root, "42").unwrap()
  assert_eq(captures.length(), 1)
  assert_eq(captures[0].capture_name, "module.name")
}

///|
test "build_bundle/lint rules compile and round trip" {
  let bundle = build_bundle(test_lint_source(), PackBuildOptions::default()).unwrap()
  assert_true(bundle.capabilities.lint)
  assert_true(bundle.capabilities.rewrite)
  assert_eq(bundle.lint_rule_sets.length(), 1)
  assert_true(bundle.lint_rule_sets[0].rules[0].compiled_query is Some(_))
  let json = bundle_to_json(bundle)
  assert_true(json.contains("\"querySource\":\"(number) @value\""))
  assert_false(json.contains("queries/lint/normalize.scm"))
  let restored = bundle_from_json(json).unwrap()
  assert_true(restored.capabilities.lint)
  assert_true(restored.capabilities.rewrite)
  assert_true(restored.lint_rule_sets[0].rules[0].compiled_query is Some(_))
  assert_eq(restored.lint_rule_sets[0].rules[0].query_path, None)
}

///|
test "build_bundle/lint without fix disables rewrite" {
  let bundle = build_bundle(
    test_lint_source(ruleset=test_lint_ruleset(fix="")),
    PackBuildOptions::default(),
  ).unwrap()
  assert_true(bundle.capabilities.lint)
  assert_false(bundle.capabilities.rewrite)
  let restored = bundle_from_json(bundle_to_json(bundle)).unwrap()
  assert_true(restored.capabilities.lint)
  assert_false(restored.capabilities.rewrite)
  assert_true(restored.lint_rule_sets[0].rules[0].fix is None)
}

///|
test "build_bundle/rejects invalid lint query and missing capture" {
  let compile_errors = build_bundle(
    test_lint_source(lint_query="(missing"),
    PackBuildOptions::default(),
  ).unwrap_err()
  assert_true(compile_errors.any(fn(error) { error.code == "PACK401" }))
  let capture_errors = build_bundle(
    test_lint_source(lint_query="(number) @other"),
    PackBuildOptions::default(),
  ).unwrap_err()
  assert_true(capture_errors.any(fn(error) { error.code == "PACK403" }))
}

///|
test "load_pack/rejects missing declared folding query" {
  let manifest = test_manifest().replace(
    old="\"queries\":{\"highlights\":\"queries/highlights.scm\"}",
    new="\"queries\":{\"highlights\":\"queries/highlights.scm\",\"folding\":\"queries/folding.scm\"}",
  )
  let errors = load_pack(test_source(manifest~)).unwrap_err()
  assert_true(
    errors.any(fn(error) {
      error.code == "PACK203" && error.path == "queries/folding.scm"
    }),
  )
}

///|
test "load_pack/rejects missing declared modules query" {
  let manifest = test_manifest().replace(
    old="\"queries\":{\"highlights\":\"queries/highlights.scm\"}",
    new="\"queries\":{\"highlights\":\"queries/highlights.scm\",\"modules\":\"queries/modules.scm\"}",
  )
  let errors = load_pack(test_source(manifest~)).unwrap_err()
  assert_true(
    errors.any(fn(error) {
      error.code == "PACK203" && error.path == "queries/modules.scm"
    }),
  )
}

///|
test "build_bundle/missing entry rule is explicit" {
  let source = test_source(manifest=test_manifest(entry="missing"))
  let errors = build_bundle(source, PackBuildOptions::default()).unwrap_err()
  assert_true(errors.any(fn(error) { error.code == "PACK302" }))
}

///|
test "build_bundle/absent optional queries disable capability" {
  let manifest = test_manifest().replace(
    old="\"queries\":{\"highlights\":\"queries/highlights.scm\"}",
    new="\"queries\":{}",
  )
  let source = test_source(manifest~)
  source.files.remove("queries/highlights.scm")
  let bundle = build_bundle(source, PackBuildOptions::default()).unwrap()
  assert_false(bundle.capabilities.highlights)
  assert_false(bundle.capabilities.modules)
  assert_true(bundle.highlights_query is None)
}

///|
test "bundle/json and binary round trip" {
  let bundle = build_bundle(test_source(), PackBuildOptions::default()).unwrap()
  let restored = bundle_from_json(bundle_to_json(bundle)).unwrap()
  assert_eq(restored.pack_name, "Test Language")
  assert_eq(restored.pack_maturity, "experimental")
  assert_eq(restored.pack_extensions, [".test"])
  let root = parse_bundle(restored, "7").unwrap()
  assert_eq(root.start_byte, 0)
  assert_eq(restored.table_json, @tablegen.table_to_json(restored.table))
}

///|
test "bundle/old v1 metadata remains loadable" {
  let bundle = build_bundle(test_source(), PackBuildOptions::default()).unwrap()
  let old = bundle_to_json(bundle)
    .replace(old=",\"name\":\"Test Language\"", new="")
    .replace(old=",\"maturity\":\"experimental\"", new="")
    .replace(old=",\"extensions\":[\".test\"]", new="")
  let restored = bundle_from_json(old).unwrap()
  assert_eq(restored.pack_name, "test-lang")
  assert_eq(restored.pack_maturity, "experimental")
  assert_true(restored.pack_extensions.is_empty())
}

///|
test "bundle/old v1 without folding fields remains loadable" {
  let bundle = build_bundle(test_source(), PackBuildOptions::default()).unwrap()
  let old = bundle_to_json(bundle)
    .replace(old=",\"folding\":null", new="")
    .replace(old=",\"folding\":false", new="")
    .replace(old=",\"modules\":null", new="")
    .replace(old=",\"modules\":false", new="")
  let restored = bundle_from_json(old).unwrap()
  assert_false(restored.capabilities.folding)
  assert_false(restored.capabilities.modules)
  assert_true(restored.folding_query is None)
  assert_true(restored.modules_query is None)
}

///|
test "bundle/old v1 without lint fields remains loadable" {
  let bundle = build_bundle(test_source(), PackBuildOptions::default()).unwrap()
  let old = bundle_to_json(bundle)
    .replace(old="\"lint\":{\"ruleSets\":[]},", new="")
    .replace(old=",\"lint\":false", new="")
    .replace(old=",\"rewrite\":false", new="")
  let restored = bundle_from_json(old).unwrap()
  assert_false(restored.capabilities.lint)
  assert_false(restored.capabilities.rewrite)
  assert_true(restored.lint_rule_sets.is_empty())
}

///|
test "bundle/rejects mismatched representations" {
  let bundle = build_bundle(test_source(), PackBuildOptions::default()).unwrap()
  let json = bundle_to_json(bundle).replace(
    old="\"binaryBase64\":\"",
    new="\"binaryBase64\":\"AAAA",
  )
  let errors = bundle_from_json(json).unwrap_err()
  assert_true(has_pack_errors(errors))
}

///|
test "bundle/rejects capability metadata mismatch" {
  let bundle = build_bundle(test_source(), PackBuildOptions::default()).unwrap()
  let json = bundle_to_json(bundle).replace(
    old="\"capabilities\":{\"highlights\":true",
    new="\"capabilities\":{\"highlights\":false",
  )
  let errors = bundle_from_json(json).unwrap_err()
  assert_true(errors.any(fn(error) { error.code == "PACK708" }))
}

///|
test "scanner/unknown scanner is explicit" {
  let source = test_source(manifest=test_manifest(scanner="custom"))
  let errors = build_bundle(source, PackBuildOptions::default()).unwrap_err()
  assert_true(errors.any(fn(error) { error.code == "PACK502" }))
}

///|
test "query/compile failure is explicit" {
  let source = test_source(query="(missing")
  let errors = build_bundle(source, PackBuildOptions::default()).unwrap_err()
  assert_true(errors.any(fn(error) { error.code == "PACK401" }))
}

///|
test "corpus/rejects malformed file" {
  let errors = load_pack(test_source(corpus="not a corpus")).unwrap_err()
  assert_true(
    errors.any(fn(error) { error.code == "PACK602" || error.code == "PACK605" }),
  )
}

///|
test "corpus/v2 parses and rewrites inline snapshot" {
  let text = "====\nnumber\n====\n42\n----\nerror: ok\n# keep me\nsexp:\n  (old)\n"
  let document = parse_corpus_document(
    "corpus/basic.txt", text, "moonparse-corpus-v2",
  ).unwrap()
  assert_eq(document.cases[0].expected_sexp, Some("(old)"))
  assert_eq(document.cases[0].source_line, 4)
  let updated = rewrite_corpus_snapshots(document, [
    { case_index: 0, case_name: "number", sexp: "(document (number))" },
  ]).unwrap()
  assert_true(updated.contains("# keep me"))
  assert_true(updated.contains("sexp:\n  (document (number))"))
  let reparsed = parse_corpus_document(
    "corpus/basic.txt", updated, "moonparse-corpus-v2",
  ).unwrap()
  assert_eq(reparsed.cases[0].expected_sexp, Some("(document (number))"))
}

///|
test "corpus/v1 rejects v2 snapshot" {
  let text = "====\nnumber\n====\n42\n----\nerror: ok\nsexp:\n  (number)\n"
  let errors = parse_corpus_document(
    "corpus/basic.txt", text, "moonparse-corpus-v1",
  ).unwrap_err()
  assert_true(errors.any(fn(error) { error.code == "PACK607" }))
}
