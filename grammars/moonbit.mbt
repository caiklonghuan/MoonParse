///|
// MoonBit 语法定义（项目内高频写法的核心子集）。
//
// 覆盖：
//   - fn / let / type / struct / enum / test
//   - if / match / for / while / return
//   - 记录字面量、数组、调用、索引、成员访问
//   - 基于 newline 的语句分隔

///|
pub let moonbit_grammar : String =
  #|start module
  #|extras [/[ \t\f]+/, /\/\/[^\n\r]*/, /\/\*([^*]|\*+[^*/])*\*+\//]
  #|rule newline: /(\r\n|\n|\r)[ \t\f]*/
  #|rule module: newline* item*
  #|rule item: function_decl newline* | let_decl newline* | type_alias_decl newline* | struct_decl newline* | enum_decl newline* | test_decl newline*
  #|rule visibility: "pub" ("(" "all" ")")? | "priv"
  #|rule function_decl: visibility? "fn" fn_name type_params? "(" parameter_list? ")" return_type? block
  #|rule let_decl: visibility? "let" "mut"? pattern type_annotation? ("=" expression)?
  #|rule type_alias_decl: visibility? "type" identifier type_params? "=" type_expr
  #|rule struct_decl: visibility? "struct" identifier type_params? "{" newline* field_decl (newline+ field_decl)* newline* "}" derive_clause?
  #|rule field_decl: identifier ":" type_expr
  #|rule enum_decl: visibility? "enum" identifier type_params? "{" newline* enum_case (newline+ enum_case)* newline* "}" derive_clause?
  #|rule enum_case: identifier ("(" type_expr_list? ")")?
  #|rule test_decl: "test" string_literal block
  #|rule fn_name: identifier ("::" identifier)*
  #|rule type_params: "[" identifier ("," identifier)* "]"
  #|rule parameter_list: parameter ("," parameter)*
  #|rule parameter: "self" | pattern type_annotation?
  #|rule type_annotation: ":" type_expr
  #|rule return_type: "->" type_expr
  #|rule type_expr: simple_type ("->" type_expr)?
  #|rule simple_type: qualified_identifier type_args? "?"* | "(" type_expr_list? ")" | "[" type_expr_list? "]" | "()"
  #|rule type_expr_list: type_expr ("," type_expr)*
  #|rule type_args: "[" type_expr ("," type_expr)* "]"
  #|rule block: "{" newline* statement* "}"
  #|rule statement: let_statement newline* | return_statement newline* | break_statement newline* | continue_statement newline* | if_statement newline* | while_statement newline* | for_statement newline* | expression newline*
  #|rule let_statement: "let" "mut"? pattern type_annotation? ("=" expression)?
  #|rule return_statement: "return" expression?
  #|rule break_statement: "break"
  #|rule continue_statement: "continue"
  #|rule if_statement: "if" expression block ("else" (block | if_statement))?
  #|rule while_statement: "while" expression block
  #|rule for_statement: "for" pattern "in" expression block
  #|rule expression: match_expression | assignment_expression
  #|rule match_expression: "match" expression "{" newline* match_case* "}"
  #|rule match_case: pattern guard_clause? "=>" expression_or_block newline*
  #|rule guard_clause: "if" expression
  #|rule expression_or_block: block | expression
  #|rule assignment_expression: logical_or_expression (("=" | ":=") assignment_expression)?
  #|rule logical_or_expression: logical_and_expression ("||" logical_and_expression)*
  #|rule logical_and_expression: equality_expression ("&&" equality_expression)*
  #|rule equality_expression: comparison_expression (("==" | "!=") comparison_expression)*
  #|rule comparison_expression: range_expression (("<" | ">" | "<=" | ">=") range_expression)*
  #|rule range_expression: additive_expression ((".." | "..<" | "..=") additive_expression)?
  #|rule additive_expression: multiplicative_expression (("+" | "-") multiplicative_expression)*
  #|rule multiplicative_expression: unary_expression (("*" | "/" | "%") unary_expression)*
  #|rule unary_expression: postfix_expression | ("!" | "-" | "+") unary_expression
  #|rule postfix_expression: primary_expression postfix_suffix*
  #|rule postfix_suffix: "(" argument_list? ")" | "[" expression "]" | "." identifier
  #|rule argument_list: expression ("," expression)*
  #|rule primary_expression: literal | qualified_identifier | tuple_literal | list_literal | record_literal | "(" expression ")"
  #|rule tuple_literal: "(" expression ("," expression)+ ")"
  #|rule list_literal: "[" expression_list? "]"
  #|rule expression_list: expression ("," expression)*
  #|rule record_literal: "{" record_field_list? "}"
  #|rule record_field_list: record_field ("," record_field)* ","?
  #|rule record_field: identifier ":" expression
  #|rule pattern: "_" | literal | qualified_identifier pattern_suffix? | "(" pattern_list? ")" | "[" pattern_list? "]"
  #|rule pattern_suffix: "(" pattern_list? ")"
  #|rule pattern_list: pattern ("," pattern)*
  #|rule derive_clause: "derive" "(" qualified_identifier ("," qualified_identifier)* ")"
  #|rule qualified_identifier: identifier (("." | "::") identifier)*
  #|rule identifier: /@?[A-Za-z_][A-Za-z0-9_]*/
  #|rule literal: number_literal | string_literal | char_literal | "true" | "false" | "()"
  #|rule number_literal: /[0-9]+(\.[0-9]+)?/
  #|rule string_literal: /"([^"\\]|\\.)*"/
  #|rule char_literal: /'([^'\\]|\\.)'/

///|
let moonbit_table : @tablegen.ParseTable = compile_builtin_grammar(
  moonbit_grammar,
)

///|
pub fn parse_moonbit(
  source : String,
) -> Result[@runtime.CstNode, @runtime.ParseError] {
  @runtime.parse(moonbit_table, source)
}
