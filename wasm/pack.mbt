///|
suberror PackWireError {
  InvalidWire(String)
} derive(Debug)

///|
impl Show for PackWireError with output(self, logger) {
  match self {
    InvalidWire(message) => logger.write_string(message)
  }
}

///|
fn pack_wire_diagnostic(message : String) -> @languagepack.PackDiagnostic {
  @languagepack.pack_diagnostic(
    "PACK800",
    @languagepack.PackSeverity::Error,
    message,
    path="<project>",
  )
}

///|
fn pack_wire_field(
  object : Map[String, Json],
  name : String,
) -> Json raise PackWireError {
  match object.get(name) {
    Some(value) => value
    None => raise InvalidWire("missing required field '" + name + "'")
  }
}

///|
fn pack_wire_object(value : Json) -> Map[String, Json] raise PackWireError {
  match value {
    Object(object) => object
    _ => raise InvalidWire("expected object")
  }
}

///|
fn pack_wire_string(value : Json) -> String raise PackWireError {
  match value {
    String(text) => text
    _ => raise InvalidWire("expected string")
  }
}

///|
fn pack_wire_int(value : Json) -> Int raise PackWireError {
  match value {
    Number(number, ..) => number.to_int()
    _ => raise InvalidWire("expected integer")
  }
}

///|
fn pack_wire_array(value : Json) -> Array[Json] raise PackWireError {
  match value {
    Array(values) => values
    _ => raise InvalidWire("expected array")
  }
}

///|
fn pack_valid_project_path(path : String) -> Bool {
  if path.is_empty() || path.has_prefix("/") || path.contains("\\") {
    return false
  }
  for part in path.split("/") {
    if part.is_empty() || part == "." || part == ".." {
      return false
    }
  }
  true
}

///|
fn pack_project_source(
  project_json : String,
) -> Result[
  @languagepack.LanguagePackSource,
  Array[@languagepack.PackDiagnostic],
] {
  let root = @json.parse(project_json) catch {
    error =>
      return Err([pack_wire_diagnostic("invalid project JSON: \{error}")])
  }
  let diagnostics : Array[@languagepack.PackDiagnostic] = []
  let source = try {
    let project = pack_wire_object(root)
    let file_values = pack_wire_object(pack_wire_field(project, "files"))
    let files : Map[String, Bytes] = {}
    let mut manifest : String? = None
    file_values.each(fn(path, value) {
      if !pack_valid_project_path(path) {
        diagnostics.push(
          pack_wire_diagnostic("invalid project path '" + path + "'"),
        )
      } else {
        match value {
          String(text) =>
            if path == "language-pack.json" {
              manifest = Some(text)
            } else {
              files[path] = @utf8.encode(text)
            }
          _ =>
            diagnostics.push(
              pack_wire_diagnostic(
                "project file '" + path + "' must contain UTF-8 text",
              ),
            )
        }
      }
    })
    match manifest {
      Some(text) => Some(@languagepack.LanguagePackSource::new(text, files))
      None => {
        diagnostics.push(
          pack_wire_diagnostic("project must contain language-pack.json"),
        )
        None
      }
    }
  } catch {
    error => {
      diagnostics.push(pack_wire_diagnostic("invalid project: \{error}"))
      None
    }
  }
  match source {
    Some(source) if !@languagepack.has_pack_errors(diagnostics) => Ok(source)
    _ => Err(diagnostics)
  }
}

///|
fn pack_build_options() -> @languagepack.PackBuildOptions {
  {
    software_version: moonparse_version(),
    known_scanners: @grammars.known_pack_scanners(),
  }
}

///|
fn pack_severity_rank(severity : @languagepack.PackSeverity) -> Int {
  match severity {
    @languagepack.PackSeverity::Info => 0
    @languagepack.PackSeverity::Warning => 1
    @languagepack.PackSeverity::Error => 2
  }
}

///|
fn pack_compare_diagnostics(
  left : @languagepack.PackDiagnostic,
  right : @languagepack.PackDiagnostic,
) -> Int {
  let by_severity = pack_severity_rank(left.severity).compare(
    pack_severity_rank(right.severity),
  )
  if by_severity != 0 {
    return by_severity
  }
  let by_path = left.path.compare(right.path)
  if by_path != 0 {
    return by_path
  }
  let by_line = left.line.compare(right.line)
  if by_line != 0 {
    return by_line
  }
  let by_column = left.column.compare(right.column)
  if by_column != 0 {
    return by_column
  }
  left.code.compare(right.code)
}

