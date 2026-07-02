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
test "manifest/default resources and schema" {
  let manifest = load_manifest(test_manifest()).unwrap()
  assert_eq(manifest.schema_version, 1)
  assert_eq(manifest.grammar.path, "grammar/main.grammar")
  assert_eq(manifest.corpus.format, "moonparse-corpus-v1")
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
