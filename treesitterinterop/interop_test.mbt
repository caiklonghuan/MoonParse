///|
fn simple_options() -> TreeSitterImportOptions {
  {
    output_id: None,
    output_name: None,
    package_version: None,
    extensions: [],
    allow_tags_bindings_candidate: false,
  }
}

///|
fn simple_grammar_json() -> String {
  (
    #|{
    #|  "name": "json",
    #|  "rules": {
    #|    "document": {"type": "SYMBOL", "name": "value"},
    #|    "value": {
    #|      "type": "CHOICE",
    #|      "members": [
    #|        {"type": "SYMBOL", "name": "number"},
    #|        {"type": "SYMBOL", "name": "string"}
    #|      ]
    #|    },
    #|    "number": {"type": "TOKEN", "content": {"type": "PATTERN", "value": "[0-9]+"}},
    #|    "string": {"type": "TOKEN", "content": {"type": "SEQ", "members": [
    #|      {"type": "STRING", "value": "\""},
    #|      {"type": "REPEAT", "content": {"type": "PATTERN", "value": "[^\\\"]"}},
    #|      {"type": "STRING", "value": "\""}
    #|    ]}}
    #|  },
    #|  "extras": [{"type": "PATTERN", "value": "\\s+"}]
    #|}
  )
}

///|
fn simple_source() -> TreeSitterProjectSource {
  let queries : Map[String, String] = Map([])
  queries["highlights"] = "(number) @number\n"
  queries["tags"] = "(document) @definition.file\n"
  let corpus : Map[String, String] = Map([])
  corpus["basic.txt"] = "===\nnumber\n===\n42\n---\n(document (number))\n"
  let source_files : Map[String, Bytes] = Map([])
  source_files["grammar.json"] = @utf8.encode(simple_grammar_json())
  {
    grammar_json: simple_grammar_json(),
    tree_sitter_json: Some(
      "{\"grammars\":[{\"name\":\"json\",\"file-types\":[\"json\"]}]}",
    ),
    package_json: Some("{\"name\":\"tree-sitter-json\",\"version\":\"1.2.3\"}"),
    queries,
    corpus,
    source_files,
    project_name: Some("tree-sitter-json"),
  }
}

///|
test "corpus conversion produces moonparse v2 snapshots" {
  let (converted, diagnostics) = convert_tree_sitter_corpus(
    "basic.txt",
    "===\ncase\n===\nabc\n---\n(root (leaf))\n",
    simple_options(),
  )
  assert_true(diagnostics.is_empty())
  assert_true(converted.contains("====\ncase\n===="))
  assert_true(converted.contains("----\nerror: ok\nsexp:\n  (root (leaf))"))
}

