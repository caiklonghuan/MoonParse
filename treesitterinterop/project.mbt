///|
fn first_tree_sitter_grammar_object(
  tree_sitter_json : Map[String, Json]?,
) -> Map[String, Json]? {
  match tree_sitter_json {
    Some(root) =>
      match obj_get_array(root, "grammars") {
        Some(values) => {
          for value in values {
            match value {
              Object(object) => return Some(object)
              _ => ()
            }
          }
          None
        }
        None => None
      }
    None => None
  }
}

///|
fn metadata_id(
  source : TreeSitterProjectSource,
  options : TreeSitterImportOptions,
  grammar_root : Map[String, Json],
  tree_sitter_root : Map[String, Json]?,
  package_root : Map[String, Json]?,
) -> String {
  match options.output_id {
    Some(id) => normalize_id(id)
    None => {
      match package_root {
        Some(pkg) =>
          match obj_get_string(pkg, "name") {
            Some(name) => return normalize_id(name)
            None => ()
          }
        None => ()
      }
      match first_tree_sitter_grammar_object(tree_sitter_root) {
        Some(grammar) =>
          match obj_get_string(grammar, "name") {
            Some(name) => return normalize_id(name)
            None => ()
          }
        None => ()
      }
      match tree_sitter_root {
        Some(root) =>
          match obj_get_string(root, "name") {
            Some(name) => return normalize_id(name)
            None => ()
          }
        None => ()
      }
      match obj_get_string(grammar_root, "name") {
        Some(name) => normalize_id(name)
        None =>
          normalize_id(source.project_name.unwrap_or("tree-sitter-import"))
      }
    }
  }
}

///|
fn metadata_name(
  id : String,
  options : TreeSitterImportOptions,
  grammar_root : Map[String, Json],
  tree_sitter_root : Map[String, Json]?,
) -> String {
  match options.output_name {
    Some(name) => name
    None =>
      match first_tree_sitter_grammar_object(tree_sitter_root) {
        Some(grammar) =>
          match obj_get_string(grammar, "name") {
            Some(name) => name
            None =>
              obj_get_string(grammar_root, "name").unwrap_or(title_case_id(id))
          }
        None =>
          obj_get_string(grammar_root, "name").unwrap_or(title_case_id(id))
      }
  }
}

///|
fn metadata_version(
  options : TreeSitterImportOptions,
  package_root : Map[String, Json]?,
) -> String {
  match options.package_version {
    Some(version) => version
    None =>
      match package_root {
        Some(pkg) => obj_get_string(pkg, "version").unwrap_or("0.1.0")
        None => "0.1.0"
      }
  }
}

///|
fn metadata_extensions(
  options : TreeSitterImportOptions,
  tree_sitter_root : Map[String, Json]?,
) -> Array[String] {
  if !options.extensions.is_empty() {
    return options.extensions.map(normalize_extension)
  }
  match first_tree_sitter_grammar_object(tree_sitter_root) {
    Some(grammar) =>
      match obj_get_array(grammar, "file-types") {
        Some(values) =>
          return json_string_values(values).map(normalize_extension)
        None => ()
      }
    None => ()
  }
  match tree_sitter_root {
    Some(root) =>
      match obj_get_array(root, "file-types") {
        Some(values) => json_string_values(values).map(normalize_extension)
        None => []
      }
    None => []
  }
}

///|
fn metadata_entry(
  grammar_name : String,
  grammar_root : Map[String, Json],
) -> String {
  match obj_get_object(grammar_root, "rules") {
    Some(rules) =>
      if rules.contains(grammar_name) {
        grammar_name
      } else if rules.contains("source_file") {
        "source_file"
      } else if rules.contains("program") {
        "program"
      } else if rules.contains("document") {
        "document"
      } else {
        let names : Array[String] = []
        for name, _ in rules {
          names.push(name)
        }
        names.sort()
        if names.is_empty() {
          grammar_name
        } else {
          names[0]
        }
      }
    None => grammar_name
  }
}

