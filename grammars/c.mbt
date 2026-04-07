///|
// C 语法定义（实用核心子集）。
//
// 覆盖：
//   - 预处理行 / 函数定义 / 声明
//   - if / while / for / return / break / continue
//   - 常见表达式优先级与调用、下标、成员访问

///|
pub let c_grammar : String =
  #|start translation_unit
  #|extras [/[ \t\n\r]+/, /\/\/[^\n\r]*/, /\/\*([^*]|\*+[^*/])*\*+\//]
  #|rule translation_unit: item*
  #|rule item: preproc_directive | function_definition | declaration
  #|rule preproc_directive: /#[^\n\r]*/
  #|rule function_definition: declaration_specifiers declarator compound_statement
  #|rule declaration: declaration_specifiers init_declarator_list? ";"
  #|rule declaration_specifiers: declaration_specifier+
  #|rule declaration_specifier: type_specifier | "const" | "static" | "extern"
  #|rule type_specifier: "void" | "char" | "short" | "int" | "long" | "float" | "double" | "signed" | "unsigned" | "struct" identifier
  #|rule init_declarator_list: init_declarator ("," init_declarator)*
  #|rule init_declarator: declarator ("=" initializer)?
  #|rule initializer: assignment_expression | "{" initializer_list ","? "}"
  #|rule initializer_list: initializer ("," initializer)*
  #|rule declarator: pointer? identifier function_suffix?
  #|rule pointer: "*" pointer?
  #|rule function_suffix: "(" parameter_list? ")"
  #|rule parameter_list: parameter ("," parameter)* ("," "...")?
  #|rule parameter: declaration_specifiers declarator?
  #|rule compound_statement: "{" block_item* "}"
  #|rule block_item: declaration | statement
  #|rule statement: compound_statement | if_statement | while_statement | for_statement | return_statement | break_statement | continue_statement | expression_statement
  #|rule if_statement: "if" "(" expression ")" statement ("else" statement)?
  #|rule while_statement: "while" "(" expression ")" statement
  #|rule for_statement: "for" "(" for_init? ";" expression? ";" expression? ")" statement
  #|rule for_init: for_declaration | expression
  #|rule for_declaration: declaration_specifiers init_declarator_list?
  #|rule return_statement: "return" expression? ";"
  #|rule break_statement: "break" ";"
  #|rule continue_statement: "continue" ";"
  #|rule expression_statement: expression? ";"
  #|rule expression: assignment_expression ("," assignment_expression)*
  #|rule assignment_expression: unary_expression assignment_operator assignment_expression | conditional_expression
  #|rule assignment_operator: "=" | "+=" | "-=" | "*=" | "/=" | "%="
  #|rule conditional_expression: logical_or_expression ("?" expression ":" conditional_expression)?
  #|rule logical_or_expression: logical_and_expression ("||" logical_and_expression)*
  #|rule logical_and_expression: equality_expression ("&&" equality_expression)*
  #|rule equality_expression: relational_expression (("==" | "!=") relational_expression)*
  #|rule relational_expression: additive_expression (("<" | ">" | "<=" | ">=") additive_expression)*
  #|rule additive_expression: multiplicative_expression (("+" | "-") multiplicative_expression)*
  #|rule multiplicative_expression: unary_expression (("*" | "/" | "%") unary_expression)*
  #|rule unary_expression: postfix_expression | unary_operator unary_expression
  #|rule unary_operator: "&" | "*" | "+" | "-" | "!" | "~" | "++" | "--"
  #|rule postfix_expression: primary_expression postfix_suffix*
  #|rule postfix_suffix: "(" argument_list? ")" | "[" expression "]" | "." identifier | "->" identifier | "++" | "--"
  #|rule argument_list: assignment_expression ("," assignment_expression)*
  #|rule primary_expression: identifier | number_literal | string_literal | char_literal | "(" expression ")"
  #|rule identifier: /[_A-Za-z][_A-Za-z0-9]*/
  #|rule number_literal: /(0[xX][0-9a-fA-F]+|[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?)[uUlLfF]*/
  #|rule string_literal: /"([^"\\]|\\.)*"/
  #|rule char_literal: /'([^'\\]|\\.)'/

///|
let c_table : @tablegen.ParseTable = compile_builtin_grammar(c_grammar)

///|
pub fn parse_c(
  source : String,
) -> Result[@runtime.CstNode, @runtime.ParseError] {
  @runtime.parse(c_table, source)
}
