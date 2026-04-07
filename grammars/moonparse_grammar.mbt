///|
// 元语法

///|
/// MoonParse Grammar DSL 的形式化语法，用 MoonParse DSL 本身书写。
///
/// 语法文件结构（EBNF 概述）：
/// ```
/// grammar_file  = newline* start_decl
///                 (newline+ extras_decl)?
///                 (newline+ precedence_decl)?
///                 (newline+ rule_def)*
///
/// start_decl    = "start"  identifier
/// extras_decl   = "extras" "[" pattern_atom ("," pattern_atom)* "]"
/// precedence_decl = "precedence" "[" prec_entry ("," prec_entry)* "]"
/// prec_entry    = prec_kind ":" identifier
/// prec_kind     = "left" | "right" | "nonassoc" | "dynamic"
///
/// rule_def      = "rule" identifier ":" pattern
/// pattern       = choice_pattern
/// choice_pattern = seq_pattern ("|" seq_pattern)*
/// seq_pattern   = modified_pattern+
/// modified_pattern = core_pattern ("*" | "+" | "?" | repeat_range)?
/// repeat_range  = "{" integer ("," integer)? "}"
///
/// core_pattern  = field_pattern
///               | tagged_pattern
///               | prec_annotation
///               | neg_lookahead
///               | pos_lookahead
///               | alias_pattern
///               | atom_pattern
///
/// field_pattern    = identifier ":" atom_pattern
/// tagged_pattern   = "@" identifier atom_pattern
/// prec_annotation  = "prec" ("." prec_kind)? "(" integer "," pattern ")"
/// neg_lookahead    = "!" atom_pattern
/// pos_lookahead    = "&" atom_pattern
/// alias_pattern    = "alias" "(" dq_string "," pattern ")"
/// atom_pattern     = dq_string | regex | "." | identifier | "(" pattern ")"
///
/// dq_string     = /"([^"\\]|\\.)*"/
/// regex         = /\/([^\/\\]|\\.)*\//
/// identifier    = /[A-Za-z_][A-Za-z0-9_]*/
/// integer       = /[0-9]+/
/// ```
pub let moonparse_grammar_dsl : String =
  #|start grammar_file
  #|extras [/[ \t]+/]
  #|rule grammar_file: newline* start_decl (newline+ extras_decl)? (newline+ precedence_decl)? (newline+ rule_def)*
  #|rule newline: /(\r\n|\n|\r)([ \t]*(\r\n|\n|\r))*/
  #|rule start_decl: "start" identifier
  #|rule extras_decl: "extras" "[" pattern_atom ("," pattern_atom)* "]"
  #|rule precedence_decl: "precedence" "[" prec_entry ("," prec_entry)* "]"
  #|rule prec_entry: prec_kind ":" identifier
  #|rule prec_kind: "left" | "right" | "nonassoc" | "dynamic"
  #|rule rule_def: "rule" identifier ":" pattern
  #|rule pattern: choice_pattern
  #|rule choice_pattern: seq_pattern ("|" seq_pattern)*
  #|rule seq_pattern: modified_pattern+
  #|rule modified_pattern: core_pattern repeat_mod?
  #|rule repeat_mod: "*" | "+" | "?" | "{" integer ("," integer)? "}"
  #|rule core_pattern: field_pattern | tagged_pattern | prec_annotation | neg_lookahead | pos_lookahead | alias_pattern | atom_pattern
  #|rule field_pattern: identifier ":" atom_pattern
  #|rule tagged_pattern: "@" identifier atom_pattern
  #|rule prec_annotation: "prec" ("." prec_kind)? "(" integer "," pattern ")"
  #|rule neg_lookahead: "!" atom_pattern
  #|rule pos_lookahead: "&" atom_pattern
  #|rule alias_pattern: "alias" "(" dq_string "," pattern ")"
  #|rule atom_pattern: dq_string | regex | "." | identifier | "(" pattern ")"
  #|rule pattern_atom: regex | dq_string
  #|rule dq_string: /"([^"\\]|\\.)*"/
  #|rule regex: /\/([^\/\\]|\\.)*\//
  #|rule identifier: /[A-Za-z_][A-Za-z0-9_]*/
  #|rule integer: /[0-9]+/

///|
let moonparse_meta_table : @tablegen.ParseTable = compile_builtin_grammar(
  moonparse_grammar_dsl,
)

///|
/// 用 MoonParse 的元语法验证一段 Grammar DSL 文本的词法/语法合规性。
pub fn parse_moonparse_dsl(
  source : String,
) -> Result[@runtime.CstNode, @runtime.ParseError] {
  @runtime.parse(moonparse_meta_table, source)
}