///|
fn query_status(
  path : String,
  text : String?,
) -> (String, Array[@languagepack.PackDiagnostic]) {
  match text {
    None => ("missing", [])
    Some(value) =>
      match @query.compile(value) {
        Ok(_) => ("compatible", [])
        Err(error) =>
          (
            "incompatible",
            [
              ts_diag(
                "TS401",
                @languagepack.PackSeverity::Error,
                "Tree-sitter query is not compatible: \{error}",
                path~,
              ),
            ],
          )
      }
  }
}

///|
pub fn convert_tree_sitter_query(
  path : String,
  text : String,
  _options : TreeSitterImportOptions,
) -> (String, Array[@languagepack.PackDiagnostic]) {
  let (_, diagnostics) = query_status(path, Some(text))
  (text, diagnostics)
}

///|
fn manifest_json(
  id : String,
  name : String,
  version : String,
  entry : String,
  extensions : Array[String],
  scanner_id : String?,
) -> String {
  let scanner = match scanner_id {
    Some(id) =>
      ",\n  \"scanner\": {\"id\": " + json_string(id) + ", \"apiVersion\": 1}"
    None => ""
  }
  "{\n  \"schemaVersion\": 1,\n  \"id\": " +
  json_string(id) +
  ",\n  \"name\": " +
  json_string(name) +
  ",\n  \"version\": " +
  json_string(version) +
  ",\n  \"maturity\": \"imported\",\n  \"entryRule\": " +
  json_string(entry) +
  ",\n  \"extensions\": " +
  json_string_array(extensions) +
  ",\n  \"compatibility\": {\"minimumMoonParseVersion\": \"0.1.0\", \"maximumMoonParseVersionExclusive\": \"0.2.0\"},\n  \"grammar\": {\"path\": \"grammar/main.grammar\", \"format\": \"dsl\"},\n  \"queries\": {\"highlights\": \"queries/highlights.scm\", \"locals\": \"queries/locals.scm\"}" +
  scanner +
  ",\n  \"corpus\": {\"directory\": \"corpus\", \"format\": \"moonparse-corpus-v2\"},\n  \"build\": {\"allowAmbiguousConflicts\": true}\n}\n"
}

///|
fn add_text(files : Map[String, Bytes], path : String, text : String) -> Unit {
  files[path] = @utf8.encode(text)
}

