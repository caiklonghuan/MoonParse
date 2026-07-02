///|
// cmd_wbtest.mbt — whitebox tests for cmd/main package

///|
test "derive_output_path/grammar_suffix_replaced" {
  // .grammar 后缀应被替换为 .parse_table
  assert_eq(derive_output_path("json.grammar"), "json.parse_table")
}

///|
test "derive_output_path/path_with_directory" {
  assert_eq(
    derive_output_path("grammars/json.grammar"),
    "grammars/json.parse_table",
  )
}

///|
test "derive_output_path/no_grammar_suffix_appends_parse_table" {
  // 没有 .grammar 后缀 → 直接拼接 .parse_table
  assert_eq(derive_output_path("myfile.txt"), "myfile.txt.parse_table")
}

///|
test "derive_output_path/grammar_as_filename_base" {
  // 文件名就叫 "grammar"（不含路径）
  assert_eq(derive_output_path("grammar"), "grammar.parse_table")
}

///|
// ── parse_args ───────────────────────────────────────────────────

///|
test "parse_args/empty_args_returns_help" {
  let result = parse_args([])
  match result {
    Ok(Help(None)) => ()
    other => fail("expected Help(None), got \{other}")
  }
}

///|
test "parse_args/help_flag_returns_help" {
  let result = parse_args(["--help"])
  match result {
    Ok(Help(None)) => ()
    other => fail("expected Help(None), got \{other}")
  }
}

///|
test "parse_args/version_flag_returns_version" {
  let result = parse_args(["--version"])
  match result {
    Ok(Version) => ()
    other => fail("expected Version, got \{other}")
  }
}

///|
test "parse_args/generate_command_with_grammar_file" {
  let result = parse_args(["generate", "json.grammar"])
  match result {
    Ok(Generate(args)) => assert_eq(args.grammar_file, "json.grammar")
    other => fail("expected Generate, got \{other}")
  }
}

///|
test "parse_args/generate_command_with_output_flag" {
  let result = parse_args(["generate", "json.grammar", "--output", "out.pt"])
  match result {
    Ok(Generate(args)) => {
      assert_eq(args.grammar_file, "json.grammar")
      assert_eq(args.output, Some("out.pt"))
    }
    other => fail("expected Generate, got \{other}")
  }
}

///|
test "parse_args/generate_command_with_json_flag" {
  let result = parse_args(["generate", "my.grammar", "--json"])
  match result {
    Ok(Generate(args)) => assert_eq(args.json, true)
    other => fail("expected Generate, got \{other}")
  }
}

///|
test "parse_args/check_command" {
  let result = parse_args(["check", "my.grammar"])
  match result {
    Ok(Check(args)) => {
      assert_eq(args.grammar_file, "my.grammar")
      assert_eq(args.conflict_detail, false)
    }
    other => fail("expected Check, got \{other}")
  }
}

///|
test "parse_args/check_command_with_conflict_detail" {
  let result = parse_args(["check", "my.grammar", "--conflict-detail"])
  match result {
    Ok(Check(args)) => {
      assert_eq(args.grammar_file, "my.grammar")
      assert_eq(args.conflict_detail, true)
    }
    other => fail("expected Check, got \{other}")
  }
}

///|
test "parse_args/fmt_command" {
  let result = parse_args(["fmt", "my.grammar"])
  match result {
    Ok(Fmt(args)) => {
      assert_eq(args.grammar_file, "my.grammar")
      assert_eq(args.check, false)
    }
    other => fail("expected Fmt, got \{other}")
  }
}

///|
test "parse_args/fmt_command_with_check_flag" {
  let result = parse_args(["fmt", "my.grammar", "--check"])
  match result {
    Ok(Fmt(args)) => assert_eq(args.check, true)
    other => fail("expected Fmt, got \{other}")
  }
}

///|
test "parse_args/parse_command_with_tree_format" {
  let result = parse_args(["parse", "json.grammar", "--format", "tree"])
  match result {
    Ok(Parse(args)) => assert_eq(args.format, Tree)
    other => fail("expected Parse, got \{other}")
  }
}

