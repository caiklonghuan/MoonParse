///|
let expression_dsl =
  #|start document
  #|rule document: number
  #|rule number: /[0-9]+/

///|
fn characterization_pack_source() -> @languagepack.LanguagePackSource {
  let files : Map[String, Bytes] = {
    "grammar/main.grammar": @utf8.encode(expression_dsl),
    "corpus/basic.txt": @utf8.encode(
      "====\nnumber\n====\n42\n----\nerror: ok\n",
    ),
  }
  let manifest = "{" +
    "\"schemaVersion\":1," +
    "\"id\":\"characterization\"," +
    "\"name\":\"Characterization\"," +
    "\"version\":\"0.1.0\"," +
    "\"maturity\":\"experimental\"," +
    "\"entryRule\":\"document\"," +
    "\"extensions\":[\".char\"]," +
    "\"compatibility\":{\"minimumMoonParseVersion\":\"0.1.0\",\"maximumMoonParseVersionExclusive\":\"0.2.0\"}," +
    "\"grammar\":{\"path\":\"grammar/main.grammar\",\"format\":\"dsl\"}," +
    "\"corpus\":{\"directory\":\"corpus\",\"format\":\"moonparse-corpus-v1\"}" +
    "}"
  @languagepack.LanguagePackSource::new(manifest, files)
}

///|
test "characterization/root DSL parse has deterministic public tree description" {
  let first = @moonparse.parse(expression_dsl, "42")
  let second = @moonparse.parse(expression_dsl, "42")
  assert_eq(first, second)
  assert_true(first.contains("CstNode("))
  assert_true(first.contains("start_byte: 0"))
  assert_true(first.contains("end_byte: 2"))
}

///|
test "characterization/invalid JSON returns the current structured parse error" {
  let result = @moonparse.parse_json("{\"key\":")
  inspect(
    result,
    content="Error: ParseError(position: 7, point: (0, 7), message: accept: no root node)",
  )
}

///|
test "characterization/query observes the same public parse tree" {
  let compiled = match @moonparse.compile_dsl(expression_dsl) {
    Ok(value) => value
    Err(error) => fail("compile_dsl failed: \{error.message}")
  }
  let parsed = match @moonparse.parse_dsl(expression_dsl, "42") {
    Ok(value) => value
    Err(error) => fail("parse_dsl failed: \{error.message}")
  }
  let query = match @query.compile("(number) @value") {
    Ok(value) => value
    Err(error) => fail("query compile failed: \{error}")
  }
  let captures = @query.exec(query, parsed.root, parsed.source, compiled.table)
  inspect(captures.length(), content="1")
}

///|
test "characterization/language pack checks and builds through public APIs" {
  let source = characterization_pack_source()
  let options = @languagepack.PackBuildOptions::default()
  inspect(@languagepack.check_pack(source, options).length(), content="0")
  match @languagepack.build_bundle(source, options) {
    Ok(bundle) => {
      let encoded = @languagepack.bundle_to_json(bundle)
      assert_true(encoded.length() > 0)
      assert_true(@languagepack.bundle_from_json(encoded) is Ok(_))
    }
    Err(diagnostics) => fail("bundle build failed: \{diagnostics.length()}")
  }
}