///|
fn pack_severity_text(severity : @languagepack.PackSeverity) -> String {
  match severity {
    @languagepack.PackSeverity::Info => "info"
    @languagepack.PackSeverity::Warning => "warning"
    @languagepack.PackSeverity::Error => "error"
  }
}

///|
fn pack_diagnostics_json(
  diagnostics : Array[@languagepack.PackDiagnostic],
) -> String {
  diagnostics.sort_by(pack_compare_diagnostics)
  let output = StringBuilder::new()
  output.write_char('[')
  for index in 0..<diagnostics.length() {
    if index > 0 {
      output.write_char(',')
    }
    let diagnostic = diagnostics[index]
    output.write_char('{')
    write_kvs(output, "code", diagnostic.code)
    output.write_char(',')
    write_kvs(output, "severity", pack_severity_text(diagnostic.severity))
    output.write_char(',')
    write_kvs(output, "message", diagnostic.message)
    output.write_char(',')
    write_kvs(output, "path", diagnostic.path)
    output.write_char(',')
    write_kvi(output, "line", diagnostic.line)
    output.write_char(',')
    write_kvi(output, "column", diagnostic.column)
    output.write_string(",\"hint\":")
    match diagnostic.hint {
      Some(hint) => write_jstr(output, hint)
      None => output.write_string("null")
    }
    output.write_char('}')
  }
  output.write_char(']')
  output.to_string()
}

///|
fn pack_check_envelope(
  ok : Bool,
  diagnostics : Array[@languagepack.PackDiagnostic],
) -> String {
  "{\"ok\":" +
  ok.to_string() +
  ",\"diagnostics\":" +
  pack_diagnostics_json(diagnostics) +
  "}"
}

///|
fn corpus_failure_kind_text(kind : @languagepack.CorpusFailureKind) -> String {
  match kind {
    @languagepack.CorpusFailureKind::Error => "error"
    @languagepack.CorpusFailureKind::Sexp => "sexp"
    @languagepack.CorpusFailureKind::Contains => "contains"
    @languagepack.CorpusFailureKind::NotContains => "notContains"
    @languagepack.CorpusFailureKind::Parse => "parse"
  }
}

///|
fn corpus_failure_json(failure : @languagepack.CorpusFailure) -> String {
  let output = StringBuilder::new()
  output.write_char('{')
  write_kvs(output, "kind", corpus_failure_kind_text(failure.kind))
  output.write_char(',')
  write_kvs(output, "expected", failure.expected)
  output.write_char(',')
  write_kvs(output, "actual", failure.actual)
  output.write_char(',')
  write_kvs(output, "message", failure.message)
  output.write_char('}')
  output.to_string()
}

///|
fn corpus_case_json(case : @languagepack.CorpusTestResult) -> String {
  let output = StringBuilder::new()
  output.write_char('{')
  write_kvs(output, "path", case.path)
  output.write_char(',')
  write_kvi(output, "caseIndex", case.case_index)
  output.write_char(',')
  write_kvs(output, "name", case.name)
  output.write_char(',')
  write_kvi(output, "sourceLine", case.source_line)
  output.write_char(',')
  write_kvs(output, "actualError", case.actual_error)
  output.write_char(',')
  write_kvs(output, "actualSexp", case.actual_sexp)
  output.write_string(",\"failures\":[")
  for index in 0..<case.failures.length() {
    if index > 0 {
      output.write_char(',')
    }
    output.write_string(corpus_failure_json(case.failures[index]))
  }
  output.write_string("],")
  write_kvb(output, "passed", case.passed)
  output.write_char('}')
  output.to_string()
}

///|
fn pack_test_scanner_provider(
  source : @languagepack.LanguagePackSource,
) -> @languagepack.PackScannerProvider? {
  let pack = match @languagepack.load_pack(source) {
    Ok(pack) => pack
    Err(_) => return None
  }
  match pack.scanner {
    Some(scanner) if scanner.id == "python-indent" && scanner.api_version == 1 =>
      Some({
        id: scanner.id,
        api_version: scanner.api_version,
        create: fn(table) { @grammars.python_indent_scanner(table) },
      })
    Some(scanner) if scanner.id == "tree-sitter-rust" &&
      scanner.api_version == 1 =>
      Some({
        id: scanner.id,
        api_version: scanner.api_version,
        create: fn(table) { @grammars.tree_sitter_rust_scanner(table) },
      })
    _ => None
  }
}