///|
test "parse_args/parse_command_with_output_file" {
  let result = parse_args(["parse", "json.grammar", "--output", "out/tree.txt"])
  match result {
    Ok(Parse(args)) => assert_eq(args.output, Some("out/tree.txt"))
    other => fail("expected Parse, got \{other}")
  }
}

///|
test "parse_args/parse_command_with_outdir" {
  let result = parse_args([
    "parse", "json.grammar", "sample.txt", "--outdir", "tmp/tree",
  ])
  match result {
    Ok(Parse(args)) => {
      assert_eq(args.input_file, Some("sample.txt"))
      assert_eq(args.outdir, Some("tmp/tree"))
    }
    other => fail("expected Parse, got \{other}")
  }
}

///|
test "parse_args/parse_command_rejects_output_and_outdir_together" {
  let result = parse_args([
    "parse", "json.grammar", "--output", "tree.txt", "--outdir", "tmp/tree",
  ])
  match result {
    Err(_) => ()
    Ok(other) => fail("expected Err, got \{other}")
  }
}

///|
test "parse_args/build_command_with_conflict_detail" {
  let result = parse_args(["build", "my.grammar", "--explain-conflicts"])
  match result {
    Ok(Build(args)) => {
      assert_eq(args.input, "my.grammar")
      assert_eq(args.conflict_detail, true)
    }
    other => fail("expected Build, got \{other}")
  }
}

///|
fn must_make_table(dsl : String) -> @tablegen.ParseTable {
  let grammar = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(err) => {
      println("grammar parse failed: \{err.message}")
      panic()
    }
  }
  match @tablegen.generate_parse_table(grammar) {
    Ok((table, _)) => table
    Err(msg) => {
      println("tablegen failed: \{msg}")
      panic()
    }
  }
}

///|
test "cst_to_tree_text/prints_ranges_and_leaf_text" {
  let table = must_make_table("start s\nrule s: \"a\"")
  let root = match @runtime.parse(table, "a") {
    Ok(node) => node
    Err(err) => fail("parse failed: \{err.message}")
  }
  let text = cst_to_tree_text(root, "a", table)
  assert_true(text.contains("▾s [0:0–0:1]"))
  assert_true(text.contains("·EOF [0:0–0:1] \"a\""))
}

///|
test "parse_args/unknown_subcommand_returns_err" {
  let result = parse_args(["nonexistent_command"])
  match result {
    Err(_) => ()
    Ok(other) => fail("expected Err, got \{other}")
  }
}

///|
test "parse_args/pack check json" {
  match parse_args(["pack", "--format", "json", "check", "languages/json"]) {
    Ok(Pack(Check(args))) => {
      assert_eq(args.directory, "languages/json")
      assert_true(args.format == PackOutputFormat::Json)
    }
    other => abort("unexpected result: \{other}")
  }
}

///|
test "parse_args/pack init options" {
  match
    parse_args(["pack", "init", "demo", "--name", "Demo", "--extension", ".dm"]) {
    Ok(Pack(Init(args))) => {
      assert_eq(args.id, Some("demo"))
      assert_eq(args.name, Some("Demo"))
      assert_eq(args.extensions, [".dm"])
    }
    other => abort("unexpected result: \{other}")
  }
}

///|
test "parse_args/pack test update" {
  match parse_args(["pack", "test", "sample", "--update"]) {
    Ok(Pack(Test(args))) => {
      assert_eq(args.directory, "sample")
      assert_true(args.update)
    }
    other => abort("unexpected result: \{other}")
  }
}

///|
test "parse_args/pack build distribution targets" {
  match
    parse_args([
      "pack", "build", "sample", "--target", "bundle", "--target", "npm", "--out-dir",
      "dist/sample", "--package-name", "@example/sample",
    ]) {
    Ok(Pack(Build(args))) => {
      assert_eq(args.targets.length(), 2)
      assert_true(args.targets[0] == PackBuildTarget::Bundle)
      assert_true(args.targets[1] == PackBuildTarget::Npm)
      assert_eq(args.out_dir, Some("dist/sample"))
      assert_eq(args.package_name, Some("@example/sample"))
    }
    other => abort("unexpected result: \{other}")
  }
}

