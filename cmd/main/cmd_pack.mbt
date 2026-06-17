///|
fn pack_slashes(path : String) -> String {
  path.replace_all(old="\\", new="/")
}

///|
fn pack_join(base : String, relative : String) -> String {
  if base == "." {
    relative
  } else if base.has_suffix("/") || base.has_suffix("\\") {
    base + relative
  } else {
    base + "/" + relative
  }
}

///|
fn pack_parent(path : String) -> String {
  let value = pack_slashes(path)
  let mut slash = -1
  for i in 0..<value.length() {
    if value[i] == '/' {
      slash = i
    }
  }
  if slash < 0 {
    "."
  } else {
    value[:slash].to_string()
  }
}

///|
fn pack_relative(root : String, path : String) -> String {
  let r = pack_slashes(root).trim_end(chars=['/'])
  let p = pack_slashes(path)
  if p.has_prefix(r + "/") {
    p[r.length() + 1:].to_string()
  } else {
    p
  }
}

///|
fn load_pack_source_from_dir(
  directory : String,
) -> Result[@languagepack.LanguagePackSource, @languagepack.PackDiagnostic] {
  let manifest_path = pack_join(directory, "language-pack.json")
  let manifest = match read_file(manifest_path) {
    Ok(value) => value
    Err(error) =>
      return Err(
        @languagepack.pack_diagnostic(
          "CLI201",
          @languagepack.PackSeverity::Error,
          error,
          path=manifest_path,
        ),
      )
  }
  let paths = match list_files(directory) {
    Ok(value) => value
    Err(error) =>
      return Err(
        @languagepack.pack_diagnostic(
          "CLI202",
          @languagepack.PackSeverity::Error,
          error,
          path=directory,
        ),
      )
  }
  let mut actual_root = directory
  for path in paths {
    if pack_slashes(path).has_suffix("/language-pack.json") ||
      pack_slashes(path) == "language-pack.json" {
      actual_root = pack_parent(path)
    }
  }
  let files : Map[String, Bytes] = Map::new()
  for path in paths {
    let relative = pack_relative(actual_root, path)
    if relative != "language-pack.json" {
      match read_bytes(path) {
        Ok(bytes) => files[relative] = bytes
        Err(error) =>
          return Err(
            @languagepack.pack_diagnostic(
              "CLI203",
              @languagepack.PackSeverity::Error,
              error,
              path~,
            ),
          )
      }
    }
  }
  Ok(@languagepack.LanguagePackSource::new(manifest, files))
}

///|
fn pack_options() -> @languagepack.PackBuildOptions {
  { software_version: "0.1.0", known_scanners: @grammars.known_pack_scanners() }
}

///|
fn pack_provider(
  bundle : @languagepack.LanguageBundle,
) -> @languagepack.PackScannerProvider? {
  @grammars.builtin_pack_scanner_provider(bundle)
}

///|
fn pack_diag_json(d : @languagepack.PackDiagnostic) -> String {
  let hint = match d.hint {
    Some(v) => "\"" + json_escape(v) + "\""
    None => "null"
  }
  "{\"code\":\"" +
  json_escape(d.code) +
  "\",\"severity\":\"" +
  d.severity.to_string() +
  "\",\"message\":\"" +
  json_escape(d.message) +
  "\",\"path\":\"" +
  json_escape(d.path) +
  "\",\"line\":" +
  d.line.to_string() +
  ",\"column\":" +
  d.column.to_string() +
  ",\"hint\":" +
  hint +
  "}"
}

///|
fn emit_pack_result(
  command : String,
  format : PackOutputFormat,
  diagnostics : Array[@languagepack.PackDiagnostic],
  summary : String,
  artifacts : Array[String],
  code : Int,
) -> Int {
  match format {
    Json => {
      let ds = diagnostics.map(fn(d) { pack_diag_json(d) }).join(",")
      let artifact_json = artifacts
        .map(fn(v) { "\"" + json_escape(v) + "\"" })
        .join(",")
      let status = if code == 0 {
        "ok"
      } else if code == 1 {
        "warning"
      } else {
        "error"
      }
      println(
        "{\"command\":\"pack " +
        command +
        "\",\"status\":\"" +
        status +
        "\",\"diagnostics\":[" +
        ds +
        "],\"summary\":{\"message\":\"" +
        json_escape(summary) +
        "\"},\"artifacts\":[" +
        artifact_json +
        "]}",
      )
    }
    Human => {
      for d in diagnostics {
        print_err(d.severity.to_string() + "[" + d.code + "]: " + d.message)
        if !d.path.is_empty() {
          print_err(
            "  --> " +
            d.path +
            ":" +
            d.line.to_string() +
            ":" +
            d.column.to_string(),
          )
        }
        match d.hint {
          Some(hint) => print_err("help: " + hint)
          None => ()
        }
      }
      if !summary.is_empty() {
        print_info(summary)
      }
      for artifact in artifacts {
        print_info("written: " + artifact)
      }
    }
  }
  code
}

