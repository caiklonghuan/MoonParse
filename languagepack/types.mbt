///|
pub(all) enum PackSeverity {
  Info
  Warning
  Error
} derive(Debug, Eq)

///|
pub impl Show for PackSeverity with output(self, logger) {
  match self {
    Info => logger.write_string("info")
    Warning => logger.write_string("warning")
    Error => logger.write_string("error")
  }
}

///|
pub(all) struct PackDiagnostic {
  code : String
  severity : PackSeverity
  message : String
  path : String
  line : Int
  column : Int
  hint : String?
} derive(Debug)

///|
pub impl Show for PackDiagnostic with output(self, logger) {
  logger.write_string(self.code + ": " + self.message)
}

///|
pub(all) enum PackMaturity {
  Stable
  Subset
  Experimental
  Imported
} derive(Debug, Eq)

///|
pub(all) enum GrammarFormat {
  Dsl
  Json
} derive(Debug, Eq)

///|
pub(all) struct PackCompatibility {
  minimum_moonparse_version : String
  maximum_moonparse_version_exclusive : String
} derive(Debug)

///|
pub(all) struct GrammarResource {
  path : String
  format : GrammarFormat
} derive(Debug)

///|
pub(all) struct QueryResources {
  highlights : String?
  locals : String?
  bindings : String?
  folding : String?
  modules : String?
} derive(Debug)

///|
pub(all) struct ScannerDescriptor {
  id : String
  api_version : Int
  config_path : String?
  config : String?
} derive(Debug)

///|
pub(all) struct CorpusResource {
  directory : String
  format : String
} derive(Debug)

///|
pub(all) struct PackBuildPolicy {
  allow_ambiguous_conflicts : Bool
} derive(Debug)

///|
pub(all) struct LanguagePackManifest {
  schema_version : Int
  id : String
  name : String
  version : String
  maturity : PackMaturity
  entry_rule : String
  extensions : Array[String]
  compatibility : PackCompatibility
  grammar : GrammarResource
  queries : QueryResources
  scanner : ScannerDescriptor?
  corpus : CorpusResource
  build : PackBuildPolicy
} derive(Debug)

///|
pub(all) struct LanguagePackSource {
  manifest : String
  files : Map[String, Bytes]
}

///|
pub fn LanguagePackSource::new(
  manifest : String,
  files : Map[String, Bytes],
) -> LanguagePackSource {
  { manifest, files }
}

///|
pub(all) struct CorpusCase {
  name : String
  source : String
  expected_error : String
  sexp_contains : Array[String]
  sexp_not_contains : Array[String]
  path : String
  expected_sexp : String?
  source_line : Int
  expectation_line : Int
} derive(Debug)

///|
pub(all) struct CorpusDocument {
  path : String
  text : String
  format : String
  cases : Array[CorpusCase]
  expectation_starts : Array[Int]
  expectation_ends : Array[Int]
  newline : String
} derive(Debug)

///|
pub(all) struct CorpusSnapshotUpdate {
  case_index : Int
  case_name : String
  sexp : String
} derive(Debug)

///|
pub(all) struct LanguagePack {
  manifest : LanguagePackManifest
  grammar_source : String
  highlights_query : String?
  locals_query : String?
  bindings_query : String?
  folding_query : String?
  modules_query : String?
  scanner : ScannerDescriptor?
  corpus : Array[CorpusCase]
} derive(Debug)

///|
pub(all) struct BundleCapabilities {
  highlights : Bool
  locals : Bool
  bindings : Bool
  folding : Bool
  modules : Bool
  scanner : Bool
} derive(Debug, Eq)

///|
pub(all) enum BundleQueryKind {
  Highlights
  Locals
  Bindings
  Folding
  Modules
} derive(Debug, Eq)

///|
pub(all) struct PackBuildOptions {
  software_version : String
  known_scanners : Array[(String, Int)]
} derive(Debug)

///|
pub fn PackBuildOptions::default() -> PackBuildOptions {
  { software_version: "0.1.0", known_scanners: [] }
}

///|
pub(all) struct LanguageBundle {
  schema_version : Int
  parse_table_schema_version : Int
  software_version : String
  pack_id : String
  pack_version : String
  pack_name : String
  pack_maturity : String
  pack_extensions : Array[String]
  grammar_json : String
  table : @tablegen.ParseTable
  table_json : String
  table_binary : Bytes
  highlights_source : String?
  locals_source : String?
  bindings_source : String?
  folding_source : String?
  modules_source : String?
  highlights_query : @query.CompiledQuery?
  locals_query : @query.CompiledQuery?
  bindings_query : @query.CompiledQuery?
  folding_query : @query.CompiledQuery?
  modules_query : @query.CompiledQuery?
  scanner : ScannerDescriptor?
  capabilities : BundleCapabilities
}

///|
pub(all) struct PackScannerProvider {
  id : String
  api_version : Int
  create : (@tablegen.ParseTable) -> &@runtime.StatefulScanner
}

///|
pub fn pack_diagnostic(
  code : String,
  severity : PackSeverity,
  message : String,
  path? : String = "language-pack.json",
  line? : Int = 0,
  column? : Int = 0,
  hint? : String,
) -> PackDiagnostic {
  { code, severity, message, path, line, column, hint }
}

///|
pub fn has_pack_errors(diagnostics : Array[PackDiagnostic]) -> Bool {
  diagnostics.iter().any(fn(d) { d.severity == PackSeverity::Error })
}