///|
test "parse_args/pack build tool targets" {
  match
    parse_args([
      "pack", "build", "sample", "--target", "lsp", "--target", "vscode", "--target",
      "web", "--out-dir", "dist/sample",
    ]) {
    Ok(Pack(Build(args))) => {
      assert_eq(args.targets.length(), 3)
      assert_true(args.targets[0] == PackBuildTarget::Lsp)
      assert_true(args.targets[1] == PackBuildTarget::Vscode)
      assert_true(args.targets[2] == PackBuildTarget::Web)
      assert_eq(args.out_dir, Some("dist/sample"))
    }
    other => abort("unexpected result: \{other}")
  }
  assert_true(
    parse_args([
      "pack", "build", "sample", "--target", "vscode", "--package-name", "@example/sample",
    ])
    is Err(_),
  )
}

///|
fn test_tool_bundle() -> @languagepack.LanguageBundle {
  let files : Map[String, Bytes] = Map::new()
  files["grammar/main.grammar"] = @utf8.encode(
    "start document\nrule document: number\nrule number: /[0-9]+/",
  )
  files["queries/highlights.scm"] = @utf8.encode("(number) @number")
  let manifest = "{" +
    "\"schemaVersion\":1," +
    "\"id\":\"test-lang\"," +
    "\"name\":\"Test Language\"," +
    "\"version\":\"0.1.0\"," +
    "\"maturity\":\"experimental\"," +
    "\"entryRule\":\"document\"," +
    "\"extensions\":[\".test\"]," +
    "\"grammar\":{\"path\":\"grammar/main.grammar\",\"format\":\"dsl\"}," +
    "\"compatibility\":{\"minimumMoonParseVersion\":\"0.1.0\",\"maximumMoonParseVersionExclusive\":\"0.2.0\"}," +
    "\"queries\":{\"highlights\":\"queries/highlights.scm\"}," +
    "\"build\":{\"allowAmbiguousConflicts\":false}" +
    "}"
  match
    @languagepack.build_bundle(
      @languagepack.LanguagePackSource::new(manifest, files),
      pack_options(),
    ) {
    Ok(bundle) => bundle
    Err(errors) => abort("failed to build test bundle: \{errors}")
  }
}

///|
test "pack toolgen/vscode name is normalized" {
  assert_eq(
    pack_vscode_extension_name("JSON_Lang.V1"),
    "moonparse-json-lang-v1",
  )
  assert_eq(pack_vscode_extension_name("---"), "moonparse-language")
}

///|
test "pack toolgen/textmate grammar is skeleton" {
  assert_eq(
    pack_textmate_grammar("test-lang", [".test"]),
    "{\"scopeName\":\"source.test-lang\",\"fileTypes\":[\"test\"],\"patterns\":[]}",
  )
}

///|
test "pack toolgen/vscode package includes generated icon and normalized name" {
  let package_json = pack_vscode_package_json(test_tool_bundle())
  assert_true(package_json.contains("\"name\": \"moonparse-test-lang\""))
  assert_true(package_json.contains("\"icon\": \"resources/icon.png\""))
  assert_true(package_json.contains("\"scopeName\": \"source.test-lang\""))
  assert_true(package_json.contains("\"extensions\": [\".test\"]"))
}

///|
test "parse_args/bundle input and source exclusivity" {
  match parse_args(["parse", "--bundle", "json.bundle.json", "input.json"]) {
    Ok(Parse(args)) => assert_eq(args.bundle_file, Some("json.bundle.json"))
    other => abort("unexpected result: \{other}")
  }
  assert_true(
    parse_args([
      "query", "(number) @n", "--bundle", "json.bundle.json", "--grammar", "json.grammar",
    ])
    is Err(_),
  )
}

///|
test "parse_args/generate_missing_grammar_file_returns_err" {
  let result = parse_args(["generate"])
  match result {
    Err(_) => ()
    Ok(other) => fail("expected Err, got \{other}")
  }
}
