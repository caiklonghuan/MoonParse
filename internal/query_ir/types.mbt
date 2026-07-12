///|
/// Symbols visible to the deterministic query compiler.
///
/// Array order is the language-pack ID order. Query compilation never depends
/// on map iteration order.
pub(all) struct QuerySchema {
  nodes : Array[String]
  fields : Array[String]
  anonymous_tokens : Array[String]
}

///|
pub fn QuerySchema::new(
  nodes : Array[String],
  fields : Array[String],
  anonymous_tokens? : Array[String] = [],
) -> QuerySchema {
  {
    nodes: nodes.copy(),
    fields: fields.copy(),
    anonymous_tokens: anonymous_tokens.copy(),
  }
}

///|
fn find_name(names : Array[String], wanted : String) -> Int? {
  for i, name in names {
    if name == wanted {
      return Some(i)
    }
  }
  None
}

///|
fn QuerySchema::node_id(self : QuerySchema, name : String) -> Int? {
  find_name(self.nodes, name)
}

///|
fn QuerySchema::field_id(self : QuerySchema, name : String) -> Int? {
  find_name(self.fields, name)
}

///|
fn QuerySchema::has_anonymous_token(self : QuerySchema, token : String) -> Bool {
  find_name(self.anonymous_tokens, token) is Some(_)
}

///|
pub(all) suberror QueryCompileError {
  ParseError(Int, String)
  UnsupportedFeature(String)
  UnknownNode(String)
  UnknownField(String)
  UnknownCapture(String)
}

///|
pub(all) enum QueryQuantifier {
  One
  ZeroOrOne
  ZeroOrMore
  OneOrMore
} derive(Debug, Eq)

///|
pub(all) enum QueryExpr {
  Named(Int, String, Array[QueryChild])
  Anonymous(String)
  Wildcard
  Alternation(Array[QueryExpr])
} derive(Debug, Eq)

///|
pub(all) struct QueryChild {
  field_id : Int?
  field_name : String?
  expr : QueryExpr
  quantifier : QueryQuantifier
  capture_index : Int?
  anchor_before : Bool
  anchor_after : Bool
} derive(Debug, Eq)

///|
pub(all) enum QueryPredicate {
  Eq(String, String)
  NotEq(String, String)
  Match(String, String)
  NotMatch(String, String)
  AnyOf(String, Array[String])
} derive(Debug, Eq)

///|
pub(all) struct QueryPattern {
  index : Int
  root : QueryExpr
  root_capture_index : Int?
  capture_names : Array[String]
  predicates : Array[QueryPredicate]
} derive(Debug, Eq)

///|
pub(all) struct CompiledQueryIr {
  patterns : Array[QueryPattern]
  bytecode : Bytes
}

///|
pub fn CompiledQueryIr::patterns(self : CompiledQueryIr) -> Array[QueryPattern] {
  self.patterns.copy()
}

///|
pub fn CompiledQueryIr::bytecode(self : CompiledQueryIr) -> Bytes {
  self.bytecode
}

///|
pub fn CompiledQueryIr::pattern_count(self : CompiledQueryIr) -> Int {
  self.patterns.length()
}
