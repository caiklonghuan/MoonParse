///|
// cmd_wbtest.mbt — whitebox tests for cmd/main package
// 仅测试纯函数（不依赖文件 IO 的部分）

///|
// ── derive_output_path ───────────────────────────────────────────

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
    Ok(Check(args)) => assert_eq(args.grammar_file, "my.grammar")
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
test "parse_args/unknown_subcommand_returns_err" {
  let result = parse_args(["nonexistent_command"])
  match result {
    Err(_) => ()
    Ok(other) => fail("expected Err, got \{other}")
  }
}

///|
test "parse_args/generate_missing_grammar_file_returns_err" {
  let result = parse_args(["generate"])
  match result {
    Err(_) => ()
    Ok(other) => fail("expected Err, got \{other}")
  }
}
