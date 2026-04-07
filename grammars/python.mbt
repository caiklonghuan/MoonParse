///|
// Python 语法定义（行级核心子集）。
//
// 覆盖：
//   - def / class / if / while / for
//   - import / from-import / return / pass / break / continue
//   - 常见表达式、调用、索引、属性访问、列表 / 字典字面量
//   - 缩进块以“整行缩进文本”方式收集，优先保证标准库示例可稳定解析

///|
pub let python_grammar : String =
  #|start module
  #|extras [/[ \t\f]+/, /#[^\n\r]*/]
  #|rule newline: /(\r\n|\n|\r)[ \t\f]*/
  #|rule indented_text: /[ \t]+[^\n\r][^\n\r]*/
  #|rule module: (newline | statement)*
  #|rule statement: compound_statement newline* | simple_statement newline*
  #|rule simple_statement: import_statement | return_statement | pass_statement | break_statement | continue_statement | assign_statement | expression_statement
  #|rule compound_statement: if_statement | while_statement | for_statement | def_statement | class_statement
  #|rule import_statement: "import" dotted_name ("," dotted_name)* | "from" dotted_name "import" import_targets
  #|rule import_targets: "*" | identifier ("," identifier)*
  #|rule return_statement: "return" expression?
  #|rule pass_statement: "pass"
  #|rule break_statement: "break"
  #|rule continue_statement: "continue"
  #|rule assign_statement: target (":" type_hint)? "=" expression
  #|rule expression_statement: expression
  #|rule target: identifier | postfix_expression
  #|rule if_statement: "if" expression ":" suite ("elif" expression ":" suite)* ("else" ":" suite)?
  #|rule while_statement: "while" expression ":" suite
  #|rule for_statement: "for" identifier "in" expression ":" suite
  #|rule def_statement: "def" identifier "(" parameter_list? ")" return_hint? ":" suite
  #|rule class_statement: "class" identifier ("(" argument_list? ")")? ":" suite
  #|rule suite: simple_statement | newline indented_text (newline indented_text)* newline*
  #|rule return_hint: "->" type_hint
  #|rule type_hint: dotted_name ("[" type_hint ("," type_hint)* "]")?
  #|rule parameter_list: parameter ("," parameter)*
  #|rule parameter: identifier (":" type_hint)? ("=" expression)?
  #|rule dotted_name: identifier ("." identifier)*
  #|rule expression: lambda_expression | or_expression
  #|rule lambda_expression: "lambda" parameter_names? ":" expression
  #|rule parameter_names: identifier ("," identifier)*
  #|rule or_expression: and_expression ("or" and_expression)*
  #|rule and_expression: not_expression ("and" not_expression)*
  #|rule not_expression: "not" not_expression | comparison_expression
  #|rule comparison_expression: additive_expression (comparison_operator additive_expression)*
  #|rule comparison_operator: "==" | "!=" | "<" | ">" | "<=" | ">=" | "in"
  #|rule additive_expression: multiplicative_expression (("+" | "-") multiplicative_expression)*
  #|rule multiplicative_expression: unary_expression (("*" | "/" | "%" | "//") unary_expression)*
  #|rule unary_expression: postfix_expression | ("+" | "-") unary_expression
  #|rule postfix_expression: primary_expression postfix_suffix*
  #|rule postfix_suffix: "(" argument_list? ")" | "[" expression "]" | "." identifier
  #|rule argument_list: expression ("," expression)*
  #|rule primary_expression: literal | identifier | tuple_literal | list_literal | dict_literal | "(" expression ")"
  #|rule tuple_literal: "(" expression ("," expression)+ ")"
  #|rule list_literal: "[" expression_list? "]"
  #|rule dict_literal: "{" dict_item ("," dict_item)* ","? "}" | "{" "}"
  #|rule dict_item: expression ":" expression
  #|rule expression_list: expression ("," expression)*
  #|rule literal: number_literal | string_literal | "True" | "False" | "None"
  #|rule identifier: /[A-Za-z_][A-Za-z0-9_]*/
  #|rule number_literal: /[0-9]+(\.[0-9]+)?/
  #|rule string_literal: /"([^"\\]|\\.)*"|'([^'\\]|\\.)*'/

///|
let python_table : @tablegen.ParseTable = compile_builtin_grammar(
  python_grammar,
)

///|
pub fn parse_python(
  source : String,
) -> Result[@runtime.CstNode, @runtime.ParseError] {
  @runtime.parse(python_table, source)
}
