///|
fn pack_test_manifest(
  corpus_format? : String = "moonparse-corpus-v1",
  scanner? : String = "",
) -> String {
  let scanner_field = if scanner.is_empty() {
    ""
  } else {
    ",\"scanner\":{\"id\":\"" + scanner + "\",\"apiVersion\":1}"
  }
  "{" +
  "\"schemaVersion\":1," +
  "\"id\":\"runner-test\"," +
  "\"name\":\"Runner Test\"," +
  "\"version\":\"0.1.0\"," +
  "\"maturity\":\"experimental\"," +
  "\"entryRule\":\"document\"," +
  "\"extensions\":[\".runner\"]," +
  "\"compatibility\":{\"minimumMoonParseVersion\":\"0.1.0\",\"maximumMoonParseVersionExclusive\":\"0.2.0\"}," +
  "\"grammar\":{\"path\":\"grammar/main.grammar\",\"format\":\"dsl\"}," +
  "\"corpus\":{\"directory\":\"corpus\",\"format\":\"" +
  corpus_format +
  "\"}" +
  scanner_field +
  "}"
}

///|
fn pack_test_source(
  corpus : String,
  corpus_format? : String = "moonparse-corpus-v1",
  scanner? : String = "",
) -> LanguagePackSource {
  let files : Map[String, Bytes] = {
    "grammar/main.grammar": @utf8.encode(
      "start document\nrule document: number\nrule number: /[0-9]+/",
    ),
    "corpus/basic.txt": @utf8.encode(corpus),
  }
  LanguagePackSource::new(pack_test_manifest(corpus_format~, scanner~), files)
}

///|
test "build_bundle_report/retains warning and bundle" {
  let source = pack_test_source("====\nnumber\n====\n42\n----\nerror: ok\n")
  source.files.remove("corpus/basic.txt")
  let report = build_bundle_report(source, PackBuildOptions::default())
  assert_true(report.bundle is Some(_))
  assert_true(report.diagnostics.any(fn(item) { item.severity == Warning }))
}

///|
test "build_bundle_report/error has no bundle and old APIs agree" {
  let source = pack_test_source("====\nnumber\n====\n42\n----\nerror: ok\n")
  source.files.remove("grammar/main.grammar")
  let report = build_bundle_report(source, PackBuildOptions::default())
  assert_true(report.bundle is None)
  assert_true(has_pack_errors(report.diagnostics))
  assert_true(has_pack_errors(check_pack(source, PackBuildOptions::default())))
  assert_true(build_bundle(source, PackBuildOptions::default()) is Err(_))
}

///|
test "test_pack/runs all cases and reports expectation failures" {
  let corpus =
    #|====
    #|mixed failures
    #|====
    #|42
    #|----
    #|error: error:9:9
    #|sexp-contains:
    #|  absent
    #|sexp-not-contains:
    #|  document
    #|sexp:
    #|  (wrong)
    #|
    #|====
    #|passing case
    #|====
    #|7
    #|----
    #|error: ok
    #|sexp:
    #|  (document (number))
  let report = test_pack(
    pack_test_source(corpus, corpus_format="moonparse-corpus-v2"),
    PackBuildOptions::default(),
  )
  assert_eq(report.cases.length(), 2)
  assert_false(report.cases[0].passed)
  assert_true(report.cases[1].passed)
  let failures = report.cases[0].failures
  assert_true(failures.any(fn(item) { item.kind == CorpusFailureKind::Error }))
  assert_true(failures.any(fn(item) { item.kind == CorpusFailureKind::Sexp }))
  assert_true(
    failures.any(fn(item) { item.kind == CorpusFailureKind::Contains }),
  )
  assert_true(
    failures.any(fn(item) { item.kind == CorpusFailureKind::NotContains }),
  )
  assert_eq(report.cases[0].actual_error, "ok")
  assert_eq(report.cases[0].actual_sexp, "(document (number))")
}

///|
test "test_pack/parse failure does not abort report" {
  let corpus = "====\nfirst\n====\n42\n----\nerror: ok\n\n====\nsecond\n====\n7\n----\nerror: ok\n"
  let options = {
    ..PackBuildOptions::default(),
    known_scanners: [("custom", 1)],
  }
  let report = test_pack(pack_test_source(corpus, scanner="custom"), options)
  assert_eq(report.cases.length(), 2)
  assert_true(
    report.cases.all(fn(item) {
      !item.passed && item.failures[0].kind == CorpusFailureKind::Parse
    }),
  )
}

///|
test "test_pack/build failure returns no cases" {
  let source = pack_test_source("====\nnumber\n====\n42\n----\nerror: ok\n")
  source.files.remove("grammar/main.grammar")
  let report = test_pack(source, PackBuildOptions::default())
  assert_true(has_pack_errors(report.diagnostics))
  assert_true(report.cases.is_empty())
}
