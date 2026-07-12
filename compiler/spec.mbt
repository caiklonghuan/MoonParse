///|
/// MoonParse v1 offline compiler contract.
///
/// `compile_pack` is deterministic and pure: it receives logical source names
/// and text only, never filesystem paths, environment variables, clocks, random
/// values, or runtime parser objects.
pub(all) enum CompileSeverity {
  Information
  Warning
  Error
}

///|
pub(all) struct CompileSpan {
  source_name : String
  start_byte : Int
  end_byte : Int
}

///|
declare pub type PackManifest

///|
declare pub type PackSource

///|
declare pub type PackArtifact

///|
declare pub type CompileOutput

///|
declare pub type CompileDiagnostic

///|
declare pub fn PackManifest::new(
  name~ : String,
  version~ : String,
  license~ : String,
) -> PackManifest

///|
declare pub fn PackManifest::with_source(
  self : Self,
  repository~ : String,
  commit~ : String,
) -> Self

///|
declare pub fn PackSource::new(
  manifest : PackManifest,
  grammar_name~ : String,
  grammar~ : String,
) -> PackSource

///|
declare pub fn PackSource::with_highlights(
  self : Self,
  source_name~ : String,
  query~ : String,
) -> Self

///|
declare pub fn PackSource::with_locals(
  self : Self,
  source_name~ : String,
  query~ : String,
) -> Self

///|
declare pub fn PackSource::with_folds(
  self : Self,
  source_name~ : String,
  query~ : String,
) -> Self

///|
declare pub fn PackSource::with_outline(
  self : Self,
  source_name~ : String,
  query~ : String,
) -> Self

///|
declare pub fn PackSource::with_scanner(
  self : Self,
  source_name~ : String,
  scanner~ : String,
) -> Self

///|
declare pub fn compile_pack(source : PackSource) -> CompileOutput

///|
declare pub fn CompileOutput::artifact(self : Self) -> PackArtifact?

///|
declare pub fn CompileOutput::diagnostics(
  self : Self,
) -> ReadOnlyArray[CompileDiagnostic]

///|
declare pub fn CompileOutput::has_errors(self : Self) -> Bool

///|
declare pub fn PackArtifact::bytes(self : Self) -> Bytes

///|
declare pub fn PackArtifact::fingerprint(self : Self) -> String

///|
declare pub fn CompileDiagnostic::code(self : Self) -> String

///|
declare pub fn CompileDiagnostic::message(self : Self) -> String

///|
declare pub fn CompileDiagnostic::severity(self : Self) -> CompileSeverity

///|
declare pub fn CompileDiagnostic::span(self : Self) -> CompileSpan?

///|
declare pub fn CompileDiagnostic::notes(self : Self) -> ReadOnlyArray[String]
