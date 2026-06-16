///|
pub(all) struct TreeSitterProjectSource {
  grammar_json : String
  tree_sitter_json : String?
  package_json : String?
  queries : Map[String, String]
  corpus : Map[String, String]
  source_files : Map[String, Bytes]
  project_name : String?
}

///|
pub(all) struct TreeSitterImportOptions {
  output_id : String?
  output_name : String?
  package_version : String?
  extensions : Array[String]
  allow_tags_bindings_candidate : Bool
}

///|
pub(all) struct TreeSitterCompatibilityReport {
  grammar_path : String
  grammar_name : String
  diagnostics : Array[@languagepack.PackDiagnostic]
  unsupported_nodes : Array[String]
  generated_inline_tokens : Array[String]
  highlights_status : String
  locals_status : String
  tags_status : String
  scanner_required : Bool
  scanner_id : String?
  scanner_status : String
}

///|
pub(all) struct TreeSitterImportResult {
  files : Map[String, Bytes]
  diagnostics : Array[@languagepack.PackDiagnostic]
  report : TreeSitterCompatibilityReport
}

///|
pub(all) struct TreeSitterExportOptions {
  grammar_name : String?
}

///|
pub(all) struct TreeSitterExportReport {
  source_path : String
  grammar_name : String
  diagnostics : Array[@languagepack.PackDiagnostic]
  exported_rules : Array[String]
  unsupported_patterns : Array[String]
  monomorphized_rules : Array[String]
}

///|
pub(all) struct TreeSitterExportResult {
  grammar_json : String
  diagnostics : Array[@languagepack.PackDiagnostic]
  report : TreeSitterExportReport
}

///|
fn ts_diag(
  code : String,
  severity : @languagepack.PackSeverity,
  message : String,
  path? : String = "grammar.json",
  line? : Int = 0,
  column? : Int = 0,
  hint? : String,
) -> @languagepack.PackDiagnostic {
  match hint {
    Some(hint) =>
      @languagepack.pack_diagnostic(
        code,
        severity,
        message,
        path~,
        line~,
        column~,
        hint~,
      )
    None =>
      @languagepack.pack_diagnostic(
        code,
        severity,
        message,
        path~,
        line~,
        column~,
      )
  }
}
