export const BUILTIN_LANGUAGE_PRESETS = [
  {
    id: 'json',
    name: 'JSON',
    desc: '来自 grammars/json.mbt 的内置 JSON 文法，符合 RFC 8259 完整规范，支持对象、数组、字符串（含转义序列与 \\uXXXX）、数字、布尔值和 null。',
    grammar: String.raw`start json
extras [/[ \t\n\r]+/]
rule json: value
rule value: object | array | jstring | number | "true" | "false" | "null"
rule object: "{" pairs? "}"
rule pairs:  pair ("," pair)*
rule pair:   jstring ":" value
rule array:  "[" elements? "]"
rule elements: value ("," value)*
rule jstring: /"([^"\\]|\\["\\bfnrt]|\\u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])*"/
rule number: /-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?/`,
    source: `{
  "name": "MoonParse",
  "version": "1.0.0",
  "description": "A \\\"parser-generator\\\" for MoonBit",
  "path": "C:\\\\projects\\\\moonparse",
  "unicode": "\\u6708\\u5149",
  "stable": true,
  "count": 42,
  "pi": 3.14159,
  "tags": ["wasm", "glr", "incremental"],
  "meta": { "author": null, "license": "Apache-2.0" }
}`,
    query: '(pair (jstring) @property ":" (value) @value)',
    highlightQuery: String.raw`(jstring) @string
(number) @number
"true" @constant
"false" @constant
"null" @constant
(pair (jstring) @property)`,
  },
  {
    id: 'json5',
    name: 'JSON5',
    desc: '来自 grammars/json5.mbt 的内置 JSON5 文法，支持注释、尾随逗号和未加引号的 key。',
    grammar: String.raw`start json5
extras [/[ \t\n\r]+/, /[ \t]*\/\/[^\n\r]*(\r\n|\n|\r)?/, /\/\*([^*]|\*+[^*/])*\*+\//]
rule json5: value
rule value: object | array | string | number | "true" | "false" | "null" | "Infinity" | "NaN" | "+Infinity" | "-Infinity"
rule object: "{" members? ","? "}"
rule members: member ("," member)*
rule member: property_name ":" value
rule property_name: string | identifier
rule array: "[" elements? ","? "]"
rule elements: value ("," value)*
rule string: dstring | sstring
rule dstring: /"([^"\\]|\\.)*"/
rule sstring: /'([^'\\]|\\.)*'/
rule number: /[-+]?(0[xX][0-9a-fA-F]+|([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?)/
rule identifier: /[$A-Za-z_][$0-9A-Za-z_]*/`,
    source: `// MoonParse project config
{
  name: 'moonparse',
  version: '1.0.0',
  // trailing commas & hex literals
  features: ['glr', 'incremental', 'wasm',],
  limits: {
    maxTokens: 0xFF,
    timeout: +Infinity,
  },
  debug: false,
  ratio: +0.5e2,
  author: null,
}`,
    query: '(member (property_name) @property ":" (value) @value)',
    highlightQuery: String.raw`(dstring) @string
(sstring) @string
(number) @number
"true" @constant
"false" @constant
"null" @constant
"Infinity" @constant
"NaN" @constant
(member (identifier) @property)
(member (string) @property)`,
  },
  {
    id: 'c',
    name: 'C',
    desc: '来自 grammars/c.mbt 的在线同步版，覆盖预处理行、函数定义、声明、do/while、switch 以及位运算和复合赋值。',
    grammar: String.raw`start translation_unit
extras [/[ \t\n\r]+/, /\/\/[^\n\r]*/, /\/\*([^*]|\*+[^*/])*\*+\//]
rule translation_unit: item*
rule item: preproc_directive | function_definition | declaration
rule preproc_directive: /#[^\n\r]*/
rule function_definition: declaration_specifiers declarator compound_statement
rule declaration: declaration_specifiers init_declarator_list? ";"
rule declaration_specifiers: declaration_specifier+
rule declaration_specifier: type_specifier | "const" | "static" | "extern"
rule type_specifier: "void" | "char" | "short" | "int" | "long" | "float" | "double" | "signed" | "unsigned" | "struct" identifier
rule init_declarator_list: init_declarator ("," init_declarator)*
rule init_declarator: declarator ("=" initializer)?
rule initializer: assignment_expression | "{" initializer_list ","? "}"
rule initializer_list: initializer ("," initializer)*
rule declarator: pointer? identifier function_suffix?
rule pointer: "*" pointer?
rule function_suffix: "(" parameter_list? ")"
rule parameter_list: parameter ("," parameter)* ("," "...")?
rule parameter: declaration_specifiers declarator?
rule compound_statement: "{" block_item* "}"
rule block_item: declaration | statement
rule statement: compound_statement | if_statement | while_statement | do_while_statement | for_statement | switch_statement | return_statement | break_statement | continue_statement | expression_statement
rule if_statement: "if" "(" expression ")" statement ("else" statement)?
rule while_statement: "while" "(" expression ")" statement
rule for_statement: "for" "(" for_init? ";" expression? ";" expression? ")" statement
rule for_init: for_declaration | expression
rule for_declaration: declaration_specifiers init_declarator_list?
rule do_while_statement: "do" statement "while" "(" expression ")" ";"
rule switch_statement: "switch" "(" expression ")" "{" switch_item* "}"
rule switch_item: case_clause | default_clause | block_item
rule case_clause: "case" conditional_expression ":"
rule default_clause: "default" ":"
rule return_statement: "return" expression? ";"
rule break_statement: "break" ";"
rule continue_statement: "continue" ";"
rule expression_statement: expression? ";"
rule expression: assignment_expression ("," assignment_expression)*
rule assignment_expression: unary_expression assignment_operator assignment_expression | conditional_expression
rule assignment_operator: "=" | "+=" | "-=" | "*=" | "/=" | "%=" | "|=" | "^=" | "&=" | "<<=" | ">>="
rule conditional_expression: logical_or_expression ("?" expression ":" conditional_expression)?
rule logical_or_expression: logical_and_expression ("||" logical_and_expression)*
rule logical_and_expression: bitwise_or_expression ("&&" bitwise_or_expression)*
rule bitwise_or_expression: bitwise_xor_expression ("|" bitwise_xor_expression)*
rule bitwise_xor_expression: bitwise_and_expression ("^" bitwise_and_expression)*
rule bitwise_and_expression: equality_expression ("&" equality_expression)*
rule equality_expression: relational_expression (("==" | "!=") relational_expression)*
rule relational_expression: shift_expression (("<" | ">" | "<=" | ">=") shift_expression)*
rule shift_expression: additive_expression (("<<" | ">>") additive_expression)*
rule additive_expression: multiplicative_expression (("+" | "-") multiplicative_expression)*
rule multiplicative_expression: unary_expression (("*" | "/" | "%") unary_expression)*
rule unary_expression: postfix_expression | unary_operator unary_expression
rule unary_operator: "&" | "*" | "+" | "-" | "!" | "~" | "++" | "--"
rule postfix_expression: primary_expression postfix_suffix*
rule postfix_suffix: "(" argument_list? ")" | "[" expression "]" | "." identifier | "->" identifier | "++" | "--"
rule argument_list: assignment_expression ("," assignment_expression)*
rule primary_expression: identifier | number_literal | string_literal | char_literal | "(" expression ")"
rule identifier: /[_A-Za-z][_A-Za-z0-9]*/
rule number_literal: /(0[xX][0-9a-fA-F]+|[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?)[uUlLfF]*/
rule string_literal: /"([^"\\]|\\.)*"/
rule char_literal: /'([^'\\]|\\.)'/`,
    source: `#include <stdio.h>

static int fib(int n) {
  if (n < 2) return n;
  return fib(n - 1) + fib(n - 2);
}

int main(int argc, char *argv) {
  int i = 0;
  int sum = 0;

  do {
    sum += i;
    i += 1;
  } while (i < argc);

  switch (sum) {
    case 0:
      return 0;
    default:
      return fib(sum & 7);
  }
}`,
    query: '(function_definition (declarator (identifier) @function))',
    highlightQuery: String.raw`(string_literal) @string
(char_literal) @string
(number_literal) @number
(preproc_directive) @keyword
(function_definition (declarator (identifier) @function))
(identifier) @variable
"void" @type
"char" @type
"short" @type
"int" @type
"long" @type
"float" @type
"double" @type
"signed" @type
"unsigned" @type
"const" @keyword
"static" @keyword
"extern" @keyword
"struct" @keyword
"if" @keyword
"else" @keyword
"while" @keyword
"do" @keyword
"for" @keyword
"switch" @keyword
"case" @keyword
"default" @keyword
"return" @keyword
"break" @keyword
"continue" @keyword
"+" @operator
"-" @operator
"*" @operator
"/" @operator
"%" @operator
"=" @operator
"+=" @operator
"-=" @operator
"*=" @operator
"/=" @operator
"%=" @operator
"|=" @operator
"^=" @operator
"&=" @operator
"<<=" @operator
">>=" @operator
"==" @operator
"!=" @operator
"<" @operator
">" @operator
"<=" @operator
">=" @operator
"&&" @operator
"||" @operator
"&" @operator
"|" @operator
"^" @operator
"~" @operator
"<<" @operator
">>" @operator
"->" @operator
"++" @operator
"--" @operator`,
  },
  {
    id: 'python',
    name: 'Python',
    desc: '与仓库内置 Python grammar 同步，使用缩进 scanner 解析真实代码块，树结构和高亮都能进入函数体。',
    grammar: String.raw`start module
extras [/[ \t]+/, /#[^\n\r]*/]
externals [indent dedent newline]
rule module: (newline | statement)*
rule statement: compound_statement newline* | simple_statement newline*
rule simple_statement: import_statement | return_statement | pass_statement | break_statement | continue_statement | raise_statement | del_statement | global_statement | nonlocal_statement | assert_statement | augmented_assign_statement | assign_statement | expression_statement
rule compound_statement: if_statement | while_statement | for_statement | decorated_statement | try_statement | with_statement
rule import_statement: "import" import_alias ("," import_alias)* | "from" dotted_name "import" import_targets
rule import_alias: dotted_name ("as" identifier)?
rule import_targets: "*" | import_as_item ("," import_as_item)*
rule import_as_item: identifier ("as" identifier)?
rule return_statement: "return" expression_list?
rule pass_statement: "pass"
rule break_statement: "break"
rule continue_statement: "continue"
rule raise_statement: "raise" expression? ("from" expression)?
rule del_statement: "del" expression ("," expression)*
rule global_statement: "global" identifier ("," identifier)*
rule nonlocal_statement: "nonlocal" identifier ("," identifier)*
rule assert_statement: "assert" expression ("," expression)?
rule assign_statement: target ("," target)* ","? (":" type_hint)? "=" expression
rule augmented_assign_statement: target augmented_operator expression
rule augmented_operator: "+=" | "-=" | "*=" | "/=" | "%=" | "**=" | "//=" | "&=" | "|=" | "^=" | "<<=" | ">>="
rule expression_statement: expression
rule target: identifier | postfix_expression | "*" identifier
rule if_statement: "if" expression ":" suite ("elif" expression ":" suite)* ("else" ":" suite)?
rule while_statement: "while" expression ":" suite
rule for_statement: "for" for_target "in" expression ":" suite
rule for_target: identifier ("," identifier)*
rule def_statement: "def" identifier "(" parameter_list? ")" return_hint? ":" suite
rule class_statement: "class" identifier ("(" argument_list? ")")? ":" suite
rule try_statement: "try" ":" suite except_clause* ("else" ":" suite)? ("finally" ":" suite)?
rule except_clause: "except" exception_spec? ":" suite
rule exception_spec: expression ("as" identifier)?
rule with_statement: "with" with_item ("," with_item)* ":" suite
rule with_item: expression ("as" target)?
rule async_def_statement: "async" "def" identifier "(" parameter_list? ")" return_hint? ":" suite
rule suite: simple_statement | newline indent statement+ dedent
rule return_hint: "->" type_hint
rule type_hint: dotted_name ("[" type_hint ("," type_hint)* "]")?
rule parameter_list: parameter_item ("," parameter_item)* ("," "/" ("," parameter_item)*)?
rule parameter_item: "**" identifier | "*" identifier? | identifier (":" type_hint)? ("=" expression)?
rule dotted_name: identifier ("." identifier)*
rule expression: lambda_expression | yield_expression | named_expression | conditional_expression
rule lambda_expression: "lambda" parameter_names? ":" expression
rule parameter_names: identifier ("," identifier)*
rule conditional_expression: or_expression ("if" or_expression "else" expression)?
rule or_expression: and_expression ("or" and_expression)*
rule and_expression: not_expression ("and" not_expression)*
rule not_expression: "not" not_expression | comparison_expression
rule comparison_expression: bitwise_or_expression (comparison_operator bitwise_or_expression)*
rule comparison_operator: "==" | "!=" | "<" | ">" | "<=" | ">=" | "in" | "not" "in" | "is" "not" | "is"
rule bitwise_or_expression: bitwise_xor_expression ("|" bitwise_xor_expression)*
rule bitwise_xor_expression: bitwise_and_expression ("^" bitwise_and_expression)*
rule bitwise_and_expression: shift_expression ("&" shift_expression)*
rule shift_expression: additive_expression (("<<" | ">>") additive_expression)*
rule additive_expression: multiplicative_expression (("+" | "-") multiplicative_expression)*
rule multiplicative_expression: power_expression (("*" | "/" | "%" | "//") power_expression)*
rule power_expression: unary_expression ("**" unary_expression)?
rule unary_expression: postfix_expression | await_expression | ("+" | "-" | "~") unary_expression
rule postfix_expression: primary_expression postfix_suffix*
rule postfix_suffix: "(" argument_list? ")" | "[" subscript "]" | "." identifier
rule subscript: slice | expression
rule slice: expression? ":" expression? (":" expression?)?
rule argument_list: argument_item ("," argument_item)*
rule argument_item: "**" expression | "*" expression | identifier "=" expression | expression
rule primary_expression: literal | identifier | tuple_literal | list_literal | set_literal | dict_literal | "(" expression ")"
rule tuple_literal: "(" expression ("," expression)* "," ")"
rule list_literal: "[" expression_list? "]" | "[" expression comp_clause+ "]"
rule set_literal: "{" expression ("," expression)* ","? "}" | "{" expression comp_clause+ "}"
rule dict_literal: "{" dict_item ("," dict_item)* ","? "}" | "{" "}" | "{" dict_item comp_clause+ "}"
rule dict_item: expression ":" expression
rule expression_list: expression ("," expression)*
rule literal: number_literal | string_literal | "True" | "False" | "None" | "..."
rule identifier: /[A-Za-z_][A-Za-z0-9_]*/
rule number_literal: /0[xX][0-9a-fA-F][0-9a-fA-F_]*|0[bB][01][01_]*|0[oO][0-7][0-7_]*|[0-9][0-9_]*(\.[0-9][0-9_]*)?([eE][+-]?[0-9]+)?[jJ]?/
rule string_literal: /(r|b|rb|br|f|fr|rf|R|B|RB|BR|F|FR|RF)?("""([^"\\]|\\.)*"""|'''([^'\\]|\\.)*'''|"([^"\\]|\\.)*"|'([^'\\]|\\.)*')/
rule comp_clause: "for" for_target "in" or_expression ("if" or_expression)*
rule decorated_statement: decorator* (def_statement | class_statement | async_def_statement)
rule decorator: "@" dotted_name ("(" argument_list? ")")? newline
rule yield_expression: "yield" "from" expression | "yield" expression?
rule await_expression: "await" unary_expression
rule named_expression: identifier ":=" expression`,
    source: `import math
from typing import Iterable

def fib(n: int) -> int:
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)

def squares(xs: Iterable[int]) -> list[int]:
    result = []
    for x in xs:
        result.append(x * x)
    return result

async def load(xs):
    return [x * 2 for x in xs if x > 0]

class Circle:
    def area(self) -> float:
        return math.pi * self.radius * self.radius`,
    query: '(def_statement (identifier) @function)\n(async_def_statement (identifier) @function)\n(class_statement (identifier) @type)',
    highlightQuery: String.raw`(string_literal) @string
(number_literal) @number
(decorator (dotted_name (identifier) @attribute))
(def_statement (identifier) @function)
(async_def_statement (identifier) @function)
(class_statement (identifier) @type)
(identifier) @variable
"async" @keyword
"def" @keyword
"class" @keyword
"if" @keyword
"elif" @keyword
"else" @keyword
"while" @keyword
"for" @keyword
"in" @keyword
"import" @keyword
"from" @keyword
"as" @keyword
"try" @keyword
"except" @keyword
"finally" @keyword
"with" @keyword
"return" @keyword
"pass" @keyword
"break" @keyword
"continue" @keyword
"raise" @keyword
"del" @keyword
"global" @keyword
"nonlocal" @keyword
"assert" @keyword
"await" @keyword
"yield" @keyword
"True" @constant
"False" @constant
"None" @constant
"..." @constant
"+" @operator
"-" @operator
"*" @operator
"/" @operator
"**" @operator
"//" @operator
"&" @operator
"|" @operator
"^" @operator
"<<" @operator
">>" @operator
"~" @operator
"==" @operator
"!=" @operator
"<" @operator
">" @operator
"<=" @operator
">=" @operator`,
  },
  {
    id: 'moonbit',
    name: 'MoonBit',
    desc: '来自 grammars/moonbit.mbt 的在线同步版，覆盖 fn/let/const/type/struct/enum/trait/impl/test/suberror、控制流与常用表达式。',
    grammar: String.raw`start module
extras [/[ \t\f]+/, /\/\/[^\n\r]*/, /\/\*([^*]|\*+[^*\/])*\*+\//]
word identifier
conflicts [[for_in_statement, for_c_statement]]
conflicts [[pattern_item, single_pattern]]
conflicts [[block, record_literal]]
rule newline: /(\r\n|\n|\r)[ \t\f]*/
rule module: (newline | item)*
rule item: function_decl | let_decl | const_decl | type_alias_decl | struct_decl | enum_decl | trait_decl | impl_decl | test_decl | suberror_decl
rule visibility: "pub" ("(" ("all" | "readonly" | "open") ")")? | "priv"
rule function_decl: attribute* visibility? "fn" constrained_type_params? fn_name type_params? parameter_clause return_type? error_type? block
rule let_decl: visibility? "let" "mut"? pattern type_annotation? ("=" expression)?
rule const_decl: visibility? "const" identifier type_annotation? "=" expression
rule type_alias_decl: visibility? "type" identifier type_params? "=" type_expr
rule struct_decl: visibility? "struct" identifier type_params? ("(" struct_tuple_fields? ")")? ("{" field_decl_list "}")? derive_clause?
rule struct_tuple_fields: type_expr ("," type_expr)*
rule field_decl_list: (newline | field_decl)*
rule field_decl: "mut"? identifier ":" type_expr
rule enum_decl: visibility? "enum" identifier type_params? "{" enum_case_list "}" derive_clause?
rule enum_case_list: (newline | enum_case)*
rule enum_case: identifier ("(" enum_payload_list? ")")?
rule enum_payload_list: enum_payload_item ("," enum_payload_item)*
rule enum_payload_item: "mut"? identifier "~" ":" type_expr | type_expr
rule trait_decl: visibility? "trait" identifier type_params? (":" trait_bound_list)? "{" trait_method_list "}"
rule trait_bound_list: qualified_identifier ("+" qualified_identifier)*
rule trait_method_list: (newline | trait_method_decl)*
rule trait_method_decl: identifier type_params? parameter_clause return_type? error_type? ("=" "_")?
rule impl_decl: visibility? "impl" constrained_type_params? qualified_identifier ("for" qualified_identifier type_args?)? ("with" newline? impl_method_decl)?
rule impl_method_decl: identifier type_params? parameter_clause return_type? error_type? block
rule test_decl: "test" string_literal? block
rule suberror_decl: visibility? "suberror" identifier ("{" enum_case_list "}")? derive_clause?
rule attribute: "#" identifier "(" attribute_args? ")"
rule attribute_args: attribute_arg ("," attribute_arg)*
rule attribute_arg: identifier ("=" (string_literal | identifier))?
rule fn_name: identifier ("::" identifier)*
rule constrained_type_params: "[" constrained_param ("," constrained_param)* "]"
rule constrained_param: identifier (":" trait_bound_list)?
rule type_params: "[" identifier ("," identifier)* "]"
rule parameter_clause: "()" | "(" newline* parameter_list? newline* ")"
rule parameter_list: parameter ("," newline* parameter)* ("," newline*)?
rule parameter: "self" | "~"? identifier type_annotation? ("=" expression)? | "_" | ".." identifier
rule type_annotation: ":" type_expr
rule return_type: "->" type_expr
rule error_type: "raise" type_expr?
rule type_expr: simple_type ("->" type_expr ("raise" type_expr?)?)?
rule simple_type: qualified_identifier type_args? "?"* | "(" type_expr_list? ")" | "[" type_expr_list? "]" | "()" | "&" qualified_identifier type_args?
rule type_expr_list: type_expr ("," type_expr)*
rule type_args: "[" type_expr ("," type_expr)* "]"
rule block: "{" newline* (statement newline*)* "}"
rule statement: let_statement | return_statement | break_statement | continue_statement | raise_statement | guard_statement | if_statement | while_statement | loop_statement | for_in_statement | for_c_statement | defer_statement | expression
rule let_statement: "let" "mut"? pattern type_annotation? ("=" expression)?
rule return_statement: "return" expression?
rule break_statement: "break" (identifier "~")? expression?
rule continue_statement: "continue" (identifier "~")? continue_args?
rule continue_args: expression ("," expression)*
rule raise_statement: "raise" expression
rule guard_statement: "guard" expression ("is" pattern)? ("else" "{" match_case_list "}")?
rule if_statement: "if" expression block ("else" (block | if_statement))?
rule while_statement: "while" expression block nobreak_clause?
rule nobreak_clause: "nobreak" block
rule loop_statement: "loop" block
rule for_in_statement: label_clause? "for" pattern ("," pattern)? "in" expression block nobreak_clause?
rule for_c_statement: label_clause? "for" for_init_list? ";" expression? ";" for_update_list? block nobreak_clause?
rule label_clause: identifier "~" ":"
rule for_init_list: for_init_item ("," for_init_item)*
rule for_init_item: identifier "=" expression
rule for_update_list: for_update_item ("," for_update_item)*
rule for_update_item: identifier "=" expression
rule defer_statement: "defer" expression
rule expression: match_expression | try_expression | fn_expression | arrow_expression | assignment_expression
rule match_expression: "match" expression "{" match_case_list "}"
rule match_case_list: (newline | match_case)*
rule match_case: pattern guard_clause? "=>" expression_or_block
rule guard_clause: "if" expression
rule expression_or_block: block | expression
rule fn_expression: "fn" parameter_clause return_type? error_type? block
rule arrow_expression: identifier "=>" (block | expression)
rule try_expression: "try" try_tail
rule try_tail: "?" expression | "!" expression | block catch_clause+ noraise_clause?
rule catch_clause: "catch" catch_binding? block
rule catch_binding: "{" match_case_list "}" | "(" pattern ")"
rule noraise_clause: "noraise" block
rule assignment_expression: pipe_expression (("=" | ":=" | "+=" | "-=" | "*=" | "/=") assignment_expression)?
rule pipe_expression: logical_or_expression ("|>" pipe_target)*
rule pipe_target: logical_or_expression | arrow_expression
rule logical_or_expression: logical_and_expression ("||" logical_and_expression)*
rule logical_and_expression: is_expression ("&&" is_expression)*
rule is_expression: equality_expression ("is" pattern)?
rule equality_expression: comparison_expression (("==" | "!=") comparison_expression)*
rule comparison_expression: bitwise_or_expression (("<" | ">" | "<=" | ">=") bitwise_or_expression)*
rule bitwise_or_expression: bitwise_xor_expression ("|" bitwise_xor_expression)*
rule bitwise_xor_expression: bitwise_and_expression ("^" bitwise_and_expression)*
rule bitwise_and_expression: shift_expression ("&" shift_expression)*
rule shift_expression: range_expression (("<<" | ">>") range_expression)*
rule range_expression: additive_expression ((".." | "..<" | "..=" | ">=.." | ">..") additive_expression)?
rule additive_expression: multiplicative_expression (("+" | "-") multiplicative_expression)*
rule multiplicative_expression: unary_expression (("*" | "/" | "%") unary_expression)*
rule unary_expression: postfix_expression | ("!" | "-" | "+") unary_expression
rule postfix_expression: primary_expression postfix_suffix*
rule postfix_suffix: "()" | "(" argument_list? ")" | "[" slice_or_index "]" | "." identifier | ".." identifier "(" argument_list? ")" | "?"
rule slice_or_index: expression? ":" expression? | expression
rule argument_list: argument ("," argument)*
rule argument: identifier "~" | identifier "=" expression | identifier "?" ("=" expression)? | expression
rule primary_expression: literal | "self" | qualified_identifier | tuple_literal | list_literal | record_literal | "(" expression ")" | "_"
rule tuple_literal: "(" expression ("," expression)+ ")"
rule list_literal: "[" list_elements? "]"
rule list_elements: list_element ("," list_element)*
rule list_element: ".." expression | expression
rule record_literal: "{" record_body? "}"
rule record_body: ".." expression ("," record_field)* ","? | record_field_list
rule record_field_list: record_field ("," record_field)* ","?
rule record_field: identifier (":" expression)?
rule pattern: or_pattern
rule or_pattern: as_pattern ("|" as_pattern)*
rule as_pattern: single_pattern ("as" identifier)?
rule single_pattern: "_" | literal | range_pattern | qualified_identifier pattern_suffix? | "(" pattern_items? ")" | "[" array_pattern_items? "]" | "{" map_pattern_items "}" | ".." identifier?
rule range_pattern: (literal | "_") ("..<" | "..=") (literal | "_")
rule pattern_suffix: "(" pattern_items? ")" | "::" "{" "}"
rule pattern_items: pattern_item ("," pattern_item)*
rule pattern_item: identifier "~" | identifier "=" pattern | ".." identifier? | pattern
rule array_pattern_items: pattern_item ("," pattern_item)*
rule map_pattern_items: map_pattern_entry ("," map_pattern_entry)* ","? ".."
rule map_pattern_entry: literal "?"? ":" pattern
rule derive_clause: "derive" "(" qualified_identifier ("," qualified_identifier)* ")"
rule qualified_identifier: identifier (("." | "::") identifier)*
token rule identifier: /@?[A-Za-z_][A-Za-z0-9_]*/
rule literal: number_literal | string_literal | char_literal | byte_literal | bytes_literal | "true" | "false" | "()"
rule number_literal: /0[xX][0-9a-fA-F][0-9a-fA-F_]*|0[bB][01][01_]*|0[oO][0-7][0-7_]*|[0-9][0-9_]*(\.[0-9][0-9_]*)?([eE][+-]?[0-9]+)?[uUlLnN]*/
rule string_literal: /"([^"\\]|\\.)*"/
rule char_literal: /'([^'\\]|\\.)'/
rule byte_literal: /b'([^'\\]|\\.)'/
rule bytes_literal: /b"([^"\\]|\\.)*"/`,
    source: `struct Point {
  x : Int
  y : Int
} derive(Show)

enum Shape {
  Circle(Double)
  Rect(Double, Double)
}

fn area(s : Shape) -> Double {
  match s {
    Circle(r) => 3.14159 * r * r
    Rect(w, h) => w * h
  }
}

fn make_point(x : Int, y : Int) -> Point {
  { x: x, y: y }
}

test "shapes" {
  let p = make_point(3, 4)
  let c = Shape::Circle(1.0)
  let _ = area(c)
}`,
    query: '(function_decl (fn_name (identifier) @function))\n(struct_decl (identifier) @type)\n(enum_decl (identifier) @type)\n(trait_decl (identifier) @type)',
    highlightQuery: String.raw`(string_literal) @string
(char_literal) @string
(byte_literal) @string
(bytes_literal) @string
(number_literal) @number
(function_decl (fn_name (identifier) @function))
(struct_decl (identifier) @type)
(enum_decl (identifier) @type)
(type_alias_decl (identifier) @type)
(trait_decl (identifier) @type)
(identifier) @variable
"fn" @keyword
"let" @keyword
"const" @keyword
"mut" @keyword
"type" @keyword
"struct" @keyword
"enum" @keyword
"trait" @keyword
"impl" @keyword
"test" @keyword
"suberror" @keyword
"pub" @keyword
"priv" @keyword
"if" @keyword
"else" @keyword
"match" @keyword
"for" @keyword
"in" @keyword
"while" @keyword
"loop" @keyword
"guard" @keyword
"return" @keyword
"raise" @keyword
"break" @keyword
"continue" @keyword
"defer" @keyword
"try" @keyword
"catch" @keyword
"noraise" @keyword
"nobreak" @keyword
"derive" @attribute
"true" @constant
"false" @constant
"()" @constant
"+" @operator
"-" @operator
"*" @operator
"/" @operator
"%" @operator
"=" @operator
":=" @operator
"+=" @operator
"-=" @operator
"*=" @operator
"/=" @operator
"|>" @operator
"|" @operator
"^" @operator
"&" @operator
"<<" @operator
">>" @operator
".." @operator
"..<" @operator
"..=" @operator
"=>" @operator
"==" @operator
"!=" @operator
"<" @operator
">" @operator
"<=" @operator
">=" @operator`,
  },
]

