///|
/// MoonParse v1 public runtime contract.
///
/// Implementations are introduced by M2-C12. Keep this surface stable; add
/// implementation in dedicated files rather than changing the declarations.
pub(all) struct ByteRange {
  start_byte : Int
  end_byte : Int
}

///|
pub(all) struct Point {
  row : Int
  byte_column : Int
}

///|
pub(all) struct Span {
  range : ByteRange
  start_point : Point
  end_point : Point
}

///|
pub(all) enum QueryRole {
  Highlights
  Locals
  Folds
  Outline
}

///|
pub(all) enum DiagnosticSeverity {
  Error
  Warning
  Information
}

///|
pub(all) enum RecoveryAction {
  Insert(String)
  Delete(String)
  PopToSync(String)
}

///|
pub(all) suberror SourceError {
  InvalidUtf8(Int)
  InvalidByteRange(Int, Int, Int)
  SplitUtf8CodePoint(Int)
  InvalidPoint(Int, Int)
}

///|
pub(all) suberror PackError {
  BadMagic
  UnsupportedFormat(Int, Int)
  UnsupportedRuntimeAbi(Int, Int)
  Truncated(String)
  InvalidOffset(String)
  DuplicateSection(String)
  MissingSection(String)
  ChecksumMismatch
  LimitExceeded(String, Int, Int)
  InvalidModel(String)
}

///|
pub(all) suberror ParseFailure {
  LanguageMismatch
  InvalidEdit(Int, Int, Int, Int)
  SplitUtf8CodePoint(Int, Int)
  InvalidLimit(String, Int, Int)
  BudgetExceeded(String, Int)
}

///|
pub(all) suberror QueryError {
  ParseError(Int, String)
  UnknownNode(String)
  UnknownField(String)
  UnsupportedFeature(String)
  LanguageMismatch
  InvalidRange
  MatchLimitExceeded(Int)
}

///|
declare pub type Language

///|
declare pub type KindId

///|
declare pub type FieldId

///|
declare pub type Parser

///|
declare pub type ParseLimits

///|
declare pub type Snapshot

///|
declare pub type Node

///|
declare pub type TreeCursor

///|
declare pub type ChangedRange

///|
declare pub type Diagnostic

///|
declare pub type ParseStats

///|
declare pub type Query

///|
declare pub type Capture

///|
declare pub fn Language::load(bytes : Bytes) -> Language raise PackError

///|
declare pub fn Language::name(self : Self) -> String

///|
declare pub fn Language::version(self : Self) -> String

///|
declare pub fn Language::fingerprint(self : Self) -> String

///|
declare pub fn Language::kind_name(self : Self, kind : KindId) -> String?

///|
declare pub fn Language::kind_id(self : Self, name : String) -> KindId?

///|
declare pub fn Language::field_name(self : Self, field : FieldId) -> String?

///|
declare pub fn Language::field_id(self : Self, name : String) -> FieldId?

///|
declare pub fn Language::query(self : Self, role : QueryRole) -> Query?

///|
declare pub fn ParseLimits::editor_default() -> ParseLimits

///|
declare pub fn ParseLimits::with_max_active_versions(
  self : Self,
  limit : Int,
) -> ParseLimits raise ParseFailure

///|
declare pub fn ParseLimits::with_max_parser_steps(
  self : Self,
  limit : Int,
) -> ParseLimits raise ParseFailure

///|
declare pub fn ParseLimits::with_max_tree_nodes(
  self : Self,
  limit : Int,
) -> ParseLimits raise ParseFailure

///|
declare pub fn ParseLimits::with_max_query_matches(
  self : Self,
  limit : Int,
) -> ParseLimits raise ParseFailure

///|
declare pub fn Parser::new(language : Language) -> Parser

///|
declare pub fn Parser::new_with_limits(
  language : Language,
  limits : ParseLimits,
) -> Parser

///|
declare pub fn Parser::parse(
  self : Self,
  source : Source,
) -> Snapshot raise ParseFailure