///|
pub fn import_tree_sitter_project(
  source : TreeSitterProjectSource,
  options : TreeSitterImportOptions,
) -> TreeSitterImportResult {
  let diagnostics : Array[@languagepack.PackDiagnostic] = []
  let grammar_root = match parse_json_object(source.grammar_json) {
    Ok(value) => value
    Err(error) => {
      diagnostics.push(
        ts_diag(
          "TS101",
          @languagepack.PackSeverity::Error,
          "invalid grammar.json: " + error,
        ),
      )
      let report : TreeSitterCompatibilityReport = {
        grammar_path: "grammar.json",
        grammar_name: "tree-sitter-import",
        diagnostics,
        unsupported_nodes: [],
        generated_inline_tokens: [],
        highlights_status: "missing",
        locals_status: "missing",
        tags_status: "missing",
        scanner_required: false,
        scanner_id: None,
        scanner_status: "none",
      }
      return { files: Map::new(), diagnostics, report }
    }
  }
  let tree_sitter_root = parse_optional_json_object(source.tree_sitter_json)
  let package_root = parse_optional_json_object(source.package_json)
  let grammar_import = import_tree_sitter_grammar(
    "grammar.json",
    source.grammar_json,
    options,
  )
  diagnostics.push_iter(grammar_import.diagnostics.iter())
  let grammar_name = grammar_import.report.grammar_name
  let id = metadata_id(
    source, options, grammar_root, tree_sitter_root, package_root,
  )
  let name = metadata_name(id, options, grammar_root, tree_sitter_root)
  let version = metadata_version(options, package_root)
  let extensions = metadata_extensions(options, tree_sitter_root)
  let entry = metadata_entry(grammar_name, grammar_root)
  let ext = match obj_get_array(grammar_root, "externals") {
    Some(values) => symbol_list(values)
    None => []
  }
  let scanner_id : String? = if ext.is_empty() {
    None
  } else {
    Some("tree-sitter-" + id)
  }
  if scanner_id is Some(_) {
    diagnostics.push(
      ts_diag(
        "TS501",
        @languagepack.PackSeverity::Error,
        "Tree-sitter external scanner is required but no MoonParse scanner is available in P1b fallback",
        path="grammar.json",
        hint="implement a PackScannerProvider for tree-sitter-" + id,
      ),
    )
  }
  let files = grammar_import.files
  add_text(
    files,
    "language-pack.json",
    manifest_json(id, name, version, entry, extensions, scanner_id),
  )
  let highlights = source.queries.get("highlights").unwrap_or("")
  let locals = source.queries.get("locals").unwrap_or("")
  let tags = source.queries.get("tags").unwrap_or("")
  add_text(files, "queries/highlights.scm", highlights)
  add_text(files, "queries/locals.scm", locals)
  add_text(files, "queries/tags.scm", tags)
  let (highlight_status, highlight_diag) = query_status(
    "queries/highlights.scm",
    if highlights.is_empty() {
      None
    } else {
      Some(highlights)
    },
  )
  let (locals_status, locals_diag) = query_status(
    "queries/locals.scm",
    if locals.is_empty() {
      None
    } else {
      Some(locals)
    },
  )
  diagnostics.push_iter(highlight_diag.iter())
  diagnostics.push_iter(locals_diag.iter())
  let tags_status = if tags.is_empty() { "missing" } else { "preserved" }
  source.corpus.each(fn(path, text) {
    let (converted, corpus_diag) = convert_tree_sitter_corpus(
      path, text, options,
    )
    diagnostics.push_iter(corpus_diag.iter())
    add_text(files, "corpus/" + path, converted)
    add_text(files, "corpus-tree-sitter/" + path, text)
  })
  add_text(files, "tree-sitter-source.json", source_manifest_to_json(source))
  let report : TreeSitterCompatibilityReport = {
    grammar_path: "grammar.json",
    grammar_name,
    diagnostics,
    unsupported_nodes: grammar_import.report.unsupported_nodes,
    generated_inline_tokens: grammar_import.report.generated_inline_tokens,
    highlights_status: highlight_status,
    locals_status,
    tags_status,
    scanner_required: scanner_id is Some(_),
    scanner_id,
    scanner_status: if scanner_id is Some(_) {
      "missing"
    } else {
      "none"
    },
  }
  add_text(
    files,
    "tree-sitter-compatibility.json",
    compatibility_report_to_json(report),
  )
  add_text(
    files,
    "README.md",
    "# " +
    name +
    " Language Pack\n\nGenerated from Tree-sitter grammar.json by MoonParse.\n",
  )
  { files, diagnostics, report }
}

///|
pub fn compatibility_report_to_json(
  report : TreeSitterCompatibilityReport,
) -> String {
  "{\"schemaVersion\":1,\"source\":{\"grammarPath\":" +
  json_string(report.grammar_path) +
  ",\"grammarName\":" +
  json_string(report.grammar_name) +
  "},\"diagnostics\":[" +
  report.diagnostics.map(diag_json).join(",") +
  "],\"grammar\":{\"unsupportedNodes\":" +
  json_string_array(report.unsupported_nodes) +
  ",\"generatedInlineTokens\":" +
  json_string_array(report.generated_inline_tokens) +
  "},\"queries\":{\"highlights\":" +
  json_string(report.highlights_status) +
  ",\"locals\":" +
  json_string(report.locals_status) +
  ",\"tags\":" +
  json_string(report.tags_status) +
  "},\"scanner\":{\"required\":" +
  report.scanner_required.to_string() +
  ",\"id\":" +
  json_optional_string(report.scanner_id) +
  ",\"status\":" +
  json_string(report.scanner_status) +
  "}}\n"
}

///|
pub fn source_manifest_to_json(source : TreeSitterProjectSource) -> String {
  let file_entries : Array[String] = []
  source.source_files.each(fn(path, bytes) {
    file_entries.push(
      json_string(path) + ":" + json_string("sha256-" + sha256_bytes_hex(bytes)),
    )
  })
  file_entries.sort()
  "{\"schemaVersion\":1,\"url\":\"\",\"commit\":\"\",\"downloadDate\":\"\",\"license\":\"\",\"files\":{" +
  file_entries.join(",") +
  "}}\n"
}