///|
pub fn pack_check(project_json : String) -> String {
  match pack_project_source(project_json) {
    Err(diagnostics) => pack_check_envelope(false, diagnostics)
    Ok(source) => {
      let diagnostics = @languagepack.check_pack(source, pack_build_options())
      pack_check_envelope(
        !@languagepack.has_pack_errors(diagnostics),
        diagnostics,
      )
    }
  }
}

///|
pub fn pack_build(project_json : String) -> String {
  match pack_project_source(project_json) {
    Err(diagnostics) =>
      "{\"ok\":false,\"diagnostics\":" +
      pack_diagnostics_json(diagnostics) +
      ",\"bundle\":null}"
    Ok(source) => {
      let report = @languagepack.build_bundle_report(
        source,
        pack_build_options(),
      )
      match report.bundle {
        None =>
          "{\"ok\":false,\"diagnostics\":" +
          pack_diagnostics_json(report.diagnostics) +
          ",\"bundle\":null}"
        Some(bundle) =>
          "{\"ok\":true,\"diagnostics\":" +
          pack_diagnostics_json(report.diagnostics) +
          ",\"bundle\":" +
          @languagepack.bundle_to_json(bundle) +
          "}"
      }
    }
  }
}

///|
pub fn pack_test(project_json : String) -> String {
  match pack_project_source(project_json) {
    Err(diagnostics) =>
      "{\"ok\":false,\"diagnostics\":" +
      pack_diagnostics_json(diagnostics) +
      ",\"cases\":[]}"
    Ok(source) => {
      let provider = pack_test_scanner_provider(source)
      let report = match provider {
        Some(provider) =>
          @languagepack.test_pack(
            source,
            pack_build_options(),
            scanner_provider=provider,
          )
        None => @languagepack.test_pack(source, pack_build_options())
      }
      let ok = !@languagepack.has_pack_errors(report.diagnostics)
      let output = StringBuilder::new()
      output.write_string("{\"ok\":")
      output.write_string(ok.to_string())
      output.write_string(",\"diagnostics\":")
      output.write_string(pack_diagnostics_json(report.diagnostics))
      output.write_string(",\"cases\":[")
      for index in 0..<report.cases.length() {
        if index > 0 {
          output.write_char(',')
        }
        output.write_string(corpus_case_json(report.cases[index]))
      }
      output.write_string("]}")
      output.to_string()
    }
  }
}

///|
pub fn corpus_rewrite_snapshots(request_json : String) -> String {
  let root = @json.parse(request_json) catch {
    error =>
      return "{\"ok\":false,\"diagnostics\":" +
        pack_diagnostics_json([
          pack_wire_diagnostic("invalid snapshot request JSON: \{error}"),
        ]) +
        ",\"updatedText\":null}"
  }
  let diagnostics : Array[@languagepack.PackDiagnostic] = []
  let updated : String? = try {
    let request = pack_wire_object(root)
    let path = pack_wire_string(pack_wire_field(request, "path"))
    if !pack_valid_project_path(path) {
      raise InvalidWire("invalid corpus path '" + path + "'")
    }
    let text = pack_wire_string(pack_wire_field(request, "text"))
    let format = pack_wire_string(pack_wire_field(request, "format"))
    let update_values = pack_wire_array(pack_wire_field(request, "updates"))
    let updates : Array[@languagepack.CorpusSnapshotUpdate] = []
    for value in update_values {
      let update = pack_wire_object(value)
      updates.push({
        case_index: pack_wire_int(pack_wire_field(update, "caseIndex")),
        case_name: pack_wire_string(pack_wire_field(update, "caseName")),
        sexp: pack_wire_string(pack_wire_field(update, "sexp")),
      })
    }
    match @languagepack.parse_corpus_document(path, text, format) {
      Err(errors) => {
        diagnostics.push_iter(errors.iter())
        None
      }
      Ok(document) =>
        match @languagepack.rewrite_corpus_snapshots(document, updates) {
          Ok(text) => Some(text)
          Err(errors) => {
            diagnostics.push_iter(errors.iter())
            None
          }
        }
    }
  } catch {
    error => {
      diagnostics.push(
        pack_wire_diagnostic("invalid snapshot request: \{error}"),
      )
      None
    }
  }
  match updated {
    Some(text) => {
      let output = StringBuilder::new()
      output.write_string("{\"ok\":true,\"diagnostics\":[]")
      output.write_string(",\"updatedText\":")
      write_jstr(output, text)
      output.write_char('}')
      output.to_string()
    }
    None =>
      "{\"ok\":false,\"diagnostics\":" +
      pack_diagnostics_json(diagnostics) +
      ",\"updatedText\":null}"
  }
}
