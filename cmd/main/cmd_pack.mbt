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
fn pack_relative_from_list_root(root : String, path : String) -> String {
  let direct = pack_relative(root, path)
  let p = pack_slashes(path)
  if direct != p {
    return direct
  }
  let r = pack_slashes(root).trim_end(chars=['/']).to_string()
  let marker = "/" + r + "/"
  if p.has_prefix(r + "/") {
    return p[r.length() + 1:].to_string()
  }
  if p.has_suffix("/" + r) {
    return ""
  }
  if p.length() >= marker.length() {
    for i in 0..<(p.length() - marker.length() + 1) {
      if p[i:i + marker.length()].to_string() == marker {
        return p[i + marker.length():].to_string()
      }
    }
  }
  direct
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
  let tool_targets = args.targets.filter(fn(target) {
    target == PackBuildTarget::Lsp ||
    target == PackBuildTarget::Vscode ||
    target == PackBuildTarget::Web
  })
  if !tool_targets.is_empty() {
    match pack_check_tool_scanner(bundle) {
      Some(message) => error = Some((args.directory, message))
      None => {
        let bundle_output = pack_join(
          pack_join(root, "bundle"),
          bundle.pack_id + ".language-bundle.json",
        )
        match pack_write_text(bundle_output, json) {
          Ok(_) => artifacts.push(bundle_output)
          Err(message) => error = Some((bundle_output, message))
        }
      }
    }
  }
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
      Lsp =>
        match pack_generate_lsp(root, bundle, json) {
          Ok(paths) => artifacts.append(paths)
          Err(value) => error = Some(value)
        }
      Vscode =>
        match pack_generate_vscode(root, bundle, json) {
          Ok(paths) => artifacts.append(paths)
          Err(value) => error = Some(value)
        }
      Web =>
        match pack_generate_web(root, bundle, json) {
          Ok(paths) => artifacts.append(paths)
          Err(value) => error = Some(value)
        }
    }
  }
  if error is None && !tool_targets.is_empty() {
    match
      pack_write_toolgen_report(
        root, bundle, json, tool_targets, artifacts, diagnostics,
      ) {
      Ok(path) => artifacts.push(path)
      Err(value) => error = Some(value)
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
    "queries/folding.scm" => Some("folding")
    "queries/modules.scm" => Some("modules")
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
        let relative = pack_relative_from_list_root(directory, path)
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
fn pack_copy_file(source : String, output : String) -> Result[Unit, String] {
  let bytes = match read_bytes(source) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match make_dir(pack_parent(output)) {
    Err(error) => Err(error)
    Ok(_) => write_bytes(output, bytes)
  }
}

///|
fn pack_json_string_array(values : Array[String]) -> String {
  "[" +
  values.map(fn(value) { "\"" + json_escape(value) + "\"" }).join(",") +
  "]"
}

///|
fn pack_concat(parts : Array[String]) -> String {
  let buf = StringBuilder::new()
  for part in parts {
    buf.write_string(part)
  }
  buf.to_string()
}

///|
fn pack_extension_name(value : String) -> String {
  if value.has_prefix(".") {
    value[1:].to_string()
  } else {
    value
  }
}

///|
fn pack_extension_associations(bundle : @languagepack.LanguageBundle) -> String {
  let fields = bundle.pack_extensions.map(fn(ext) {
    "\"" +
    json_escape(pack_extension_name(ext)) +
    "\":\"" +
    json_escape(bundle.pack_id) +
    "\""
  })
  "{" + fields.join(",") + "}"
}

///|
fn pack_vscode_name_char(ch : Char) -> Char? {
  let lower = if ch >= 'A' && ch <= 'Z' {
    (ch.to_int() + 32).unsafe_to_char()
  } else {
    ch
  }
  if (lower >= 'a' && lower <= 'z') || (lower >= '0' && lower <= '9') {
    Some(lower)
  } else if lower == '-' || lower == '_' || lower == '.' {
    Some('-')
  } else {
    None
  }
}

///|
fn pack_vscode_extension_name(pack_id : String) -> String {
  let buf = StringBuilder::new()
  let mut last_dash = true
  for i in 0..<pack_id.length() {
    match pack_vscode_name_char(pack_id[i].to_int().unsafe_to_char()) {
      Some('-') =>
        if !last_dash {
          buf.write_char('-')
          last_dash = true
        }
      Some(ch) => {
        buf.write_char(ch)
        last_dash = false
      }
      None => ()
    }
  }
  let normalized = buf.to_string().trim_end(chars=['-']).to_string()
  "moonparse-" + (if normalized.is_empty() { "language" } else { normalized })
}

///|
fn pack_textmate_grammar(
  pack_id : String,
  extensions : Array[String],
) -> String {
  "{\"scopeName\":\"source." +
  json_escape(pack_id) +
  "\",\"fileTypes\":" +
  pack_json_string_array(extensions.map(pack_extension_name)) +
  ",\"patterns\":[]}"
}

///|
fn pack_vscode_file_watch_glob(extensions : Array[String]) -> String {
  let normalized = extensions.map(pack_extension_name)
  if normalized.is_empty() {
    "**/*"
  } else if normalized.length() == 1 {
    "**/*." + normalized[0]
  } else {
    "**/*.{" + normalized.join(",") + "}"
  }
}

///|
fn pack_build_target_name(target : PackBuildTarget) -> String {
  match target {
    Bundle => "bundle"
    Moonbit => "moonbit"
    Wasm => "wasm"
    Npm => "npm"
    Lsp => "lsp"
    Vscode => "vscode"
    Web => "web"
  }
}

///|
fn pack_check_tool_scanner(bundle : @languagepack.LanguageBundle) -> String? {
  match bundle.scanner {
    None => None
    Some(scanner) if scanner.id == "python-indent" && scanner.api_version == 1 =>
      None
    Some(scanner) =>
      Some(
        "tool targets only support scanner-less packs or python-indent@1; found " +
        scanner.id +
        "@" +
        scanner.api_version.to_string(),
      )
  }
}

///|
fn pack_copy_runtime_files(
  directory : String,
) -> Result[Array[String], (String, String)] {
  let outputs = [
    ("wasm/moonparse.js", pack_join(directory, "moonparse.js")),
    ("wasm/moonparse.d.ts", pack_join(directory, "moonparse.d.ts")),
    ("wasm/moonparse.wasm", pack_join(directory, "moonparse.wasm")),
  ]
  let paths : Array[String] = []
  for item in outputs {
    let source = item.0
    let output = item.1
    match pack_copy_file(source, output) {
      Err(error) => return Err((output, error))
      Ok(_) => paths.push(output)
    }
  }
  Ok(paths)
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
    (
      #|  let provider = @grammars.builtin_pack_scanner_provider(bundle)
      #|  @languagepack.parse_bundle(bundle, source, scanner_provider=provider)
    )
  } else {
    (
      #|  @languagepack.parse_bundle(bundle, source)
    )
  }
  let module_text = pack_concat([
    (
      #|{"name":"moonparse-language/
    ),
    bundle.pack_id,
    (
      #|","version":"
    ),
    bundle.pack_version,
    (
      #|","deps":{"caiklonghuan/MoonParse":"0.1.0"}}
    ),
  ])
  let package_text =
    #|import {
    #|  "caiklonghuan/MoonParse/languagepack" @languagepack,
    #|  "caiklonghuan/MoonParse/grammars" @grammars,
    #|  "caiklonghuan/MoonParse/query" @query,
    #|  "caiklonghuan/MoonParse/runtime" @runtime,
    #|}
  let source_text = pack_concat([
    (
      #|///|
    ),
    "\n",
    (
      #|pub let bundle_json : String = "
    ),
    json_escape(json),
    (
      #|"
    ),
    "\n\n",
    (
      #|///|
    ),
    "\n",
    (
      #|pub fn load_bundle() -> Result[@languagepack.LanguageBundle, Array[@languagepack.PackDiagnostic]] {
    ),
    "\n",
    (
      #|  @languagepack.bundle_from_json(bundle_json)
    ),
    "\n}\n\n",
    (
      #|///|
    ),
    "\n",
    (
      #|pub fn parse(source : String) -> Result[@runtime.CstNode, @languagepack.PackDiagnostic] {
    ),
    "\n",
    (
      #|  let bundle = load_bundle().unwrap()
    ),
    "\n",
    scanner_code,
    "\n}\n\n",
    (
      #|///|
    ),
    "\n",
    (
      #|pub fn query(kind : @languagepack.BundleQueryKind, tree : @runtime.CstNode, source : String) -> Result[Array[@query.CaptureResult], @languagepack.PackDiagnostic] {
    ),
    "\n",
    (
      #|  let bundle = load_bundle().unwrap()
    ),
    "\n",
    (
      #|  @languagepack.exec_bundle_query(bundle, kind, tree, source)
    ),
    "\n}\n",
  ])
  let files = [
    (mod_path, module_text),
    (pkg_path, package_text),
    (source_path, source_text),
  ]
  for item in files {
    let path = item.0
    let content = item.1
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
  for item in outputs {
    let source = item.0
    let output = item.1
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
  let entry_text = pack_concat([
    (
      #|import { loadMoonParse } from "./moonparse.js";
    ),
    "\n",
    (
      #|export const bundleJson = "
    ),
    json_escape(json),
    (
      #|";
    ),
    "\n",
    (
      #|export async function loadLanguage(wasmUrl = "./moonparse.wasm") {
    ),
    "\n",
    (
      #|  const moonparse = await loadMoonParse(wasmUrl);
    ),
    "\n",
    (
      #|  return moonparse.loadBundle(bundleJson);
    ),
    "\n}\n",
  ])
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
    (
      pack_join(directory, "package.json"),
      pack_concat([
        (
          #|{"name":"
        ),
        json_escape(name),
        (
          #|","version":"
        ),
        json_escape(bundle.pack_version),
        (
          #|","type":"module","main":"index.js","types":"index.d.ts","files":["index.js","index.d.ts","language-bundle.json","README.md"],"peerDependencies":{"moonparse":"^0.1.0"}}
        ),
      ]),
    ),
    (pack_join(directory, "language-bundle.json"), json),
    (
      pack_join(directory, "index.js"),
      pack_concat([
        (
          #|export const bundleJson = "
        ),
        json_escape(json),
        (
          #|";
        ),
        "\n",
        (
          #|export function loadLanguage(moonparse) { return moonparse.loadBundle(bundleJson); }
        ),
        "\n",
      ]),
    ),
    (
      pack_join(directory, "index.d.ts"),
      pack_concat([
        (
          #|import type { MoonLanguage, MoonParseInstance } from "moonparse";
        ),
        "\n",
        (
          #|export declare const bundleJson: string;
        ),
        "\n",
        (
          #|export declare function loadLanguage(moonparse: MoonParseInstance): MoonLanguage;
        ),
        "\n",
      ]),
    ),
    (
      pack_join(directory, "README.md"),
      "# " + bundle.pack_name + " language bundle\n\nGenerated by MoonParse.\n",
    ),
  ]
  for item in files {
    let path = item.0
    let content = item.1
    match pack_write_text(path, content) {
      Err(error) => return Err((path, error))
      Ok(_) => ()
    }
  }
  Ok(files.map(fn(item) { item.0 }))
}

///|
fn pack_generated_lsp_config(bundle : @languagepack.LanguageBundle) -> String {
  let extensions = bundle.pack_extensions.map(pack_extension_name)
  pack_concat([
    (
      #|export interface ServerConfig {
      #|  trace: ServerTraceLevel;
      #|  maxDiagnostics: number;
      #|  enabledExtensions: string[];
      #|  grammarAssociations: Record<string, string>;
      #|  incrementalParse: boolean;
      #|  wasmPath: string;
      #|  debounceMs: number;
      #|  languageBundles: Array<{ path: string; extensions?: string[] }>;
      #|  workspaceIndex: WorkspaceIndexConfig;
      #|}
      #|
      #|export type ServerTraceLevel = "off" | "messages" | "verbose";
      #|
      #|export interface WorkspaceIndexConfig {
      #|  enabled: boolean;
      #|  maxFileBytes: number;
      #|  maxFiles: number;
      #|  parseTimeoutMs: number;
      #|  idleEvictMs: number;
      #|}
      #|
      #|export const defaultConfig: ServerConfig = {
      #|  trace: "off",
      #|  maxDiagnostics: 256,
      #|  enabledExtensions: 
    ),
    pack_json_string_array(extensions),
    (
      #|,
      #|  grammarAssociations: 
    ),
    pack_extension_associations(bundle),
    (
      #|,
      #|  incrementalParse: true,
      #|  wasmPath: "./moonparse.wasm",
      #|  debounceMs: 100,
      #|  languageBundles: [{ path: "./
    ),
    json_escape(bundle.pack_id),
    (
      #|.language-bundle.json", extensions: 
    ),
    pack_json_string_array(extensions),
    (
      #| }],
      #|  workspaceIndex: {
      #|    enabled: true,
      #|    maxFileBytes: 1000000,
      #|    maxFiles: 2000,
      #|    parseTimeoutMs: 5000,
      #|    idleEvictMs: 300000,
      #|  },
      #|};
      #|
      #|export function mergeConfig(
      #|  defaults: ServerConfig,
      #|  overrides: Partial<ServerConfig> | undefined,
      #|): ServerConfig {
      #|  const value = overrides ?? {};
      #|  return {
      #|    trace: value.trace ?? defaults.trace,
      #|    maxDiagnostics: value.maxDiagnostics ?? defaults.maxDiagnostics,
      #|    enabledExtensions: [...(value.enabledExtensions ?? defaults.enabledExtensions)],
      #|    grammarAssociations: { ...(value.grammarAssociations ?? defaults.grammarAssociations) },
      #|    incrementalParse: value.incrementalParse ?? defaults.incrementalParse,
      #|    wasmPath: value.wasmPath ?? defaults.wasmPath,
      #|    debounceMs: value.debounceMs ?? defaults.debounceMs,
      #|    languageBundles: [...(value.languageBundles ?? defaults.languageBundles)],
      #|    workspaceIndex: {
      #|      enabled: value.workspaceIndex?.enabled ?? defaults.workspaceIndex.enabled,
      #|      maxFileBytes: value.workspaceIndex?.maxFileBytes ?? defaults.workspaceIndex.maxFileBytes,
      #|      maxFiles: value.workspaceIndex?.maxFiles ?? defaults.workspaceIndex.maxFiles,
      #|      parseTimeoutMs: value.workspaceIndex?.parseTimeoutMs ?? defaults.workspaceIndex.parseTimeoutMs,
      #|      idleEvictMs: value.workspaceIndex?.idleEvictMs ?? defaults.workspaceIndex.idleEvictMs,
      #|    },
      #|  };
      #|}
      #|
    ),
  ])
}

///|
fn pack_should_copy_lsp_source(relative : String) -> Bool {
  relative.has_suffix(".ts") &&
  !relative.has_suffix(".test.ts") &&
  !relative.has_suffix(".spec.ts")
}

///|
fn pack_generate_lsp_at(
  directory : String,
  bundle : @languagepack.LanguageBundle,
  json : String,
) -> Result[Array[String], (String, String)] {
  let artifacts : Array[String] = []
  for
    item in [
      ("lsp/package.json", pack_join(directory, "package.json")),
      ("lsp/tsconfig.json", pack_join(directory, "tsconfig.json")),
    ] {
    let source = item.0
    let output = item.1
    match pack_copy_file(source, output) {
      Err(error) => return Err((output, error))
      Ok(_) => artifacts.push(output)
    }
  }
  match pack_copy_runtime_files(directory) {
    Err(value) => return Err(value)
    Ok(paths) => artifacts.append(paths)
  }
  let bundle_path = pack_join(
    directory,
    bundle.pack_id + ".language-bundle.json",
  )
  match pack_write_text(bundle_path, json) {
    Err(error) => return Err((bundle_path, error))
    Ok(_) => artifacts.push(bundle_path)
  }
  match list_files("lsp/src") {
    Err(error) => return Err(("lsp/src", error))
    Ok(paths) =>
      for source in paths {
        let relative = pack_relative_from_list_root("lsp/src", source)
        if !pack_should_copy_lsp_source(relative) {
          continue
        }
        let output = pack_join(pack_join(directory, "src"), relative)
        let text = if relative == "config.ts" {
          pack_generated_lsp_config(bundle)
        } else {
          match read_file(source) {
            Err(error) => return Err((source, error))
            Ok(value) =>
              value.replace_all(
                old="../../wasm/moonparse.js",
                new="../moonparse.js",
              )
          }
        }
        match pack_write_text(output, text) {
          Err(error) => return Err((output, error))
          Ok(_) => artifacts.push(output)
        }
      }
  }
  Ok(artifacts)
}

///|
fn pack_generate_lsp(
  root : String,
  bundle : @languagepack.LanguageBundle,
  json : String,
) -> Result[Array[String], (String, String)] {
  pack_generate_lsp_at(pack_join(root, "lsp"), bundle, json)
}

///|
fn pack_vscode_package_json(bundle : @languagepack.LanguageBundle) -> String {
  let ext_name = pack_vscode_extension_name(bundle.pack_id)
  pack_concat([
    (
      #|{
      #|  "name": "
    ),
    json_escape(ext_name),
    (
      #|",
      #|  "displayName": "
    ),
    json_escape(bundle.pack_name),
    (
      #|",
      #|  "version": "
    ),
    json_escape(bundle.pack_version),
    (
      #|",
      #|  "publisher": "moonparse",
      #|  "description": "Generated MoonParse language extension for 
    ),
    json_escape(bundle.pack_name),
    (
      #|.",
      #|  "license": "Apache-2.0",
      #|  "engines": { "vscode": "^1.90.0" },
      #|  "main": "./dist/extension.js",
      #|  "icon": "resources/icon.png",
      #|  "activationEvents": ["onLanguage:
    ),
    json_escape(bundle.pack_id),
    (
      #|"],
      #|  "contributes": {
      #|    "languages": [{
      #|      "id": "
    ),
    json_escape(bundle.pack_id),
    (
      #|",
      #|      "aliases": 
    ),
    pack_json_string_array([bundle.pack_name, bundle.pack_id]),
    (
      #|,
      #|      "extensions": 
    ),
    pack_json_string_array(bundle.pack_extensions),
    (
      #|,
      #|      "configuration": "./language-configuration.json"
      #|    }],
      #|    "grammars": [{
      #|      "language": "
    ),
    json_escape(bundle.pack_id),
    (
      #|",
      #|      "scopeName": "source.
    ),
    json_escape(bundle.pack_id),
    (
      #|",
      #|      "path": "./syntaxes/
    ),
    json_escape(bundle.pack_id),
    (
      #|.tmLanguage.json"
      #|    }],
      #|    "configuration": {
      #|      "title": "
    ),
    json_escape(bundle.pack_name),
    (
      #|",
      #|      "properties": {
      #|        "moonparse.trace": {
      #|          "type": "string",
      #|          "enum": ["off", "messages", "verbose"],
      #|          "default": "off"
      #|        }
      #|      }
      #|    }
      #|  },
      #|  "scripts": {
      #|    "compile": "tsc --noEmit && esbuild src/extension.ts --bundle --platform=node --format=cjs --external:vscode --outfile=dist/extension.js && npm --prefix server install && npm --prefix server run build",
      #|    "package": "vsce package --no-dependencies"
      #|  },
      #|  "dependencies": {
      #|    "vscode-languageclient": "^9.0.1"
      #|  },
      #|  "devDependencies": {
      #|    "@types/node": "^20.14.0",
      #|    "@types/vscode": "^1.90.0",
      #|    "@vscode/vsce": "^3.2.1",
      #|    "esbuild": "^0.25.0",
      #|    "typescript": "^5.5.0"
      #|  },
      #|  "files": [
      #|    "dist",
      #|    "server",
      #|    "syntaxes",
      #|    "resources",
      #|    "language-configuration.json",
      #|    "README.md",
      #|    "CHANGELOG.md"
      #|  ]
      #|}
    ),
  ])
}

///|
fn pack_vscode_extension_ts(bundle : @languagepack.LanguageBundle) -> String {
  pack_concat([
    (
      #|import * as path from "node:path";
      #|import * as vscode from "vscode";
      #|import { LanguageClient, TransportKind, type LanguageClientOptions, type ServerOptions } from "vscode-languageclient/node.js";
      #|
      #|let client: LanguageClient | undefined;
      #|
      #|export async function activate(context: vscode.ExtensionContext): Promise<void> {
      #|  const serverDir = context.asAbsolutePath("server");
      #|  const serverModule = path.join(serverDir, "dist", "server.js");
      #|  const serverOptions: ServerOptions = {
      #|    run: { module: serverModule, transport: TransportKind.ipc, options: { cwd: serverDir } },
      #|    debug: { module: serverModule, transport: TransportKind.ipc, options: { cwd: serverDir } },
      #|  };
      #|  const fileWatcher = vscode.workspace.createFileSystemWatcher("
    ),
    json_escape(pack_vscode_file_watch_glob(bundle.pack_extensions)),
    (
      #|");
      #|  context.subscriptions.push(fileWatcher);
      #|  const clientOptions: LanguageClientOptions = {
      #|    documentSelector: [{ scheme: "file", language: "
    ),
    json_escape(bundle.pack_id),
    (
      #|" }],
      #|    synchronize: { fileEvents: fileWatcher },
      #|    initializationOptions: {
      #|      wasmPath: path.join(serverDir, "moonparse.wasm"),
      #|      languageBundles: [{
      #|        path: path.join(serverDir, "
    ),
    json_escape(bundle.pack_id),
    (
      #|.language-bundle.json"),
      #|        extensions: 
    ),
    pack_json_string_array(bundle.pack_extensions.map(pack_extension_name)),
    (
      #|
      #|      }]
      #|    }
      #|  };
      #|  client = new LanguageClient("moonparse-
    ),
    json_escape(bundle.pack_id),
    (
      #|", "
    ),
    json_escape(bundle.pack_name),
    (
      #|", serverOptions, clientOptions);
      #|  context.subscriptions.push(client);
      #|  await client.start();
      #|}
      #|
      #|export async function deactivate(): Promise<void> {
      #|  if (client) await client.stop();
      #|}
      #|
    ),
  ])
}

///|
fn pack_run_vscode_command(
  directory : String,
  label : String,
  command : String,
) -> Result[Unit, (String, String)] {
  match run_command(directory, command) {
    Ok(_) => Ok(())
    Err(error) => Err((directory, label + " failed: " + error))
  }
}

///|
fn pack_find_vsix(directory : String) -> Result[String, (String, String)] {
  let files = match list_files(directory) {
    Err(error) => return Err((directory, error))
    Ok(value) => value
  }
  for path in files {
    if path.has_suffix(".vsix") {
      let bytes = match read_bytes(path) {
        Err(error) => return Err((path, error))
        Ok(value) => value
      }
      if bytes.length() > 0 {
        return Ok(path)
      }
      return Err((path, "generated VSIX is empty"))
    }
  }
  Err((directory, "npm run package did not produce a .vsix file"))
}

///|
fn pack_vscode_icon_png() -> Bytes {
  let bytes = [
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 128, 0,
    0, 0, 128, 8, 6, 0, 0, 0, 195, 62, 97, 203, 0, 0, 1, 228, 73, 68, 65, 84, 120,
    218, 237, 219, 65, 110, 194, 48, 20, 69, 81, 239, 164, 227, 174, 160, 251, 223,
    21, 170, 42, 181, 243, 74, 72, 64, 98, 251, 61, 114, 6, 119, 138, 248, 206, 81,
    251, 73, 96, 124, 124, 126, 253, 234, 186, 13, 135, 0, 128, 131, 0, 64, 0, 8,
    0, 1, 32, 0, 4, 128, 0, 16, 0, 2, 64, 0, 8, 0, 1, 32, 0, 4, 128, 0, 16, 0, 2,
    64, 0, 8, 0, 1, 32, 0, 4, 128, 0, 16, 0, 2, 64, 0, 8, 0, 1, 32, 0, 4, 192, 129,
    110, 223, 63, 46, 208, 213, 1, 64, 0, 0, 4, 0, 64, 80, 9, 224, 255, 5, 60, 163,
    230, 131, 78, 157, 191, 10, 64, 43, 130, 228, 217, 235, 0, 180, 33, 72, 159,
    187, 18, 64, 11, 130, 134, 153, 107, 1, 164, 35, 104, 153, 183, 26, 64, 42, 130,
    166, 89, 71, 250, 214, 219, 134, 160, 13, 251, 104, 248, 216, 211, 130, 160,
    241, 175, 221, 104, 249, 220, 155, 142, 160, 245, 223, 221, 104, 186, 241, 145,
    138, 160, 121, 223, 25, 109, 119, 190, 210, 16, 156, 185, 203, 0, 240, 224, 192,
    41, 8, 206, 222, 99, 0, 120, 98, 224, 221, 8, 102, 236, 48, 0, 60, 57, 240, 174,
    67, 155, 181, 191, 0, 240, 194, 192, 171, 15, 110, 230, 238, 2, 192, 139, 3,
    175, 58, 188, 217, 123, 11, 0, 7, 6, 158, 125, 128, 43, 118, 22, 0, 14, 14, 60,
    235, 16, 87, 237, 43, 0, 132, 92, 172, 25, 175, 7, 192, 194, 129, 19, 23, 76,
    0, 22, 15, 156, 118, 159, 1, 128, 13, 3, 39, 221, 110, 6, 96, 211, 192, 41, 79,
    29, 1, 216, 56, 112, 194, 247, 14, 0, 216, 60, 240, 238, 111, 30, 1, 16, 48,
    112, 250, 62, 2, 64, 200, 131, 156, 93, 187, 8, 0, 139, 30, 231, 38, 238, 33,
    0, 132, 63, 207, 7, 224, 205, 0, 60, 178, 24, 2, 240, 230, 0, 238, 189, 79, 191,
    14, 190, 16, 0, 63, 15, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 245, 5, 0, 0, 14, 1, 0, 1, 32, 0, 4,
    128, 0, 16, 0, 2, 64, 0, 8, 0, 1, 32, 0, 4, 128, 0, 16, 0, 2, 64, 0, 8, 0, 1,
    32, 0, 4, 128, 0, 16, 0, 2, 64, 0, 8, 0, 1, 32, 0, 4, 128, 0, 16, 0, 2, 64, 0,
    40, 185, 63, 233, 192, 75, 96, 180, 240, 218, 230, 0, 0, 0, 0, 73, 69, 78, 68,
    174, 66, 96, 130,
  ]
  Bytes::makei(bytes.length(), fn(i) { bytes[i].to_byte() })
}

///|
fn pack_generate_vscode(
  root : String,
  bundle : @languagepack.LanguageBundle,
  json : String,
) -> Result[Array[String], (String, String)] {
  let directory = pack_join(root, "vscode")
  let artifacts : Array[String] = []
  match pack_generate_lsp_at(pack_join(directory, "server"), bundle, json) {
    Err(value) => return Err(value)
    Ok(paths) => artifacts.append(paths)
  }
  let syntax_path = pack_join(
    pack_join(directory, "syntaxes"),
    bundle.pack_id + ".tmLanguage.json",
  )
  let files = [
    (pack_join(directory, "package.json"), pack_vscode_package_json(bundle)),
    (
      pack_join(directory, "tsconfig.json"),
      (
        #|{"compilerOptions":{"target":"ES2022","module":"Node16","moduleResolution":"Node16","outDir":"dist","rootDir":"src","strict":true,"skipLibCheck":true,"esModuleInterop":true},"include":["src/**/*.ts"],"exclude":["node_modules","dist"]}
      ),
    ),
    (
      pack_join(pack_join(directory, "src"), "extension.ts"),
      pack_vscode_extension_ts(bundle),
    ),
    (
      pack_join(directory, "language-configuration.json"),
      (
        #|{"comments":{"lineComment":"//"},"brackets":[["{","}"],["[","]"],["(",")"]],"autoClosingPairs":[{"open":"{","close":"}"},{"open":"[","close":"]"},{"open":"(","close":")"},{"open":"\"","close":"\""}]}
      ),
    ),
    (syntax_path, pack_textmate_grammar(bundle.pack_id, bundle.pack_extensions)),
    (
      pack_join(directory, "README.md"),
      "# " + bundle.pack_name + "\n\nGenerated MoonParse VS Code extension.\n",
    ),
    (
      pack_join(directory, "CHANGELOG.md"),
      "# Changelog\n\n## " +
      bundle.pack_version +
      "\n\nGenerated initial package.\n",
    ),
  ]
  for item in files {
    let path = item.0
    let content = item.1
    match pack_write_text(path, content) {
      Err(error) => return Err((path, error))
      Ok(_) => artifacts.push(path)
    }
  }
  let icon_path = pack_join(pack_join(directory, "resources"), "icon.png")
  match make_dir(pack_parent(icon_path)) {
    Err(error) => return Err((icon_path, error))
    Ok(_) =>
      match write_bytes(icon_path, pack_vscode_icon_png()) {
        Err(error) => return Err((icon_path, error))
        Ok(_) => artifacts.push(icon_path)
      }
  }
  match pack_run_vscode_command(directory, "npm install", "npm install") {
    Err(value) => return Err(value)
    Ok(_) => ()
  }
  match
    pack_run_vscode_command(directory, "npm run compile", "npm run compile") {
    Err(value) => return Err(value)
    Ok(_) => ()
  }
  match
    pack_run_vscode_command(directory, "npm run package", "npm run package") {
    Err(value) => return Err(value)
    Ok(_) => ()
  }
  match pack_find_vsix(directory) {
    Err(value) => return Err(value)
    Ok(path) => artifacts.push(path)
  }
  Ok(artifacts)
}

///|
fn pack_web_main_js(bundle : @languagepack.LanguageBundle) -> String {
  pack_concat([
    (
      #|const base = import.meta.env.BASE_URL ?? "/";
      #|const { loadMoonParse } = await import(/* @vite-ignore */ `${base}moonparse.js`);
      #|const source = document.querySelector("#source");
      #|const treeOut = document.querySelector("#tree");
      #|const diagOut = document.querySelector("#diagnostics");
      #|const hlOut = document.querySelector("#highlights");
      #|
      #|const bundleUrl = `${base}
    ),
    json_escape(bundle.pack_id),
    (
      #|.language-bundle.json`;
      #|const mp = await loadMoonParse(`${base}moonparse.wasm`);
      #|const bundleJson = await fetch(bundleUrl).then((r) => r.text());
      #|const language = mp.loadBundle(bundleJson);
      #|
      #|function render() {
      #|  const text = source.value;
      #|  let tree;
      #|  try {
      #|    tree = language.parse(text);
      #|    treeOut.textContent = tree.sexp();
      #|    diagOut.textContent = tree.errorSummary();
      #|    hlOut.textContent = JSON.stringify(language.highlight(tree), null, 2);
      #|  } catch (error) {
      #|    treeOut.textContent = "";
      #|    diagOut.textContent = error instanceof Error ? error.message : String(error);
      #|    hlOut.textContent = "[]";
      #|  } finally {
      #|    tree?.free?.();
      #|  }
      #|}
      #|
      #|source.value = "";
      #|source.addEventListener("input", render);
      #|render();
      #|
    ),
  ])
}

///|
fn pack_generate_web(
  root : String,
  bundle : @languagepack.LanguageBundle,
  json : String,
) -> Result[Array[String], (String, String)] {
  let directory = pack_join(root, "web")
  let public_dir = pack_join(directory, "public")
  let artifacts : Array[String] = []
  match pack_copy_runtime_files(public_dir) {
    Err(value) => return Err(value)
    Ok(paths) => artifacts.append(paths)
  }
  let bundle_path = pack_join(
    public_dir,
    bundle.pack_id + ".language-bundle.json",
  )
  let files = [
    (bundle_path, json),
    (
      pack_join(directory, "package.json"),
      pack_concat([
        (
          #|{"name":"moonparse-web-
        ),
        json_escape(bundle.pack_id),
        (
          #|","version":"
        ),
        json_escape(bundle.pack_version),
        (
          #|","private":true,"type":"module","scripts":{"build":"vite build","preview":"vite preview","dev":"vite"},"devDependencies":{"vite":"^8.0.4"}}
        ),
      ]),
    ),
    (
      pack_join(directory, "index.html"),
      pack_concat([
        (
          #|<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>
        ),
        json_escape(bundle.pack_name),
        (
          #|</title><style>body{font-family:system-ui,sans-serif;margin:0;display:grid;grid-template-columns:1fr 1fr;height:100vh}textarea{width:100%;height:100%;box-sizing:border-box;padding:16px;border:0;border-right:1px solid #ddd;font:14px ui-monospace,monospace}.panels{display:grid;grid-template-rows:1fr auto 1fr;min-width:0}pre{margin:0;padding:16px;overflow:auto;border-bottom:1px solid #ddd;font:13px ui-monospace,monospace}#diagnostics{min-height:48px;background:#f8fafc}</style></head><body><textarea id="source" spellcheck="false"></textarea><div class="panels"><pre id="tree"></pre><pre id="diagnostics"></pre><pre id="highlights"></pre></div><script type="module" src="/src/main.js"></script></body></html>
        ),
      ]),
    ),
    (
      pack_join(pack_join(directory, "src"), "main.js"),
      pack_web_main_js(bundle),
    ),
  ]
  for item in files {
    let path = item.0
    let content = item.1
    match pack_write_text(path, content) {
      Err(error) => return Err((path, error))
      Ok(_) => artifacts.push(path)
    }
  }
  Ok(artifacts)
}

///|
fn pack_write_toolgen_report(
  root : String,
  bundle : @languagepack.LanguageBundle,
  json : String,
  targets : Array[PackBuildTarget],
  artifacts : Array[String],
  diagnostics : Array[@languagepack.PackDiagnostic],
) -> Result[String, (String, String)] {
  let wasm_bytes = match read_bytes("wasm/moonparse.wasm") {
    Err(error) => return Err(("wasm/moonparse.wasm", error))
    Ok(value) => value
  }
  let path = pack_join(root, "toolgen-report.json")
  let bundle_path = pack_join(
    "bundle",
    bundle.pack_id + ".language-bundle.json",
  )
  let report = pack_concat([
    (
      #|{
      #|  "schemaVersion": 1,
      #|  "pack": {
      #|    "id": "
    ),
    json_escape(bundle.pack_id),
    (
      #|",
      #|    "name": "
    ),
    json_escape(bundle.pack_name),
    (
      #|",
      #|    "version": "
    ),
    json_escape(bundle.pack_version),
    (
      #|"
      #|  },
      #|  "targets": 
    ),
    pack_json_string_array(targets.map(pack_build_target_name)),
    (
      #|,
      #|  "bundle": {
      #|    "path": "
    ),
    json_escape(bundle_path),
    (
      #|",
      #|    "sha256": "sha256-
    ),
    @treesitterinterop.sha256_bytes_hex(@utf8.encode(json)),
    (
      #|"
      #|  },
      #|  "runtime": {
      #|    "moonparseVersion": "
    ),
    json_escape(bundle.software_version),
    (
      #|",
      #|    "wasmPath": "wasm/moonparse.wasm",
      #|    "wasmSha256": "sha256-
    ),
    @treesitterinterop.sha256_bytes_hex(wasm_bytes),
    (
      #|"
      #|  },
      #|  "artifacts": 
    ),
    pack_json_string_array(
      artifacts.map(fn(artifact) { pack_relative(root, artifact) }),
    ),
    (
      #|,
      #|  "diagnostics": [
    ),
    diagnostics.map(pack_diag_json).join(","),
    (
      #|]
      #|}
    ),
  ])
  match pack_write_text(path, report) {
    Err(error) => Err((path, error))
    Ok(_) => Ok(path)
  }
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