///|
declare pub fn Parser::reparse(
  self : Self,
  previous : Snapshot,
  edit : TextEdit,
) -> Snapshot raise ParseFailure

///|
declare pub fn Parser::reparse_many(
  self : Self,
  previous : Snapshot,
  edits : ReadOnlyArray[TextEdit],
) -> Snapshot raise ParseFailure

///|
declare pub fn Snapshot::source(self : Self) -> Source

///|
declare pub fn Snapshot::language(self : Self) -> Language

///|
declare pub fn Snapshot::root(self : Self) -> Node

///|
declare pub fn Snapshot::diagnostics(self : Self) -> ReadOnlyArray[Diagnostic]

///|
declare pub fn Snapshot::changed_ranges(
  self : Self,
) -> ReadOnlyArray[ChangedRange]

///|
declare pub fn Snapshot::stats(self : Self) -> ParseStats

///|
declare pub fn Snapshot::point_at(
  self : Self,
  byte_offset : Int,
) -> Point raise SourceError

///|
declare pub fn Snapshot::byte_at(
  self : Self,
  point : Point,
) -> Int raise SourceError

///|
declare pub fn Snapshot::captures(
  self : Self,
  query : Query,
  within? : ByteRange,
) -> Array[Capture] raise QueryError

///|
declare pub fn Node::kind_id(self : Self) -> KindId

///|
declare pub fn Node::kind(self : Self) -> String

///|
declare pub fn Node::span(self : Self) -> Span

///|
declare pub fn Node::is_named(self : Self) -> Bool

///|
declare pub fn Node::is_extra(self : Self) -> Bool

///|
declare pub fn Node::is_error(self : Self) -> Bool

///|
declare pub fn Node::is_missing(self : Self) -> Bool

///|
declare pub fn Node::child_count(self : Self) -> Int

///|
declare pub fn Node::named_child_count(self : Self) -> Int

///|
declare pub fn Node::child(self : Self, index : Int) -> Node?

///|
declare pub fn Node::child_by_field(self : Self, field : String) -> Node?

///|
declare pub fn Node::child_by_field_id(self : Self, field : FieldId) -> Node?

///|
declare pub fn Node::text(self : Self) -> String

///|
declare pub fn Node::walk(self : Self) -> TreeCursor

///|
declare pub fn TreeCursor::node(self : Self) -> Node

///|
declare pub fn TreeCursor::goto_first_child(self : Self) -> Bool

///|
declare pub fn TreeCursor::goto_next_sibling(self : Self) -> Bool

///|
declare pub fn TreeCursor::goto_parent(self : Self) -> Bool

///|
declare pub fn Query::compile(
  language : Language,
  source : String,
) -> Query raise QueryError

///|
declare pub fn Capture::name(self : Self) -> String

///|
declare pub fn Capture::node(self : Self) -> Node

///|
declare pub fn Capture::pattern_index(self : Self) -> Int

///|
declare pub fn Diagnostic::code(self : Self) -> String

///|
declare pub fn Diagnostic::message(self : Self) -> String

///|
declare pub fn Diagnostic::severity(self : Self) -> DiagnosticSeverity

///|
declare pub fn Diagnostic::span(self : Self) -> Span

///|
declare pub fn Diagnostic::expected(self : Self) -> ReadOnlyArray[String]

///|
declare pub fn Diagnostic::recovery(self : Self) -> RecoveryAction?

///|
declare pub fn Diagnostic::fix(self : Self) -> TextEdit?

///|
declare pub fn ChangedRange::old_span(self : Self) -> Span

///|
declare pub fn ChangedRange::new_span(self : Self) -> Span

///|
declare pub fn ParseStats::source_bytes(self : Self) -> Int

///|
declare pub fn ParseStats::reparsed_bytes(self : Self) -> Int

///|
declare pub fn ParseStats::reused_bytes(self : Self) -> Int

///|
declare pub fn ParseStats::reused_nodes(self : Self) -> Int

///|
declare pub fn ParseStats::peak_branches(self : Self) -> Int

///|
declare pub fn ParseStats::recovery_actions(self : Self) -> Int