const ADDITIONAL_DEMO_PRESETS = [
  {
    id: 'arithmetic',
    name: '四则运算',
    desc: '用 precedence 声明解决运算符优先级与结合性冲突的表达式文法。',
    grammar: String.raw`start expr
extras [/[ \t]+/]

// 优先级从低到高；同级左结合
precedence left plus, minus
precedence left star, slash

rule expr: expr plus expr
         | expr minus expr
         | expr star expr
         | expr slash expr
         | "(" expr ")"
         | number
rule plus:  "+"
rule minus: "-"
rule star:  "*"
rule slash: "/"
rule number: /[0-9]+/`,
    source: '3 + 4 * (2 - 1)',
    query: '(number) @number',
    highlightQuery: String.raw`(number) @number
(plus) @operator
(minus) @operator
(star) @operator
(slash) @operator`,
  },
  {
    id: 'csv',
    name: 'CSV',
    desc: '支持可选引号字段的逗号分隔值格式。',
    grammar: String.raw`start csv
extras []
rule newline: /\n/
rule csv: row (newline row)*
rule row: field ("," field)*
rule field: quoted | plain
rule quoted: /"[^"]*"/
rule plain: /[^,\n]*/`,
    source: `name,age,city
"Alice",30,Paris
Bob,25,"New York"`,
    query: '(quoted) @string',
    highlightQuery: String.raw`(quoted) @string`,
  },
  {
    id: 'sexp',
    name: 'S 表达式',
    desc: '极简的 Lisp / Scheme 风格 S 表达式文法。',
    grammar: String.raw`start sexp
extras [/[ \t\n\r]+/]
rule sexp: atom | list
rule list: "(" sexp* ")"
rule atom: symbol | number | string
rule symbol: /[a-zA-Z+\-*\/=<>!?][a-zA-Z0-9+\-*\/=<>!?]*/
rule number: /-?[0-9]+/
rule string: /"[^"]*"/`,
    source: `(defun fib (n)
  (if (< n 2)
    n
    (+ (fib (- n 1)) (fib (- n 2)))))`,
    query: '(symbol) @variable',
    highlightQuery: String.raw`(number) @number
(string) @string
(symbol) @variable`,
  },
  {
    id: 'markdown-headers',
    name: 'Markdown 标题',
    desc: '从 Markdown 文本中提取 ATX 风格标题。',
    grammar: String.raw`start doc
extras []
rule newline: /\n/
rule doc: line*
rule line: heading | text_line
rule heading: /#+/ heading_body? newline?
rule heading_body: /[ \t][^\n]*/
rule text_line: /[^#\n][^\n]*/ newline? | newline`,
    source: `# MoonParse\n\nA GLR parsing toolkit.\n\n## Core Features\n\nIncremental parsing, tree queries and error recovery.`,
    query: '(heading) @keyword',
    highlightQuery: String.raw`(heading) @keyword`,
  },
  {
    id: 'toml-like',
    name: '类 TOML 配置',
    desc: '一个简化版的 TOML 风格配置格式，支持段落和键值对。',
    grammar: String.raw`start config
extras [/[ \t]+/]
rule config: block*
rule block: section | pair | newline
rule newline: /\n/
rule section: "[" name "]" newline
rule pair: name "=" value newline
rule value: string | number | "true" | "false"
rule name: /[a-zA-Z_][a-zA-Z0-9_]*/
rule string: /"[^"]*"/
rule number: /-?[0-9]+/`,
    source: `[database]
host = "localhost"
port = 5432
enabled = true

[cache]
ttl = 300
`,
    query: '(pair (name) @property "=" (value) @value)',
    highlightQuery: String.raw`(string) @string
(number) @number
"true" @constant
"false" @constant
(name) @property`,
  },
]

export const EXAMPLE_PRESETS = [
  ...BUILTIN_LANGUAGE_PRESETS,
  ...ADDITIONAL_DEMO_PRESETS,
]

export function findBuiltinPresetByGrammar(grammar) {
  if (!grammar) return null
  return BUILTIN_LANGUAGE_PRESETS.find((preset) => preset.grammar === grammar) ?? null
}

export function findExamplePresetById(id) {
  if (!id) return null
  return EXAMPLE_PRESETS.find((preset) => preset.id === id) ?? null
}