///|
test "project import extracts metadata and preserves tags" {
  let result = import_tree_sitter_project(simple_source(), simple_options())
  assert_false(
    result.diagnostics.any(fn(d) {
      d.severity == @languagepack.PackSeverity::Error
    }),
  )
  let manifest = @utf8.decode_lossy(result.files["language-pack.json"])
  assert_true(manifest.contains("\"id\": \"json\""))
  assert_true(manifest.contains("\"version\": \"1.2.3\""))
  assert_true(manifest.contains("\"extensions\": [\".json\"]"))
  assert_eq(
    @utf8.decode_lossy(result.files["queries/tags.scm"]),
    "(document) @definition.file\n",
  )
  assert_true(
    @utf8.decode_lossy(result.files["corpus/basic.txt"]).contains("sexp:"),
  )
  assert_true(
    @utf8.decode_lossy(result.files["tree-sitter-compatibility.json"]).contains(
      "\"tags\":\"preserved\"",
    ),
  )
  let source_manifest = source_manifest_to_json({
    ..simple_source(),
    source_files: {
      let files : Map[String, Bytes] = Map([])
      files["abc.txt"] = @utf8.encode("abc")
      files
    },
  })
  assert_true(
    source_manifest.contains(
      "sha256-ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    ),
  )
}

///|
test "externals produce TS5xx fallback and scanner descriptor" {
  let source = {
    ..simple_source(),
    grammar_json: simple_grammar_json().replace(
      old="\"extras\":",
      new="\"externals\":[{\"type\":\"SYMBOL\",\"name\":\"automatic_semicolon\"}],\"extras\":",
    ),
  }
  let result = import_tree_sitter_project(source, simple_options())
  assert_true(result.diagnostics.any(fn(d) { d.code == "TS501" }))
  assert_true(
    @utf8.decode_lossy(result.files["language-pack.json"]).contains(
      "\"scanner\": {\"id\": \"tree-sitter-json\", \"apiVersion\": 1}",
    ),
  )
}

///|
test "unsupported grammar node reports TS2xx" {
  let result = import_tree_sitter_grammar(
    "grammar.json",
    "{\"name\":\"x\",\"rules\":{\"source_file\":{\"type\":\"UNKNOWN\"}}}",
    simple_options(),
  )
  assert_true(result.diagnostics.any(fn(d) { d.code == "TS201" }))
  assert_true(
    @utf8.decode_lossy(result.files["grammar/main.grammar"]).contains(
      "rule source_file",
    ),
  )
}

///|
test "export maps core MoonParse patterns to Tree-sitter grammar JSON" {
  let grammar =
    #|start document
    #|extras [/[ \t]+/]
    #|externals [raw_string_literal]
    #|word identifier
    #|conflicts [[document, identifier]]
    #|supertypes [expression]
    #|reserved keywords ["fn", "let"]
    #|token rule number: /[0-9]+/
    #|token rule bang: "!"
    #|rule document: name: alias("id", identifier) number* bang?
    #|rule identifier: reserved("keywords", /[a-z]+/)
    #|rule expression: identifier | number
  let result = export_tree_sitter_grammar("grammar/main.grammar", grammar, {
    grammar_name: Some("demo"),
  })
  if result.diagnostics.any(fn(d) {
      d.severity == @languagepack.PackSeverity::Error
    }) {
    fail(
      "export diagnostics: " +
      result.diagnostics.map(fn(d) { d.code + ":" + d.message }).join("|"),
    )
  }
  assert_true(result.grammar_json.contains("\"name\":\"demo\""))
  assert_true(result.grammar_json.contains("\"TOKEN\""))
  assert_true(result.grammar_json.contains("\"FIELD\""))
  assert_true(result.grammar_json.contains("\"ALIAS\""))
  assert_true(result.grammar_json.contains("\"RESERVED\""))
  assert_true(result.grammar_json.contains("\"externals\""))
  assert_true(result.grammar_json.contains("\"reserved_sets\""))
  let reimported = import_tree_sitter_grammar(
    "grammar.json",
    result.grammar_json,
    simple_options(),
  )
  if reimported.diagnostics.any(fn(d) {
      d.severity == @languagepack.PackSeverity::Error
    }) {
    fail(
      "reimport diagnostics: " +
      reimported.diagnostics.map(fn(d) { d.code + ":" + d.message }).join("|"),
    )
  }
}

///|
test "export pack grammar JSON preserves immediate token rules" {
  let manifest =
    #|{"schemaVersion":1,"id":"immediate","name":"Immediate","version":"0.1.0","maturity":"imported","entryRule":"s","extensions":[],"compatibility":{"minimumMoonParseVersion":"0.1.0","maximumMoonParseVersionExclusive":"0.2.0"},"grammar":{"path":"grammar/main.json","format":"json"},"queries":{},"corpus":{"directory":"corpus","format":"moonparse-corpus-v2"},"build":{"allowAmbiguousConflicts":false}}
  let grammar_json =
    #|{"start":"s","rules":{"s":{"name":"s","is_named":true,"is_token":false,"is_immediate":false,"lexical_precedence":0,"declaration_order":0,"params":[],"attributes":[],"pattern":{"type":"RuleRef","name":"bang"}},"bang":{"name":"bang","is_named":true,"is_token":true,"is_immediate":true,"lexical_precedence":0,"declaration_order":1,"params":[],"attributes":[],"pattern":{"type":"Literal","value":"!"}}},"precedences":[],"extras":[],"externals":[],"word":null,"conflicts":[],"supertypes":[],"reserved_sets":{}}
  let files : Map[String, Bytes] = Map([])
  files["grammar/main.json"] = @utf8.encode(grammar_json)
  let result = export_tree_sitter_pack(
    @languagepack.LanguagePackSource::new(manifest, files),
    { grammar_name: None },
  )
  assert_false(
    result.diagnostics.any(fn(d) {
      d.severity == @languagepack.PackSeverity::Error
    }),
  )
  assert_true(result.grammar_json.contains("\"IMMEDIATE_TOKEN\""))
}

///|
test "export RepeatRange expands bounded ranges and rejects unsafe ranges" {
  let ok = export_tree_sitter_grammar(
    "range.grammar",
    "start s\nrule s: \"a\"{2,4}\n",
    { grammar_name: Some("range") },
  )
  assert_false(ok.diagnostics.any(fn(d) { d.code == "TS432" }))
  assert_true(ok.grammar_json.contains("\"SEQ\""))
  assert_true(ok.grammar_json.contains("\"BLANK\""))
  let bad = export_tree_sitter_grammar(
    "range.grammar",
    "start s\nrule s: \"a\"{0,21}\n",
    { grammar_name: Some("range") },
  )
  assert_true(bad.diagnostics.any(fn(d) { d.code == "TS432" }))
}

///|
test "export RuleApp monomorphizes call sites and reports lookahead" {
  let mono = export_tree_sitter_grammar(
    "template.grammar",
    "start s\nrule pair[A, B]: A B\nrule s: pair[\"a\", \"b\"] pair[\"a\", \"b\"]\n",
    { grammar_name: Some("template") },
  )
  assert_false(
    mono.diagnostics.any(fn(d) {
      d.severity == @languagepack.PackSeverity::Error
    }),
  )
  assert_eq(mono.report.monomorphized_rules.length(), 1)
  assert_true(mono.grammar_json.contains("_ts_export_pair_"))
  let lookahead = export_tree_sitter_grammar(
    "lookahead.grammar",
    "start s\nrule s: &\"a\" \"a\"\n",
    { grammar_name: Some("lookahead") },
  )
  assert_true(lookahead.diagnostics.any(fn(d) { d.code == "TS441" }))
}

///|
test "export report JSON is stable enough for CLI artifacts" {
  let result = export_tree_sitter_grammar(
    "grammar/main.grammar",
    "start s\nrule s: \"x\"\n",
    { grammar_name: Some("x-lang") },
  )
  let report = tree_sitter_export_report_to_json(result.report)
  assert_true(report.contains("\"schemaVersion\":1"))
  assert_true(report.contains("\"grammarName\":\"x-lang\""))
  assert_true(report.contains("\"exportedRules\""))
}
