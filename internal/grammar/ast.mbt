///|
pub(all) enum Associativity {
  None
  Left
  Right
  NonAssoc
  Dynamic
} derive(Debug, Eq)

///|
pub(all) enum RuleAttribute {
  Inline
  Hidden
} derive(Debug, Eq)

///|
pub(all) enum GrammarPattern {
  Ref(String)
  Literal(String)
  Regex(String, @regex.RegexIr)
  AnyScalar
  Choice(Array[GrammarPattern])
  Sequence(Array[GrammarPattern])
  ZeroOrMore(GrammarPattern)
  OneOrMore(GrammarPattern)
  Optional(GrammarPattern)
  RepeatRange(GrammarPattern, Int, Int)
  Field(String, GrammarPattern)
  Tagged(String, GrammarPattern)
  Lookahead(GrammarPattern, Bool)
  Precedence(Int, Associativity, GrammarPattern)
  Alias(String, Bool, GrammarPattern)
  LexicalPrecedence(Int, GrammarPattern)
  Reserved(String, GrammarPattern)
} derive(Debug, Eq)

///|
pub(all) struct RuleDecl {
  name : String
  pattern : GrammarPattern
  is_token : Bool
  immediate : Bool
  declaration_order : Int
  attributes : Array[RuleAttribute]
} derive(Debug, Eq)

///|
pub(all) struct PrecedenceDecl {
  associativity : Associativity
  rules : Array[String]
  declaration_order : Int
} derive(Debug, Eq)

///|
pub(all) struct ReservedSet {
  name : String
  words : Array[String]
  declaration_order : Int
} derive(Debug, Eq)

///|
/// Parsed grammar data remains in canonical declaration arrays. No semantic
/// decision depends on mutable-map iteration order.
pub(all) struct GrammarAst {
  start : String?
  rules : Array[RuleDecl]
  extras : Array[GrammarPattern]
  externals : Array[String]
  word : String?
  conflicts : Array[Array[String]]
  supertypes : Array[String]
  precedences : Array[PrecedenceDecl]
  reserved_sets : Array[ReservedSet]
} derive(Debug, Eq)

///|
pub(all) suberror GrammarParseError {
  InvalidGrammar(byte_offset~ : Int, code~ : String, reason~ : String)
} derive(Debug, Eq)

///|
pub(all) enum NormalizedSymbolKind {
  NamedNonterminal
  AnonymousNonterminal
  NamedTerminal
  LiteralTerminal
  RegexTerminal
  AnyTerminal
  ExternalTerminal
} derive(Debug, Eq)

///|
pub(all) struct NormalizedSymbol {
  id : Int
  name : String
  kind : NormalizedSymbolKind
  declaration_order : Int
} derive(Debug, Eq)

///|
pub(all) enum LookaheadKind {
  Positive
  Negative
} derive(Debug, Eq)

///|
pub(all) struct NormalizedElement {
  symbol_id : Int
  field : String?
  alias_name : String?
  alias_is_named : Bool
  lookahead : LookaheadKind?
  reserved_set : String?
} derive(Debug, Eq)

///|
pub(all) struct NormalizedProduction {
  id : Int
  lhs : Int
  rhs : Array[NormalizedElement]
  precedence : Int
  associativity : Associativity
  dynamic_precedence : Int
} derive(Debug, Eq)

///|
pub(all) struct NormalizedToken {
  symbol_id : Int
  pattern : GrammarPattern
  immediate : Bool
  lexical_precedence : Int
  declaration_order : Int
} derive(Debug, Eq)

///|
pub(all) struct NormalizedReservedSet {
  name : String
  words : Array[String]
} derive(Debug, Eq)

///|
pub(all) struct NormalizedGrammar {
  start_symbol : Int
  symbols : Array[NormalizedSymbol]
  productions : Array[NormalizedProduction]
  tokens : Array[NormalizedToken]
  extras : Array[Int]
  word_symbol : Int?
  conflicts : Array[Array[Int]]
  supertypes : Array[Int]
  inline_symbols : Array[Int]
  reserved_sets : Array[NormalizedReservedSet]
} derive(Debug, Eq)
