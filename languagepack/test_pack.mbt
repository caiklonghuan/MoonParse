///|
fn corpus_node_type_name(
  node : @runtime.CstNode,
  table : @tablegen.ParseTable,
) -> String {
  if node.is_error || node.symbol == @runtime.sym_error {
    return "ERROR"
  }
  if node.children.is_empty() {
    if node.symbol == @runtime.sym_end {
      return "EOF"
    }
    return table.terminal_names
      .get(node.symbol)
      .unwrap_or("<t:" + node.symbol.to_string() + ">")
  }
  if node.symbol < 0 || node.symbol >= table.symbol_metadata.length() {
    return "<nt:" + node.symbol.to_string() + ">"
  }
  if node.production_id >= 0 && node.production_id < table.productions.length() {
    match table.productions[node.production_id].alias_name {
      Some(name) => return name
      None => ()
    }
  }
  table.symbol_metadata[node.symbol].name
}

///|
fn corpus_write_sexp_children(
  output : StringBuilder,
  node : @runtime.CstNode,
  source : String,
  table : @tablegen.ParseTable,
) -> Unit {
  for index in 0..<node.children.length() {
    let child = node.children[index]
    if child.is_named || child.is_error {
      output.write_char(' ')
      let field = if index < node.field_names.length() {
        node.field_names[index]
      } else {
        None
      }
      corpus_write_sexp(output, child, source, table, field)
    } else if !child.children.is_empty() {
      corpus_write_sexp_children(output, child, source, table)
    }
  }
}

///|
fn corpus_write_sexp(
  output : StringBuilder,
  node : @runtime.CstNode,
  source : String,
  table : @tablegen.ParseTable,
  field : String?,
) -> Unit {
  match field {
    Some(name) => {
      output.write_string(name)
      output.write_string(": ")
    }
    None => ()
  }
  if node.is_named || node.is_error {
    output.write_char('(')
    output.write_string(corpus_node_type_name(node, table))
    corpus_write_sexp_children(output, node, source, table)
    output.write_char(')')
    return
  }
  output.write_char('"')
  let text = if node.start_byte >= 0 &&
    node.start_byte <= node.end_byte &&
    node.end_byte <= source.length() {
    source[node.start_byte:node.end_byte].to_string()
  } else {
    ""
  }
  for char in text {
    if char == '"' || char == '\\' {
      output.write_char('\\')
    }
    output.write_char(char)
  }
  output.write_char('"')
}

///|
fn corpus_tree_sexp(
  root : @runtime.CstNode,
  source : String,
  table : @tablegen.ParseTable,
) -> String {
  let output = StringBuilder::new()
  corpus_write_sexp(output, root, source, table, None)
  output.to_string()
}

///|
fn corpus_first_error(node : @runtime.CstNode) -> @runtime.CstNode? {
  if node.is_error || node.is_missing {
    return Some(node)
  }
  for child in node.children {
    match corpus_first_error(child) {
      Some(error) => return Some(error)
      None => ()
    }
  }
  None
}

///|
fn corpus_error_summary(root : @runtime.CstNode) -> String {
  match corpus_first_error(root) {
    None => "ok"
    Some(error) =>
      "error:" +
      error.start_point.row.to_string() +
      ":" +
      error.start_point.column.to_string()
  }
}

///|
fn corpus_failure(
  kind : CorpusFailureKind,
  expected : String,
  actual : String,
  message : String,
) -> CorpusFailure {
  { kind, expected, actual, message }
}

///|
fn test_corpus_case(
  bundle : LanguageBundle,
  case_index : Int,
  case : CorpusCase,
  scanner_provider : PackScannerProvider?,
) -> CorpusTestResult {
  let parsed = match scanner_provider {
    Some(provider) =>
      parse_bundle(bundle, case.source, scanner_provider=provider)
    None => parse_bundle(bundle, case.source)
  }
  let failures : Array[CorpusFailure] = []
  let (actual_error, actual_sexp) = match parsed {
    Err(error) => {
      failures.push(
        corpus_failure(
          CorpusFailureKind::Parse,
          case.expected_error,
          error.message,
          "parse failed: " + error.message,
        ),
      )
      ("invalid", "")
    }
    Ok(root) => {
      let error_summary = corpus_error_summary(root)
      let sexp = corpus_tree_sexp(root, case.source, bundle.table)
      if error_summary != case.expected_error {
        failures.push(
          corpus_failure(
            CorpusFailureKind::Error,
            case.expected_error,
            error_summary,
            "expected error summary '" +
            case.expected_error +
            "', got '" +
            error_summary +
            "'",
          ),
        )
      }
      match case.expected_sexp {
        Some(expected) if expected != sexp =>
          failures.push(
            corpus_failure(
              CorpusFailureKind::Sexp,
              expected,
              sexp,
              "S-expression snapshot does not match",
            ),
          )
        _ => ()
      }
      for expected in case.sexp_contains {
        if !sexp.contains(expected) {
          failures.push(
            corpus_failure(
              CorpusFailureKind::Contains,
              expected,
              sexp,
              "S-expression does not contain '" + expected + "'",
            ),
          )
        }
      }
      for excluded in case.sexp_not_contains {
        if sexp.contains(excluded) {
          failures.push(
            corpus_failure(
              CorpusFailureKind::NotContains,
              excluded,
              sexp,
              "S-expression unexpectedly contains '" + excluded + "'",
            ),
          )
        }
      }
      (error_summary, sexp)
    }
  }
  {
    path: case.path,
    case_index,
    name: case.name,
    source_line: case.source_line,
    actual_error,
    actual_sexp,
    failures,
    passed: failures.is_empty(),
  }
}

///|
/// Build a Language Pack once and execute all of its Corpus cases.
pub fn test_pack(
  source : LanguagePackSource,
  options : PackBuildOptions,
  scanner_provider? : PackScannerProvider,
) -> PackTestReport {
  let build = build_bundle_report(source, options)
  let bundle = match build.bundle {
    Some(bundle) => bundle
    None => return { diagnostics: build.diagnostics, cases: [] }
  }
  let pack = match load_pack(source) {
    Ok(pack) => pack
    Err(diagnostics) => return { diagnostics, cases: [] }
  }
  let cases : Array[CorpusTestResult] = []
  for index in 0..<pack.corpus.length() {
    cases.push(
      test_corpus_case(bundle, index, pack.corpus[index], scanner_provider),
    )
  }
  { diagnostics: build.diagnostics, cases }
}