///|
fn pack_diagnostic_code(
  diagnostics : Array[@languagepack.PackDiagnostic],
) -> Int {
  if diagnostics.any(fn(d) { d.severity == @languagepack.PackSeverity::Error }) {
    2
  } else if diagnostics.any(fn(d) {
      d.severity == @languagepack.PackSeverity::Warning
    }) {
    1
  } else {
    0
  }
}

///|
fn cmd_pack_check(args : PackCheckArgs) -> Int {
  let source = match load_pack_source_from_dir(args.directory) {
    Err(error) =>
      return emit_pack_result("check", args.format, [error], "", [], 2)
    Ok(value) => value
  }
  let diagnostics = @languagepack.check_pack(source, pack_options())
  let code = pack_diagnostic_code(diagnostics)
  emit_pack_result(
    "check",
    args.format,
    diagnostics,
    if code < 2 {
      "Language Pack check completed"
    } else {
      ""
    },
    [],
    code,
  )
}

///|
fn pack_has_error(node : @runtime.CstNode) -> Bool {
  if node.is_error || node.is_missing {
    return true
  }
  node.children.any(fn(child) { pack_has_error(child) })
}

///|
fn cmd_pack_test(args : PackTestArgs) -> Int {
  let source = match load_pack_source_from_dir(args.directory) {
    Err(error) =>
      return emit_pack_result("test", args.format, [error], "", [], 2)
    Ok(value) => value
  }
  let pack = match @languagepack.load_pack(source) {
    Err(errors) =>
      return emit_pack_result("test", args.format, errors, "", [], 2)
    Ok(value) => value
  }
  if args.update && pack.manifest.corpus.format != "moonparse-corpus-v2" {
    let error = @languagepack.pack_diagnostic(
      "CLI301",
      @languagepack.PackSeverity::Error,
      "snapshot updates require moonparse-corpus-v2",
      path="language-pack.json",
      hint="change corpus.format explicitly before updating snapshots",
    )
    return emit_pack_result("test", args.format, [error], "", [], 2)
  }
  let bundle = match @languagepack.build_bundle(source, pack_options()) {
    Err(errors) =>
      return emit_pack_result("test", args.format, errors, "", [], 2)
    Ok(value) => value
  }
  let provider = pack_provider(bundle)
  let diagnostics : Array[@languagepack.PackDiagnostic] = []
  let updates : Map[String, Array[@languagepack.CorpusSnapshotUpdate]] = Map::new()
  let local_indices : Map[String, Int] = Map::new()
  for case in pack.corpus {
    let local_index = local_indices.get(case.path).unwrap_or(0)
    local_indices[case.path] = local_index + 1
    let root = match provider {
      Some(p) =>
        @languagepack.parse_bundle(bundle, case.source, scanner_provider=p)
      None => @languagepack.parse_bundle(bundle, case.source)
    }
    match root {
      Err(error) => diagnostics.push(error)
      Ok(root) => {
        let has_error = pack_has_error(root)
        if (case.expected_error == "ok" && has_error) ||
          (case.expected_error != "ok" && !has_error) {
          diagnostics.push(
            @languagepack.pack_diagnostic(
              "CLI302",
              @languagepack.PackSeverity::Warning,
              "unexpected parse error status in case '" + case.name + "'",
              path=case.path,
              line=case.source_line,
            ),
          )
        }
        let sexp = cst_to_sexp(root, case.source, bundle.table)
        for fragment in case.sexp_contains {
          if !sexp.contains(fragment) {
            diagnostics.push(
              @languagepack.pack_diagnostic(
                "CLI303",
                @languagepack.PackSeverity::Warning,
                "case '" +
                case.name +
                "' is missing expected S-expression fragment '" +
                fragment +
                "'",
                path=case.path,
                line=case.expectation_line,
              ),
            )
          }
        }
        for fragment in case.sexp_not_contains {
          if sexp.contains(fragment) {
            diagnostics.push(
              @languagepack.pack_diagnostic(
                "CLI304",
                @languagepack.PackSeverity::Warning,
                "case '" +
                case.name +
                "' contains forbidden S-expression fragment '" +
                fragment +
                "'",
                path=case.path,
                line=case.expectation_line,
              ),
            )
          }
        }
        if args.update {
          let values = updates.get(case.path).unwrap_or([])
          values.push({ case_index: local_index, case_name: case.name, sexp })
          updates[case.path] = values
        } else {
          match case.expected_sexp {
            Some(expected) if expected != sexp =>
              diagnostics.push(
                @languagepack.pack_diagnostic(
                  "CLI305",
                  @languagepack.PackSeverity::Warning,
                  "snapshot mismatch in case '" +
                  case.name +
                  "'\nexpected: " +
                  expected +
                  "\nactual:   " +
                  sexp,
                  path=case.path,
                  line=case.expectation_line,
                ),
              )
            None if pack.manifest.corpus.format == "moonparse-corpus-v2" =>
              diagnostics.push(
                @languagepack.pack_diagnostic(
                  "CLI306",
                  @languagepack.PackSeverity::Warning,
                  "snapshot missing in case '" + case.name + "'",
                  path=case.path,
                  line=case.expectation_line,
                  hint="run moonparse pack test --update",
                ),
              )
            _ => ()
          }
        }
      }
    }
  }
  if diagnostics.any(fn(d) { d.severity == @languagepack.PackSeverity::Error }) {
    return emit_pack_result("test", args.format, diagnostics, "", [], 2)
  }
  let artifacts : Array[String] = []
  if args.update {
    let rewrites : Map[String, String] = Map::new()
    updates.each(fn(relative, file_updates) {
      let full = pack_join(args.directory, relative)
      match read_file(full) {
        Err(message) =>
          diagnostics.push(
            @languagepack.pack_diagnostic(
              "CLI203",
              @languagepack.PackSeverity::Error,
              message,
              path=full,
            ),
          )
        Ok(text) =>
          match
            @languagepack.parse_corpus_document(
              relative,
              text,
              pack.manifest.corpus.format,
            ) {
            Err(errors) => diagnostics.push_iter(errors.iter())
            Ok(document) =>
              match
                @languagepack.rewrite_corpus_snapshots(document, file_updates) {
                Err(errors) => diagnostics.push_iter(errors.iter())
                Ok(rewritten) => rewrites[full] = rewritten
              }
          }
      }
    })
    if diagnostics.any(fn(d) { d.severity == @languagepack.PackSeverity::Error }) {
      return emit_pack_result("test", args.format, diagnostics, "", [], 2)
    }
    rewrites.each(fn(full, rewritten) {
      match atomic_write_file(full, rewritten) {
        Err(message) =>
          diagnostics.push(
            @languagepack.pack_diagnostic(
              "CLI307",
              @languagepack.PackSeverity::Error,
              message,
              path=full,
            ),
          )
        Ok(_) => artifacts.push(full)
      }
    })
    if !diagnostics.any(fn(d) {
        d.severity == @languagepack.PackSeverity::Error
      }) {
      match load_pack_source_from_dir(args.directory) {
        Err(error) => diagnostics.push(error)
        Ok(updated_source) =>
          match @languagepack.load_pack(updated_source) {
            Err(errors) => diagnostics.push_iter(errors.iter())
            Ok(updated_pack) =>
              for case in updated_pack.corpus {
                let parsed = match provider {
                  Some(p) =>
                    @languagepack.parse_bundle(
                      bundle,
                      case.source,
                      scanner_provider=p,
                    )
                  None => @languagepack.parse_bundle(bundle, case.source)
                }
                match parsed {
                  Err(error) => diagnostics.push(error)
                  Ok(root) => {
                    let actual = cst_to_sexp(root, case.source, bundle.table)
                    if case.expected_sexp != Some(actual) {
                      diagnostics.push(
                        @languagepack.pack_diagnostic(
                          "CLI308",
                          @languagepack.PackSeverity::Error,
                          "snapshot verification failed for case '" +
                          case.name +
                          "'",
                          path=case.path,
                          line=case.expectation_line,
                        ),
                      )
                    }
                  }
                }
              }
          }
      }
    }
  }
  let code = pack_diagnostic_code(diagnostics)
  emit_pack_result(
    "test",
    args.format,
    diagnostics,
    if code == 0 {
      pack.corpus.length().to_string() + " corpus cases passed"
    } else {
      ""
    },
    artifacts,
    code,
  )
}

