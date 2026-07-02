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
pub(all) struct LintResources {
  rule_sets : Array[String]
} derive(Debug)

///|
pub(all) enum LintSeverity {
  LintHint
  LintInformation
  LintWarning
  LintError
} derive(Debug, Eq)

///|
pub(all) enum LintFixOperation {
  Replace
  Delete
  InsertBefore
  InsertAfter
} derive(Debug, Eq)

///|
pub(all) enum LintRuleSetting {
  LintOff
  LintLevel(LintSeverity)
} derive(Debug, Eq)

///|
pub(all) struct LintOptions {
  enabled : Bool
  rule_sets : Map[String, Bool]
  rules : Map[String, LintRuleSetting]
} derive(Debug)

///|
pub fn LintOptions::default() -> LintOptions {
  { enabled: true, rule_sets: {}, rules: {} }
}

///|
pub(all) struct LintFixTemplate {
  title : String
  operation : LintFixOperation
  target_capture : String
  template : String
} derive(Debug)

///|
/// A self-contained lint rule. Pack paths are retained only while loading a
/// source pack and are omitted from serialized Language Bundles.
pub(all) struct LintRule {
  id : String
  global_id : String
  query_path : String?
  query_source : String
  compiled_query : @query.CompiledQuery?
  enabled_by_default : Bool
  severity : LintSeverity
  message : String
  diagnostic_capture : String
  fix : LintFixTemplate?
} derive(Debug)

///|
pub(all) struct LintRuleSet {
  id : String
  enabled_by_default : Bool
  rules : Array[LintRule]
} derive(Debug)

///|
pub(all) struct LintTextEdit {
  start_byte : Int
  end_byte : Int
  replacement : String
} derive(Debug, Eq)

///|
pub(all) struct LintFix {
  title : String
  edit : LintTextEdit
} derive(Debug, Eq)

///|
pub(all) struct LintDiagnostic {
  rule_id : String
  message : String
  severity : LintSeverity
  start_byte : Int
  end_byte : Int
  fix : LintFix?
} derive(Debug, Eq)

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
  lint : LintResources
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
  lint_rule_sets : Array[LintRuleSet]
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
  lint : Bool
  rewrite : Bool
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
  lint_rule_sets : Array[LintRuleSet]
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