///|
fn cmd_pack_build(args : PackBuildArgs) -> Int {
  let source = match load_pack_source_from_dir(args.directory) {
    Err(error) =>
      return emit_pack_result("build", args.format, [error], "", [], 2)
    Ok(value) => value
  }
  let diagnostics = @languagepack.check_pack(source, pack_options())
  if pack_diagnostic_code(diagnostics) == 2 {
    return emit_pack_result("build", args.format, diagnostics, "", [], 2)
  }
  let bundle = match @languagepack.build_bundle(source, pack_options()) {
    Err(errors) =>
      return emit_pack_result("build", args.format, errors, "", [], 2)
    Ok(value) => value
  }
  let json = @languagepack.bundle_to_json(bundle)
  match @languagepack.bundle_from_json(json) {
    Err(errors) =>
      return emit_pack_result("build", args.format, errors, "", [], 2)
    Ok(_) => ()
  }
  if args.targets.is_empty() {
    let output = args.output.unwrap_or(
      pack_join("build", bundle.pack_id + ".language-bundle.json"),
    )
    return pack_write_bundle_result(args, diagnostics, output, json)
  }
  let root = args.out_dir.unwrap_or(pack_join("dist", bundle.pack_id))
  let artifacts : Array[String] = []
  let mut error : (String, String)? = None
  for target in args.targets {
    if error is Some(_) {
      continue
    }
    match target {
      Bundle => {
        let output = args.output.unwrap_or(
          pack_join(root, bundle.pack_id + ".language-bundle.json"),
        )
        match pack_write_text(output, json) {
          Ok(_) => artifacts.push(output)
          Err(message) => error = Some((output, message))
        }
      }
      Moonbit =>
        match pack_generate_moonbit(root, bundle, json) {
          Ok(paths) => artifacts.append(paths)
          Err(value) => error = Some(value)
        }
      Wasm =>
        match pack_generate_wasm(root, bundle, json) {
          Ok(paths) => artifacts.append(paths)
          Err(value) => error = Some(value)
        }
      Npm =>
        match pack_generate_npm(root, bundle, json, args.package_name) {
          Ok(paths) => artifacts.append(paths)
          Err(value) => error = Some(value)
        }
    }
  }
  match error {
    Some((path, message)) =>
      emit_pack_result(
        "build",
        args.format,
        [
          @languagepack.pack_diagnostic(
            "CLI204",
            @languagepack.PackSeverity::Error,
            message,
            path~,
          ),
        ],
        "",
        [],
        2,
      )
    None =>
      emit_pack_result(
        "build",
        args.format,
        diagnostics,
        "Language Pack distribution built",
        artifacts,
        pack_diagnostic_code(diagnostics),
      )
  }
}

///|
fn read_optional_pack_file(path : String) -> String? {
  match read_file(path) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
fn pack_basename(path : String) -> String {
  let value = pack_slashes(path).trim_end(chars=['/']).to_string()
  let mut slash = -1
  for i in 0..<value.length() {
    if value[i] == '/' {
      slash = i
    }
  }
  if slash < 0 {
    value
  } else {
    value[slash + 1:].to_string()
  }
}

///|
fn source_query_name(relative : String) -> String? {
  match relative {
    "queries/highlights.scm" => Some("highlights")
    "queries/locals.scm" => Some("locals")
    "queries/tags.scm" => Some("tags")
    _ => None
  }
}

///|
fn source_corpus_name(relative : String) -> String? {
  if relative.has_prefix("test/corpus/") && relative.has_suffix(".txt") {
    Some(relative[12:].to_string())
  } else if relative.has_prefix("corpus/") && relative.has_suffix(".txt") {
    Some(relative[7:].to_string())
  } else {
    None
  }
}

///|
fn load_tree_sitter_source(
  directory : String,
) -> Result[
  @treesitterinterop.TreeSitterProjectSource,
  @languagepack.PackDiagnostic,
] {
  let grammar_path = pack_join(directory, "grammar.json")
  let grammar_json = match read_file(grammar_path) {
    Ok(value) => value
    Err(error) =>
      return Err(
        @languagepack.pack_diagnostic(
          "TS101",
          @languagepack.PackSeverity::Error,
          error,
          path=grammar_path,
        ),
      )
  }
  let queries : Map[String, String] = Map::new()
  let corpus : Map[String, String] = Map::new()
  let source_files : Map[String, Bytes] = Map::new()
  source_files["grammar.json"] = @utf8.encode(grammar_json)
  let tree_sitter_json = read_optional_pack_file(
    pack_join(directory, "tree-sitter.json"),
  )
  match tree_sitter_json {
    Some(text) => source_files["tree-sitter.json"] = @utf8.encode(text)
    None => ()
  }
  let package_json = read_optional_pack_file(
    pack_join(directory, "package.json"),
  )
  match package_json {
    Some(text) => source_files["package.json"] = @utf8.encode(text)
    None => ()
  }
  match list_files(directory) {
    Ok(paths) =>
      for path in paths {
        let relative = pack_relative(directory, path)
        match source_query_name(relative) {
          Some(name) =>
            match read_file(path) {
              Ok(text) => {
                queries[name] = text
                source_files[relative] = @utf8.encode(text)
              }
              Err(_) => ()
            }
          None =>
            match source_corpus_name(relative) {
              Some(name) =>
                match read_file(path) {
                  Ok(text) => {
                    corpus[name] = text
                    source_files[relative] = @utf8.encode(text)
                  }
                  Err(_) => ()
                }
              None => ()
            }
        }
      }
    Err(_) => ()
  }
  Ok({
    grammar_json,
    tree_sitter_json,
    package_json,
    queries,
    corpus,
    source_files,
    project_name: Some(pack_basename(directory)),
  })
}

///|
fn directory_is_empty_or_missing(path : String) -> Bool {
  match list_files(path) {
    Ok(files) => files.is_empty()
    Err(_) => true
  }
}

///|
fn cmd_pack_import_tree_sitter(args : PackImportTreeSitterArgs) -> Int {
  if !directory_is_empty_or_missing(args.directory) {
    return emit_pack_result(
      "import-tree-sitter",
      args.format,
      [
        @languagepack.pack_diagnostic(
          "CLI205",
          @languagepack.PackSeverity::Error,
          "target directory already exists and is not empty",
          path=args.directory,
        ),
      ],
      "",
      [],
      2,
    )
  }
  let source = match load_tree_sitter_source(args.source_dir) {
    Ok(value) => value
    Err(error) =>
      return emit_pack_result(
        "import-tree-sitter",
        args.format,
        [error],
        "",
        [],
        2,
      )
  }
  let result = @treesitterinterop.import_tree_sitter_project(source, {
    output_id: args.id,
    output_name: args.name,
    package_version: args.version,
    extensions: args.extensions,
    allow_tags_bindings_candidate: false,
  })
  let artifacts : Array[String] = []
  let diagnostics = result.diagnostics
  result.files.each(fn(relative, bytes) {
    let output = pack_join(args.directory, relative)
    match make_dir(pack_parent(output)) {
      Err(message) =>
        diagnostics.push(
          @languagepack.pack_diagnostic(
            "CLI206",
            @languagepack.PackSeverity::Error,
            message,
            path=pack_parent(output),
          ),
        )
      Ok(_) =>
        match write_bytes(output, bytes) {
          Err(message) =>
            diagnostics.push(
              @languagepack.pack_diagnostic(
                "CLI207",
                @languagepack.PackSeverity::Error,
                message,
                path=output,
              ),
            )
          Ok(_) => artifacts.push(output)
        }
    }
  })
  if !diagnostics.any(fn(d) { d.severity == @languagepack.PackSeverity::Error }) {
    match load_pack_source_from_dir(args.directory) {
      Err(error) => diagnostics.push(error)
      Ok(pack_source) =>
        diagnostics.push_iter(
          @languagepack.check_pack(pack_source, pack_options()).iter(),
        )
    }
  }
  let code = pack_diagnostic_code(diagnostics)
  emit_pack_result(
    "import-tree-sitter",
    args.format,
    diagnostics,
    if code < 2 {
      "Tree-sitter project imported"
    } else {
      ""
    },
    artifacts,
    code,
  )
}

///|
fn cmd_pack_export_tree_sitter(args : PackExportTreeSitterArgs) -> Int {
  let source = match load_pack_source_from_dir(args.directory) {
    Err(error) =>
      return emit_pack_result(
        "export-tree-sitter",
        args.format,
        [error],
        "",
        [],
        2,
      )
    Ok(value) => value
  }
  let result = @treesitterinterop.export_tree_sitter_pack(source, {
    grammar_name: None,
  })
  let diagnostics = result.diagnostics
  let artifacts : Array[String] = []
  let report_path = pack_join(
    pack_parent(args.output),
    "tree-sitter-export-report.json",
  )
  match pack_write_text(args.output, result.grammar_json) {
    Err(message) =>
      diagnostics.push(
        @languagepack.pack_diagnostic(
          "CLI207",
          @languagepack.PackSeverity::Error,
          message,
          path=args.output,
        ),
      )
    Ok(_) => artifacts.push(args.output)
  }
  match
    pack_write_text(
      report_path,
      @treesitterinterop.tree_sitter_export_report_to_json(result.report),
    ) {
    Err(message) =>
      diagnostics.push(
        @languagepack.pack_diagnostic(
          "CLI207",
          @languagepack.PackSeverity::Error,
          message,
          path=report_path,
        ),
      )
    Ok(_) => artifacts.push(report_path)
  }
  let code = pack_diagnostic_code(diagnostics)
  emit_pack_result(
    "export-tree-sitter",
    args.format,
    diagnostics,
    if code < 2 {
      "Language Pack exported as Tree-sitter grammar.json"
    } else {
      ""
    },
    artifacts,
    code,
  )
}

///|
fn pack_write_text(path : String, content : String) -> Result[Unit, String] {
  match make_dir(pack_parent(path)) {
    Err(error) => Err(error)
    Ok(_) => atomic_write_file(path, content)
  }
}

///|
fn pack_write_bundle_result(
  args : PackBuildArgs,
  diagnostics : Array[@languagepack.PackDiagnostic],
  output : String,
  json : String,
) -> Int {
  match pack_write_text(output, json) {
    Err(message) =>
      emit_pack_result(
        "build",
        args.format,
        [
          @languagepack.pack_diagnostic(
            "CLI204",
            @languagepack.PackSeverity::Error,
            message,
            path=output,
          ),
        ],
        "",
        [],
        2,
      )
    Ok(_) =>
      emit_pack_result(
        "build",
        args.format,
        diagnostics,
        "LanguageBundle built",
        [output],
        pack_diagnostic_code(diagnostics),
      )
  }
}

///|
fn pack_generate_moonbit(
  root : String,
  bundle : @languagepack.LanguageBundle,
  json : String,
) -> Result[Array[String], (String, String)] {
  let directory = pack_join(root, "moonbit")
  let mod_path = pack_join(directory, "moon.mod.json")
  let pkg_path = pack_join(directory, "moon.pkg")
  let source_path = pack_join(directory, "bundle.mbt")
  let scanner_code = if bundle.scanner is Some(_) {
    #|  let provider = @grammars.builtin_pack_scanner_provider(bundle)
    #|  @languagepack.parse_bundle(bundle, source, scanner_provider=provider)
  } else {
    #|  @languagepack.parse_bundle(bundle, source)
  }
  let module_text =
    #|{"name":"moonparse-language/
    + bundle.pack_id
    + #|","version":"
    + bundle.pack_version
    + #|","deps":{"caiklonghuan/MoonParse":"0.1.0"}}
  let package_text =
    #|import {
    #|  "caiklonghuan/MoonParse/languagepack" @languagepack,
    #|  "caiklonghuan/MoonParse/grammars" @grammars,
    #|  "caiklonghuan/MoonParse/query" @query,
    #|  "caiklonghuan/MoonParse/runtime" @runtime,
    #|}
  let source_text =
    #|///|
    + "\n"
    + #|pub let bundle_json : String = "
    + json_escape(json)
    + #|"
    + "\n\n"
    + #|///|
    + "\n"
    + #|pub fn load_bundle() -> Result[@languagepack.LanguageBundle, Array[@languagepack.PackDiagnostic]] {
    + "\n"
    + #|  @languagepack.bundle_from_json(bundle_json)
    + "\n}\n\n"
    + #|///|
    + "\n"
    + #|pub fn parse(source : String) -> Result[@runtime.CstNode, @languagepack.PackDiagnostic] {
    + "\n"
    + #|  let bundle = load_bundle().unwrap()
    + "\n"
    + scanner_code
    + "\n}\n\n"
    + #|///|
    + "\n"
    + #|pub fn query(kind : @languagepack.BundleQueryKind, tree : @runtime.CstNode, source : String) -> Result[Array[@query.CaptureResult], @languagepack.PackDiagnostic] {
    + "\n"
    + #|  let bundle = load_bundle().unwrap()
    + "\n"
    + #|  @languagepack.exec_bundle_query(bundle, kind, tree, source)
    + "\n}\n"
  let files = [(mod_path, module_text), (pkg_path, package_text), (source_path, source_text)]
  for (path, content) in files {
    match pack_write_text(path, content) {
      Err(error) => return Err((path, error))
      Ok(_) => ()
    }
  }
  Ok(files.map(fn(item) { item.0 }))
}

///|
fn pack_generate_wasm(
  root : String,
  bundle : @languagepack.LanguageBundle,
  json : String,
) -> Result[Array[String], (String, String)] {
  let directory = pack_join(root, "wasm")
  let bundle_path = pack_join(
    directory,
    bundle.pack_id + ".language-bundle.json",
  )
  let outputs = [
    ("wasm/moonparse.js", pack_join(directory, "moonparse.js")),
    ("wasm/moonparse.d.ts", pack_join(directory, "moonparse.d.ts")),
    ("wasm/moonparse.wasm", pack_join(directory, "moonparse.wasm")),
  ]
  match pack_write_text(bundle_path, json) {
    Err(error) => return Err((bundle_path, error))
    Ok(_) => ()
  }
  for (source, output) in outputs {
    let bytes = match read_bytes(source) {
      Err(error) => return Err((source, error))
      Ok(value) => value
    }
    ignore(make_dir(pack_parent(output)))
    match write_bytes(output, bytes) {
      Err(error) => return Err((output, error))
      Ok(_) => ()
    }
  }
  let entry = pack_join(directory, "language.js")
  let entry_text =
    #|import { loadMoonParse } from "./moonparse.js";
    + "\n"
    + #|export const bundleJson = "
    + json_escape(json)
    + #|";
    + "\n"
    + #|export async function loadLanguage(wasmUrl = "./moonparse.wasm") {
    + "\n"
    + #|  const moonparse = await loadMoonParse(wasmUrl);
    + "\n"
    + #|  return moonparse.loadBundle(bundleJson);
    + "\n}\n"
  match pack_write_text(entry, entry_text) {
    Err(error) => Err((entry, error))
    Ok(_) => Ok([bundle_path, outputs[0].1, outputs[1].1, outputs[2].1, entry])
  }
}

///|
fn pack_generate_npm(
  root : String,
  bundle : @languagepack.LanguageBundle,
  json : String,
  package_name : String?,
) -> Result[Array[String], (String, String)] {
  let directory = pack_join(root, "npm")
  let name = package_name.unwrap_or("@moonparse-language/" + bundle.pack_id)
  let files = [
    (pack_join(directory, "package.json"),
      #|{"name":"
      + json_escape(name)
      + #|","version":"
      + json_escape(bundle.pack_version)
      + #|","type":"module","main":"index.js","types":"index.d.ts","files":["index.js","index.d.ts","language-bundle.json","README.md"],"peerDependencies":{"moonparse":"^0.1.0"}}
    ),
    (pack_join(directory, "language-bundle.json"), json),
    (pack_join(directory, "index.js"),
      #|export const bundleJson = "
      + json_escape(json)
      + #|";
      + "\n"
      + #|export function loadLanguage(moonparse) { return moonparse.loadBundle(bundleJson); }
      + "\n"
    ),
    (pack_join(directory, "index.d.ts"),
      #|import type { MoonLanguage, MoonParseInstance } from "moonparse";
      + "\n"
      + #|export declare const bundleJson: string;
      + "\n"
      + #|export declare function loadLanguage(moonparse: MoonParseInstance): MoonLanguage;
      + "\n"
    ),
    (pack_join(directory, "README.md"),
      "# " + bundle.pack_name + " language bundle\n\nGenerated by MoonParse.\n"
    ),
  ]
  for (path, content) in files {
    match pack_write_text(path, content) {
      Err(error) => return Err((path, error))
      Ok(_) => ()
    }
  }
  Ok(files.map(fn(item) { item.0 }))
}

///|
fn prompt(label : String, default : String) -> String? {
  print_info(label + " [" + default + "]: ")
  match read_line() {
    Some(value) if !value.trim().is_empty() => Some(value.trim().to_string())
    Some(_) => Some(default)
    None => None
  }
}

///|
fn cmd_pack_init(args : PackInitArgs) -> Int {
  let mut id = args.id
  let mut name = args.name
  let mut entry = args.entry_rule
  let mut directory = args.directory
  if id is None {
    if !isatty(0) || !isatty(1) {
      return emit_pack_result(
        "init",
        args.format,
        [
          @languagepack.pack_diagnostic(
            "CLI101",
            @languagepack.PackSeverity::Error,
            "interactive pack init requires a TTY",
            hint="pass an id and options for non-interactive use",
          ),
        ],
        "",
        [],
        2,
      )
    }
    id = prompt("Pack id", "my-language")
    let selected = id.unwrap_or("my-language")
    name = prompt("Display name", selected)
    entry = prompt("Entry rule", "document")
    directory = prompt("Target directory", selected)
  }
  let selected_id = id.unwrap()
  let selected_name = name.unwrap_or(selected_id)
  let selected_entry = entry.unwrap_or("document")
  let selected_dir = directory.unwrap_or(selected_id)
  let maturity = args.maturity.unwrap_or("experimental")
  let extensions = if args.extensions.is_empty() {
    ["." + selected_id]
  } else {
    args.extensions
  }
  if read_file(pack_join(selected_dir, "language-pack.json")) is Ok(_) ||
    list_files(selected_dir) is Ok(_) {
    return emit_pack_result(
      "init",
      args.format,
      [
        @languagepack.pack_diagnostic(
          "CLI205",
          @languagepack.PackSeverity::Error,
          "target directory already exists",
          path=selected_dir,
        ),
      ],
      "",
      [],
      2,
    )
  }
  let ext_json = extensions
    .map(fn(v) { "\"" + json_escape(v) + "\"" })
    .join(",")
  let manifest = "{\n  \"schemaVersion\": 1,\n  \"id\": \"" +
    json_escape(selected_id) +
    "\",\n  \"name\": \"" +
    json_escape(selected_name) +
    "\",\n  \"version\": \"0.1.0\",\n  \"maturity\": \"" +
    json_escape(maturity) +
    "\",\n  \"entryRule\": \"" +
    json_escape(selected_entry) +
    "\",\n  \"extensions\": [" +
    ext_json +
    "],\n  \"compatibility\": {\"minimumMoonParseVersion\": \"0.1.0\", \"maximumMoonParseVersionExclusive\": \"0.2.0\"},\n  \"grammar\": {\"path\": \"grammar/main.grammar\", \"format\": \"dsl\"},\n  \"queries\": {\"highlights\": \"queries/highlights.scm\"},\n  \"corpus\": {\"directory\": \"corpus\", \"format\": \"moonparse-corpus-v2\"},\n  \"build\": {\"allowAmbiguousConflicts\": false}\n}\n"
  match @languagepack.load_manifest(manifest) {
    Err(errors) =>
      return emit_pack_result("init", args.format, errors, "", [], 2)
    Ok(_) => ()
  }
  for
    dir in [
      selected_dir,
      pack_join(selected_dir, "grammar"),
      pack_join(selected_dir, "queries"),
      pack_join(selected_dir, "corpus"),
    ] {
    match make_dir(dir) {
      Err(message) =>
        return emit_pack_result(
          "init",
          args.format,
          [
            @languagepack.pack_diagnostic(
              "CLI206",
              @languagepack.PackSeverity::Error,
              message,
              path=dir,
            ),
          ],
          "",
          [],
          2,
        )
      Ok(_) => ()
    }
  }
  let grammar = "start " +
    selected_entry +
    "\nrule " +
    selected_entry +
    ": number\nrule number: /[0-9]+/\n"
  let corpus = "====\nbasic number\n====\n42\n----\nerror: ok\nsexp:\n  (" +
    selected_entry +
    " (number))\n"
  let outputs = [
    ("language-pack.json", manifest),
    ("grammar/main.grammar", grammar),
    ("queries/highlights.scm", "(number) @number\n"),
    ("corpus/basic.txt", corpus),
    ("README.md", "# " + selected_name + " Language Pack\n"),
  ]
  for item in outputs {
    match write_file(pack_join(selected_dir, item.0), item.1) {
      Err(message) =>
        return emit_pack_result(
          "init",
          args.format,
          [
            @languagepack.pack_diagnostic(
              "CLI207",
              @languagepack.PackSeverity::Error,
              message,
              path=pack_join(selected_dir, item.0),
            ),
          ],
          "",
          [],
          2,
        )
      Ok(_) => ()
    }
  }
  let source = match load_pack_source_from_dir(selected_dir) {
    Err(error) =>
      return emit_pack_result("init", args.format, [error], "", [], 2)
    Ok(value) => value
  }
  let diagnostics = @languagepack.check_pack(source, pack_options())
  let code = pack_diagnostic_code(diagnostics)
  emit_pack_result(
    "init",
    args.format,
    diagnostics,
    if code < 2 {
      "Language Pack created"
    } else {
      ""
    },
    outputs.map(fn(item) { pack_join(selected_dir, item.0) }),
    code,
  )
}

///|
pub fn cmd_pack(command : PackCommand) -> Int {
  match command {
    Init(args) => cmd_pack_init(args)
    Check(args) => cmd_pack_check(args)
    Test(args) => cmd_pack_test(args)
    Build(args) => cmd_pack_build(args)
    ImportTreeSitter(args) => cmd_pack_import_tree_sitter(args)
    ExportTreeSitter(args) => cmd_pack_export_tree_sitter(args)
  }
}
